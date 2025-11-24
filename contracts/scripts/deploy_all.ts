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
  WETH_ADDRESS,
  LAUNCHPAD_FEE,
  MIN_LOCK_DURATION,
} = process.env;

if (!VAULT_ADMIN_ADDRESS) throw new Error("VAULT_ADMIN_ADDRESS not set in .env");
if (!MIN_LOCK_DURATION) throw new Error("MIN_LOCK_DURATION not set in .env");

async function main() {
  const deployed: Record<string, string> = {};
  console.log("Deploying contracts with admin:", VAULT_ADMIN_ADDRESS);

  // -------------------------------
  // 1️⃣ Deploy AtlasToken
  // -------------------------------
  const Token = await ethers.getContractFactory("AtlasToken");
  const token = await upgrades.deployProxy(Token, [VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await token.deployed();
  deployed.AtlasToken = token.address;
  console.log("AtlasToken deployed at:", token.address);

  // -------------------------------
  // 2️⃣ Deploy Presale
  // -------------------------------
  const Presale = await ethers.getContractFactory("AtlasPresale");
  const presale = await upgrades.deployProxy(Presale, [VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await presale.deployed();
  deployed.AtlasPresale = presale.address;
  console.log("AtlasPresale deployed at:", presale.address);

  // -------------------------------
  // 3️⃣ Deploy Vesting (optional buyer vesting)
  // -------------------------------
  const Vesting = await ethers.getContractFactory("AtlasVesting");
  const vesting = await upgrades.deployProxy(Vesting, [VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await vesting.deployed();
  deployed.AtlasVesting = vesting.address;
  console.log("AtlasVesting deployed at:", vesting.address);

  // -------------------------------
  // 4️⃣ Deploy Launchpad with fee & optional buyer vesting
  // -------------------------------
  const Launchpad = await ethers.getContractFactory("AtlasLaunchpad");
  const launchpad = await upgrades.deployProxy(
    Launchpad,
    [VAULT_ADMIN_ADDRESS, vesting.address],
    { kind: "uups" }
  );
  await launchpad.deployed();
  deployed.AtlasLaunchpad = launchpad.address;
  console.log("AtlasLaunchpad deployed at:", launchpad.address);

  // -------------------------------
  // 5️⃣ Deploy Reward Distributor / LP rewards
  // -------------------------------
  const Reward = await ethers.getContractFactory("AtlasLPRewards");
  const reward = await upgrades.deployProxy(
    Reward,
    [token.address, ethers.constants.AddressZero], // lpToken will be set per pool later
    { kind: "uups" }
  );
  await reward.deployed();
  deployed.RewardDistributor = reward.address;
  console.log("RewardDistributor deployed at:", reward.address);

  // -------------------------------
  // 6️⃣ Deploy Bridge
  // -------------------------------
  const Bridge = await ethers.getContractFactory("AtlasBridge");
  const bridge = await upgrades.deployProxy(
    Bridge,
    [token.address, VAULT_ADMIN_ADDRESS],
    { kind: "uups" }
  );
  await bridge.deployed();
  deployed.AtlasBridge = bridge.address;
  console.log("AtlasBridge deployed at:", bridge.address);

  // -------------------------------
  // 7️⃣ Deploy AMM (Factory & Router)
  // -------------------------------
  const Factory = await ethers.getContractFactory("AtlasFactory");
  const factory = await Factory.deploy(VAULT_ADMIN_ADDRESS);
  await factory.deployed();
  deployed.AtlasFactory = factory.address;

  const Router = await ethers.getContractFactory("AtlasRouter");
  const router = await Router.deploy(factory.address, WETH_ADDRESS);
  await router.deployed();
  deployed.AtlasRouter = router.address;
  console.log("AMM deployed: Factory =", factory.address, "Router =", router.address);

  // -------------------------------
  // 8️⃣ Deploy Liquidity Locker
  // -------------------------------
  const LiquidityLocker = await ethers.getContractFactory("LiquidityLocker");
  const locker = await LiquidityLocker.deploy();
  await locker.deployed();
  deployed.LiquidityLocker = locker.address;
  console.log("LiquidityLocker deployed at:", locker.address);

  // -------------------------------
  // 9️⃣ Token Allocations
  // -------------------------------
  const parse = (amount?: string) => ethers.utils.parseUnits(amount || "0", 18);

  // Presale
  await token.transfer(presale.address, parse(PRESALE_ALLOCATION));

  // LP & staking rewards
  await token.transfer(reward.address, parse(LP_REWARD_ALLOCATION));

  // DEX liquidity
  await token.transfer(router.address, parse(DEX_LIQUIDITY_ALLOCATION));

  // CEX / Treasury / Marketing / Team
  const vaultAllocations = [
    CEX_LISTINGS_ALLOCATION,
    TREASURY_ALLOCATION,
    MARKETING_ALLOCATION,
    TEAM_ALLOCATION,
  ];
  for (const alloc of vaultAllocations) {
    await token.transfer(VAULT_ADMIN_ADDRESS, parse(alloc));
  }

  // -------------------------------
  // 🔹 Handle Launchpad Fee in Atlas (ETH equivalent)
  // -------------------------------
  const feeEth = parseFloat(LAUNCHPAD_FEE || "0.2");
  // TODO: replace with oracle or on-chain price feed
  const atlasPerEth = 1000; // example placeholder
  const feeAtlas = ethers.utils.parseUnits((feeEth * atlasPerEth).toString(), 18);
  await token.transfer(launchpad.address, feeAtlas);
  console.log(`Launchpad fee allocated: ${feeAtlas.toString()} Atlas`);

  // -------------------------------
  // 10️⃣ Optional: Pre-deploy a default LP pair and attach rewards
  // -------------------------------
  // Example: Atlas/WETH
  // const Pair = await ethers.getContractFactory("MultiTokenPair");
  // const pair = await Pair.deploy(token.address, WETH_ADDRESS, MIN_LOCK_DURATION);
  // await pair.deployed();
  // deployed.DefaultPair = pair.address;
  // await reward.setLPToken(pair.address);

  // -------------------------------
  // 11️⃣ Grant Roles
  // -------------------------------
  const MINTER_ROLE = await token.MINTER_ROLE();
  await token.grantRole(MINTER_ROLE, VAULT_ADMIN_ADDRESS);

  // -------------------------------
  // 12️⃣ Save Deployed Addresses
  // -------------------------------
  fs.writeFileSync("deployed_addresses.json", JSON.stringify(deployed, null, 2));
  console.log("All deployed addresses saved to deployed_addresses.json");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
