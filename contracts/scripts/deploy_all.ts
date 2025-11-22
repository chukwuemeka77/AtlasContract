// scripts/deploy_all.ts
import fs from "fs";
import path from "path";
import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

type DeployedMap = { [k: string]: string | Record<string, string> };

async function main() {
  const deployer = (await ethers.getSigners())[0];
  console.log("Deploying as:", deployer.address);
  console.log("Network:", (await ethers.provider.getNetwork()).name);

  // --- Required env checks ---
  const VAULT_ADMIN = process.env.VAULT_ADMIN_ADDRESS;
  if (!VAULT_ADMIN) throw new Error("VAULT_ADMIN_ADDRESS missing in .env");
  const USDC = process.env.TOKEN1 || process.env.USDC_ADDRESS || "";

  // Allocation and presale params
  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000";
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000";
  const TOTAL_SUPPLY = process.env.TOTAL_SUPPLY || "10000000000";
  const PRESALE_PRICE = process.env.PRESALE_PRICE || "50000000";
  const PRESALE_VESTING_MONTHS = Number(process.env.PRESALE_VESTING_MONTHS || 1);

  const outDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, "deployed_addresses.json");
  const deployed: DeployedMap = {};

  // ---------- 1) Deploy Vesting ----------
  console.log("\n1) Deploying Vesting...");
  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = await Vesting.deploy("", VAULT_ADMIN); // token address blank, will set later
  await vesting.deployed();
  deployed["Vesting"] = vesting.address;
  console.log("Vesting deployed at:", vesting.address);

  // ---------- 2) Deploy Presale ----------
  console.log("\n2) Deploying Presale...");
  const Presale = await ethers.getContractFactory("presale/Presale");
  const presale = await Presale.deploy("", vesting.address, VAULT_ADMIN); // token address blank, set later
  await presale.deployed();
  deployed["Presale"] = presale.address;
  console.log("Presale deployed at:", presale.address);

  // ---------- 3) Deploy Launchpad ----------
  console.log("\n3) Deploying Launchpad...");
  const Launchpad = await ethers.getContractFactory("launchpad/Launchpad");
  const launchpad = await Launchpad.deploy("", VAULT_ADMIN);
  await launchpad.deployed();
  deployed["Launchpad"] = launchpad.address;
  console.log("Launchpad deployed at:", launchpad.address);

  // ---------- 4) Deploy AtlasToken ----------
  console.log("\n4) Deploying AtlasToken (UUPS)...");
  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasToken = await upgrades.deployProxy(AtlasToken, ["Atlas Token", "ATLAS", VAULT_ADMIN], { kind: "uups" });
  await atlasToken.deployed();
  deployed["AtlasToken"] = atlasToken.address;
  console.log("AtlasToken proxy:", atlasToken.address);

  // ---------- 5) Update Vesting & Presale token addresses ----------
  await vesting.initialize(atlasToken.address, VAULT_ADMIN);
  await presale.initialize(atlasToken.address);
  console.log("Updated Vesting & Presale with AtlasToken address");

  // ---------- 6) Deploy AtlasBridge ----------
  console.log("\n5) Deploying AtlasBridge...");
  const AtlasBridge = await ethers.getContractFactory("token/AtlasBridge");
  const bridge = await AtlasBridge.deploy(atlasToken.address);
  await bridge.deployed();
  deployed["AtlasBridge"] = bridge.address;
  console.log("AtlasBridge deployed at:", bridge.address);

  // Grant BRIDGE_ROLE to AtlasBridge
  const BRIDGE_ROLE = await atlasToken.BRIDGE_ROLE();
  await atlasToken.grantRole(BRIDGE_ROLE, bridge.address);
  console.log("Granted BRIDGE_ROLE to AtlasBridge");

  // ---------- 7) Deploy AtlasVault ----------
  console.log("\n6) Deploying AtlasVault...");
  const AtlasVault = await ethers.getContractFactory("vaults/AtlasVault");
  const vaultProxy = await upgrades.deployProxy(AtlasVault, [atlasToken.address, VAULT_ADMIN], { kind: "uups" });
  await vaultProxy.deployed();
  deployed["AtlasVault"] = vaultProxy.address;
  console.log("AtlasVault proxy:", vaultProxy.address);

  // Grant MINTER_ROLE to Vault
  const MINTER_ROLE = await atlasToken.MINTER_ROLE();
  await atlasToken.grantRole(MINTER_ROLE, vaultProxy.address);
  console.log("Granted MINTER_ROLE to Vault");

  // ---------- 8) Deploy AMM Factory & Router ----------
  console.log("\n7) Deploying AMM Factory & Router...");
  const AtlasFactory = await ethers.getContractFactory("amm/AtlasFactory");
  const factory = await AtlasFactory.deploy(deployer.address);
  await factory.deployed();
  deployed["AtlasFactory"] = factory.address;
  console.log("AtlasFactory deployed at:", factory.address);

  const AtlasRouter = await ethers.getContractFactory("amm/AtlasRouter");
  const WETH = process.env.WETH_ADDRESS || USDC || atlasToken.address;
  const router = await AtlasRouter.deploy(factory.address, WETH);
  await router.deployed();
  deployed["AtlasRouter"] = router.address;
  console.log("AtlasRouter deployed at:", router.address);

  // ---------- 9) Deploy Rewards ----------
  console.log("\n8) Deploying RewardDistributorV2, LPRewardSink & StakingRewardSink...");
  const RewardDistributorV2 = await ethers.getContractFactory("rewards/RewardDistributorV2");
  const rewardDistributor = await upgrades.deployProxy(RewardDistributorV2, [vaultProxy.address, atlasToken.address], { kind: "uups" });
  await rewardDistributor.deployed();
  deployed["RewardDistributorV2"] = rewardDistributor.address;

  const LPRewardSink = await ethers.getContractFactory("rewards/LPRewardSink");
  const lpSink = await upgrades.deployProxy(LPRewardSink, [vaultProxy.address], { kind: "uups" });
  await lpSink.deployed();
  deployed["LPRewardSink"] = lpSink.address;

  const StakingRewardSink = await ethers.getContractFactory("rewards/StakingRewardSink");
  const stakingSink = await upgrades.deployProxy(StakingRewardSink, [vaultProxy.address], { kind: "uups" });
  await stakingSink.deployed();
  deployed["StakingRewardSink"] = stakingSink.address;

  console.log("Reward contracts deployed");

  // Connect sinks to RewardDistributor if method exists
  try {
    await (rewardDistributor as any).setLpSink(lpSink.address);
    await (rewardDistributor as any).setStakingSink(stakingSink.address);
    console.log("Connected sinks to RewardDistributor");
  } catch {}

  // ---------- 10) Save deployed addresses ----------
  fs.writeFileSync(outFile, JSON.stringify(deployed, null, 2));
  console.log("\n✅ Deployment complete. Addresses saved to:", outFile);
}

main().catch((err) => {
  console.error("Deployment failed:", err);
  process.exit(1);
});
