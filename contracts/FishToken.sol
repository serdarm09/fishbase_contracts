// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title FishToken
 * @dev ERC-20 reward token for the FishBase game.
 *
 * Security improvements:
 *  - setGameController() rejects the zero address
 *  - mintDailyReward() and mintLevelReward() have per-tx mint caps to prevent
 *    accidental or malicious over-minting
 */
contract FishToken is ERC20, Ownable, Pausable {

    /// @dev Hard cap: 1 billion FISH
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev Per-transaction mint safety cap (10 000 FISH)
    uint256 public constant MAX_MINT_PER_TX = 10_000 * 10 ** 18;

    /// @dev Only the GameController may call the mint functions
    address public gameController;

    /// @dev Tiered XP to token conversion rates
    mapping(uint256 => uint256) public xpToTokenRate;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event GameControllerUpdated(address indexed oldController, address indexed newController);
    event TokensMinted(address indexed to, uint256 amount, string reason);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(address initialOwner)
        ERC20("Fish Token", "FISH")
        Ownable(initialOwner)
    {
        // Tiered XP to FISH conversion
        xpToTokenRate[100]  = 10  * 10 ** 18;  //  100 XP to 10  FISH
        xpToTokenRate[500]  = 60  * 10 ** 18;  //  500 XP to 60  FISH
        xpToTokenRate[1000] = 150 * 10 ** 18;  // 1000 XP to 150 FISH
        xpToTokenRate[2500] = 400 * 10 ** 18;  // 2500 XP to 400 FISH
        xpToTokenRate[5000] = 900 * 10 ** 18;  // 5000 XP to 900 FISH
    }

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyGameController() {
        require(msg.sender == gameController, "Caller is not game controller");
        _;
    }

    // -----------------------------------------------------------------------
    // Administration
    // -----------------------------------------------------------------------

    /**
     * @dev Set the address that is allowed to mint tokens.
     *      The zero address is rejected to prevent accidentally locking minting.
     */
    function setGameController(address _gameController) external onlyOwner {
        require(_gameController != address(0), "Zero address not allowed");
        address old = gameController;
        gameController = _gameController;
        emit GameControllerUpdated(old, _gameController);
    }

    /**
     * @dev Update a single XP-tier conversion rate.
     */
    function updateXpToTokenRate(uint256 xpLevel, uint256 tokenAmount) external onlyOwner {
        xpToTokenRate[xpLevel] = tokenAmount;
    }

    // -----------------------------------------------------------------------
    // Minting (game controller only)
    // -----------------------------------------------------------------------

    /**
     * @dev Mint tokens proportional to the XP earned in a daily claim.
     */
    function mintDailyReward(address to, uint256 xpAmount) external onlyGameController whenNotPaused {
        require(to != address(0), "Zero address");
        require(xpAmount > 0,     "XP must be positive");

        uint256 tokenAmount = calculateTokenReward(xpAmount);
        require(tokenAmount <= MAX_MINT_PER_TX,             "Exceeds per-tx mint cap");
        require(totalSupply() + tokenAmount <= MAX_SUPPLY,  "Would exceed max supply");

        _mint(to, tokenAmount);
        emit TokensMinted(to, tokenAmount, "daily_reward");
    }

    /**
     * @dev Mint a level-up bonus.
     */
    function mintLevelReward(address to, uint256 level) external onlyGameController whenNotPaused {
        require(to    != address(0), "Zero address");
        require(level >  0,          "Level must be positive");

        uint256 tokenAmount = level * 50 * 10 ** 18;
        require(tokenAmount <= MAX_MINT_PER_TX,             "Exceeds per-tx mint cap");
        require(totalSupply() + tokenAmount <= MAX_SUPPLY,  "Would exceed max supply");

        _mint(to, tokenAmount);
        emit TokensMinted(to, tokenAmount, "level_reward");
    }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    /**
     * @dev Calculate the token reward for a given XP amount using tiered rates.
     */
    function calculateTokenReward(uint256 xpAmount) public view returns (uint256) {
        if (xpAmount >= 5000) return xpToTokenRate[5000];
        if (xpAmount >= 2500) return xpToTokenRate[2500];
        if (xpAmount >= 1000) return xpToTokenRate[1000];
        if (xpAmount >= 500)  return xpToTokenRate[500];
        if (xpAmount >= 100)  return xpToTokenRate[100];
        // Below 100 XP: 0.1 FISH per XP
        return xpAmount * 10 ** 17;
    }

    // -----------------------------------------------------------------------
    // Emergency controls
    // -----------------------------------------------------------------------

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /**
     * @dev Block transfers while paused.
     */
    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
