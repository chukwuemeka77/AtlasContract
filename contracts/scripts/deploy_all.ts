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
  const network = await ethers.provider.getNetwork();
  console.log("Network:", network.name);

  const outDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, "deployed_addresses.json");
  const deployed: DeployedMap = {};

  const VAULT_ADMIN = process.env.VAULT_ADMIN_ADDRESS!;
  const USDC = process.env.TOKEN1 || process.env.USDC_ADDRESS || ethers.constants.AddressZero;
  const PRESALE_PRICE = process.env.PRESALE_PRICE || "50000000";
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000";
  const TOTAL_SUPPLY = process.env.TOTAL_SUPPLY || "10000000000";
  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000";

  // ---------- 1) Deploy Vesting ----------
  console.log("\n1) Deploying Vesting...");
  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = await Vesting.deploy(ethers.constants.AddressZero, VAULT_ADMIN); // token unknown yet
  await vesting.deployed();
  console.log("Vesting deployed at:", vesting.address);
  deployed["Vesting"] = vesting.address;

  // ---------- 2) Deploy Presale ----------
  console.log("\n2) Deploying Presale...");
  const Presale = await ethers.getContractFactory("presale/Presale");
  const presale = await Presale.deploy(
    ethers.constants.AddressZero, // token unknown yet
    vesting.address,
    USDC,
    PRESALE_PRICE,
    ethers.utils.parseUnits(PRESALE_ALLOCATION, 18)
  );
  await presale.deployed();
  console.log("Presale deployed at:", presale.address);
  deployed["Presale"] = presale.address;

  // ---------- 3) Deploy Launchpad ----------
  console.log("\n3) Deploying Launchpad...");
  const Launchpad = await ethers.getContractFactory("launchpad/Launchpad");
  const launchpad = await Launchpad.deploy(ethers.constants.AddressZero, VAULT_ADMIN);
  await launchpad.deployed();
  console.log("Launchpad deployed at:", launchpad.address);
  deployed["Launchpad"] = launchpad.address;

  // ---------- 4) Deploy AtlasToken (UUPS) ----------
  console.log("\n4) Deploying AtlasToken...");
  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasTokenProxy = await upgrades.deployProxy(AtlasToken, ["Atlas Token", "ATLAS", VAULT_ADMIN], { kind: "uups" });
  await atlasTokenProxy.deployed();
  console.log("AtlasToken proxy:", atlasTokenProxy.address);
  deployed["AtlasToken"] = atlasTokenProxy.address;

  const atlasToken = AtlasToken.attach(atlasTokenProxy.address);

  // ---------- 5) Link Vesting & Presale to Token ----------
  console.log("\n5) Linking Vesting and Presale to AtlasToken...");
  await vesting.setToken(atlasTokenProxy.address);
  await presale.setToken(atlasTokenProxy.address);
  await launchpad.setToken(atlasTokenProxy.address);

  // ---------- 6) Deploy AtlasBridge ----------
  console.log("\n6) Deploying AtlasBridge...");
  const AtlasBridge = await ethers.getContractFactory("bridge/AtlasBridge");
  const bridge = await AtlasBridge.deploy(atlasTokenProxy.address);
  await bridge.deployed();
  console.log("AtlasBridge deployed at:", bridge.address);
  deployed["AtlasBridge"] = bridge.address;

  // Grant BRIDGE_ROLE to bridge
  const BRIDGE_ROLE = await atlasToken.BRIDGE_ROLE();
  await atlasToken.grantRole(BRIDGE_ROLE, bridge.address);
  console.log("Granted BRIDGE_ROLE to AtlasBridge");

  // ---------- 7) Mint total supply ----------
  console.log("\n7) Minting total supply to deployer...");
  const totalSupplyUnits = ethers.utils.parseUnits(TOTAL_SUPPLY, 18);
  await atlasToken.mint(deployer.address, totalSupplyUnits);
  console.log("Minted total supply:", TOTAL_SUPPLY);

  // Transfer LP & Presale allocations to Vault (optional)
  const vaultAmount = ethers.utils.parseUnits(LP_REWARDS, 18)
    .add(ethers.utils.parseUnits(PRESALE_ALLOCATION, 18));
  await atlasToken.transfer(VAULT_ADMIN, vaultAmount);
  console.log("Transferred LP + Presale allocations to Vault/Admin");

  // ---------- 8) Deploy AMM ----------
  console.log("\n8) Deploying AMM Factory & Router...");
  const AtlasFactory = await ethers.getContractFactory("amm/AtlasFactory");
  const factory = await AtlasFactory.deploy(deployer.address);
  await factory.deployed();
  deployed["AtlasFactory"] = factory.address;
  console.log("AtlasFactory:", factory.address);

  const WETH = process.env.WETH_ADDRESS || USDC;
  const AtlasRouter = await ethers.getContractFactory("amm/AtlasRouter");
  const router = await AtlasRouter.deploy(factory.address, WETH);
  await router.deployed();
  deployed["AtlasRouter"] = router.address;
  console.log("AtlasRouter:", router.address);

  // ---------- 9) Deploy Rewards ----------
  console.log("\n9) Deploying RewardDistributor and Sinks...");
  const RewardDistributorV2 = await ethers.getContractFactory("rewards/RewardDistributorV2");
  const rewardDistributor = await upgrades.deployProxy(RewardDistributorV2, [VAULT_ADMIN, atlasTokenProxy.address], { kind: "uups" });
  await rewardDistributor.deployed();
  deployed["RewardDistributorV2"] = rewardDistributor.address;

  const LPRewardSink = await ethers.getContractFactory("rewards/LPRewardSink");
  const lpSink = await upgrades.deployProxy(LPRewardSink, [VAULT_ADMIN], { kind: "uups" });
  await lpSink.deployed();
  deployed["LPRewardSink"] = lpSink.address;

  const StakingRewardSink = await ethers.getContractFactory("rewards/StakingRewardSink");
  const stakingSink = await upgrades.deployProxy(StakingRewardSink, [VAULT_ADMIN], { kind: "uups" });
  await stakingSink.deployed();
  deployed["StakingRewardSink"] = stakingSink.address;

  // ---------- 10) Grant MINTER_ROLE ----------
  const MINTER_ROLE = await atlasToken.MINTER_ROLE();
  await atlasToken.grantRole(MINTER_ROLE, VAULT_ADMIN);
  await atlasToken.grantRole(MINTER_ROLE, rewardDistributor.address);
  console.log("Granted MINTER_ROLE to Vault/Admin and RewardDistributor");

  // ---------- 11) Save deployed addresses ----------
  fs.writeFileSync(outFile, JSON.stringify(deployed, null, 2));
  console.log("\n✅ Deployment complete. Addresses written to:", outFile);
}

main()
  .then(() => process.exit(0))
  .catch(err => {
    console.error("Deployment failed:", err);
    process.exit(1);
  });
