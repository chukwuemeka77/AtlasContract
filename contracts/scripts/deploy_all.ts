import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

const {
  VAULT_ADMIN_ADDRESS,
  PRESALE_ALLOCATION,
  LP_REWARD_ALLOCATION,
  DEX_LIQUIDITY_ALLOCATION,
  CEX_LISTINGS_ALLOCATION,
  TREASURY_ALLOCATION,
  MARKETING_ALLOCATION,
  TEAM_ALLOCATION,
  PRESALE_PRICE,
  PRESALE_VESTING_MONTHS,
  PRESALE_TGE_PERCENT,
  LP_DURATION,
} = process.env;

async function main() {
  // Deploy Token
  const AtlasToken = await ethers.getContractFactory("AtlasToken");
  const token = await upgrades.deployProxy(AtlasToken, ["Atlas Token", "ATLAS"], { kind: "uups" });
  await token.deployed();
  console.log("AtlasToken deployed at:", token.address);

  // Deploy Presale
  const Presale = await ethers.getContractFactory("AtlasPresale");
  const presale = await upgrades.deployProxy(Presale, [
    token.address,
    PRESALE_ALLOCATION,
    PRESALE_PRICE,
    PRESALE_VESTING_MONTHS,
    PRESALE_TGE_PERCENT,
    VAULT_ADMIN_ADDRESS
  ], { kind: "uups" });
  await presale.deployed();
  console.log("Presale deployed at:", presale.address);

  // Deploy Vesting for LP / Rewards
  const Vesting = await ethers.getContractFactory("AtlasVesting");
  const vesting = await upgrades.deployProxy(Vesting, [
    token.address,
    LP_REWARD_ALLOCATION,
    LP_DURATION,
    VAULT_ADMIN_ADDRESS
  ], { kind: "uups" });
  await vesting.deployed();
  console.log("Vesting deployed at:", vesting.address);

  // Deploy Bridge
  const Bridge = await ethers.getContractFactory("AtlasBridge");
  const bridge = await upgrades.deployProxy(Bridge, [
    token.address,
    VAULT_ADMIN_ADDRESS
  ], { kind: "uups" });
  await bridge.deployed();
  console.log("Bridge deployed at:", bridge.address);

  // Deploy AMM / Liquidity pools
  const AMM = await ethers.getContractFactory("AtlasAMM");
  const amm = await upgrades.deployProxy(AMM, [
    token.address,
    DEX_LIQUIDITY_ALLOCATION,
    CEX_LISTINGS_ALLOCATION,
    VAULT_ADMIN_ADDRESS
  ], { kind: "uups" });
  await amm.deployed();
  console.log("AMM deployed at:", amm.address);

  // Deploy Reward Distributor
  const Rewards = await ethers.getContractFactory("RewardDistributor");
  const rewards = await upgrades.deployProxy(Rewards, [
    token.address,
    TREASURY_ALLOCATION,
    MARKETING_ALLOCATION,
    TEAM_ALLOCATION,
    VAULT_ADMIN_ADDRESS
  ], { kind: "uups" });
  await rewards.deployed();
  console.log("Rewards deployed at:", rewards.address);

  console.log("All contracts deployed and ready!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
