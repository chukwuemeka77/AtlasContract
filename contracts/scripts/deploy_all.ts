import { ethers, upgrades } from "hardhat";
import * as fs from "fs";
import * as dotenv from "dotenv";

dotenv.config();

const {
  VAULT_ADMIN_ADDRESS
} = process.env;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with:", deployer.address);

  const deployed: any = {};

  // ------------------------------
  // 1️⃣ Deploy Presale
  // ------------------------------
  const Presale = await ethers.getContractFactory("AtlasPresale");
  const presale = await upgrades.deployProxy(Presale, [], { kind: "uups" });
  await presale.deployed();
  console.log("AtlasPresale deployed at:", presale.address);
  deployed.AtlasPresale = presale.address;

  // ------------------------------
  // 2️⃣ Deploy Vesting
  // ------------------------------
  const Vesting = await ethers.getContractFactory("AtlasVesting");
  const vesting = await upgrades.deployProxy(Vesting, [], { kind: "uups" });
  await vesting.deployed();
  console.log("AtlasVesting deployed at:", vesting.address);
  deployed.AtlasVesting = vesting.address;

  // ------------------------------
  // 3️⃣ Deploy Launchpad (if any)
  // ------------------------------
  const Launchpad = await ethers.getContractFactory("AtlasLaunchpad");
  const launchpad = await upgrades.deployProxy(Launchpad, [], { kind: "uups" });
  await launchpad.deployed();
  console.log("AtlasLaunchpad deployed at:", launchpad.address);
  deployed.AtlasLaunchpad = launchpad.address;

  // ------------------------------
  // 4️⃣ Deploy Token
  // ------------------------------
  const Token = await ethers.getContractFactory("AtlasToken");
  const token = await upgrades.deployProxy(Token, [], { kind: "uups" });
  await token.deployed();
  console.log("AtlasToken deployed at:", token.address);
  deployed.AtlasToken = token.address;

  // ------------------------------
  // 5️⃣ Deploy Vault
  // ------------------------------
  const Vault = await ethers.getContractFactory("AtlasVault");
  const vault = await upgrades.deployProxy(Vault, [VAULT_ADMIN_ADDRESS], { kind: "uups" });
  await vault.deployed();
  console.log("AtlasVault deployed at:", vault.address);
  deployed.AtlasVault = vault.address;

  // ------------------------------
  // 6️⃣ Deploy Bridge
  // ------------------------------
  const Bridge = await ethers.getContractFactory("AtlasBridge");
  const bridge = await upgrades.deployProxy(Bridge, [token.address], { kind: "uups" });
  await bridge.deployed();
  console.log("AtlasBridge deployed at:", bridge.address);
  deployed.AtlasBridge = bridge.address;

  // ------------------------------
  // 7️⃣ Deploy AMM (Factory + Router)
  // ------------------------------
  const Factory = await ethers.getContractFactory("AtlasFactory");
  const factory = await Factory.deploy();
  await factory.deployed();
  console.log("AtlasFactory deployed at:", factory.address);
  deployed.AtlasFactory = factory.address;

  const Router = await ethers.getContractFactory("AtlasRouter");
  const router = await Router.deploy(factory.address, token.address);
  await router.deployed();
  console.log("AtlasRouter deployed at:", router.address);
  deployed.AtlasRouter = router.address;

  // ------------------------------
  // 8️⃣ Deploy Reward Distributor
  // ------------------------------
  const Reward = await ethers.getContractFactory("RewardDistributor");
  const reward = await upgrades.deployProxy(Reward, [token.address], { kind: "uups" });
  await reward.deployed();
  console.log("RewardDistributor deployed at:", reward.address);
  deployed.RewardDistributor = reward.address;

  // ------------------------------
  // 9️⃣ Deploy Multicall (for batching)
  // ------------------------------
  const Multicall = await ethers.getContractFactory("Multicall");
  const multicall = await Multicall.deploy();
  await multicall.deployed();
  console.log("Multicall deployed at:", multicall.address);
  deployed.Multicall = multicall.address;

  // ------------------------------
  // Save deployed addresses
  // ------------------------------
  fs.writeFileSync("deployed_addresses.json", JSON.stringify(deployed, null, 2));
  console.log("All deployed addresses saved to deployed_addresses.json");

  // ------------------------------
  // 🔥 Fund presale, vesting, DEX & CEX allocations
  // ------------------------------
  console.log("Starting batch funding...");

  const fundPresale = await ethers.getContractAt("Multicall", multicall.address);
  const tokenContract = await ethers.getContractAt("AtlasToken", token.address);
  const vaultContract = await ethers.getContractAt("AtlasVault", vault.address);

  const allocations = JSON.parse(fs.readFileSync(".env", "utf-8")
    .split("\n")
    .filter(line => line.includes("_ALLOCATION"))
    .map(line => line.split("="))
    .reduce((acc: any, [key, value]) => ({ ...acc, [key]: value }), {}));

  const parseAmount = (amountStr: string) => ethers.utils.parseUnits(amountStr, 18);

  const calls: string[] = [];

  // Presale
  calls.push(tokenContract.interface.encodeFunctionData("transfer", [vault.address, parseAmount(allocations.PRESALE_ALLOCATION)]));
  calls.push(vaultContract.interface.encodeFunctionData("fundPresale", [presale.address, parseAmount(allocations.PRESALE_ALLOCATION), VAULT_ADMIN_ADDRESS]));

  // Vesting / LP Rewards
  calls.push(tokenContract.interface.encodeFunctionData("transfer", [vault.address, parseAmount(allocations.LP_REWARD_ALLOCATION)]));
  calls.push(vaultContract.interface.encodeFunctionData("fundVesting", [vesting.address, parseAmount(allocations.LP_REWARD_ALLOCATION)]));

  // DEX Liquidity
  calls.push(tokenContract.interface.encodeFunctionData("transfer", [vault.address, parseAmount(allocations.DEX_LIQUIDITY_ALLOCATION)]));
  calls.push(vaultContract.interface.encodeFunctionData("fundDexLiquidity", [parseAmount(allocations.DEX_LIQUIDITY_ALLOCATION)]));

  // CEX Listings
  calls.push(tokenContract.interface.encodeFunctionData("transfer", [vault.address, parseAmount(allocations.CEX_LISTINGS_ALLOCATION)]));
  calls.push(vaultContract.interface.encodeFunctionData("fundCexLiquidity", [parseAmount(allocations.CEX_LISTINGS_ALLOCATION)]));

  const tx = await fundPresale.multicall(calls);
  await tx.wait();
  console.log("Batch funding completed successfully!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
