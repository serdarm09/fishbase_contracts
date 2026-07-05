const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FishQuest Game Contracts", function () {
  let fishToken, boatNFT, gameController;
  let owner, player1, player2;

  beforeEach(async function () {
    [owner, player1, player2] = await ethers.getSigners();

    // Deploy Fish Token
    const FishToken = await ethers.getContractFactory("FishToken");
    fishToken = await FishToken.deploy(owner.address);
    await fishToken.waitForDeployment();

    // Deploy Boat NFT
    const BoatNFT = await ethers.getContractFactory("BoatNFT");
    boatNFT = await BoatNFT.deploy(owner.address, owner.address);
    await boatNFT.waitForDeployment();

    // Deploy Game Controller
    const GameController = await ethers.getContractFactory("GameController");
    gameController = await GameController.deploy(
      await fishToken.getAddress(),
      await boatNFT.getAddress(),
      owner.address
    );
    await gameController.waitForDeployment();

    // Set up permissions
    await fishToken.setGameController(await gameController.getAddress());
    await boatNFT.setGameController(await gameController.getAddress());
  });

  describe("Fish Token", function () {
    it("Should have correct name and symbol", async function () {
      expect(await fishToken.name()).to.equal("Fish Token");
      expect(await fishToken.symbol()).to.equal("FISH");
    });

    it("Should mint daily rewards correctly", async function () {
      const xpAmount = 100;
      await fishToken.setGameController(owner.address);
      await fishToken.mintDailyReward(player1.address, xpAmount);
      
      const balance = await fishToken.balanceOf(player1.address);
      const expectedTokens = await fishToken.calculateTokenReward(xpAmount);
      expect(balance).to.equal(expectedTokens);
    });

    it("Should calculate token rewards correctly", async function () {
      expect(await fishToken.calculateTokenReward(50)).to.equal(ethers.parseEther("5")); // 0.1 FISH per XP
      expect(await fishToken.calculateTokenReward(100)).to.equal(ethers.parseEther("10"));
      expect(await fishToken.calculateTokenReward(500)).to.equal(ethers.parseEther("60"));
    });
  });

  describe("Boat NFT", function () {
    it("Should mint starter boat correctly", async function () {
      await boatNFT.setGameController(owner.address);
      await boatNFT.mintStarterBoat(player1.address);
      
      expect(await boatNFT.balanceOf(player1.address)).to.equal(1);
      expect(await boatNFT.ownerOf(1)).to.equal(player1.address);
      
      const activeBoat = await boatNFT.getActiveBoat(player1.address);
      expect(activeBoat.tokenId).to.equal(1);
      expect(activeBoat.boatType).to.equal(0); // DINGHY
    });

    it("Should mint paid boats correctly", async function () {
      const sailboatPrice = ethers.parseEther("0.00034");
      
      await boatNFT.connect(player1).mintBoat(1, { // SAILBOAT
        value: sailboatPrice
      });
      
      expect(await boatNFT.balanceOf(player1.address)).to.equal(1);
      
      const activeBoat = await boatNFT.getActiveBoat(player1.address);
      expect(activeBoat.boatType).to.equal(1); // SAILBOAT
      expect(activeBoat.dailyXp).to.equal(25);
    });

    it("Should activate boats correctly", async function () {
      // Mint starter boat
      await boatNFT.setGameController(owner.address);
      await boatNFT.mintStarterBoat(player1.address);
      
      // Mint sailboat
      const sailboatPrice = ethers.parseEther("0.00034");
      await boatNFT.connect(player1).mintBoat(1, {
        value: sailboatPrice
      });
      
      // Activate sailboat
      await boatNFT.connect(player1).activateBoat(2);
      
      const activeBoat = await boatNFT.getActiveBoat(player1.address);
      expect(activeBoat.tokenId).to.equal(2);
      expect(activeBoat.boatType).to.equal(1); // SAILBOAT
    });
  });

  describe("Game Controller", function () {
    beforeEach(async function () {
      // Register players and give them starter boats
      await gameController.connect(player1).registerPlayer();
      await gameController.connect(player2).registerPlayer();
    });

    it("Should register players correctly", async function () {
      const playerInfo = await gameController.getPlayerInfo(player1.address);
      expect(playerInfo.totalXp).to.equal(0);
      expect(playerInfo.currentStreak).to.equal(0);
      expect(playerInfo.hasPosition).to.equal(false);
    });

    it("Should place boats on map", async function () {
      const placementFee = ethers.parseEther("0.001");
      
      await gameController.connect(player1).placeBoat(10, 20, {
        value: placementFee
      });
      
      const playerInfo = await gameController.getPlayerInfo(player1.address);
      expect(playerInfo.hasPosition).to.equal(true);
      expect(playerInfo.mapX).to.equal(10);
      expect(playerInfo.mapY).to.equal(20);
      
      const boatAtPosition = await gameController.getBoatAtPosition(10, 20);
      expect(boatAtPosition.owner).to.equal(player1.address);
    });

    it("Should prevent placing boats on occupied positions", async function () {
      const placementFee = ethers.parseEther("0.001");
      
      // Player 1 places boat
      await gameController.connect(player1).placeBoat(10, 20, {
        value: placementFee
      });
      
      // Player 2 tries to place on same position
      await expect(
        gameController.connect(player2).placeBoat(10, 20, {
          value: placementFee
        })
      ).to.be.revertedWith("Position already occupied");
    });

    it("Should move boats correctly", async function () {
      const placementFee = ethers.parseEther("0.001");
      
      // Place boat
      await gameController.connect(player1).placeBoat(10, 20, {
        value: placementFee
      });
      
      // Move boat
      await gameController.connect(player1).moveBoat(15, 25, {
        value: placementFee
      });
      
      const playerInfo = await gameController.getPlayerInfo(player1.address);
      expect(playerInfo.mapX).to.equal(15);
      expect(playerInfo.mapY).to.equal(25);
      
      // Old position should be empty
      const oldPosition = await gameController.getBoatAtPosition(10, 20);
      expect(oldPosition.owner).to.equal(ethers.ZeroAddress);
      
      // New position should have the boat
      const newPosition = await gameController.getBoatAtPosition(15, 25);
      expect(newPosition.owner).to.equal(player1.address);
    });

    it("Should handle daily claims correctly", async function () {
      const placementFee = ethers.parseEther("0.001");
      
      // Place boat
      await gameController.connect(player1).placeBoat(10, 20, {
        value: placementFee
      });
      
      // Claim daily reward
      await gameController.connect(player1).claimDaily();
      
      const playerInfo = await gameController.getPlayerInfo(player1.address);
      expect(playerInfo.totalXp).to.be.gt(0);
      expect(playerInfo.currentStreak).to.equal(1);
      
      // Check FISH token balance
      const fishBalance = await fishToken.balanceOf(player1.address);
      expect(fishBalance).to.be.gt(0);
    });

    it("Should calculate streak multipliers correctly", async function () {
      expect(await gameController.calculateStreakMultiplier(1)).to.equal(100);  // 1x
      expect(await gameController.calculateStreakMultiplier(7)).to.equal(200);  // 2x
      expect(await gameController.calculateStreakMultiplier(14)).to.equal(300); // 3x
      expect(await gameController.calculateStreakMultiplier(30)).to.equal(500); // 5x
      expect(await gameController.calculateStreakMultiplier(100)).to.equal(1000); // 10x
    });

    it("Should prevent claiming twice in 24 hours", async function () {
      const placementFee = ethers.parseEther("0.001");
      
      // Place boat and claim
      await gameController.connect(player1).placeBoat(10, 20, {
        value: placementFee
      });
      await gameController.connect(player1).claimDaily();
      
      // Try to claim again immediately
      await expect(
        gameController.connect(player1).claimDaily()
      ).to.be.revertedWith("Claim not ready yet");
    });
  });

  describe("Integration Tests", function () {
    it("Should handle complete game flow", async function () {
      const placementFee = ethers.parseEther("0.001");
      
      // 1. Register player
      await gameController.connect(player1).registerPlayer();
      
      // 2. Check starter boat
      expect(await boatNFT.balanceOf(player1.address)).to.equal(1);
      
      // 3. Place boat on map
      await gameController.connect(player1).placeBoat(50, 50, {
        value: placementFee
      });
      
      // 4. Claim daily reward
      await gameController.connect(player1).claimDaily();
      
      // 5. Check rewards
      const playerInfo = await gameController.getPlayerInfo(player1.address);
      expect(playerInfo.totalXp).to.be.gt(0);
      expect(playerInfo.currentStreak).to.equal(1);
      
      const fishBalance = await fishToken.balanceOf(player1.address);
      expect(fishBalance).to.be.gt(0);
      
      // 6. Move boat
      await gameController.connect(player1).moveBoat(60, 60, {
        value: placementFee
      });
      
      const updatedInfo = await gameController.getPlayerInfo(player1.address);
      expect(updatedInfo.mapX).to.equal(60);
      expect(updatedInfo.mapY).to.equal(60);
    });
  });
});
