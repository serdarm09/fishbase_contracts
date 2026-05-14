// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BoatNFT
 * @dev NFT contract for FishQuest game boats
 */
contract BoatNFT is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable, Pausable, ReentrancyGuard {
    
    enum BoatType { DINGHY, SAILBOAT, YACHT, TRAWLER, MEGASHIP }
    
    struct BoatConfig {
        string name;
        uint256 dailyXp;
        uint256 price;
        uint256 maxSupply;
        uint256 currentSupply;
        string baseURI;
    }
    
    struct BoatData {
        BoatType boatType;
        uint256 mintedAt;
        uint256 lastUsed;
        bool isActive;
    }
    
    // Boat configurations
    mapping(BoatType => BoatConfig) public boatConfigs;
    
    // Token ID to boat data
    mapping(uint256 => BoatData) public boats;
    
    // User to active boat mapping
    mapping(address => uint256) public activeBoats;
    
    // Current token ID counter
    uint256 private _tokenIdCounter = 1;
    
    // Game controller address
    address public gameController;
    
    // Events
    event BoatMinted(address indexed to, uint256 indexed tokenId, BoatType boatType);
    event BoatActivated(address indexed owner, uint256 indexed tokenId);
    event GameControllerUpdated(address indexed oldController, address indexed newController);
    
    constructor(
        address initialOwner
    ) ERC721("FishQuest Boats", "FQBOAT") Ownable(initialOwner) {
        _initializeBoatConfigs();
    }
    
    function _initializeBoatConfigs() private {
        // Dinghy - Starter boat (free)
        boatConfigs[BoatType.DINGHY] = BoatConfig({
            name: "Dinghy",
            dailyXp: 10,
            price: 0,
            maxSupply: 10000,
            currentSupply: 0,
            baseURI: "https://fishquest.io/metadata/dinghy/"
        });
        
        // Sailboat - 10% XP boost
        boatConfigs[BoatType.SAILBOAT] = BoatConfig({
            name: "Sailboat", 
            dailyXp: 25,
            price: 0.025 ether,
            maxSupply: 5000,
            currentSupply: 0,
            baseURI: "https://fishquest.io/metadata/sailboat/"
        });
        
        // Yacht - 30% XP boost
        boatConfigs[BoatType.YACHT] = BoatConfig({
            name: "Yacht",
            dailyXp: 50,
            price: 0.05 ether,
            maxSupply: 2000,
            currentSupply: 0,
            baseURI: "https://fishquest.io/metadata/yacht/"
        });
        
        // Trawler - 50% XP boost
        boatConfigs[BoatType.TRAWLER] = BoatConfig({
            name: "Trawler",
            dailyXp: 100,
            price: 0.1 ether,
            maxSupply: 500,
            currentSupply: 0,
            baseURI: "https://fishquest.io/metadata/trawler/"
        });
        
        // Megaship - 100% XP boost (legendary)
        boatConfigs[BoatType.MEGASHIP] = BoatConfig({
            name: "Mega Ship",
            dailyXp: 200,
            price: 0.2 ether,
            maxSupply: 100,
            currentSupply: 0,
            baseURI: "https://fishquest.io/metadata/megaship/"
        });
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
     * @dev Mint a new boat NFT
     */
    function mintBoat(address to, BoatType boatType) external payable nonReentrant whenNotPaused {
        require(to != address(0), "Cannot mint to zero address");
        
        BoatConfig storage config = boatConfigs[boatType];
        require(config.currentSupply < config.maxSupply, "Max supply reached for this boat type");
        require(msg.value >= config.price, "Insufficient payment");
        
        uint256 tokenId = _tokenIdCounter++;
        
        // Create boat data
        boats[tokenId] = BoatData({
            boatType: boatType,
            mintedAt: block.timestamp,
            lastUsed: 0,
            isActive: false
        });
        
        // Update supply
        config.currentSupply++;
        
        // Mint the NFT
        _safeMint(to, tokenId);
        
        // Set token URI
        string memory uri = string(abi.encodePacked(config.baseURI, _toString(tokenId), ".json"));
        _setTokenURI(tokenId, uri);
        
        // If user doesn't have an active boat, make this one active
        if (activeBoats[to] == 0) {
            activeBoats[to] = tokenId;
            boats[tokenId].isActive = true;
            emit BoatActivated(to, tokenId);
        }
        
        emit BoatMinted(to, tokenId, boatType);
        
        // Refund excess payment
        if (msg.value > config.price) {
            payable(msg.sender).transfer(msg.value - config.price);
        }
    }
    
    /**
     * @dev Mint starter boat (free dinghy for new players)
     */
    function mintStarterBoat(address to) external onlyGameController {
        require(to != address(0), "Cannot mint to zero address");
        require(balanceOf(to) == 0, "User already has a boat");
        
        BoatConfig storage config = boatConfigs[BoatType.DINGHY];
        require(config.currentSupply < config.maxSupply, "Max supply reached for dinghy");
        
        uint256 tokenId = _tokenIdCounter++;
        
        boats[tokenId] = BoatData({
            boatType: BoatType.DINGHY,
            mintedAt: block.timestamp,
            lastUsed: 0,
            isActive: true
        });
        
        config.currentSupply++;
        activeBoats[to] = tokenId;
        
        _safeMint(to, tokenId);
        
        string memory uri = string(abi.encodePacked(config.baseURI, _toString(tokenId), ".json"));
        _setTokenURI(tokenId, uri);
        
        emit BoatMinted(to, tokenId, BoatType.DINGHY);
        emit BoatActivated(to, tokenId);
    }
    
    /**
     * @dev Activate a boat (set as primary)
     */
    function activateBoat(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this boat");
        
        // Deactivate current active boat
        uint256 currentActive = activeBoats[msg.sender];
        if (currentActive != 0) {
            boats[currentActive].isActive = false;
        }
        
        // Activate new boat
        activeBoats[msg.sender] = tokenId;
        boats[tokenId].isActive = true;
        boats[tokenId].lastUsed = block.timestamp;
        
        emit BoatActivated(msg.sender, tokenId);
    }
    
    /**
     * @dev Get user's active boat info
     */
    function getActiveBoat(address user) external view returns (
        uint256 tokenId,
        BoatType boatType,
        uint256 dailyXp,
        string memory name
    ) {
        tokenId = activeBoats[user];
        if (tokenId == 0) {
            return (0, BoatType.DINGHY, 0, "");
        }
        
        BoatData memory boat = boats[tokenId];
        BoatConfig memory config = boatConfigs[boat.boatType];
        
        return (tokenId, boat.boatType, config.dailyXp, config.name);
    }
    
    /**
     * @dev Get boat configuration
     */
    function getBoatConfig(BoatType boatType) external view returns (BoatConfig memory) {
        return boatConfigs[boatType];
    }
    
    /**
     * @dev Update boat configuration (owner only)
     */
    function updateBoatConfig(
        BoatType boatType,
        string memory name,
        uint256 dailyXp,
        uint256 price,
        uint256 maxSupply,
        string memory baseURI
    ) external onlyOwner {
        BoatConfig storage config = boatConfigs[boatType];
        config.name = name;
        config.dailyXp = dailyXp;
        config.price = price;
        config.maxSupply = maxSupply;
        config.baseURI = baseURI;
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
    
    // Helper function to convert uint to string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    // Required overrides
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
