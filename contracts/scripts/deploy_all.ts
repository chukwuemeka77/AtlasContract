import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";
import fs from "fs";

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
} = process.env;

if (!VAULT_ADMIN_ADDRESS) throw new Error("VAULT_ADMIN_ADDRESS not set in .env");

async function main() {
  const deployed: Record<string, string> = {};

  console.log("Deploying contracts with admin:", VAULT_ADMIN_ADDRESS);

  // -------------------------------
  // 1️⃣ Deploy Presale
  // -------------------------------
  const Presale = await ethers.getContractFactory("AtlasPresale");
  const presale = await upgrades.deployProxy(Presale, [VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await presale.deployed();
  deployed.AtlasPresale = presale.address;
  console.log("AtlasPresale deployed at:", presale.address);

  // -------------------------------
  // 2️⃣ Deploy Vesting
  // -------------------------------
  const Vesting = await ethers.getContractFactory("AtlasVesting");
  const vesting = await upgrades.deployProxy(Vesting, [VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await vesting.deployed();
  deployed.AtlasVesting = vesting.address;
  console.log("AtlasVesting deployed at:", vesting.address);

  // -------------------------------
  // 3️⃣ Deploy Launchpad
  // -------------------------------
  const Launchpad = await ethers.getContractFactory("AtlasLaunchpad");
  const launchpad = await upgrades.deployProxy(Launchpad, [VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await launchpad.deployed();
  deployed.AtlasLaunchpad = launchpad.address;
  console.log("AtlasLaunchpad deployed at:", launchpad.address);

  // -------------------------------
  // 4️⃣ Deploy Token
  // -------------------------------
  const Token = await ethers.getContractFactory("AtlasToken");
  const token = await upgrades.deployProxy(Token, [VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await token.deployed();
  deployed.AtlasToken = token.address;
  console.log("AtlasToken deployed at:", token.address);

  // -------------------------------
  // 5️⃣ Deploy Bridge
  // -------------------------------
  const Bridge = await ethers.getContractFactory("AtlasBridge");
  const bridge = await upgrades.deployProxy(Bridge, [token.address, VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await bridge.deployed();
  deployed.AtlasBridge = bridge.address;
  console.log("AtlasBridge deployed at:", bridge.address);

  // -------------------------------
  // 6️⃣ Deploy AMM (Router/Factory)
  // -------------------------------
  const Factory = await ethers.getContractFactory("AtlasFactory");
  const factory = await Factory.deploy(VAULT_ADMIN_ADDRESS);
  await factory.deployed();
  deployed.AtlasFactory = factory.address;

  const Router = await ethers.getContractFactory("AtlasRouter");
  const router = await Router.deploy(factory.address, await ethers.getContractAt("WETH", process.env.WETH_ADDRESS).then(w => w.address));
  await router.deployed();
  deployed.AtlasRouter = router.address;

  console.log("AMM deployed: Factory =", factory.address, "Router =", router.address);

  // -------------------------------
  // 7️⃣ Deploy Reward Distributor / Vault
  // -------------------------------
  const Reward = await ethers.getContractFactory("RewardDistributor");
  const reward = await upgrades.deployProxy(Reward, [token.address, VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await reward.deployed();
  deployed.RewardDistributor = reward.address;
  console.log("RewardDistributor deployed at:", reward.address);

  // -------------------------------
  // 8️⃣ Set Roles and Fund Allocations
  // -------------------------------
  const MINTER_ROLE = await token.MINTER_ROLE();
  await token.grantRole(MINTER_ROLE, VAULT_ADMIN_ADDRESS);

  // Presale allocation
  await token.transfer(presale.address, ethers.utils.parseUnits(PRESALE_ALLOCATION || "0", 18));

  // LP & staking rewards
  await token.transfer(reward.address, ethers.utils.parseUnits(LP_REWARD_ALLOCATION || "0", 18));

  // DEX liquidity
  await token.transfer(router.address, ethers.utils.parseUnits(DEX_LIQUIDITY_ALLOCATION || "0", 18));

  // CEX listings
  await token.transfer(VAULT_ADMIN_ADDRESS, ethers.utils.parseUnits(CEX_LISTINGS_ALLOCATION || "0", 18));

  // Treasury
  await token.transfer(VAULT_ADMIN_ADDRESS, ethers.utils.parseUnits(TREASURY_ALLOCATION || "0", 18));

  // Marketing
  await token.transfer(VAULT_ADMIN_ADDRESS, ethers.utils.parseUnits(MARKETING_ALLOCATION || "0", 18));

  // Team
  await token.transfer(VAULT_ADMIN_ADDRESS, ethers.utils.parseUnits(TEAM_ALLOCATION || "0", 18));

  // -------------------------------
  // Save deployed addresses
  // -------------------------------
  fs.writeFileSync("deployed_addresses.json", JSON.stringify(deployed, null, 2));
  console.log("All deployed addresses saved to deployed_addresses.json");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
