# FishBase Contracts

Hardhat project for the FishBase Base network contracts.

## Setup

```bash
npm install
cp env.sample .env
npm run compile
```

## Scripts

- `npm run compile` compiles contracts.
- `npm test` runs the Hardhat test suite.
- `npm run deploy:base-sepolia` deploys to Base Sepolia.
- `npm run deploy:base` deploys to Base mainnet.

Never commit a real deployer private key. Use `env.sample` as the public template only.
