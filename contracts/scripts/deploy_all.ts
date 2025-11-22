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
  PRESALE_PRICE,
  PRESALE_VESTING_MONTHS,
  PRESALE_TGE_PERCENT,
  LP_REWARD_RATE_PER_SECOND,
  VAULT_ADMIN_ADDRESS,
} = process.env;

const deployedAddressesFile = "deployed_addresses.json";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with:", deployer.address);

  const deployed: any = {};

  // -------------------------------
  // 1️⃣ Deploy AtlasToken
  // -------------------------------
  const AtlasToken = await ethers.getContractFactory("AtlasToken");
  const atlasToken = await upgrades.deployProxy(AtlasToken, ["Atlas Token", "ATLAS"], { kind: "uups" });
  await atlasToken.deployed();
  console.log("AtlasToken deployed at:", atlasToken.address);
  deployed.AtlasToken = atlasToken.address;

  // -------------------------------
  // 2️⃣ Deploy AtlasPresale
  // -------------------------------
  const AtlasPresale = await ethers.getContractFactory("AtlasPresale");
  const presale = await upgrades.deployProxy(
    AtlasPresale,
    [
      atlasToken.address,
      PRESALE_PRICE,
      PRESALE_TGE_PERCENT,
      PRESALE_VESTING_MONTHS,
      deployer.address, // admin
    ],
    { kind: "uups" }
  );
  await presale.deployed();
  console.log("AtlasPresale deployed at:", presale.address);
  deployed.AtlasPresale = presale.address;

  // -------------------------------
  // 3️⃣ Deploy AtlasVesting (Flexible LP)
  // -------------------------------
  const AtlasVesting = await ethers.getContractFactory("AtlasVesting");
  const vesting = await upgrades.deployProxy(
    AtlasVesting,
    [atlasToken.address, LP_REWARD_RATE_PER_SECOND],
    { kind: "uups" }
  );
  await vesting.deployed();
  console.log("AtlasVesting deployed at:", vesting.address);
  deployed.AtlasVesting = vesting.address;

  // -------------------------------
  // 4️⃣ Deploy AtlasBridge
  // -------------------------------
  const AtlasBridge = await ethers.getContractFactory("AtlasBridge");
  const bridge = await upgrades.deployProxy(AtlasBridge, [atlasToken.address, VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await bridge.deployed();
  console.log("AtlasBridge deployed at:", bridge.address);
  deployed.AtlasBridge = bridge.address;

  // -------------------------------
  // 5️⃣ Deploy AMM (Liquidity Pool / Router)
  // -------------------------------
  const AtlasFactory = await ethers.getContractFactory("AtlasFactory");
  const factory = await AtlasFactory.deploy(deployer.address);
  await factory.deployed();
  deployed.AtlasFactory = factory.address;

  const AtlasRouter = await ethers.getContractFactory("AtlasRouter");
  const router = await AtlasRouter.deploy(factory.address);
  await router.deployed();
  deployed.AtlasRouter = router.address;

  // -------------------------------
  // 6️⃣ Deploy RewardDistributor / Vault
  // -------------------------------
  const RewardDistributor = await ethers.getContractFactory("RewardDistributor");
  const rewards = await RewardDistributor.deploy(atlasToken.address, VAULT_ADMIN_ADDRESS);
  await rewards.deployed();
  deployed.RewardDistributor = rewards.address;

  // -------------------------------
  // 7️⃣ Fund Presale, LP, Treasury, DEX/CEX allocations
  // -------------------------------
  const allocations = [
    { addr: presale.address, amount: PRESALE_ALLOCATION },
    { addr: vesting.address, amount: LP_REWARD_ALLOCATION },
    { addr: router.address, amount: DEX_LIQUIDITY_ALLOCATION },
    // CEX listings can be sent to treasury/admin for external use
    { addr: VAULT_ADMIN_ADDRESS, amount: CEX_LISTINGS_ALLOCATION },
    { addr: VAULT_ADMIN_ADDRESS, amount: TREASURY_ALLOCATION },
    { addr: VAULT_ADMIN_ADDRESS, amount: MARKETING_ALLOCATION },
    { addr: VAULT_ADMIN_ADDRESS, amount: TEAM_ALLOCATION },
  ];

  for (const alloc of allocations) {
    const amount = ethers.utils.parseUnits(alloc.amount.toString(), 18);
    await atlasToken.mint(alloc.addr, amount);
    console.log(`Minted ${alloc.amount} tokens to ${alloc.addr}`);
  }

  // -------------------------------
  // 8️⃣ Save deployed addresses
  // -------------------------------
  fs.writeFileSync(deployedAddressesFile, JSON.stringify(deployed, null, 2));
  console.log("Deployed addresses saved to", deployedAddressesFile);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
