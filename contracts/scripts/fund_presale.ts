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
  console.log("Batch funding presale and vaults with:", deployer.address);

  // Load deployed addresses
  const deployed = JSON.parse(fs.readFileSync("deployed_addresses.json", "utf-8"));
  const tokenAddress = deployed.AtlasToken;
  const vaultAddress = deployed.AtlasVault;
  const presaleAddress = deployed.AtlasPresale;
  const vestingAddress = deployed.AtlasVesting;
  const multicallAddress = deployed.Multicall; // assuming deployed

  const token = await ethers.getContractAt("AtlasToken", tokenAddress);
  const vault = await ethers.getContractAt("AtlasVault", vaultAddress);
  const presale = await ethers.getContractAt("AtlasPresale", presaleAddress);
  const vesting = await ethers.getContractAt("AtlasVesting", vestingAddress);
  const multicall = await ethers.getContractAt("Multicall", multicallAddress);

  const decimals = 18;

  const parseAmount = (amountStr: string | undefined) => ethers.utils.parseUnits(amountStr || "0", decimals);

  // Prepare batched calls
  const calls: string[] = [];

  // 1️⃣ Fund Presale
  const presaleAmount = parseAmount(PRESALE_ALLOCATION);
  calls.push(
    token.interface.encodeFunctionData("transfer", [vault.address, presaleAmount])
  );
  calls.push(
    vault.interface.encodeFunctionData("fundPresale", [presale.address, presaleAmount, VAULT_ADMIN_ADDRESS])
  );

  // 2️⃣ Fund Vesting schedules
  const lpRewardAmount = parseAmount(LP_REWARD_ALLOCATION);
  calls.push(
    token.interface.encodeFunctionData("transfer", [vault.address, lpRewardAmount])
  );
  calls.push(
    vault.interface.encodeFunctionData("fundVesting", [vesting.address, lpRewardAmount])
  );

  // 3️⃣ Fund DEX liquidity
  const dexLiquidityAmount = parseAmount(DEX_LIQUIDITY_ALLOCATION);
  calls.push(
    token.interface.encodeFunctionData("transfer", [vault.address, dexLiquidityAmount])
  );
  calls.push(
    vault.interface.encodeFunctionData("fundDexLiquidity", [dexLiquidityAmount])
  );

  // 4️⃣ Fund CEX listings
  const cexAmount = parseAmount(CEX_LISTINGS_ALLOCATION);
  calls.push(
    token.interface.encodeFunctionData("transfer", [vault.address, cexAmount])
  );
  calls.push(
    vault.interface.encodeFunctionData("fundCexLiquidity", [cexAmount])
  );

  // Execute batched calls
  const tx = await multicall.multicall(calls);
  await tx.wait();
  console.log("All presale, vesting, DEX, and CEX allocations completed in a single batch!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
