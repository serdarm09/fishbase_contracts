// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./FishToken.sol";
import "./BoatNFT.sol";

/**
 * @title GameController
 * @dev Main game logic controller for FishBase
 *
 * Security improvements:
 *  - withdraw() uses call{} instead of transfer() to avoid 2300-gas limit issues
 *  - Refunds use call{} pattern
 *  - Owner bypass removed from placeBoat()
 *  - XP decay calculation safe-guards for uninitialized lastMoveDate
 *  - Placement fee is validated before any state changes
 */
contract GameController is Ownable, Pausable, ReentrancyGuard {

    FishToken public fishToken;
    BoatNFT public boatNFT;

    /// @dev 100×100 grid for boat placement
    uint256 public constant GRID_SIZE = 100;

    /// @dev Fee charged per placement / movement (adjustable by owner)
    uint256 public placementFee = 0.001 ether;

    /// @dev XP decay rate per idle day beyond the movement-bonus window (5 %)
    uint256 public constant XP_DECAY_RATE = 5;

    /// @dev Days after a move during which the movement bonus applies
    uint256 public constant MOVEMENT_BONUS_DAYS = 3;

    /// @dev Movement bonus multiplier expressed in percentage points (200 = 2×)
    uint256 public constant MOVEMENT_BONUS_MULTIPLIER = 200;

    struct PlayerData {
        uint256 totalXp;
        uint256 currentStreak;
        uint256 longestStreak;
        uint256 lastClaimDate;
        uint256 lastMoveDate;
        uint256 mapX;
        uint256 mapY;
        bool hasPosition;
        bool registered;
    }

    struct BoatPosition {
        address owner;
        uint256 boatTokenId;
        uint256 x;
        uint256 y;
        uint256 placedAt;
        uint256 lastMoved;
    }

    /// @dev Player state keyed by wallet address
    mapping(address => PlayerData) public players;

    /// @dev Grid cell → boat at that cell
    mapping(uint256 => mapping(uint256 => BoatPosition)) public grid;

    /// @dev Quick occupancy look-up
    mapping(uint256 => mapping(uint256 => bool)) public isPositionOccupied;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event PlayerRegistered(address indexed player);
    event BoatPlaced(address indexed player, uint256 x, uint256 y, uint256 boatTokenId);
    event BoatMoved(address indexed player, uint256 fromX, uint256 fromY, uint256 toX, uint256 toY);
    event DailyClaimed(address indexed player, uint256 xpEarned, uint256 tokensEarned, uint256 streak);
    event XPEarned(address indexed player, uint256 amount, string reason);
    event PlacementFeeUpdated(uint256 oldFee, uint256 newFee);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        address _fishToken,
        address _boatNFT,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_fishToken != address(0), "Zero address: fishToken");
        require(_boatNFT  != address(0), "Zero address: boatNFT");
        fishToken = FishToken(_fishToken);
        boatNFT   = BoatNFT(_boatNFT);
    }

    // -----------------------------------------------------------------------
    // Player registration
    // -----------------------------------------------------------------------

    /**
     * @dev Register a new player and grant a starter (Dinghy) boat.
     */
    function registerPlayer() external whenNotPaused {
        require(!players[msg.sender].registered, "Already registered");

        players[msg.sender] = PlayerData({
            totalXp:       0,
            currentStreak: 0,
            longestStreak: 0,
            lastClaimDate: 0,
            lastMoveDate:  0,
            mapX:          0,
            mapY:          0,
            hasPosition:   false,
            registered:    true
        });

        boatNFT.mintStarterBoat(msg.sender);
        emit PlayerRegistered(msg.sender);
    }

    // -----------------------------------------------------------------------
    // Map placement
    // -----------------------------------------------------------------------

    /**
     * @dev Place the caller's active boat on the map.
     *      Excess ETH is refunded.
     */
    function placeBoat(uint256 x, uint256 y) external payable nonReentrant whenNotPaused {
        require(x < GRID_SIZE && y < GRID_SIZE, "Position out of bounds");
        require(!isPositionOccupied[x][y],       "Position already occupied");
        require(msg.value >= placementFee,        "Insufficient placement fee");

        PlayerData storage player = players[msg.sender];
        require(player.registered, "Player not registered");

        (uint256 boatTokenId, , , ) = boatNFT.getActiveBoat(msg.sender);
        require(boatTokenId > 0, "No active boat");

        // Free the old cell if the player is already placed
        if (player.hasPosition) {
            isPositionOccupied[player.mapX][player.mapY] = false;
            delete grid[player.mapX][player.mapY];
        }

        grid[x][y] = BoatPosition({
            owner:       msg.sender,
            boatTokenId: boatTokenId,
            x:           x,
            y:           y,
            placedAt:    block.timestamp,
            lastMoved:   block.timestamp
        });

        isPositionOccupied[x][y] = true;
        player.mapX         = x;
        player.mapY         = y;
        player.hasPosition  = true;
        player.lastMoveDate = block.timestamp;

        emit BoatPlaced(msg.sender, x, y, boatTokenId);

        // Refund any overpayment
        _refund(msg.value - placementFee);
    }

    /**
     * @dev Move the caller's boat to a new map cell.
     *      Excess ETH is refunded.
     */
    function moveBoat(uint256 newX, uint256 newY) external payable nonReentrant whenNotPaused {
        require(newX < GRID_SIZE && newY < GRID_SIZE, "Position out of bounds");
        require(!isPositionOccupied[newX][newY],       "Position already occupied");
        require(msg.value >= placementFee,             "Insufficient movement fee");

        PlayerData storage player = players[msg.sender];
        require(player.hasPosition, "No boat placed yet");

        uint256 oldX = player.mapX;
        uint256 oldY = player.mapY;
        uint256 originalPlacedAt = grid[oldX][oldY].placedAt;

        // Vacate old cell
        isPositionOccupied[oldX][oldY] = false;
        delete grid[oldX][oldY];

        (uint256 boatTokenId, , , ) = boatNFT.getActiveBoat(msg.sender);

        grid[newX][newY] = BoatPosition({
            owner:       msg.sender,
            boatTokenId: boatTokenId,
            x:           newX,
            y:           newY,
            placedAt:    originalPlacedAt,
            lastMoved:   block.timestamp
        });

        isPositionOccupied[newX][newY] = true;
        player.mapX         = newX;
        player.mapY         = newY;
        player.lastMoveDate = block.timestamp;

        emit BoatMoved(msg.sender, oldX, oldY, newX, newY);
        _refund(msg.value - placementFee);
    }

    // -----------------------------------------------------------------------
    // Daily claim
    // -----------------------------------------------------------------------

    /**
     * @dev Claim daily XP/token reward.
     *      Can only be called once per 24-hour window.
     */
    function claimDaily() external nonReentrant whenNotPaused {
        PlayerData storage player = players[msg.sender];
        require(player.hasPosition, "Must place boat first");
        require(
            player.lastClaimDate == 0 || block.timestamp >= player.lastClaimDate + 24 hours,
            "Claim not ready yet"
        );

        (, , uint256 dailyXp, ) = boatNFT.getActiveBoat(msg.sender);
        require(dailyXp > 0, "No active boat");

        // Update streak
        bool streakContinues = player.lastClaimDate > 0 &&
                               block.timestamp <= player.lastClaimDate + 48 hours;

        if (streakContinues) {
            player.currentStreak++;
        } else {
            player.currentStreak = 1;
        }

        if (player.currentStreak > player.longestStreak) {
            player.longestStreak = player.currentStreak;
        }

        uint256 finalXp = calculateFinalXP(msg.sender, dailyXp);

        player.totalXp      += finalXp;
        player.lastClaimDate = block.timestamp;

        fishToken.mintDailyReward(msg.sender, finalXp);

        emit DailyClaimed(msg.sender, finalXp, finalXp, player.currentStreak);
        emit XPEarned(msg.sender, finalXp, "daily_claim");
    }

    // -----------------------------------------------------------------------
    // XP calculations
    // -----------------------------------------------------------------------

    /**
     * @dev Returns the final XP after applying streak multiplier, movement
     *      bonus, and idle decay.
     */
    function calculateFinalXP(address playerAddr, uint256 baseXp) public view returns (uint256) {
        PlayerData memory p = players[playerAddr];
        uint256 finalXp = baseXp;

        // Streak multiplier
        uint256 streakMul = calculateStreakMultiplier(p.currentStreak + 1);
        finalXp = (finalXp * streakMul) / 100;

        // Movement bonus / decay only applies once the player has actually moved
        if (p.lastMoveDate > 0) {
            if (block.timestamp <= p.lastMoveDate + MOVEMENT_BONUS_DAYS * 24 hours) {
                // Within the bonus window → 2× multiplier
                finalXp = (finalXp * MOVEMENT_BONUS_MULTIPLIER) / 100;
            } else {
                // Beyond the bonus window → apply decay
                uint256 daysSinceMove = (block.timestamp - p.lastMoveDate) / 24 hours;
                if (daysSinceMove > MOVEMENT_BONUS_DAYS) {
                    uint256 decayDays    = daysSinceMove - MOVEMENT_BONUS_DAYS;
                    uint256 decayPenalty = decayDays * XP_DECAY_RATE;
                    if (decayPenalty > 50) decayPenalty = 50; // hard cap at 50 %
                    finalXp = finalXp - (finalXp * decayPenalty) / 100;
                }
            }
        }

        return finalXp;
    }

    /**
     * @dev Maps a streak day count to a percentage multiplier.
     *      Examples: day 1 → 100 %, day 7 → 200 %, day 30 → 500 %.
     */
    function calculateStreakMultiplier(uint256 streakDay) public pure returns (uint256) {
        if (streakDay >= 100) return 1000; // 10×
        if (streakDay >= 30)  return 500;  // 5×
        if (streakDay >= 14)  return 300;  // 3×
        if (streakDay >= 7)   return 200;  // 2×
        // Linear 100 %→150 % for days 1–6
        return 100 + (streakDay - 1) * 10;
    }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    function getPlayerInfo(address player) external view returns (
        uint256 totalXp,
        uint256 currentStreak,
        uint256 longestStreak,
        uint256 lastClaimDate,
        uint256 mapX,
        uint256 mapY,
        bool    hasPosition,
        bool    canClaim
    ) {
        PlayerData memory pd = players[player];
        canClaim = pd.lastClaimDate == 0 || block.timestamp >= pd.lastClaimDate + 24 hours;

        return (
            pd.totalXp,
            pd.currentStreak,
            pd.longestStreak,
            pd.lastClaimDate,
            pd.mapX,
            pd.mapY,
            pd.hasPosition,
            canClaim
        );
    }

    function getBoatAtPosition(uint256 x, uint256 y) external view returns (BoatPosition memory) {
        return grid[x][y];
    }

    // -----------------------------------------------------------------------
    // Owner administration
    // -----------------------------------------------------------------------

    function setPlacementFee(uint256 _fee) external onlyOwner {
        emit PlacementFeeUpdated(placementFee, _fee);
        placementFee = _fee;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Nothing to withdraw");
        (bool ok, ) = payable(owner()).call{value: balance}("");
        require(ok, "Withdrawal failed");
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    /**
     * @dev Safely refunds excess ETH to the caller.
     */
    function _refund(uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Refund failed");
    }
}
