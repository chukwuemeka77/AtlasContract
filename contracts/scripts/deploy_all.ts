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

  // --- required env checks ---
  const RPC = process.env.RPC_URL;
  if (!RPC) throw new Error("RPC_URL missing in .env");
  const PRIVATE_KEY = process.env.PRIVATE_KEY;
  if (!PRIVATE_KEY) console.warn("WARNING: PRIVATE_KEY missing — cannot send live txs");

  // token & vault params
  const VAULT_ADMIN = process.env.VAULT_ADMIN_ADDRESS;
  if (!VAULT_ADMIN) throw new Error("VAULT_ADMIN_ADDRESS missing in .env");

  const USDC = process.env.TOKEN1 || process.env.USDC_ADDRESS || "";
  if (!USDC) console.warn("Warning: TOKEN1 / USDC_ADDRESS not set. You should set it in .env for presale/liquidity.");

  // Allocation amounts (strings) - parseUnits later
  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000"; // 1B default
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000"; // 300M default
  const TOTAL_SUPPLY = process.env.TOTAL_SUPPLY || "10000000000"; // 10B default

  // Presale params
  const PRESALE_PRICE = process.env.PRESALE_PRICE || "50000000"; // e.g. 0.05 with USDC 6 decimals -> 50000000
  const PRESALE_VESTING_MONTHS = Number(process.env.PRESALE_VESTING_MONTHS || 1);
  const PRESALE_TGE_PERCENT = Number(process.env.PRESALE_TGE_PERCENT || 15);

  // fee & LP params
  const FEE_PPM = Number(process.env.FEE_PPM || 3000);

  // output path for deployed addresses
  const outDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, "deployed_addresses.json");
  const deployed: DeployedMap = {};

  // ---------- 1) Deploy AtlasToken (upgradeable) ----------
  console.log("\n1) Deploying AtlasToken (UUPS upgradeable)...");
  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  // constructor for our AtlasToken is (string name_, string symbol_) per your source
  const atlasTokenProxy = await upgrades.deployProxy(AtlasToken, ["Atlas Token", "ATLAS"], { kind: "uups" });
  await atlasTokenProxy.deployed();
  const atlasTokenAddress = atlasTokenProxy.address;
  console.log("AtlasToken proxy:", atlasTokenAddress);
  deployed["AtlasToken"] = atlasTokenAddress;

  // ---------- 2) Deploy AtlasVault (upgradeable) ----------
  console.log("\n2) Deploying AtlasVault (UUPS upgradeable)...");
  const AtlasVault = await ethers.getContractFactory("vaults/AtlasVault");
  // Initialize with token address and admin
  const atlasVaultProxy = await upgrades.deployProxy(AtlasVault, [atlasTokenAddress, VAULT_ADMIN], { kind: "uups" });
  await atlasVaultProxy.deployed();
  console.log("AtlasVault proxy:", atlasVaultProxy.address);
  deployed["AtlasVault"] = atlasVaultProxy.address;

  // ---------- 3) Mint / Stage supply ---------
  console.log("\n3) Minting & staging allocations (staged mint approach)...");
  // Ensure atlasTokenProxy has a 'mint' with signature (address,uint256,bytes32,string) or simpler mint(to, amount)
  // We'll attempt common mint(to, amount) first, else call the specialized one.
  const atlasToken = AtlasToken.attach(atlasTokenAddress);

  // Total supply to mint (decimals assumed 18)
  const decimals = await atlasToken.decimals().catch(() => 18);
  const totalSupplyUnits = ethers.utils.parseUnits(TOTAL_SUPPLY, decimals);
  console.log("Minting total supply:", TOTAL_SUPPLY, "tokens ->", totalSupplyUnits.toString());

  // Mint full supply to deployer, then move allocations to vault / presale as needed.
  // If your token has role-based mint (MINTER_ROLE), we need to grant and use it. We'll try mint and fallback gracefully.
  try {
    // try simple mint(address,uint256)
    const mintTx = await atlasToken.mint(deployer.address, totalSupplyUnits);
    await mintTx.wait();
    console.log("Minted total supply to deployer:", deployer.address);
  } catch (err) {
    console.warn("atlasToken.mint(deployer, total) failed — token may use different signature or mint restricted. Please mint manually or update token contract.");
  }

  // Transfer allocations into AtlasVault
  const vault = AtlasVault.attach(atlasVaultProxy.address);
  try {
    const lpAmount = ethers.utils.parseUnits(LP_REWARDS, decimals);
    const presaleAmount = ethers.utils.parseUnits(PRESALE_ALLOCATION, decimals);

    // approve + transfer if needed (ERC20 transfer from deployer)
    const balance = await atlasToken.balanceOf(deployer.address);
    console.log("Deployer token balance:", ethers.utils.formatUnits(balance, decimals));

    if (balance.gte(lpAmount.add(presaleAmount))) {
      // transfer to vault
      await atlasToken.transfer(atlasVaultProxy.address, lpAmount.add(presaleAmount));
      console.log("Transferred LP + Presale allocations to AtlasVault");
    } else {
      console.warn("Not enough token balance on deployer to fund vault allocations. Please top up or mint to vault directly.");
    }

    deployed["Allocations"] = {
      LP_REWARDS: lpAmount.toString(),
      PRESALE_ALLOCATION: presaleAmount.toString(),
    };
  } catch (err) {
    console.warn("Allocation transfers to vault failed:", (err as Error).message);
  }

  // ---------- 4) Deploy RewardDistributorV2 (upgradeable) ----------
  console.log("\n4) Deploying RewardDistributorV2 (UUPS upgradeable) ...");
  const RewardDistributorV2 = await ethers.getContractFactory("rewards/RewardDistributorV2");
  // initialize with vault address & fee token perhaps
  const rewardDistributorProxy = await upgrades.deployProxy(RewardDistributorV2, [atlasVaultProxy.address, atlasTokenAddress], { kind: "uups" });
  await rewardDistributorProxy.deployed();
  console.log("RewardDistributorV2 proxy:", rewardDistributorProxy.address);
  deployed["RewardDistributorV2"] = rewardDistributorProxy.address;

  // ---------- 5) Deploy LPRewardSink & StakingRewardSink (upgradeable) ----------
  console.log("\n5) Deploying LPRewardSink & StakingRewardSink (UUPS upgradeable) ...");
  const LPRewardSink = await ethers.getContractFactory("rewards/LPRewardSink");
  const lpSinkProxy = await upgrades.deployProxy(LPRewardSink, [atlasVaultProxy.address], { kind: "uups" });
  await lpSinkProxy.deployed();
  console.log("LPRewardSink proxy:", lpSinkProxy.address);
  deployed["LPRewardSink"] = lpSinkProxy.address;

  const StakingRewardSink = await ethers.getContractFactory("rewards/StakingRewardSink");
  const stakingSinkProxy = await upgrades.deployProxy(StakingRewardSink, [atlasVaultProxy.address], { kind: "uups" });
  await stakingSinkProxy.deployed();
  console.log("StakingRewardSink proxy:", stakingSinkProxy.address);
  deployed["StakingRewardSink"] = stakingSinkProxy.address;

  // Connect reward distributor to sinks (if interface exists)
  try {
    const rd = RewardDistributorV2.attach(rewardDistributorProxy.address);
    if ((rd as any).setLpSink) {
      await (rd as any).setLpSink(lpSinkProxy.address);
      console.log("Set LP sink on RewardDistributor");
    }
    if ((rd as any).setStakingSink) {
      await (rd as any).setStakingSink(stakingSinkProxy.address);
      console.log("Set Staking sink on RewardDistributor");
    }
  } catch (err) {
    console.warn("Couldn't wire sinks to RewardDistributor automatically:", (err as Error).message);
  }

  // ---------- 6) Deploy AMM Factory & Router (immutable) ----------
  console.log("\n6) Deploying AMM core (Factory & Router) ...");
  const AtlasFactory = await ethers.getContractFactory("amm/AtlasFactory");
  const factory = await AtlasFactory.deploy(deployer.address); // owner/feeToSetter
  await factory.deployed();
  console.log("AtlasFactory:", factory.address);
  deployed["AtlasFactory"] = factory.address;

  const AtlasRouter = await ethers.getContractFactory("amm/AtlasRouter");
  // Router constructor might be (factoryAddress, WETH_address) or (factory, rewardDistributor) — adjust as per your router
  const WETH = process.env.WETH_ADDRESS || process.env.TOKEN1 || "";
  const router = await AtlasRouter.deploy(factory.address, WETH || atlasTokenAddress);
  await router.deployed();
  console.log("AtlasRouter:", router.address);
  deployed["AtlasRouter"] = router.address;

  // Grant FACTORY_ROLE to factory for pairs that require it
  // If AtlasPair expects FACTORY_ROLE to be granted after pair creation, we'll grant to factory later.

  // ---------- 7) Deploy Presale (upgradeable) ----------
  console.log("\n7) Deploying Presale (UUPS upgradeable) ...");
  const Presale = await ethers.getContractFactory("presale/Presale");
  // Presale constructor args: (atlasToken, vault, paymentToken (USDC), price, maxAmount, cliff, duration)
  const vestingDurationSecs = PRESALE_VESTING_MONTHS * 30 * 24 * 60 * 60;
  const presaleProxy = await upgrades.deployProxy(
    Presale,
    [atlasTokenAddress, atlasVaultProxy.address, USDC, PRESALE_PRICE, ethers.utils.parseUnits(PRESALE_ALLOCATION, decimals), 0, vestingDurationSecs],
    { kind: "uups" }
  );
  await presaleProxy.deployed();
  console.log("Presale proxy:", presaleProxy.address);
  deployed["Presale"] = presaleProxy.address;

  // Fund Presale from Vault: call vault.transferToPresale or transfer tokens from vault if permitted.
  try {
    // If AtlasVault has "transfer" callable by admin, use it; otherwise instruct multisig
    if ((atlasVaultProxy as any).transfer) {
      const presaleAmountUnits = ethers.utils.parseUnits(PRESALE_ALLOCATION, decimals);
      await (atlasVaultProxy as any).transfer(presaleProxy.address, presaleAmountUnits);
      console.log("Transferred presale allocation to Presale contract from Vault.");
    } else {
      console.log("AtlasVault has no direct transfer function - ensure you move PRESALE_ALLOCATION tokens into presale contract from the multisig/vault admin.");
    }
  } catch (err) {
    console.warn("Funding Presale failed automatically:", (err as Error).message);
  }

  // ---------- 8) Roles & Grants ----------
  console.log("\n8) Granting roles and final wiring ...");

  // Grant MINTER_ROLE for AtlasToken to Vault & RewardDistributor (so vault can mint/stage rewards if needed)
  try {
    const MINTER_ROLE = await atlasToken.MINTER_ROLE();
    // grant to vault
    await atlasToken.grantRole(MINTER_ROLE, atlasVaultProxy.address);
    console.log("Granted MINTER_ROLE to AtlasVault");
    // grant to reward distributor if required
    await atlasToken.grantRole(MINTER_ROLE, rewardDistributorProxy.address).catch(() => console.warn("grantRole to rewardDistributor failed (maybe unnecessary)"));
  } catch (err) {
    console.warn("Grant MINTER_ROLE failed:", (err as Error).message);
  }

  // Grant FACTORY_ROLE to factory on new pairs (if pair implements role)
  try {
    const FACTORY_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("FACTORY_ROLE"));
    // If AtlasPair exists individually, you'd call grantRole on pair. For factory itself, set deployer as owner at construction time.
    // Example: factory.setFeeTo(rewardDistributor.address) if your factory supports feeTo
    if ((factory as any).setFeeTo) {
      await (factory as any).setFeeTo(rewardDistributorProxy.address);
      console.log("Factory feeTo set to RewardDistributor");
    }
  } catch (err) {
    console.warn("Factory wiring failed:", (err as Error).message);
  }

  // ---------- 9) Write deployed addresses to file ----------
  deployed["meta"] = {
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
  };

  fs.writeFileSync(outFile, JSON.stringify(deployed, null, 2));
  console.log("\n✅ Deployment complete. Addresses written to:", outFile);
  console.log("PLEASE update your .env with ATLAS_TOKEN_ADDRESS and ATLAS_VAULT_ADDRESS and other addresses as needed.");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Deployment failed:", err);
    process.exit(1);
  });
