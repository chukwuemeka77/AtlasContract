// scripts/verify.ts
import hre from "hardhat";
import fs from "fs";
import path from "path";

const deployedFile = path.join(__dirname, "..", "deployed_addresses.json");

// Retry with backoff
async function retry<T>(fn: () => Promise<T>, retries = 5): Promise<T> {
  try {
    return await fn();
  } catch (err: any) {
    const msg = err?.message || "";
    if (retries > 0 && msg.toLowerCase().includes("rate")) {
      console.log("⏳ Rate limit hit. Retrying in 5s...");
      await new Promise((res) => setTimeout(res, 5000));
      return retry(fn, retries - 1);
    }
    throw err;
  }
}

async function verifyContract(
  name: string,
  address: string,
  constructorArguments: any[] = [],
  libraries: Record<string, string> = {}
) {
  try {
    await retry(() =>
      hre.run("verify:verify", {
        address,
        constructorArguments,
        libraries,
      })
    );
    console.log(`✅ Verified ${name}`);
  } catch (err: any) {
    const msg = err?.message || "";
    if (msg.includes("already verified")) {
      console.log(`ℹ️ ${name} already verified.`);
    } else {
      console.error(`❌ Failed verifying ${name}:`, msg);
    }
  }
}

async function main() {
  if (!fs.existsSync(deployedFile)) {
    throw new Error(`Missing deployed_addresses.json`);
  }

  const addresses = JSON.parse(fs.readFileSync(deployedFile, "utf8"));

  // REPLACE ALL VALUES WITH YOUR FINAL CONFIG
  const constructorArgsMap: Record<string, any[]> = {
    AtlasToken: ["Atlas Token", "ATLAS"],

    AtlasFactory: [process.env.FEE_TO_SETTER ?? ""],
    AtlasRouter: [addresses["AtlasFactory"], addresses["WETH"]],

    AtlasVault: [addresses["AtlasToken"], process.env.VAULT_ADMIN ?? ""],

    Presale: [
      addresses["AtlasToken"],
      addresses["AtlasVault"],
      process.env.USDC ?? "",
      process.env.PRESALE_PRICE ?? "50000000",
      process.env.MAX_PRESALE ?? "300000000",
      0,
      2592000,
    ],

    Launchpad: [
      addresses["AtlasToken"],
      process.env.LAUNCHPAD_ADMIN ?? "",
      "100000000000000000", // mincap
      "500000000000000000000", // maxcap
    ],

    RewardDistributorV2: [
      addresses["AtlasToken"],
      addresses["AtlasVault"],
      addresses["LPRewardSink"],
      addresses["StakingRewardSink"],
    ],

    LPRewardSink: [
      addresses["LiquidityLP"],
      addresses["AtlasToken"],
    ],

    StakingRewardSink: [
      addresses["AtlasToken"],
      addresses["AtlasToken"],
    ],

    MerkleAirdrop: [
      addresses["AtlasToken"],
      process.env.AIRDROP_MERKLE_ROOT ?? "",
    ],

    Governor: [
      addresses["AtlasToken"],
      addresses["Timelock"],
    ],

    Timelock: [
      process.env.GOV_ADMIN ?? "",
      3600, // 1 hr
    ],

    ProposalValidator: [
      "100000e18", // minVotes
      "20000e18"   // minStaked
    ]
  };

  // Libraries for AMM
  const libraryLinks: Record<string, Record<string, string>> = {
    AtlasPair: {
      Math: addresses["Math"],
      UQ112x112: addresses["UQ112x112"],
    },
  };

  for (const name of Object.keys(addresses)) {
    const address = addresses[name];
    const args = constructorArgsMap[name] ?? [];
    const libs = libraryLinks[name] ?? {};

    await verifyContract(name, address, args, libs);
  }

  console.log("🎉 Verification complete.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
