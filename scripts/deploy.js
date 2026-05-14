const fs = require('fs');
const path = require('path');
const hre = require('hardhat');

const { ethers, network } = hre;

async function main() {
  console.log('Starting FishBase contracts deployment...');

  const [deployer] = await ethers.getSigners();
  console.log('Deploying contracts with account:', deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log('Account balance:', ethers.formatEther(balance), 'ETH');

  const FishToken = await ethers.getContractFactory('FishToken');
  const fishToken = await FishToken.deploy(deployer.address);
  await fishToken.waitForDeployment();
  const fishTokenAddress = await fishToken.getAddress();
  console.log('Fish Token deployed to:', fishTokenAddress);

  const BoatNFT = await ethers.getContractFactory('BoatNFT');
  const boatNFT = await BoatNFT.deploy(deployer.address);
  await boatNFT.waitForDeployment();
  const boatNFTAddress = await boatNFT.getAddress();
  console.log('Boat NFT deployed to:', boatNFTAddress);

  const GameController = await ethers.getContractFactory('GameController');
  const gameController = await GameController.deploy(
    fishTokenAddress,
    boatNFTAddress,
    deployer.address
  );
  await gameController.waitForDeployment();
  const gameControllerAddress = await gameController.getAddress();
  console.log('Game Controller deployed to:', gameControllerAddress);

  const BoostFishingNFT = await ethers.getContractFactory('BoostFishingNFT');
  const boostFishingNFT = await BoostFishingNFT.deploy('', deployer.address);
  await boostFishingNFT.waitForDeployment();
  const boostFishingNFTAddress = await boostFishingNFT.getAddress();
  console.log('Boost NFT deployed to:', boostFishingNFTAddress);

  const setFishControllerTx = await fishToken.setGameController(gameControllerAddress);
  await setFishControllerTx.wait();
  console.log('Fish Token game controller set');

  const setBoatControllerTx = await boatNFT.setGameController(gameControllerAddress);
  await setBoatControllerTx.wait();
  console.log('Boat NFT game controller set');

  const deploymentInfo = {
    network: network.name,
    chainId: network.config.chainId,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      FishToken: {
        address: fishTokenAddress,
        constructorArgs: [deployer.address],
      },
      BoatNFT: {
        address: boatNFTAddress,
        constructorArgs: [deployer.address],
      },
      GameController: {
        address: gameControllerAddress,
        constructorArgs: [fishTokenAddress, boatNFTAddress, deployer.address],
      },
      BoostFishingNFT: {
        address: boostFishingNFTAddress,
        constructorArgs: ['', deployer.address],
      },
    },
  };

  const deploymentsDir = path.join(__dirname, '..', 'deployments');
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  const deploymentFile = path.join(deploymentsDir, `${network.name}.json`);
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));

  const envContent = `# FishBase Contract Addresses - ${network.name}
FISH_TOKEN_ADDRESS=${fishTokenAddress}
BOAT_NFT_ADDRESS=${boatNFTAddress}
BOOST_NFT_ADDRESS=${boostFishingNFTAddress}
GAME_CONTROLLER_ADDRESS=${gameControllerAddress}
`;

  const envFile = path.join(deploymentsDir, `${network.name}.env`);
  fs.writeFileSync(envFile, envContent);

  console.log('Deployment completed successfully.');
  console.log('Fish Token:', fishTokenAddress);
  console.log('Boat NFT:', boatNFTAddress);
  console.log('Boost NFT:', boostFishingNFTAddress);
  console.log('Game Controller:', gameControllerAddress);
  console.log('Deployment info saved to:', deploymentFile);
  console.log('Environment variables saved to:', envFile);

  if (network.name !== 'hardhat' && network.name !== 'localhost') {
    console.log('Waiting before verification...');
    await new Promise((resolve) => setTimeout(resolve, 30000));

    try {
      await hre.run('verify:verify', {
        address: fishTokenAddress,
        constructorArguments: [deployer.address],
      });

      await hre.run('verify:verify', {
        address: boatNFTAddress,
        constructorArguments: [deployer.address],
      });

      await hre.run('verify:verify', {
        address: gameControllerAddress,
        constructorArguments: [fishTokenAddress, boatNFTAddress, deployer.address],
      });

      await hre.run('verify:verify', {
        address: boostFishingNFTAddress,
        constructorArguments: ['', deployer.address],
      });

      console.log('All contracts verified.');
    } catch (error) {
      console.log('Verification failed:', error.message);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Deployment failed:', error);
    process.exit(1);
  });
