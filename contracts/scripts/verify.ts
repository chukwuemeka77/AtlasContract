// scripts/verify.ts
import hre from "hardhat";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";
dotenv.config();

const deployedFile = path.join(__dirname, "..", "deployed_addresses.json");

type ConstructorArgsMap = {
  [contractName: string]: any[];
};

async function verifyAddress(address: string, contractName: string, constructorArgs: any[]) {
  try {
    console.log(`Verifying ${contractName} at ${address} with args:`, constructorArgs);
    // Hardhat Etherscan plugin expects: run("verify:verify", { address, constructorArguments: [...] })
    await hre.run("verify:verify", {
      address,
      constructorArguments: constructorArgs,
    });
    console.log(`✅ Verified ${contractName} (${address})`);
  } catch (err: any) {
    // Etherscan may return "Contract source code already verified" or rate-limit errors
    const msg = err?.message ?? err;
    if (msg && msg.toString().toLowerCase().includes("already verified")) {
      console.log(`ℹ️ ${contractName} already verified on explorer.`);
    } else {
      console.error(`❌ Verification failed for ${contractName} (${address}):`, msg);
    }
  }
}

async function main() {
  if (!fs.existsSync(deployedFile)) {
    throw new Error(`deployed_addresses.json not found at ${deployedFile}. Run deploy script first.`);
  }

  if (!process.env.ETHERSCAN_API_KEY) {
    console.warn("⚠️ ETHERSCAN_API_KEY missing in .env — verification will likely fail.");
  }

  const addresses = JSON.parse(fs.readFileSync(deployedFile, "utf8"));

  // Add or extend constructor arguments for each contract you deployed.
  // Keep keys matching the names you used when writing deployed_addresses.json
  const constructorArgsMap: ConstructorArgsMap = {
    // Example entries — modify to match your actual constructors & order
    "WETH": [], // WETH9 has no constructor args
    "AtlasFactory": [process.env.VAULT_ADMIN_ADDRESS ?? ""], // constructor(feeToSetter)
    "AtlasRouter": [addresses["AtlasFactory"] ?? "", addresses["WETH"] ?? ""], // constructor(factory, WETH)
    // If you deployed AtlasToken with (name, symbol):
    "AtlasToken": ["Atlas Token", "ATLAS"],
    // AtlasVault(address atlasToken, address admin)
    "AtlasVault": [addresses["AtlasToken"] ?? "", process.env.VAULT_ADMIN_ADDRESS ?? ""],
    // LiquidityLP(name, symbol)
    "LiquidityLP": ["Atlas LP Token", "ALP"],
    // RewardDistributor(atlasToken, vaultAddress, lpToken?) — adjust if different
    "RewardDistributor": [addresses["AtlasToken"] ?? "", addresses["AtlasVault"] ?? ""],
    // Presale(atlas, vault, usdc, price, maxPresale, cliff, duration)
    "AtlasPresale": [
      addresses["AtlasToken"] ?? "",
      addresses["AtlasVault"] ?? "",
      process.env.USDC_ADDRESS ?? "",
      process.env.PRESALE_PRICE ?? "50000000",
      process.env.MAX_PRESALE_AMOUNT ?? "300000000",
      0,
      Number(process.env.PRESALE_VESTING_SECONDS ?? 2592000),
    ],
    // Add additional contract constructor arg mappings here...
  };

  // Iterate through addresses file and try verifying known items.
  for (const key of Object.keys(addresses)) {
    const address = addresses[key];
    if (!address) continue;
    const contractName = key; // we saved names as keys when writing file
    const constructorArgs = constructorArgsMap[contractName] ?? [];

    // Skip addresses that look invalid
    if (typeof address !== "string" || !address.startsWith("0x") || address.length < 40) {
      console.log(`Skipping ${contractName} because address appears invalid:`, address);
      continue;
    }

    // Attempt verification
    await verifyAddress(address, contractName, constructorArgs);
    // Respect rate limits — small pause between attempts
    await new Promise((res) => setTimeout(res, 1500));
  }

  console.log("Verification script finished.");
}

main().catch((err) => {
  console.error("Script error:", err);
  process.exitCode = 1;
});
