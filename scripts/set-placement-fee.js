const fs = require('fs');
const path = require('path');
const hre = require('hardhat');

const { ethers, network } = hre;

async function main() {
  const deploymentFile = path.join(__dirname, '..', 'deployments', `${network.name}.json`);
  if (!fs.existsSync(deploymentFile)) {
    throw new Error(`Deployment file not found: ${deploymentFile}`);
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentFile, 'utf8'));
  const gameControllerAddress = deployment?.contracts?.GameController?.address;
  if (!gameControllerAddress) {
    throw new Error(`GameController address not found in ${deploymentFile}`);
  }

  const targetFeeEth = process.env.PLACEMENT_FEE_ETH || '0';
  const targetFee = ethers.parseEther(targetFeeEth);
  const [deployer] = await ethers.getSigners();

  console.log('Network:', network.name);
  console.log('Signer :', deployer.address);
  console.log('GameController:', gameControllerAddress);
  console.log('Target placement fee:', targetFeeEth, 'ETH');

  const gameController = await ethers.getContractAt('GameController', gameControllerAddress);
  const currentFee = await gameController.placementFee();
  console.log('Current placement fee:', ethers.formatEther(currentFee), 'ETH');

  if (currentFee === targetFee) {
    console.log('Placement fee already configured.');
    return;
  }

  const tx = await gameController.setPlacementFee(targetFee);
  console.log('Transaction:', tx.hash);
  await tx.wait();
  console.log('Placement fee updated.');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Failed to set placement fee:', err.message);
    process.exit(1);
  });
