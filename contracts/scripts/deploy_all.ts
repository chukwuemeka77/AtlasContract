// scripts/deploy_all.ts
import fs from "fs";
import path from "path";
import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";
import { BigNumber } from "ethers";
dotenv.config();

type DeployedMap = { [k: string]: string | Record<string, string> };

async function main() {
  const deployer = (await ethers.getSigners())[0];
  console.log("Deploying as:", deployer.address);
  console.log("Network:", (await ethers.provider.getNetwork()).name);

  const VAULT_ADMIN = process.env.VAULT_ADMIN_ADDRESS;
  if (!VAULT_ADMIN) throw new Error("VAULT_ADMIN_ADDRESS missing in .env");

  const USDC = process.env.TOKEN1 || process.env.USDC_ADDRESS || "";
  if (!USDC) console.warn("USDC/TOKEN1 not set. Presale payments may fail.");

  const TOTAL_SUPPLY = process.env.TOTAL_SUPPLY || "10000000000"; // 10B default
  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000"; // 1B default
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000"; // 300M default
  const PRESALE_PRICE = process.env.PRESALE_PRICE || "50000000"; // 0.05 USDC with 6 decimals
  const PRESALE_VESTING_MONTHS = Number(process.env.PRESALE_VESTING_MONTHS || 1);
  const PRESALE_TGE_PERCENT = Number(process.env.PRESALE_TGE_PERCENT || 15);

  const outFile = path.join(__dirname, "..", "deployed_addresses.json");
  const deployed: DeployedMap = {};

  // -------- 1) Deploy Vesting (upgradeable) --------
  console.log("\n1) Deploying Vesting...");
  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = await upgrades.deployProxy(Vesting, [ethers.constants.AddressZero, VAULT_ADMIN], { kind: "uups" });
  await vesting.deployed();
  deployed["Vesting"] = vesting.address;
  console.log("Vesting deployed at:", vesting.address);

  // -------- 2) Deploy Presale (upgradeable) --------
  console.log("\n2) Deploying Presale...");
  const Presale = await ethers.getContractFactory("presale/Presale");
  const vestingDurationSecs = PRESALE_VESTING_MONTHS * 30 * 24 * 60 * 60;
  const presale = await upgrades.deployProxy(
    Presale,
    [ethers.constants.AddressZero, vesting.address, USDC, PRESALE_PRICE, ethers.utils.parseUnits(PRESALE_ALLOCATION, 18), 0, vestingDurationSecs],
    { kind: "uups" }
  );
  await presale.deployed();
  deployed["Presale"] = presale.address;
  console.log("Presale deployed at:", presale.address);

  // -------- 3) Deploy Launchpad (upgradeable) --------
  console.log("\n3) Deploying Launchpad...");
  const Launchpad = await ethers.getContractFactory("launchpad/Launchpad");
  const launchpad = await upgrades.deployProxy(Launchpad, [ethers.constants.AddressZero, VAULT_ADMIN], { kind: "uups" });
  await launchpad.deployed();
  deployed["Launchpad"] = launchpad.address;
  console.log("Launchpad deployed at:", launchpad.address);

  // -------- 4) Deploy AtlasToken (upgradeable) --------
  console.log("\n4) Deploying AtlasToken...");
  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasToken = await upgrades.deployProxy(AtlasToken, ["Atlas Token", "ATLAS"], { kind: "uups" });
  await atlasToken.deployed();
  deployed["AtlasToken"] = atlasToken.address;
  console.log("AtlasToken deployed at:", atlasToken.address);

  // -------- 5) Deploy AtlasBridge --------
  console.log("\n5) Deploying AtlasBridge...");
  const AtlasBridge = await ethers.getContractFactory("bridge/AtlasBridge");
  const bridge = await AtlasBridge.deploy(atlasToken.address);
  await bridge.deployed();
  deployed["AtlasBridge"] = bridge.address;
  console.log("AtlasBridge deployed at:", bridge.address);

  // Grant roles for bridge and vault
  const MINTER_ROLE = await atlasToken.MINTER_ROLE();
  const BRIDGE_ROLE = await atlasToken.BRIDGE_ROLE();
  await atlasToken.grantRole(MINTER_ROLE, VAULT_ADMIN);
  await atlasToken.grantRole(MINTER_ROLE, launchpad.address);
  await atlasToken.grantRole(BRIDGE_ROLE, bridge.address);
  console.log("Roles granted: MINTER to vault & launchpad, BRIDGE to AtlasBridge");

  // -------- 6) Deploy AMM (Factory + Router) --------
  console.log("\n6) Deploying AMM (Factory + Router)...");
  const Factory = await ethers.getContractFactory("amm/AtlasFactory");
  const factory = await Factory.deploy(deployer.address); // feeToSetter
  await factory.deployed();
  deployed["AtlasFactory"] = factory.address;
  console.log("AtlasFactory deployed at:", factory.address);

  const WETH = process.env.WETH_ADDRESS || ethers.constants.AddressZero;
  const Router = await ethers.getContractFactory("amm/AtlasRouter");
  const router = await Router.deploy(factory.address, WETH || atlasToken.address);
  await router.deployed();
  deployed["AtlasRouter"] = router.address;
  console.log("AtlasRouter deployed at:", router.address);

  // -------- 7) Deploy Vault + Rewards --------
  console.log("\n7) Deploying Vault and RewardDistributor...");
  const AtlasVault = await ethers.getContractFactory("vaults/AtlasVault");
  const vault = await upgrades.deployProxy(AtlasVault, [atlasToken.address, VAULT_ADMIN], { kind: "uups" });
  await vault.deployed();
  deployed["AtlasVault"] = vault.address;
  console.log("AtlasVault deployed at:", vault.address);

  const RewardDistributor = await ethers.getContractFactory("rewards/RewardDistributorV2");
  const rewardDistributor = await upgrades.deployProxy(RewardDistributor, [vault.address, atlasToken.address], { kind: "uups" });
  await rewardDistributor.deployed();
  deployed["RewardDistributor"] = rewardDistributor.address;
  console.log("RewardDistributor deployed at:", rewardDistributor.address);

  // -------- 8) Deploy Multicall --------
  console.log("\n8) Deploying Multicall...");
  const Multicall = await ethers.getContractFactory("utils/Multicall");
  const multicall = await Multicall.deploy();
  await multicall.deployed();
  deployed["Multicall"] = multicall.address;
  console.log("Multicall deployed at:", multicall.address);

  // -------- 9) Write deployed addresses --------
  fs.writeFileSync(outFile, JSON.stringify(deployed, null, 2));
  console.log("\n✅ Deployment complete. Addresses written to:", outFile);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
