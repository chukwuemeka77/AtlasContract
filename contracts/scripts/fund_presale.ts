import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import fs from "fs";

dotenv.config();

const {
  PRESALE_ALLOCATION,
  LP_REWARD_ALLOCATION,
  DEX_LIQUIDITY_ALLOCATION,
  CEX_LISTINGS_ALLOCATION,
  VAULT_ADMIN_ADDRESS
} = process.env;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Funding presale and vaults with:", deployer.address);

  // Load deployed addresses
  const deployed = JSON.parse(fs.readFileSync("deployed_addresses.json", "utf-8"));
  const tokenAddress = deployed.token;
  const vaultAddress = deployed.vault;
  const presaleAddress = deployed.presale;
  const vestingAddress = deployed.vesting;

  const token = await ethers.getContractAt("AtlasToken", tokenAddress);
  const vault = await ethers.getContractAt("AtlasVault", vaultAddress);
  const presale = await ethers.getContractAt("AtlasPresale", presaleAddress);
  const vesting = await ethers.getContractAt("AtlasVesting", vestingAddress);

  const decimals = 18;

  // Helper to parse allocation amounts
  const parseAmount = (amountStr: string | undefined) => ethers.utils.parseUnits(amountStr || "0", decimals);

  // 1️⃣ Fund Presale
  const presaleAmount = parseAmount(PRESALE_ALLOCATION);
  await token.transfer(vault.address, presaleAmount);
  await vault.fundPresale(presale.address, presaleAmount, VAULT_ADMIN_ADDRESS);
  console.log("Presale funded:", PRESALE_ALLOCATION);

  // 2️⃣ Fund Vesting schedules (if required)
  const lpRewardAmount = parseAmount(LP_REWARD_ALLOCATION);
  await token.transfer(vault.address, lpRewardAmount);
  await vault.fundVesting(vesting.address, lpRewardAmount);
  console.log("LP/staking rewards funded:", LP_REWARD_ALLOCATION);

  // 3️⃣ Fund DEX Liquidity
  const dexLiquidityAmount = parseAmount(DEX_LIQUIDITY_ALLOCATION);
  await token.transfer(vault.address, dexLiquidityAmount);
  await vault.fundDexLiquidity(dexLiquidityAmount);
  console.log("DEX liquidity funded:", DEX_LIQUIDITY_ALLOCATION);

  // 4️⃣ Fund CEX listings
  const cexAmount = parseAmount(CEX_LISTINGS_ALLOCATION);
  await token.transfer(vault.address, cexAmount);
  await vault.fundCexLiquidity(cexAmount);
  console.log("CEX liquidity funded:", CEX_LISTINGS_ALLOCATION);

  console.log("All presale and vault allocations completed safely.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
