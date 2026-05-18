// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title BoatNFT
 * @dev ERC-721 boat NFTs for FishBase.
 *      Five tiers: Dinghy (free), Sailboat ($1), Yacht ($3), Trawler ($5), Mega Ship ($6.99).
 *
 *  Payment:
 *   - ETH (owner keeps ETH prices up to date via setEthPrice)
 *   - USDC (Base mainnet: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
 *
 *  Security:
 *   - mintBoat() mints only to msg.sender
 *   - withdraw() and refunds use call{} instead of transfer()
 */
contract BoatNFT is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable, Pausable, ReentrancyGuard {

    using Strings for uint256;

    // ── USDC ────────────────────────────────────────────────────────────────
    // USDC on Base mainnet (6 decimals)
    IERC20 public usdc;

    // ── Types ───────────────────────────────────────────────────────────────

    enum BoatType { DINGHY, SAILBOAT, YACHT, TRAWLER, MEGASHIP }

    struct BoatConfig {
        string  name;
        uint256 dailyXp;
        uint256 priceEth;    // in wei  (owner-adjustable as ETH price changes)
        uint256 priceUsdc;   // in USDC micro-units (6 decimals), e.g. 1_000_000 = $1
        uint256 maxSupply;
        uint256 currentSupply;
        string  baseURI;
    }

    struct BoatData {
        BoatType boatType;
        uint256  mintedAt;
        uint256  lastUsed;
        bool     isActive;
    }

    // ── State ───────────────────────────────────────────────────────────────

    mapping(BoatType => BoatConfig) public boatConfigs;
    mapping(uint256 => BoatData)    public boats;
    mapping(address => uint256)     public activeBoats;

    uint256 private _tokenIdCounter = 1;
    address public  gameController;

    // ── Events ──────────────────────────────────────────────────────────────

    event BoatMinted(address indexed to, uint256 indexed tokenId, BoatType boatType, bool paidWithUsdc);
    event BoatActivated(address indexed owner, uint256 indexed tokenId);
    event GameControllerUpdated(address indexed oldController, address indexed newController);
    event EthPriceUpdated(BoatType boatType, uint256 newPriceWei);
    event UsdcAddressUpdated(address newUsdc);

    // ── Constructor ─────────────────────────────────────────────────────────

    /// @param _usdc  USDC token address on the target chain
    constructor(address initialOwner, address _usdc)
        ERC721("FishBase Boats", "FBBOAT")
        Ownable(initialOwner)
    {
        require(_usdc != address(0), "Zero address: usdc");
        usdc = IERC20(_usdc);
        _initializeBoatConfigs();
    }

    function _initializeBoatConfigs() private {
        // Dinghy — free starter
        boatConfigs[BoatType.DINGHY] = BoatConfig({
            name:          "Dinghy",
            dailyXp:       10,
            priceEth:      0,
            priceUsdc:     0,
            maxSupply:     10_000,
            currentSupply: 0,
            baseURI:       "https://fishbase.xyz/metadata/dinghy/"
        });

        // Sailboat — $1
        // ~0.00034 ETH @ $3 000/ETH (owner adjusts via setEthPrice)
        boatConfigs[BoatType.SAILBOAT] = BoatConfig({
            name:          "Sailboat",
            dailyXp:       25,
            priceEth:      0.00034 ether,
            priceUsdc:     1_000_000,   // 1 USDC
            maxSupply:     5_000,
            currentSupply: 0,
            baseURI:       "https://fishbase.xyz/metadata/sailboat/"
        });

        // Yacht — $3
        boatConfigs[BoatType.YACHT] = BoatConfig({
            name:          "Yacht",
            dailyXp:       50,
            priceEth:      0.001 ether,
            priceUsdc:     3_000_000,   // 3 USDC
            maxSupply:     2_000,
            currentSupply: 0,
            baseURI:       "https://fishbase.xyz/metadata/yacht/"
        });

        // Trawler — $5
        boatConfigs[BoatType.TRAWLER] = BoatConfig({
            name:          "Trawler",
            dailyXp:       100,
            priceEth:      0.0017 ether,
            priceUsdc:     5_000_000,   // 5 USDC
            maxSupply:     500,
            currentSupply: 0,
            baseURI:       "https://fishbase.xyz/metadata/trawler/"
        });

        // Mega Ship — $6.99
        boatConfigs[BoatType.MEGASHIP] = BoatConfig({
            name:          "Mega Ship",
            dailyXp:       200,
            priceEth:      0.0023 ether,
            priceUsdc:     6_990_000,   // 6.99 USDC
            maxSupply:     100,
            currentSupply: 0,
            baseURI:       "https://fishbase.xyz/metadata/megaship/"
        });
    }

    // ── Modifiers ───────────────────────────────────────────────────────────

    modifier onlyGameController() {
        require(msg.sender == gameController, "Caller is not game controller");
        _;
    }

    // ── Administration ──────────────────────────────────────────────────────

    function setGameController(address _gameController) external onlyOwner {
        require(_gameController != address(0), "Zero address");
        address old = gameController;
        gameController = _gameController;
        emit GameControllerUpdated(old, _gameController);
    }

    /// @dev Update the ETH price for a boat type as the ETH/USD rate changes.
    function setEthPrice(BoatType boatType, uint256 priceWei) external onlyOwner {
        boatConfigs[boatType].priceEth = priceWei;
        emit EthPriceUpdated(boatType, priceWei);
    }

    /// @dev Update USDC contract address (e.g. if migrating chains).
    function setUsdcAddress(address _usdc) external onlyOwner {
        require(_usdc != address(0), "Zero address");
        usdc = IERC20(_usdc);
        emit UsdcAddressUpdated(_usdc);
    }

    function updateBoatConfig(
        BoatType boatType,
        string memory name,
        uint256 dailyXp,
        uint256 priceEth,
        uint256 priceUsdc,
        uint256 maxSupply,
        string memory baseURI
    ) external onlyOwner {
        BoatConfig storage cfg = boatConfigs[boatType];
        cfg.name      = name;
        cfg.dailyXp   = dailyXp;
        cfg.priceEth  = priceEth;
        cfg.priceUsdc = priceUsdc;
        cfg.maxSupply = maxSupply;
        cfg.baseURI   = baseURI;
    }

    /// @dev Withdraw accumulated ETH to owner.
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Nothing to withdraw");
        (bool ok, ) = payable(owner()).call{value: balance}("");
        require(ok, "Withdrawal failed");
    }

    /// @dev Withdraw accumulated USDC to owner.
    function withdrawUsdc() external onlyOwner {
        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, "No USDC to withdraw");
        require(usdc.transfer(owner(), balance), "USDC transfer failed");
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ── Public minting — pay with ETH ───────────────────────────────────────

    /**
     * @dev Mint a boat paying with ETH.
     *      Overpayments are refunded.
     */
    function mintBoat(BoatType boatType) external payable nonReentrant whenNotPaused {
        BoatConfig storage cfg = boatConfigs[boatType];
        require(cfg.currentSupply < cfg.maxSupply, "Max supply reached");
        require(msg.value >= cfg.priceEth,         "Insufficient ETH");

        uint256 tokenId = _mintBoatInternal(msg.sender, boatType, cfg);

        emit BoatMinted(msg.sender, tokenId, boatType, false);

        // Refund surplus ETH
        if (msg.value > cfg.priceEth) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - cfg.priceEth}("");
            require(ok, "Refund failed");
        }
    }

    // ── Public minting — pay with USDC ──────────────────────────────────────

    /**
     * @dev Mint a boat paying with USDC.
     *      Caller must approve this contract for at least priceUsdc USDC first.
     */
    function mintBoatWithUsdc(BoatType boatType) external nonReentrant whenNotPaused {
        BoatConfig storage cfg = boatConfigs[boatType];
        require(cfg.currentSupply < cfg.maxSupply, "Max supply reached");
        require(cfg.priceUsdc > 0,                 "USDC payment not configured");

        require(
            usdc.transferFrom(msg.sender, address(this), cfg.priceUsdc),
            "USDC transfer failed - did you approve?"
        );

        uint256 tokenId = _mintBoatInternal(msg.sender, boatType, cfg);

        emit BoatMinted(msg.sender, tokenId, boatType, true);
    }

    // ── Minting — game controller only ──────────────────────────────────────

    /**
     * @dev Mint a free Dinghy to a new player (called by GameController on register).
     */
    function mintStarterBoat(address to) external onlyGameController {
        require(to != address(0),   "Zero address");
        require(balanceOf(to) == 0, "Already has a boat");

        BoatConfig storage cfg = boatConfigs[BoatType.DINGHY];
        require(cfg.currentSupply < cfg.maxSupply, "Dinghy supply exhausted");

        uint256 tokenId = _tokenIdCounter++;

        boats[tokenId] = BoatData({
            boatType: BoatType.DINGHY,
            mintedAt: block.timestamp,
            lastUsed: 0,
            isActive: true
        });

        cfg.currentSupply++;
        activeBoats[to] = tokenId;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, string.concat(cfg.baseURI, tokenId.toString(), ".json"));

        emit BoatMinted(to, tokenId, BoatType.DINGHY, false);
        emit BoatActivated(to, tokenId);
    }

    // ── Activation ──────────────────────────────────────────────────────────

    function activateBoat(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not the boat owner");

        uint256 current = activeBoats[msg.sender];
        if (current != 0 && current != tokenId) {
            boats[current].isActive = false;
        }

        activeBoats[msg.sender]  = tokenId;
        boats[tokenId].isActive  = true;
        boats[tokenId].lastUsed  = block.timestamp;

        emit BoatActivated(msg.sender, tokenId);
    }

    // ── View helpers ─────────────────────────────────────────────────────────

    function getActiveBoat(address user) external view returns (
        uint256      tokenId,
        BoatType     boatType,
        uint256      dailyXp,
        string memory name
    ) {
        tokenId = activeBoats[user];
        if (tokenId == 0) return (0, BoatType.DINGHY, 0, "");

        BoatData   memory boat = boats[tokenId];
        BoatConfig memory cfg  = boatConfigs[boat.boatType];

        return (tokenId, boat.boatType, cfg.dailyXp, cfg.name);
    }

    function getBoatConfig(BoatType boatType) external view returns (BoatConfig memory) {
        return boatConfigs[boatType];
    }

    // ── Internal helpers ────────────────────────────────────────────────────

    function _mintBoatInternal(
        address       to,
        BoatType      boatType,
        BoatConfig storage cfg
    ) internal returns (uint256 tokenId) {
        tokenId = _tokenIdCounter++;

        boats[tokenId] = BoatData({
            boatType: boatType,
            mintedAt: block.timestamp,
            lastUsed: 0,
            isActive: false
        });

        cfg.currentSupply++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, string.concat(cfg.baseURI, tokenId.toString(), ".json"));

        // Auto-activate if no active boat yet
        if (activeBoats[to] == 0) {
            activeBoats[to]         = tokenId;
            boats[tokenId].isActive = true;
            emit BoatActivated(to, tokenId);
        }
    }

    // ── ERC-721 overrides ───────────────────────────────────────────────────

    function _update(address to, uint256 tokenId, address auth)
        internal override(ERC721, ERC721Enumerable) returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public view override(ERC721, ERC721URIStorage) returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, ERC721Enumerable, ERC721URIStorage) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
