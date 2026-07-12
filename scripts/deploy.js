const fs   = require('fs');
const path = require('path');
const hre  = require('hardhat');

const { ethers, network } = hre;

// Helper: wait between transactions to avoid in-flight limits.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  console.log('\nFishBase deployment starting...');
  console.log('Network:', network.name);

  const [deployer] = await ethers.getSigners();
  console.log('Deployer:', deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log('Balance:', ethers.formatEther(balance), 'ETH\n');

  const redeployAll = process.env.REDEPLOY_ALL_CONTRACTS === 'true';
  const redeployFishToken = redeployAll || process.env.REDEPLOY_FISH_TOKEN === 'true';
  const redeployBoatNFT = redeployAll || process.env.REDEPLOY_BOAT_NFT === 'true';
  const redeployBoostFishingNFT = redeployAll || process.env.REDEPLOY_BOOST_NFT === 'true';
  const redeployGameController =
    redeployAll ||
    redeployFishToken ||
    redeployBoatNFT ||
    process.env.REDEPLOY_GAME_CONTROLLER === 'true';

  // Resume a previous partial deployment if one exists.
  const deploymentsDir = path.join(__dirname, '..', 'deployments');
  const deploymentFile = path.join(deploymentsDir, `${network.name}.json`);
  let existing = {};
  if (fs.existsSync(deploymentFile)) {
    try {
      existing = JSON.parse(fs.readFileSync(deploymentFile, 'utf8'));
      console.log('Existing deployment found, resuming...');
    } catch (_) {}
  }

  // 1. FishToken
  let fishTokenAddress = redeployFishToken ? undefined : existing?.contracts?.FishToken?.address;
  if (fishTokenAddress) {
    console.log('FishToken already deployed:', fishTokenAddress);
  } else {
    if (redeployFishToken && existing?.contracts?.FishToken?.address) {
      console.log('Redeploying FishToken, ignoring existing address:', existing.contracts.FishToken.address);
    }
    console.log('Deploying FishToken...');
    const FishToken = await ethers.getContractFactory('FishToken');
    const fishToken = await FishToken.deploy(deployer.address);
    await fishToken.waitForDeployment();
    fishTokenAddress = await fishToken.getAddress();
    console.log('FishToken:', fishTokenAddress);
    await sleep(3000);
  }

  // 2. BoatNFT
  const configuredUsdcAddress = process.env.USDC_ADDRESS;
  const boatUsdcAddress = configuredUsdcAddress || existing?.contracts?.BoatNFT?.constructorArgs?.[1];
  let boatNFTAddress = redeployBoatNFT ? undefined : existing?.contracts?.BoatNFT?.address;
  if (boatNFTAddress) {
    console.log('BoatNFT already deployed:', boatNFTAddress);
  } else {
    if (redeployBoatNFT && existing?.contracts?.BoatNFT?.address) {
      console.log('Redeploying BoatNFT, ignoring existing address:', existing.contracts.BoatNFT.address);
    }
    if (!boatUsdcAddress) {
      throw new Error('USDC_ADDRESS is required to deploy BoatNFT');
    }

    console.log('Deploying BoatNFT...');
    const BoatNFT = await ethers.getContractFactory('BoatNFT');
    const boatNFT = await BoatNFT.deploy(deployer.address, boatUsdcAddress);
    await boatNFT.waitForDeployment();
    boatNFTAddress = await boatNFT.getAddress();
    console.log('BoatNFT:', boatNFTAddress);
    await sleep(3000);
  }

  // 3. GameController
  let gameControllerAddress = redeployGameController ? undefined : existing?.contracts?.GameController?.address;
  if (gameControllerAddress) {
    console.log('GameController already deployed:', gameControllerAddress);
  } else {
    if (redeployGameController && existing?.contracts?.GameController?.address) {
      console.log('Redeploying GameController, ignoring existing address:', existing.contracts.GameController.address);
    }
    console.log('Deploying GameController...');
    const GameController = await ethers.getContractFactory('GameController');
    const gameController = await GameController.deploy(
      fishTokenAddress,
      boatNFTAddress,
      deployer.address
    );
    await gameController.waitForDeployment();
    gameControllerAddress = await gameController.getAddress();
    console.log('GameController:', gameControllerAddress);
    await sleep(3000);
  }

  // 4. BoostFishingNFT
  const boostBaseUri = process.env.BOOST_BASE_URI || existing?.contracts?.BoostFishingNFT?.constructorArgs?.[0] || '';
  let boostFishingNFTAddress = redeployBoostFishingNFT ? undefined : existing?.contracts?.BoostFishingNFT?.address;
  if (boostFishingNFTAddress) {
    console.log('BoostFishingNFT already deployed:', boostFishingNFTAddress);
  } else {
    if (redeployBoostFishingNFT && existing?.contracts?.BoostFishingNFT?.address) {
      console.log('Redeploying BoostFishingNFT, ignoring existing address:', existing.contracts.BoostFishingNFT.address);
    }
    console.log('Deploying BoostFishingNFT...');
    const BoostFishingNFT = await ethers.getContractFactory('BoostFishingNFT');
    const boostFishingNFT = await BoostFishingNFT.deploy(boostBaseUri, deployer.address);
    await boostFishingNFT.waitForDeployment();
    boostFishingNFTAddress = await boostFishingNFT.getAddress();
    console.log('BoostFishingNFT:', boostFishingNFTAddress);
    await sleep(3000);
  }

  // 5. Controller links
  const fishToken = await ethers.getContractAt('FishToken', fishTokenAddress);
  const boatNFT   = await ethers.getContractAt('BoatNFT',   boatNFTAddress);

  const currentFishController = await fishToken.gameController();
  if (currentFishController.toLowerCase() !== gameControllerAddress.toLowerCase()) {
    console.log('Linking FishToken to GameController...');
    const tx = await fishToken.setGameController(gameControllerAddress);
    await tx.wait();
    console.log('FishToken controller configured');
    await sleep(2000);
  } else {
    console.log('FishToken controller already configured');
  }

  const currentBoatController = await boatNFT.gameController();
  if (currentBoatController.toLowerCase() !== gameControllerAddress.toLowerCase()) {
    console.log('Linking BoatNFT to GameController...');
    const tx = await boatNFT.setGameController(gameControllerAddress);
    await tx.wait();
    console.log('BoatNFT controller configured');
    await sleep(2000);
  } else {
    console.log('BoatNFT controller already configured');
  }

  const targetPlacementFeeEth = process.env.PLACEMENT_FEE_ETH || '0';
  const targetPlacementFee = ethers.parseEther(targetPlacementFeeEth);
  const gameController = await ethers.getContractAt('GameController', gameControllerAddress);
  const currentPlacementFee = await gameController.placementFee();
  if (currentPlacementFee !== targetPlacementFee) {
    console.log(
      `Updating placement fee from ${ethers.formatEther(currentPlacementFee)} ETH to ${targetPlacementFeeEth} ETH...`
    );
    const tx = await gameController.setPlacementFee(targetPlacementFee);
    await tx.wait();
    console.log('Placement fee configured');
    await sleep(2000);
  } else {
    console.log(`Placement fee already configured: ${targetPlacementFeeEth} ETH`);
  }

  // Save results.
  const deploymentInfo = {
    network:   network.name,
    chainId:   network.config.chainId,
    deployer:  deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      FishToken:      { address: fishTokenAddress,      constructorArgs: [deployer.address] },
      BoatNFT:        { address: boatNFTAddress,        constructorArgs: [deployer.address, boatUsdcAddress] },
      GameController: { address: gameControllerAddress, constructorArgs: [fishTokenAddress, boatNFTAddress, deployer.address] },
      BoostFishingNFT:{ address: boostFishingNFTAddress,constructorArgs: [boostBaseUri, deployer.address] },
    },
  };

  if (!fs.existsSync(deploymentsDir)) fs.mkdirSync(deploymentsDir, { recursive: true });
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));

  const envContent =
`# FishBase Contract Addresses - ${network.name} - ${new Date().toISOString()}
FISH_TOKEN_ADDRESS=${fishTokenAddress}
BOAT_NFT_ADDRESS=${boatNFTAddress}
BOOST_NFT_ADDRESS=${boostFishingNFTAddress}
GAME_CONTROLLER_ADDRESS=${gameControllerAddress}
`;
  const envFile = path.join(deploymentsDir, `${network.name}.env`);
  fs.writeFileSync(envFile, envContent);

  console.log('\nDeploy complete!');
  console.log('-------------------------------------');
  console.log('  FishToken      :', fishTokenAddress);
  console.log('  BoatNFT        :', boatNFTAddress);
  console.log('  GameController :', gameControllerAddress);
  console.log('  BoostFishingNFT:', boostFishingNFTAddress);
  console.log('-------------------------------------');
  console.log('JSON:', deploymentFile);
  console.log('ENV :', envFile);

  // Verify
  if (network.name !== 'hardhat' && network.name !== 'localhost') {
    console.log('\nWaiting 30s before BaseScan verification...');
    await sleep(30000);

    for (const [name, info] of Object.entries(deploymentInfo.contracts)) {
      try {
        await hre.run('verify:verify', {
          address: info.address,
          constructorArguments: info.constructorArgs,
        });
        console.log(`${name} verified`);
      } catch (err) {
        if (err.message.includes('Already Verified')) {
          console.log(`${name} already verified`);
        } else {
          console.log(`${name} verification failed:`, err.message);
        }
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('\nDeploy failed:', err.message);
    process.exit(1);
  });
