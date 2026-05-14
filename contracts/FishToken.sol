// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title FishToken
 * @dev ERC20 token for FishQuest game rewards
 */
contract FishToken is ERC20, Ownable, Pausable {
    // Maximum supply: 1 billion tokens
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    
    // Game controller address that can mint tokens
    address public gameController;
    
    // Daily reward rates based on XP levels
    mapping(uint256 => uint256) public xpToTokenRate;
    
    event GameControllerUpdated(address indexed oldController, address indexed newController);
    event TokensMinted(address indexed to, uint256 amount, string reason);
    
    constructor(
        address initialOwner
    ) ERC20("Fish Token", "FISH") Ownable(initialOwner) {
        // Set initial XP to token conversion rates
        xpToTokenRate[100] = 10 * 10**18;   // 100 XP = 10 FISH
        xpToTokenRate[500] = 60 * 10**18;   // 500 XP = 60 FISH  
        xpToTokenRate[1000] = 150 * 10**18; // 1000 XP = 150 FISH
        xpToTokenRate[2500] = 400 * 10**18; // 2500 XP = 400 FISH
        xpToTokenRate[5000] = 900 * 10**18; // 5000 XP = 900 FISH
    }
    
    modifier onlyGameController() {
        require(msg.sender == gameController, "Only game controller can call this");
        _;
    }
    
    /**
     * @dev Set the game controller address
     */
    function setGameController(address _gameController) external onlyOwner {
        address oldController = gameController;
        gameController = _gameController;
        emit GameControllerUpdated(oldController, _gameController);
    }
    
    /**
     * @dev Mint tokens for daily rewards
     */
    function mintDailyReward(address to, uint256 xpAmount) external onlyGameController whenNotPaused {
        require(to != address(0), "Cannot mint to zero address");
        require(xpAmount > 0, "XP amount must be positive");
        
        uint256 tokenAmount = calculateTokenReward(xpAmount);
        require(totalSupply() + tokenAmount <= MAX_SUPPLY, "Would exceed max supply");
        
        _mint(to, tokenAmount);
        emit TokensMinted(to, tokenAmount, "daily_reward");
    }
    
    /**
     * @dev Mint tokens for level up rewards
     */
    function mintLevelReward(address to, uint256 level) external onlyGameController whenNotPaused {
        require(to != address(0), "Cannot mint to zero address");
        require(level > 0, "Level must be positive");
        
        // Level up bonus: level * 50 FISH
        uint256 tokenAmount = level * 50 * 10**18;
        require(totalSupply() + tokenAmount <= MAX_SUPPLY, "Would exceed max supply");
        
        _mint(to, tokenAmount);
        emit TokensMinted(to, tokenAmount, "level_reward");
    }
    
    /**
     * @dev Calculate token reward based on XP
     */
    function calculateTokenReward(uint256 xpAmount) public view returns (uint256) {
        if (xpAmount >= 5000) return xpToTokenRate[5000];
        if (xpAmount >= 2500) return xpToTokenRate[2500];
        if (xpAmount >= 1000) return xpToTokenRate[1000];
        if (xpAmount >= 500) return xpToTokenRate[500];
        if (xpAmount >= 100) return xpToTokenRate[100];
        
        // For XP below 100, linear calculation: 1 XP = 0.1 FISH
        return xpAmount * 10**17; // 0.1 FISH per XP
    }
    
    /**
     * @dev Update XP to token conversion rate
     */
    function updateXpToTokenRate(uint256 xpLevel, uint256 tokenAmount) external onlyOwner {
        xpToTokenRate[xpLevel] = tokenAmount;
    }
    
    /**
     * @dev Pause token transfers (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause token transfers
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Override transfer to add pause functionality
     */
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }
}
