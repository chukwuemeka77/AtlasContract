import { ethers } from "hardhat";
import fs from "fs";
import dotenv from "dotenv";
dotenv.config();

async function main() {
  const addresses = JSON.parse(fs.existsSync("deployed_addresses.json") 
    ? fs.readFileSync("deployed_addresses.json", "utf-8") 
    : "{}"
  );

  if (!addresses["AtlasToken"]) {
    throw new Error("AtlasToken address not found. Deploy token first.");
  }

  console.log("Deploying Vesting contract...");
  const Vesting = await ethers.getContractFactory("Vesting");
  const vesting = await Vesting.deploy(
    addresses["AtlasToken"],
    process.env.VAULT_ADMIN_ADDRESS || "" // multisig as vesting admin
  );
  await vesting.deployed();
  addresses["Vesting"] = vesting.address;
  console.log("Vesting deployed at:", vesting.address);

  console.log("Deploying Presale contract...");
  const Presale = await ethers.getContractFactory("Presale");
  const presale = await Presale.deploy(
    addresses["AtlasToken"],
    vesting.address,
    process.env.VAULT_ADMIN_ADDRESS || "" // multisig as presale admin
  );
  await presale.deployed();
  addresses["Presale"] = presale.address;
  console.log("Presale deployed at:", presale.address);

  // Save updated addresses
  fs.writeFileSync("deployed_addresses.json", JSON.stringify(addresses, null, 2));
  console.log("Updated addresses saved to deployed_addresses.json");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
