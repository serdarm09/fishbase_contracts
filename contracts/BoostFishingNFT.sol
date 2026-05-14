// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title FishBase Boost NFT Collection
/// @notice Three boost tiers (+20%, +30%, +40%) that permanently enhance a captain's XP rate while held.
contract BoostFishingNFT is ERC1155, Ownable, ReentrancyGuard {
    struct BoostTier {
        string name;
        uint256 multiplierBps; // basis points, e.g. 2000 = 20%
        uint256 price; // in wei
        string metadataURI;
        bool enabled;
    }

    mapping(uint256 => BoostTier) private _boosts;
    mapping(address => mapping(uint256 => bool)) public hasMinted; // wallet => boostId => minted

    event BoostMinted(address indexed account, uint256 indexed boostId, uint256 pricePaid);
    event BoostUpdated(uint256 indexed boostId, string name, uint256 multiplierBps, uint256 price, bool enabled);
    event BaseURIUpdated(string newBaseURI);

    constructor(string memory baseURI, address initialOwner) ERC1155(baseURI) Ownable(initialOwner) {
        _boosts[1] = BoostTier({
            name: "Bronze Hook",
            multiplierBps: 2000,
            price: 1_000_000_000_000_000, // 0.001 ETH
            metadataURI: "ipfs://boost-level-1.json",
            enabled: true
        });
        _boosts[2] = BoostTier({
            name: "Silver Reel",
            multiplierBps: 3000,
            price: 1_500_000_000_000_000, // 0.0015 ETH
            metadataURI: "ipfs://boost-level-2.json",
            enabled: true
        });
        _boosts[3] = BoostTier({
            name: "Golden Net",
            multiplierBps: 4000,
            price: 2_000_000_000_000_000, // 0.002 ETH
            metadataURI: "ipfs://boost-level-3.json",
            enabled: true
        });
    }

    /// @notice Mint a single boost tier. Each wallet can only mint a specific tier once.
    function mintBoost(uint256 boostId) external payable nonReentrant {
        BoostTier memory tier = _requireBoost(boostId);
        require(!hasMinted[_msgSender()][boostId], "Boost already owned");
        require(msg.value == tier.price, "Incorrect price");

        hasMinted[_msgSender()][boostId] = true;
        _mint(_msgSender(), boostId, 1, "");

        emit BoostMinted(_msgSender(), boostId, msg.value);
    }

    /// @notice Owner can airdrop boosts (e.g. rewards, partners).
    function airdrop(address to, uint256 boostId) external onlyOwner {
        _requireBoost(boostId);
        _mint(to, boostId, 1, "");
    }

    /// @notice Update core attributes for a boost tier.
    function configureBoost(
        uint256 boostId,
        string calldata name,
        uint256 multiplierBps,
        uint256 price,
        bool enabled,
        string calldata metadataURI
    ) external onlyOwner {
        require(multiplierBps <= 5000, "Multiplier too high");
        require(price <= 1 ether, "Price guard");

        _boosts[boostId] = BoostTier({
            name: name,
            multiplierBps: multiplierBps,
            price: price,
            metadataURI: metadataURI,
            enabled: enabled
        });

        emit BoostUpdated(boostId, name, multiplierBps, price, enabled);
    }

    /// @notice Withdraw collected ETH to the contract owner.
    function withdraw(address payable recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        uint256 balance = address(this).balance;
        require(balance > 0, "Nothing to withdraw");
        recipient.transfer(balance);
    }

    /// @notice Set a new base URI for metadata (e.g. IPFS gateway).
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _setURI(newBaseURI);
        emit BaseURIUpdated(newBaseURI);
    }

    /// @notice Return a boost tier definition.
    function getBoost(uint256 boostId) external view returns (BoostTier memory) {
        return _requireBoost(boostId);
    }

    /// @inheritdoc ERC1155
    function uri(uint256 boostId) public view override returns (string memory) {
        BoostTier memory tier = _requireBoost(boostId);
        return tier.metadataURI;
    }

    function _requireBoost(uint256 boostId) internal view returns (BoostTier memory) {
        BoostTier memory tier = _boosts[boostId];
        require(bytes(tier.name).length > 0, "Unknown boost");
        require(tier.enabled, "Boost disabled");
        return tier;
    }
}
