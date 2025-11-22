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

  const outDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, "deployed_addresses.json");
  const deployed: DeployedMap = {};

  // --- Required env ---
  const VAULT_ADMIN = process.env.VAULT_ADMIN_ADDRESS || deployer.address;
  const USDC = process.env.USDC_ADDRESS || deployer.address;
  const WETH = process.env.WETH_ADDRESS || deployer.address;

  // Allocation & presale params
  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000";
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000";
  const TOTAL_SUPPLY = process.env.TOTAL_SUPPLY || "10000000000";
  const PRESALE_PRICE = process.env.PRESALE_PRICE || "50000000";
  const PRESALE_VESTING_MONTHS = Number(process.env.PRESALE_VESTING_MONTHS || 1);
  const PRESALE_TGE_PERCENT = Number(process.env.PRESALE_TGE_PERCENT || 15);

  // ---------- 1) Deploy Presale Vesting ----------
  console.log("\n1) Deploying Presale Vesting...");
  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = await Vesting.deploy(
    process.env.ATLAS_TOKEN_ADDRESS || deployer.address, // token placeholder, will update later
    VAULT_ADMIN
  );
  await vesting.deployed();
  deployed["PresaleVesting"] = vesting.address;
  console.log("Presale Vesting deployed at:", vesting.address);

  // ---------- 2) Deploy Presale ----------
  console.log("\n2) Deploying Presale...");
  const Presale = await ethers.getContractFactory("presale/Presale");
  const presale = await Presale.deploy(
    process.env.ATLAS_TOKEN_ADDRESS || deployer.address, // token placeholder
    vesting.address,
    USDC,
    PRESALE_PRICE,
    ethers.utils.parseUnits(PRESALE_ALLOCATION, 18)
  );
  await presale.deployed();
  deployed["Presale"] = presale.address;
  console.log("Presale deployed at:", presale.address);

  // ---------- 3) Deploy Launchpad ----------
  console.log("\n3) Deploying Launchpad...");
  const Launchpad = await ethers.getContractFactory("launchpad/Launchpad");
  const launchpad = await Launchpad.deploy(
    process.env.ATLAS_TOKEN_ADDRESS || deployer.address,
    VAULT_ADMIN,
    ethers.utils.parseEther("0.1"),
    ethers.utils.parseEther("500")
  );
  await launchpad.deployed();
  deployed["Launchpad"] = launchpad.address;
  console.log("Launchpad deployed at:", launchpad.address);

  // ---------- 4) Deploy AtlasToken ----------
  console.log("\n4) Deploying AtlasToken (UUPS)...");
  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasTokenProxy = await upgrades.deployProxy(
    AtlasToken,
    ["Atlas Token", "ATLAS", VAULT_ADMIN],
    { kind: "uups" }
  );
  await atlasTokenProxy.deployed();
  const atlasTokenAddress = atlasTokenProxy.address;
  deployed["AtlasToken"] = atlasTokenAddress;
  console.log("AtlasToken deployed at:", atlasTokenAddress);

  // Update token address in presale & vesting
  await vesting.transferOwnership(VAULT_ADMIN);
  console.log("Update Presale Vesting token address manually or via setter if needed.");
  console.log("Update Presale token address manually if constructor placeholder was used.");

  // ---------- 5) Deploy AtlasBridge ----------
  console.log("\n5) Deploying AtlasBridge...");
  const AtlasBridge = await ethers.getContractFactory("token/AtlasBridge");
  const bridge = await AtlasBridge.deploy(atlasTokenAddress);
  await bridge.deployed();
  deployed["AtlasBridge"] = bridge.address;
  console.log("AtlasBridge deployed at:", bridge.address);

  // Grant bridge role to bridge
  const BRIDGE_ROLE = await atlasTokenProxy.BRIDGE_ROLE();
  await atlasTokenProxy.grantRole(BRIDGE_ROLE, bridge.address);
  console.log("Granted BRIDGE_ROLE to AtlasBridge.");

  // ---------- 6) Deploy AMM Factory & Router ----------
  console.log("\n6) Deploying AMM Factory & Router...");
  const AtlasFactory = await ethers.getContractFactory("amm/AtlasFactory");
  const factory = await AtlasFactory.deploy(deployer.address);
  await factory.deployed();
  deployed["AtlasFactory"] = factory.address;

  const AtlasRouter = await ethers.getContractFactory("amm/AtlasRouter");
  const router = await AtlasRouter.deploy(factory.address, WETH);
  await router.deployed();
  deployed["AtlasRouter"] = router.address;

  console.log("AMM deployed: Factory =", factory.address, "Router =", router.address);

  // ---------- 7) Deploy Rewards ----------
  console.log("\n7) Deploying RewardDistributorV2 and sinks...");
  const AtlasVault = await ethers.getContractFactory("vaults/AtlasVault");
  const atlasVaultProxy = await upgrades.deployProxy(AtlasVault, [atlasTokenAddress, VAULT_ADMIN], { kind: "uups" });
  await atlasVaultProxy.deployed();
  deployed["AtlasVault"] = atlasVaultProxy.address;

  const RewardDistributorV2 = await ethers.getContractFactory("rewards/RewardDistributorV2");
  const rewardDistributorProxy = await upgrades.deployProxy(RewardDistributorV2, [atlasVaultProxy.address, atlasTokenAddress], { kind: "uups" });
  await rewardDistributorProxy.deployed();
  deployed["RewardDistributorV2"] = rewardDistributorProxy.address;

  const LPRewardSink = await ethers.getContractFactory("rewards/LPRewardSink");
  const lpSinkProxy = await upgrades.deployProxy(LPRewardSink, [atlasVaultProxy.address], { kind: "uups" });
  await lpSinkProxy.deployed();
  deployed["LPRewardSink"] = lpSinkProxy.address;

  const StakingRewardSink = await ethers.getContractFactory("rewards/StakingRewardSink");
  const stakingSinkProxy = await upgrades.deployProxy(StakingRewardSink, [atlasVaultProxy.address], { kind: "uups" });
  await stakingSinkProxy.deployed();
  deployed["StakingRewardSink"] = stakingSinkProxy.address;

  // Grant MINTER_ROLE to Vault & RewardDistributor
  const MINTER_ROLE = await atlasTokenProxy.MINTER_ROLE();
  await atlasTokenProxy.grantRole(MINTER_ROLE, atlasVaultProxy.address);
  await atlasTokenProxy.grantRole(MINTER_ROLE, rewardDistributorProxy.address);
  console.log("Granted MINTER_ROLE to Vault & RewardDistributor.");

  // ---------- 8) Save deployed addresses ----------
  fs.writeFileSync(outFile, JSON.stringify(deployed, null, 2));
  console.log("✅ Deployment complete. Addresses written to:", outFile);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
