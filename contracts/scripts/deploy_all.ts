import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";
import fs from "fs";

dotenv.config();

const {
  PRESALE_ALLOCATION,
  LP_REWARD_ALLOCATION,
  DEX_LIQUIDITY_ALLOCATION,
  CEX_LISTINGS_ALLOCATION,
  TREASURY_ALLOCATION,
  MARKETING_ALLOCATION,
  TEAM_ALLOCATION,
  SWAP_FEE_REWARD_PERCENT,
  SWAP_FEE_TREASURY_PERCENT,
  BRIDGE_FEE_TREASURY_PERCENT,
  PRESALE_PRICE,
  PRESALE_VESTING_MONTHS,
  PRESALE_TGE_PERCENT,
  VAULT_ADMIN_ADDRESS,
  WETH_ADDRESS,
  USDC_ADDRESS
} = process.env;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with:", deployer.address);

  // --------------------------
  // 1️⃣ Deploy Presale
  // --------------------------
  const Presale = await ethers.getContractFactory("AtlasPresale");
  const presale = await upgrades.deployProxy(Presale, [WETH_ADDRESS, USDC_ADDRESS], { kind: "uups" });
  await presale.deployed();
  console.log("Presale deployed:", presale.address);

  // --------------------------
  // 2️⃣ Deploy Vesting
  // --------------------------
  const Vesting = await ethers.getContractFactory("AtlasVesting");
  const vesting = await upgrades.deployProxy(Vesting, [PRESALE_VESTING_MONTHS, PRESALE_TGE_PERCENT], { kind: "uups" });
  await vesting.deployed();
  console.log("Vesting deployed:", vesting.address);

  // --------------------------
  // 3️⃣ Deploy Launchpad (optional, depends on project)
  // --------------------------
  const Launchpad = await ethers.getContractFactory("AtlasLaunchpad");
  const launchpad = await upgrades.deployProxy(Launchpad, [], { kind: "uups" });
  await launchpad.deployed();
  console.log("Launchpad deployed:", launchpad.address);

  // --------------------------
  // 4️⃣ Deploy Token
  // --------------------------
  const Token = await ethers.getContractFactory("AtlasToken");
  const token = await upgrades.deployProxy(Token, ["Atlas Token", "ATLAS"], { kind: "uups" });
  await token.deployed();
  console.log("Token deployed:", token.address);

  // --------------------------
  // 5️⃣ Deploy Bridge
  // --------------------------
  const Bridge = await ethers.getContractFactory("AtlasBridge");
  const bridge = await upgrades.deployProxy(Bridge, [token.address], { kind: "uups" });
  await bridge.deployed();
  console.log("Bridge deployed:", bridge.address);

  // --------------------------
  // 6️⃣ Deploy AMM (DEX)
  // --------------------------
  const Factory = await ethers.getContractFactory("AtlasFactory");
  const factory = await Factory.deploy(VAULT_ADMIN_ADDRESS!);
  await factory.deployed();
  console.log("AMM Factory deployed:", factory.address);

  const Router = await ethers.getContractFactory("AtlasRouter");
  const router = await Router.deploy(factory.address, WETH_ADDRESS!);
  await router.deployed();
  console.log("AMM Router deployed:", router.address);

  // --------------------------
  // 7️⃣ Deploy RewardDistributor / Vault
  // --------------------------
  const Vault = await ethers.getContractFactory("AtlasVault");
  const vault = await upgrades.deployProxy(Vault, [token.address, VAULT_ADMIN_ADDRESS!], { kind: "uups" });
  await vault.deployed();
  console.log("Vault deployed:", vault.address);

  const RewardDistributor = await ethers.getContractFactory("RewardDistributor");
  const rewardDistributor = await upgrades.deployProxy(RewardDistributor, [vault.address], { kind: "uups" });
  await rewardDistributor.deployed();
  console.log("RewardDistributor deployed:", rewardDistributor.address);

  // --------------------------
  // 8️⃣ Grant roles
  // --------------------------
  const MINTER_ROLE = await token.MINTER_ROLE();
  await token.grantRole(MINTER_ROLE, vault.address);
  console.log("Vault granted MINTER_ROLE on Token");

  // --------------------------
  // 9️⃣ Fund vault with allocations
  // --------------------------
  const decimals = 18;

  const allocations = {
    presale: PRESALE_ALLOCATION!,
    lpRewards: LP_REWARD_ALLOCATION!,
    dexLiquidity: DEX_LIQUIDITY_ALLOCATION!,
    cexLiquidity: CEX_LISTINGS_ALLOCATION!,
    treasury: TREASURY_ALLOCATION!,
    marketing: MARKETING_ALLOCATION!,
    team: TEAM_ALLOCATION!,
  };

  for (const [key, value] of Object.entries(allocations)) {
    const amount = ethers.utils.parseUnits(value, decimals);
    await token.transfer(vault.address, amount);
    console.log(`${key} funded:`, value);
  }

  // --------------------------
  // 10️⃣ Set fee allocations
  // --------------------------
  await rewardDistributor.setSwapFeeRewardPercent(Number(SWAP_FEE_REWARD_PERCENT));
  await rewardDistributor.setSwapFeeTreasuryPercent(Number(SWAP_FEE_TREASURY_PERCENT));
  await rewardDistributor.setBridgeFeeTreasuryPercent(Number(BRIDGE_FEE_TREASURY_PERCENT));
  console.log("RewardDistributor fee allocations set");

  // --------------------------
  // 11️⃣ Save deployed addresses
  // --------------------------
  const deployed = {
    presale: presale.address,
    vesting: vesting.address,
    launchpad: launchpad.address,
    token: token.address,
    bridge: bridge.address,
    factory: factory.address,
    router: router.address,
    vault: vault.address,
    rewardDistributor: rewardDistributor.address,
  };

  fs.writeFileSync("deployed_addresses.json", JSON.stringify(deployed, null, 2));
  console.log("deployed_addresses.json saved");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
