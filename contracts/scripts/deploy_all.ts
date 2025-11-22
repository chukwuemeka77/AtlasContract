// scripts/deploy_all.ts
import fs from "fs";
import path from "path";
import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();
import { BigNumber } from "ethers";
import { SafeERC20 } from "../utils/SafeERC20"; // for TS helper usage if needed

type DeployedMap = { [k: string]: string | Record<string, string> };

async function main() {
  const deployer = (await ethers.getSigners())[0];
  console.log("Deploying as:", deployer.address);
  console.log("Network:", (await ethers.provider.getNetwork()).name);

  const VAULT_ADMIN = process.env.VAULT_ADMIN_ADDRESS!;
  if (!VAULT_ADMIN) throw new Error("VAULT_ADMIN_ADDRESS missing in .env");

  const USDC = process.env.USDC_ADDRESS || "";
  if (!USDC) console.warn("USDC_ADDRESS not set in .env");

  const decimals = 18;
  const TOTAL_MINT = "2000000000"; // 2B fragment pre-Atlaschain
  const totalMintUnits = ethers.utils.parseUnits(TOTAL_MINT, decimals);

  // Allocation amounts
  const ALLOC = {
    PRESALE: "600000000",
    INTERNAL_LIQ: "500000000",
    EXTERNAL_LIQ: "300000000",
    LP_REWARDS: "400000000",
    TREASURY: "200000000",
  };

  const allocationsUnits: Record<string, BigNumber> = {};
  for (const k in ALLOC) {
    allocationsUnits[k] = ethers.utils.parseUnits(ALLOC[k], decimals);
  }

  const outDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, "deployed_addresses.json");
  const deployed: DeployedMap = {};

  // ---------- 1) Deploy AtlasToken ----------
  console.log("\n1) Deploying AtlasToken (UUPS upgradeable)...");
  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasTokenProxy = await upgrades.deployProxy(
    AtlasToken,
    ["Atlas Token", "ATLAS", VAULT_ADMIN],
    { kind: "uups" }
  );
  await atlasTokenProxy.deployed();
  deployed["AtlasToken"] = atlasTokenProxy.address;
  console.log("AtlasToken:", atlasTokenProxy.address);

  // ---------- 2) Deploy AtlasBridge ----------
  console.log("\n2) Deploying AtlasBridge...");
  const AtlasBridge = await ethers.getContractFactory("bridge/AtlasBridge");
  const atlasBridge = await AtlasBridge.deploy(atlasTokenProxy.address);
  await atlasBridge.deployed();
  deployed["AtlasBridge"] = atlasBridge.address;
  console.log("AtlasBridge:", atlasBridge.address);

  // Grant bridge role
  const BRIDGE_ROLE = await atlasTokenProxy.BRIDGE_ROLE();
  await atlasTokenProxy.grantRole(BRIDGE_ROLE, atlasBridge.address);
  console.log("Granted BRIDGE_ROLE to AtlasBridge");

  // ---------- 3) Deploy AtlasVault ----------
  console.log("\n3) Deploying AtlasVault...");
  const AtlasVault = await ethers.getContractFactory("vaults/AtlasVault");
  const atlasVaultProxy = await upgrades.deployProxy(
    AtlasVault,
    [atlasTokenProxy.address, VAULT_ADMIN],
    { kind: "uups" }
  );
  await atlasVaultProxy.deployed();
  deployed["AtlasVault"] = atlasVaultProxy.address;
  console.log("AtlasVault:", atlasVaultProxy.address);

  // ---------- 4) Deploy Vesting (for presale) ----------
  console.log("\n4) Deploying Vesting...");
  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = await Vesting.deploy(atlasTokenProxy.address, VAULT_ADMIN);
  await vesting.deployed();
  deployed["Vesting"] = vesting.address;
  console.log("Vesting:", vesting.address);

  // ---------- 5) Deploy Presale ----------
  console.log("\n5) Deploying Presale...");
  const Presale = await ethers.getContractFactory("presale/Presale");
  const presale = await Presale.deploy(
    atlasTokenProxy.address,
    vesting.address,
    USDC,
    allocationsUnits.PRESALE
  );
  await presale.deployed();
  deployed["Presale"] = presale.address;
  console.log("Presale:", presale.address);

  // ---------- 6) Deploy AMM (Factory + Router) ----------
  console.log("\n6) Deploying AMM...");
  const AtlasFactory = await ethers.getContractFactory("amm/AtlasFactory");
  const factory = await AtlasFactory.deploy(deployer.address);
  await factory.deployed();
  deployed["AtlasFactory"] = factory.address;
  console.log("AtlasFactory:", factory.address);

  const AtlasRouter = await ethers.getContractFactory("amm/AtlasRouter");
  const WETH = process.env.WETH_ADDRESS || "";
  const router = await AtlasRouter.deploy(factory.address, WETH || atlasTokenProxy.address);
  await router.deployed();
  deployed["AtlasRouter"] = router.address;
  console.log("AtlasRouter:", router.address);

  // ---------- 7) Deploy RewardDistributor ----------
  console.log("\n7) Deploying RewardDistributor...");
  const RewardDistributorV2 = await ethers.getContractFactory("rewards/RewardDistributorV2");
  const rewardDistributor = await upgrades.deployProxy(
    RewardDistributorV2,
    [atlasVaultProxy.address, atlasTokenProxy.address],
    { kind: "uups" }
  );
  await rewardDistributor.deployed();
  deployed["RewardDistributorV2"] = rewardDistributor.address;
  console.log("RewardDistributorV2:", rewardDistributor.address);

  // ---------- 8) Deploy LP & Staking Reward Sinks ----------
  console.log("\n8) Deploying LP & Staking Reward Sinks...");
  const LPRewardSink = await ethers.getContractFactory("rewards/LPRewardSink");
  const lpSink = await upgrades.deployProxy(LPRewardSink, [atlasVaultProxy.address], { kind: "uups" });
  await lpSink.deployed();
  deployed["LPRewardSink"] = lpSink.address;

  const StakingRewardSink = await ethers.getContractFactory("rewards/StakingRewardSink");
  const stakingSink = await upgrades.deployProxy(StakingRewardSink, [atlasVaultProxy.address], { kind: "uups" });
  await stakingSink.deployed();
  deployed["StakingRewardSink"] = stakingSink.address;

  // ---------- 9) Mint & stage allocations ----------
  console.log("\n9) Minting fragment and allocating...");
  await atlasTokenProxy.mint(deployer.address, totalMintUnits);
  console.log(`Minted ${TOTAL_MINT} tokens to deployer`);

  // Use SafeERC20 transfers for allocations
  const allocations = [
    { to: presale.address, amount: allocationsUnits.PRESALE },
    { to: atlasVaultProxy.address, amount: allocationsUnits.INTERNAL_LIQ.add(allocationsUnits.EXTERNAL_LIQ).add(allocationsUnits.TREASURY) },
    { to: lpSink.address, amount: allocationsUnits.LP_REWARDS },
    // stakingSink may also get LP_REWARDS if designed
  ];

  for (const a of allocations) {
    const tx = await atlasTokenProxy.transfer(a.to, a.amount);
    await tx.wait();
    console.log(`Transferred ${ethers.utils.formatUnits(a.amount)} to ${a.to}`);
  }

  // ---------- 10) Grant MINTER_ROLE to Vault & RewardDistributor ----------
  const MINTER_ROLE = await atlasTokenProxy.MINTER_ROLE();
  await atlasTokenProxy.grantRole(MINTER_ROLE, atlasVaultProxy.address);
  await atlasTokenProxy.grantRole(MINTER_ROLE, rewardDistributor.address);

  // ---------- 11) Save deployed addresses ----------
  fs.writeFileSync(outFile, JSON.stringify(deployed, null, 2));
  console.log("\n✅ Deployment complete. Addresses written to:", outFile);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
