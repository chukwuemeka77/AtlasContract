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

  const VAULT_ADMIN = process.env.VAULT_ADMIN_ADDRESS;
  if (!VAULT_ADMIN) throw new Error("VAULT_ADMIN_ADDRESS missing in .env");

  const USDC = process.env.USDC_ADDRESS || "";
  const TOTAL_SUPPLY = process.env.TOTAL_SUPPLY || "10000000000";
  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000";
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000";
  const PRESALE_PRICE = process.env.PRESALE_PRICE || "50000000";
  const PRESALE_VESTING_MONTHS = Number(process.env.PRESALE_VESTING_MONTHS || 1);

  const outDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, "deployed_addresses.json");
  const deployed: DeployedMap = {};

  // ---------- 1) Deploy AtlasToken ----------
  console.log("\n1) Deploying AtlasToken (UUPS upgradeable)...");
  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasTokenProxy = await upgrades.deployProxy(AtlasToken, ["Atlas Token", "ATLAS", VAULT_ADMIN], { kind: "uups" });
  await atlasTokenProxy.deployed();
  deployed["AtlasToken"] = atlasTokenProxy.address;
  const atlasToken = AtlasToken.attach(atlasTokenProxy.address);

  // ---------- 2) Deploy AtlasBridge ----------
  console.log("\n2) Deploying AtlasBridge...");
  const AtlasBridge = await ethers.getContractFactory("bridge/AtlasBridge");
  const atlasBridge = await AtlasBridge.deploy(atlasTokenProxy.address, VAULT_ADMIN);
  await atlasBridge.deployed();
  deployed["AtlasBridge"] = atlasBridge.address;

  // Grant BRIDGE_ROLE to AtlasBridge
  try {
    const BRIDGE_ROLE = await atlasToken.BRIDGE_ROLE();
    await atlasToken.grantRole(BRIDGE_ROLE, atlasBridge.address);
    console.log("Granted BRIDGE_ROLE to AtlasBridge");
  } catch (err) {
    console.warn("Grant BRIDGE_ROLE failed:", (err as Error).message);
  }

  // ---------- 3) Deploy Vesting ----------
  console.log("\n3) Deploying Vesting...");
  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = await Vesting.deploy(atlasTokenProxy.address, VAULT_ADMIN);
  await vesting.deployed();
  deployed["Vesting"] = vesting.address;

  // ---------- 4) Deploy Presale ----------
  console.log("\n4) Deploying Presale...");
  const Presale = await ethers.getContractFactory("presale/Presale");
  const vestingDurationSecs = PRESALE_VESTING_MONTHS * 30 * 24 * 60 * 60;
  const presale = await upgrades.deployProxy(
    Presale,
    [atlasTokenProxy.address, vesting.address, USDC, PRESALE_PRICE, ethers.utils.parseUnits(PRESALE_ALLOCATION, 18), 0, vestingDurationSecs],
    { kind: "uups" }
  );
  await presale.deployed();
  deployed["Presale"] = presale.address;

  // ---------- 5) Deploy Launchpad ----------
  console.log("\n5) Deploying Launchpad...");
  const Launchpad = await ethers.getContractFactory("launchpad/Launchpad");
  const launchpad = await upgrades.deployProxy(Launchpad, [atlasTokenProxy.address, VAULT_ADMIN], { kind: "uups" });
  await launchpad.deployed();
  deployed["Launchpad"] = launchpad.address;

  // ---------- 6) Deploy Vault ----------
  console.log("\n6) Deploying AtlasVault...");
  const AtlasVault = await ethers.getContractFactory("vaults/AtlasVault");
  const atlasVaultProxy = await upgrades.deployProxy(AtlasVault, [atlasTokenProxy.address, VAULT_ADMIN], { kind: "uups" });
  await atlasVaultProxy.deployed();
  deployed["AtlasVault"] = atlasVaultProxy.address;

  // ---------- 7) Mint total supply ----------
  console.log("\n7) Minting total supply...");
  const totalSupplyUnits = ethers.utils.parseUnits(TOTAL_SUPPLY, 18);
  await atlasToken.mint(deployer.address, totalSupplyUnits);
  console.log("Minted total supply to deployer");

  // ---------- 8) Deploy RewardDistributor & Reward Sinks ----------
  console.log("\n8) Deploying RewardDistributorV2 & sinks...");
  const RewardDistributorV2 = await ethers.getContractFactory("rewards/RewardDistributorV2");
  const rewardDistributor = await upgrades.deployProxy(RewardDistributorV2, [atlasVaultProxy.address, atlasTokenProxy.address], { kind: "uups" });
  await rewardDistributor.deployed();
  deployed["RewardDistributorV2"] = rewardDistributor.address;

  const LPRewardSink = await ethers.getContractFactory("rewards/LPRewardSink");
  const lpSink = await upgrades.deployProxy(LPRewardSink, [atlasVaultProxy.address], { kind: "uups" });
  await lpSink.deployed();
  deployed["LPRewardSink"] = lpSink.address;

  const StakingRewardSink = await ethers.getContractFactory("rewards/StakingRewardSink");
  const stakingSink = await upgrades.deployProxy(StakingRewardSink, [atlasVaultProxy.address], { kind: "uups" });
  await stakingSink.deployed();
  deployed["StakingRewardSink"] = stakingSink.address;

  // ---------- 9) Deploy AMM (Factory & Router) ----------
  console.log("\n9) Deploying AMM Factory & Router...");
  const AtlasFactory = await ethers.getContractFactory("amm/AtlasFactory");
  const factory = await AtlasFactory.deploy(deployer.address);
  await factory.deployed();
  deployed["AtlasFactory"] = factory.address;

  const WETH = process.env.WETH_ADDRESS || USDC || atlasTokenProxy.address;
  const AtlasRouter = await ethers.getContractFactory("amm/AtlasRouter");
  const router = await AtlasRouter.deploy(factory.address, WETH);
  await router.deployed();
  deployed["AtlasRouter"] = router.address;

  // ---------- 10) Grant MINTER_ROLE to Vault/RewardDistributor ----------
  const MINTER_ROLE = await atlasToken.MINTER_ROLE();
  await atlasToken.grantRole(MINTER_ROLE, atlasVaultProxy.address);
  await atlasToken.grantRole(MINTER_ROLE, rewardDistributor.address);
  console.log("Granted MINTER_ROLE to Vault & RewardDistributor");

  // ---------- 11) Save deployed addresses ----------
  fs.writeFileSync(outFile, JSON.stringify(deployed, null, 2));
  console.log("\n✅ Deployment complete. Addresses saved to:", outFile);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Deployment failed:", err);
    process.exit(1);
  });
