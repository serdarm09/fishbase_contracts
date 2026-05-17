const fs   = require('fs');
const path = require('path');
const hre  = require('hardhat');

const { ethers, network } = hre;

// Helper: işlemler arasında bekle (in-flight limit önlemi)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  console.log('\n🚀 FishBase deployment başlıyor...');
  console.log('📡 Ağ:', network.name);

  const [deployer] = await ethers.getSigners();
  console.log('👤 Deployer:', deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log('💰 Bakiye:', ethers.formatEther(balance), 'ETH\n');

  // Daha önce yarım kalmış deployment varsa yükle
  const deploymentsDir = path.join(__dirname, '..', 'deployments');
  const deploymentFile = path.join(deploymentsDir, `${network.name}.json`);
  let existing = {};
  if (fs.existsSync(deploymentFile)) {
    try {
      existing = JSON.parse(fs.readFileSync(deploymentFile, 'utf8'));
      console.log('♻️  Mevcut deployment bulundu, devam ediliyor...');
    } catch (_) {}
  }

  // ── 1. FishToken ─────────────────────────────────────────────────────────
  let fishTokenAddress = existing?.contracts?.FishToken?.address;
  if (fishTokenAddress) {
    console.log('✅ FishToken zaten deploy edilmiş:', fishTokenAddress);
  } else {
    console.log('📄 FishToken deploy ediliyor...');
    const FishToken = await ethers.getContractFactory('FishToken');
    const fishToken = await FishToken.deploy(deployer.address);
    await fishToken.waitForDeployment();
    fishTokenAddress = await fishToken.getAddress();
    console.log('✅ FishToken:', fishTokenAddress);
    await sleep(3000);
  }

  // ── 2. BoatNFT ───────────────────────────────────────────────────────────
  const USDC_BASE = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"; // USDC on Base mainnet
  let boatNFTAddress = existing?.contracts?.BoatNFT?.address;
  if (boatNFTAddress) {
    console.log('✅ BoatNFT zaten deploy edilmiş:', boatNFTAddress);
  } else {
    console.log('📄 BoatNFT deploy ediliyor...');
    const BoatNFT = await ethers.getContractFactory('BoatNFT');
    const boatNFT = await BoatNFT.deploy(deployer.address, USDC_BASE);
    await boatNFT.waitForDeployment();
    boatNFTAddress = await boatNFT.getAddress();
    console.log('✅ BoatNFT:', boatNFTAddress);
    await sleep(3000);
  }

  // ── 3. GameController ────────────────────────────────────────────────────
  let gameControllerAddress = existing?.contracts?.GameController?.address;
  if (gameControllerAddress) {
    console.log('✅ GameController zaten deploy edilmiş:', gameControllerAddress);
  } else {
    console.log('📄 GameController deploy ediliyor...');
    const GameController = await ethers.getContractFactory('GameController');
    const gameController = await GameController.deploy(
      fishTokenAddress,
      boatNFTAddress,
      deployer.address
    );
    await gameController.waitForDeployment();
    gameControllerAddress = await gameController.getAddress();
    console.log('✅ GameController:', gameControllerAddress);
    await sleep(3000);
  }

  // ── 4. BoostFishingNFT ───────────────────────────────────────────────────
  let boostFishingNFTAddress = existing?.contracts?.BoostFishingNFT?.address;
  if (boostFishingNFTAddress) {
    console.log('✅ BoostFishingNFT zaten deploy edilmiş:', boostFishingNFTAddress);
  } else {
    console.log('📄 BoostFishingNFT deploy ediliyor...');
    const BoostFishingNFT = await ethers.getContractFactory('BoostFishingNFT');
    const boostFishingNFT = await BoostFishingNFT.deploy('', deployer.address);
    await boostFishingNFT.waitForDeployment();
    boostFishingNFTAddress = await boostFishingNFT.getAddress();
    console.log('✅ BoostFishingNFT:', boostFishingNFTAddress);
    await sleep(3000);
  }

  // ── 5. Controller bağlantıları ──────────────────────────────────────────
  const fishToken = await ethers.getContractAt('FishToken', fishTokenAddress);
  const boatNFT   = await ethers.getContractAt('BoatNFT',   boatNFTAddress);

  const currentFishController = await fishToken.gameController();
  if (currentFishController.toLowerCase() !== gameControllerAddress.toLowerCase()) {
    console.log('🔗 FishToken → GameController bağlanıyor...');
    const tx = await fishToken.setGameController(gameControllerAddress);
    await tx.wait();
    console.log('✅ FishToken controller ayarlandı');
    await sleep(2000);
  } else {
    console.log('✅ FishToken controller zaten ayarlı');
  }

  const currentBoatController = await boatNFT.gameController();
  if (currentBoatController.toLowerCase() !== gameControllerAddress.toLowerCase()) {
    console.log('🔗 BoatNFT → GameController bağlanıyor...');
    const tx = await boatNFT.setGameController(gameControllerAddress);
    await tx.wait();
    console.log('✅ BoatNFT controller ayarlandı');
  } else {
    console.log('✅ BoatNFT controller zaten ayarlı');
  }

  // ── Sonuçları kaydet ─────────────────────────────────────────────────────
  const deploymentInfo = {
    network:   network.name,
    chainId:   network.config.chainId,
    deployer:  deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      FishToken:      { address: fishTokenAddress,      constructorArgs: [deployer.address] },
      BoatNFT:        { address: boatNFTAddress,        constructorArgs: [deployer.address] },
      GameController: { address: gameControllerAddress, constructorArgs: [fishTokenAddress, boatNFTAddress, deployer.address] },
      BoostFishingNFT:{ address: boostFishingNFTAddress,constructorArgs: ['', deployer.address] },
    },
  };

  if (!fs.existsSync(deploymentsDir)) fs.mkdirSync(deploymentsDir, { recursive: true });
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));

  const envContent =
`# FishBase Contract Addresses — ${network.name} — ${new Date().toISOString()}
FISH_TOKEN_ADDRESS=${fishTokenAddress}
BOAT_NFT_ADDRESS=${boatNFTAddress}
BOOST_NFT_ADDRESS=${boostFishingNFTAddress}
GAME_CONTROLLER_ADDRESS=${gameControllerAddress}
`;
  const envFile = path.join(deploymentsDir, `${network.name}.env`);
  fs.writeFileSync(envFile, envContent);

  console.log('\n🎉 Deploy tamamlandı!');
  console.log('─────────────────────────────────────');
  console.log('  FishToken      :', fishTokenAddress);
  console.log('  BoatNFT        :', boatNFTAddress);
  console.log('  GameController :', gameControllerAddress);
  console.log('  BoostFishingNFT:', boostFishingNFTAddress);
  console.log('─────────────────────────────────────');
  console.log('📁 JSON:', deploymentFile);
  console.log('📁 ENV :', envFile);

  // ── Verify ───────────────────────────────────────────────────────────────
  if (network.name !== 'hardhat' && network.name !== 'localhost') {
    console.log('\n⏳ BaseScan verify için 30sn bekleniyor...');
    await sleep(30000);

    for (const [name, info] of Object.entries(deploymentInfo.contracts)) {
      try {
        await hre.run('verify:verify', {
          address: info.address,
          constructorArguments: info.constructorArgs,
        });
        console.log(`✅ ${name} verified`);
      } catch (err) {
        if (err.message.includes('Already Verified')) {
          console.log(`✅ ${name} zaten verified`);
        } else {
          console.log(`⚠️  ${name} verify başarısız:`, err.message);
        }
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('\n❌ Deploy başarısız:', err.message);
    process.exit(1);
  });
