// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BoostFishingNFT
 * @dev ERC-1155 boost NFT collection for FishBase.
 *      Three tiers: Bronze (+20 %), Silver (+30 %), Golden (+40 %).
 *
 * Security improvements:
 *  - mintBoost() accepts overpayment and refunds the surplus (using call{})
 *  - withdraw() uses call{} instead of transfer()
 *  - Contract can be paused in an emergency
 */
contract BoostFishingNFT is ERC1155, Ownable, Pausable, ReentrancyGuard {

    struct BoostTier {
        string  name;
        uint256 multiplierBps; // basis points, e.g. 2000 = 20 %
        uint256 price;         // in wei
        string  metadataURI;
        bool    enabled;
    }

    /// @dev boostId to tier definition
    mapping(uint256 => BoostTier)                      private _boosts;

    /// @dev wallet to boostId to already minted (one per wallet per tier)
    mapping(address => mapping(uint256 => bool)) public hasMinted;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event BoostMinted(address indexed account, uint256 indexed boostId, uint256 pricePaid);
    event BoostUpdated(uint256 indexed boostId, string name, uint256 multiplierBps, uint256 price, bool enabled);
    event BaseURIUpdated(string newBaseURI);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(string memory baseURI, address initialOwner)
        ERC1155(baseURI)
        Ownable(initialOwner)
    {
        _boosts[1] = BoostTier({
            name:          "Bronze Hook",
            multiplierBps: 2000,
            price:         0.001 ether,
            metadataURI:   "ipfs://boost-level-1.json",
            enabled:       true
        });
        _boosts[2] = BoostTier({
            name:          "Silver Reel",
            multiplierBps: 3000,
            price:         0.0015 ether,
            metadataURI:   "ipfs://boost-level-2.json",
            enabled:       true
        });
        _boosts[3] = BoostTier({
            name:          "Golden Net",
            multiplierBps: 4000,
            price:         0.002 ether,
            metadataURI:   "ipfs://boost-level-3.json",
            enabled:       true
        });
    }

    // -----------------------------------------------------------------------
    // Minting
    // -----------------------------------------------------------------------

    /**
     * @dev Mint a single boost tier NFT.
     *      Each wallet may own at most one NFT per tier.
     *      Overpayments are automatically refunded.
     */
    function mintBoost(uint256 boostId) external payable nonReentrant whenNotPaused {
        BoostTier memory tier = _requireBoost(boostId);
        require(!hasMinted[_msgSender()][boostId], "Boost already owned");
        require(msg.value >= tier.price,            "Insufficient payment");

        hasMinted[_msgSender()][boostId] = true;
        _mint(_msgSender(), boostId, 1, "");

        emit BoostMinted(_msgSender(), boostId, tier.price);

        // Refund any overpayment
        if (msg.value > tier.price) {
            (bool ok, ) = payable(_msgSender()).call{value: msg.value - tier.price}("");
            require(ok, "Refund failed");
        }
    }

    /**
     * @dev Owner can airdrop boost NFTs (e.g. for rewards or partners).
     */
    function airdrop(address to, uint256 boostId) external onlyOwner {
        require(to != address(0), "Zero address");
        _requireBoost(boostId);
        _mint(to, boostId, 1, "");
    }

    // -----------------------------------------------------------------------
    // Administration
    // -----------------------------------------------------------------------

    /**
     * @dev Update boost tier parameters.
     */
    function configureBoost(
        uint256        boostId,
        string calldata name,
        uint256        multiplierBps,
        uint256        price,
        bool           enabled,
        string calldata metadataURI
    ) external onlyOwner {
        require(multiplierBps <= 5000, "Multiplier too high");
        require(price         <= 1 ether, "Price guard");

        _boosts[boostId] = BoostTier({
            name:          name,
            multiplierBps: multiplierBps,
            price:         price,
            metadataURI:   metadataURI,
            enabled:       enabled
        });

        emit BoostUpdated(boostId, name, multiplierBps, price, enabled);
    }

    /**
     * @dev Withdraw collected ETH to a specified recipient.
     *      Uses call{} to avoid the 2300-gas limit of transfer().
     */
    function withdraw(address payable recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        uint256 balance = address(this).balance;
        require(balance > 0, "Nothing to withdraw");

        (bool ok, ) = recipient.call{value: balance}("");
        require(ok, "Withdrawal failed");
    }

    /**
     * @dev Update the base URI for metadata.
     */
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _setURI(newBaseURI);
        emit BaseURIUpdated(newBaseURI);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    function getBoost(uint256 boostId) external view returns (BoostTier memory) {
        return _requireBoost(boostId);
    }

    /// @inheritdoc ERC1155
    function uri(uint256 boostId) public view override returns (string memory) {
        BoostTier memory tier = _requireBoost(boostId);
        return tier.metadataURI;
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    function _requireBoost(uint256 boostId) internal view returns (BoostTier memory) {
        BoostTier memory tier = _boosts[boostId];
        require(bytes(tier.name).length > 0, "Unknown boost");
        require(tier.enabled,                "Boost disabled");
        return tier;
    }
}
