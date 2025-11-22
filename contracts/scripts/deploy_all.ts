// scripts/deploy_all.ts
import fs from "fs";
import path from "path";
import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

type DeployedMap = { [k: string]: string | Record<string, string> };

const deployedFile = path.join(__dirname, "..", "deployed_addresses.json");

async function main() {
  const deployer = (await ethers.getSigners())[0];
  console.log("Deploying as:", deployer.address);
  console.log("Network:", (await ethers.provider.getNetwork()).name);

  const RPC = process.env.RPC_URL;
  if (!RPC) throw new Error("RPC_URL missing in .env");
  const VAULT_ADMIN = process.env.VAULT_ADMIN_ADDRESS;
  if (!VAULT_ADMIN) throw new Error("VAULT_ADMIN_ADDRESS missing in .env");

  const USDC = process.env.TOKEN1 || process.env.USDC_ADDRESS || "";
  if (!USDC) console.warn("USDC not set in .env; presale payments may fail");

  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000";
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000";
  const TOTAL_SUPPLY = process.env.TOTAL_SUPPLY || "10000000000";

  const PRESALE_PRICE = process.env.PRESALE_PRICE || "50000000";
  const PRESALE_VESTING_MONTHS = Number(process.env.PRESALE_VESTING_MONTHS || 1);
  const PRESALE_TGE_PERCENT = Number(process.env.PRESALE_TGE_PERCENT || 15);

  const outDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const deployed: DeployedMap = fs.existsSync(deployedFile)
    ? JSON.parse(fs.readFileSync(deployedFile, "utf-8"))
    : {};

  // ---------- 1) Deploy Vesting ----------
  console.log("\n1) Deploying Vesting...");
  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = await Vesting.deploy(deployer.address); // deployer as temporary owner/admin
  await vesting.deployed();
  deployed["Vesting"] = vesting.address;
  console.log("Vesting deployed at:", vesting.address);

  // ---------- 2) Deploy Presale ----------
  console.log("\n2) Deploying Presale...");
  const Presale = await ethers.getContractFactory("presale/Presale");
  const vestingDurationSecs = PRESALE_VESTING_MONTHS * 30 * 24 * 60 * 60;
  const presale = await upgrades.deployProxy(
    Presale,
    [deployer.address, vesting.address, USDC, PRESALE_PRICE, ethers.utils.parseUnits(PRESALE_ALLOCATION, 18), 0, vestingDurationSecs],
    { kind: "uups" }
  );
  await presale.deployed();
  deployed["AtlasPresale"] = presale.address;
  console.log("Presale proxy:", presale.address);

  // ---------- 3) Deploy Launchpad ----------
  console.log("\n3) Deploying Launchpad...");
  const Launchpad = await ethers.getContractFactory("launchpad/Launchpad");
  const launchpad = await upgrades.deployProxy(Launchpad, [deployer.address], { kind: "uups" });
  await launchpad.deployed();
  deployed["Launchpad"] = launchpad.address;
  console.log("Launchpad proxy:", launchpad.address);

  // ---------- 4) Deploy AtlasToken ----------
  console.log("\n4) Deploying AtlasToken...");
  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasToken = await upgrades.deployProxy(AtlasToken, ["Atlas Token", "ATLAS", VAULT_ADMIN], { kind: "uups" });
  await atlasToken.deployed();
  deployed["AtlasToken"] = atlasToken.address;
  console.log("AtlasToken proxy:", atlasToken.address);

  // ---------- 5) Deploy AtlasBridge ----------
  console.log("\n5) Deploying AtlasBridge...");
  const AtlasBridge = await ethers.getContractFactory("bridge/AtlasBridge");
  const bridge = await AtlasBridge.deploy(atlasToken.address);
  await bridge.deployed();
  deployed["AtlasBridge"] = bridge.address;
  console.log("AtlasBridge deployed at:", bridge.address);

  // Grant roles on AtlasToken
  const MINTER_ROLE = await atlasToken.MINTER_ROLE();
  const BRIDGE_ROLE = await atlasToken.BRIDGE_ROLE();
  const BURNER_ROLE = await atlasToken.BURNER_ROLE();

  await atlasToken.grantRole(MINTER_ROLE, vesting.address);
  await atlasToken.grantRole(MINTER_ROLE, presale.address);
  await atlasToken.grantRole(MINTER_ROLE, launchpad.address);
  await atlasToken.grantRole(BRIDGE_ROLE, bridge.address);
  console.log("Granted MINTER_ROLE to vesting, presale, launchpad and BRIDGE_ROLE to AtlasBridge");

  // ---------- 6) Deploy AMM ----------
  console.log("\n6) Deploying AMM Factory & Router & WETH...");
  const WETH = await (await ethers.getContractFactory("WETH9")).deploy();
  await WETH.deployed();
  deployed["WETH"] = WETH.address;
  console.log("WETH deployed at:", WETH.address);

  const AtlasFactory = await ethers.getContractFactory("amm/AtlasFactory");
  const factory = await AtlasFactory.deploy(deployer.address); // feeToSetter
  await factory.deployed();
  deployed["AtlasFactory"] = factory.address;
  console.log("AtlasFactory deployed at:", factory.address);

  const AtlasRouter = await ethers.getContractFactory("amm/AtlasRouter");
  const router = await AtlasRouter.deploy(factory.address, WETH.address);
  await router.deployed();
  deployed["AtlasRouter"] = router.address;
  console.log("AtlasRouter deployed at:", router.address);

  // ---------- 7) Deploy Rewards ----------
  console.log("\n7) Deploying AtlasVault & RewardDistributor & Reward Sinks...");
  const AtlasVault = await ethers.getContractFactory("vaults/AtlasVault");
  const vault = await upgrades.deployProxy(AtlasVault, [atlasToken.address, VAULT_ADMIN], { kind: "uups" });
  await vault.deployed();
  deployed["AtlasVault"] = vault.address;
  console.log("AtlasVault proxy:", vault.address);

  const RewardDistributor = await ethers.getContractFactory("rewards/RewardDistributorV2");
  const rewardDistributor = await upgrades.deployProxy(RewardDistributor, [vault.address, atlasToken.address], { kind: "uups" });
  await rewardDistributor.deployed();
  deployed["RewardDistributor"] = rewardDistributor.address;
  console.log("RewardDistributor proxy:", rewardDistributor.address);

  const LPRewardSink = await ethers.getContractFactory("rewards/LPRewardSink");
  const lpSink = await upgrades.deployProxy(LPRewardSink, [vault.address], { kind: "uups" });
  await lpSink.deployed();
  deployed["LiquidityLP"] = lpSink.address;
  console.log("LPRewardSink proxy:", lpSink.address);

  const StakingRewardSink = await ethers.getContractFactory("rewards/StakingRewardSink");
  const stakingSink = await upgrades.deployProxy(StakingRewardSink, [vault.address], { kind: "uups" });
  await stakingSink.deployed();
  deployed["StakingRewardSink"] = stakingSink.address;
  console.log("StakingRewardSink proxy:", stakingSink.address);

  // Wire sinks to RewardDistributor if function exists
  try {
    if ((rewardDistributor as any).setLpSink) await (rewardDistributor as any).setLpSink(lpSink.address);
    if ((rewardDistributor as any).setStakingSink) await (rewardDistributor as any).setStakingSink(stakingSink.address);
    console.log("RewardDistributor sinks connected");
  } catch {}

  // ---------- 8) Write deployed addresses ----------
  fs.writeFileSync(deployedFile, JSON.stringify(deployed, null, 2));
  console.log("\n✅ Deployment complete. Addresses written to:", deployedFile);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Deployment failed:", err);
    process.exit(1);
  });
