// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./FishToken.sol";
import "./BoatNFT.sol";

/**
 * @title GameController
 * @dev Main game logic controller for FishQuest
 */
contract GameController is Ownable, Pausable, ReentrancyGuard {
    
    FishToken public fishToken;
    BoatNFT public boatNFT;
    
    // Grid size for the game map
    uint256 public constant GRID_SIZE = 100;
    
    // Placement fee for boats
    uint256 public placementFee = 0.001 ether;
    
    // XP decay rate (5% per day)
    uint256 public constant XP_DECAY_RATE = 5;
    
    // Movement bonus settings
    uint256 public constant MOVEMENT_BONUS_DAYS = 3;
    uint256 public constant MOVEMENT_BONUS_MULTIPLIER = 200; // 200% = 2x
    
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
    
    // Player data mapping
    mapping(address => PlayerData) public players;
    
    // Grid position to boat mapping
    mapping(uint256 => mapping(uint256 => BoatPosition)) public grid;
    
    // Position occupied check
    mapping(uint256 => mapping(uint256 => bool)) public isPositionOccupied;
    
    // Events
    event PlayerRegistered(address indexed player);
    event BoatPlaced(address indexed player, uint256 x, uint256 y, uint256 boatTokenId);
    event BoatMoved(address indexed player, uint256 fromX, uint256 fromY, uint256 toX, uint256 toY);
    event DailyClaimed(address indexed player, uint256 xpEarned, uint256 tokensEarned, uint256 streak);
    event XPEarned(address indexed player, uint256 amount, string reason);
    
    constructor(
        address _fishToken,
        address _boatNFT,
        address initialOwner
    ) Ownable(initialOwner) {
        fishToken = FishToken(_fishToken);
        boatNFT = BoatNFT(_boatNFT);
    }
    
    /**
     * @dev Register new player and give starter boat
     */
    function registerPlayer() external whenNotPaused {
        require(!players[msg.sender].registered, "Player already registered");
        
        // Initialize player data
        players[msg.sender] = PlayerData({
            totalXp: 0,
            currentStreak: 0,
            longestStreak: 0,
            lastClaimDate: 0,
            lastMoveDate: 0,
            mapX: 0,
            mapY: 0,
            hasPosition: false,
            registered: true
        });
        
        // Mint starter boat (free dinghy)
        boatNFT.mintStarterBoat(msg.sender);
        
        emit PlayerRegistered(msg.sender);
    }
    
    /**
     * @dev Place boat on the map
     */
    function placeBoat(uint256 x, uint256 y) external payable nonReentrant whenNotPaused {
        require(x < GRID_SIZE && y < GRID_SIZE, "Position out of bounds");
        require(!isPositionOccupied[x][y], "Position already occupied");
        require(msg.value >= placementFee, "Insufficient placement fee");
        
        PlayerData storage player = players[msg.sender];
        require(player.registered || msg.sender == owner(), "Player not registered");
        
        // Get player's active boat
        (uint256 boatTokenId, , , ) = boatNFT.getActiveBoat(msg.sender);
        require(boatTokenId > 0, "No active boat found");
        
        // Remove from old position if exists
        if (player.hasPosition) {
            isPositionOccupied[player.mapX][player.mapY] = false;
            delete grid[player.mapX][player.mapY];
        }
        
        // Place boat at new position
        grid[x][y] = BoatPosition({
            owner: msg.sender,
            boatTokenId: boatTokenId,
            x: x,
            y: y,
            placedAt: block.timestamp,
            lastMoved: block.timestamp
        });
        
        isPositionOccupied[x][y] = true;
        
        // Update player position
        player.mapX = x;
        player.mapY = y;
        player.hasPosition = true;
        player.lastMoveDate = block.timestamp;
        
        emit BoatPlaced(msg.sender, x, y, boatTokenId);
        
        // Refund excess payment
        if (msg.value > placementFee) {
            payable(msg.sender).transfer(msg.value - placementFee);
        }
    }
    
    /**
     * @dev Move boat to new position
     */
    function moveBoat(uint256 newX, uint256 newY) external payable nonReentrant whenNotPaused {
        require(newX < GRID_SIZE && newY < GRID_SIZE, "Position out of bounds");
        require(!isPositionOccupied[newX][newY], "Position already occupied");
        require(msg.value >= placementFee, "Insufficient movement fee");
        
        PlayerData storage player = players[msg.sender];
        require(player.hasPosition, "No boat placed");
        
        uint256 oldX = player.mapX;
        uint256 oldY = player.mapY;
        
        uint256 originalPlacedAt = grid[oldX][oldY].placedAt;

        // Remove from old position
        isPositionOccupied[oldX][oldY] = false;
        delete grid[oldX][oldY];
        
        // Get boat info
        (uint256 boatTokenId, , , ) = boatNFT.getActiveBoat(msg.sender);
        
        // Place at new position
        grid[newX][newY] = BoatPosition({
            owner: msg.sender,
            boatTokenId: boatTokenId,
            x: newX,
            y: newY,
            placedAt: originalPlacedAt,
            lastMoved: block.timestamp
        });
        
        isPositionOccupied[newX][newY] = true;
        
        // Update player position
        player.mapX = newX;
        player.mapY = newY;
        player.lastMoveDate = block.timestamp;
        
        emit BoatMoved(msg.sender, oldX, oldY, newX, newY);
        
        // Refund excess payment
        if (msg.value > placementFee) {
            payable(msg.sender).transfer(msg.value - placementFee);
        }
    }
    
    /**
     * @dev Claim daily rewards
     */
    function claimDaily() external nonReentrant whenNotPaused {
        PlayerData storage player = players[msg.sender];
        require(player.hasPosition, "Must place boat first");
        
        // Check if 24 hours have passed
        require(
            block.timestamp >= player.lastClaimDate + 24 hours || player.lastClaimDate == 0,
            "Cannot claim yet"
        );
        
        // Get active boat info
        (, , uint256 dailyXp, ) = boatNFT.getActiveBoat(msg.sender);
        require(dailyXp > 0, "No active boat");
        
        // Calculate streak
        bool streakContinues = (block.timestamp <= player.lastClaimDate + 48 hours) && player.lastClaimDate > 0;
        
        if (streakContinues) {
            player.currentStreak++;
        } else {
            player.currentStreak = 1;
        }
        
        if (player.currentStreak > player.longestStreak) {
            player.longestStreak = player.currentStreak;
        }
        
        // Calculate XP with bonuses and penalties
        uint256 finalXp = calculateFinalXP(msg.sender, dailyXp);
        
        // Update player data
        player.totalXp += finalXp;
        player.lastClaimDate = block.timestamp;
        
        // Mint Fish tokens based on XP
        fishToken.mintDailyReward(msg.sender, finalXp);
        
        emit DailyClaimed(msg.sender, finalXp, finalXp, player.currentStreak);
        emit XPEarned(msg.sender, finalXp, "daily_claim");
    }
    
    /**
     * @dev Calculate final XP with all modifiers
     */
    function calculateFinalXP(address player, uint256 baseXp) public view returns (uint256) {
        PlayerData memory playerData = players[player];
        
        uint256 finalXp = baseXp;
        
        // Apply streak multiplier
        uint256 streakMultiplier = calculateStreakMultiplier(playerData.currentStreak + 1);
        finalXp = (finalXp * streakMultiplier) / 100;
        
        // Apply movement bonus (if moved within last 3 days)
        if (block.timestamp <= playerData.lastMoveDate + (MOVEMENT_BONUS_DAYS * 24 hours)) {
            finalXp = (finalXp * MOVEMENT_BONUS_MULTIPLIER) / 100;
        }
        
        // Apply decay penalty (if stationary for more than 3 days)
        uint256 daysSinceMove = (block.timestamp - playerData.lastMoveDate) / (24 hours);
        if (daysSinceMove > MOVEMENT_BONUS_DAYS) {
            uint256 decayDays = daysSinceMove - MOVEMENT_BONUS_DAYS;
            uint256 decayPenalty = decayDays * XP_DECAY_RATE;
            if (decayPenalty > 50) decayPenalty = 50; // Max 50% penalty
            
            finalXp = finalXp - ((finalXp * decayPenalty) / 100);
        }
        
        return finalXp;
    }
    
    /**
     * @dev Calculate streak multiplier
     */
    function calculateStreakMultiplier(uint256 streakDay) public pure returns (uint256) {
        if (streakDay >= 100) return 1000; // 10x
        if (streakDay >= 30) return 500;   // 5x
        if (streakDay >= 14) return 300;   // 3x
        if (streakDay >= 7) return 200;    // 2x
        
        // Linear progression from 100% to 150% for days 1-6
        return 100 + ((streakDay - 1) * 10); // 1.0x to 1.5x
    }
    
    /**
     * @dev Get player info
     */
    function getPlayerInfo(address player) external view returns (
        uint256 totalXp,
        uint256 currentStreak,
        uint256 longestStreak,
        uint256 lastClaimDate,
        uint256 mapX,
        uint256 mapY,
        bool hasPosition,
        bool canClaim
    ) {
        PlayerData memory playerData = players[player];
        
        canClaim = block.timestamp >= playerData.lastClaimDate + 24 hours || playerData.lastClaimDate == 0;
        
        return (
            playerData.totalXp,
            playerData.currentStreak,
            playerData.longestStreak,
            playerData.lastClaimDate,
            playerData.mapX,
            playerData.mapY,
            playerData.hasPosition,
            canClaim
        );
    }
    
    /**
     * @dev Get boat at position
     */
    function getBoatAtPosition(uint256 x, uint256 y) external view returns (BoatPosition memory) {
        return grid[x][y];
    }
    
    /**
     * @dev Update placement fee
     */
    function setPlacementFee(uint256 _fee) external onlyOwner {
        placementFee = _fee;
    }
    
    /**
     * @dev Withdraw contract balance
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        payable(owner()).transfer(balance);
    }
    
    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
