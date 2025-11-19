import { ethers } from "hardhat";
import fs from "fs";
import dotenv from "dotenv";
dotenv.config();

async function main() {
  const addresses = JSON.parse(
    fs.existsSync("deployed_addresses.json")
      ? fs.readFileSync("deployed_addresses.json", "utf8")
      : "{}"
  );

  // ============= VALIDATION =============
  if (!process.env.VAULT_ADMIN_ADDRESS) {
    throw new Error("VAULT_ADMIN_ADDRESS missing in .env");
  }

  const multisig = process.env.VAULT_ADMIN_ADDRESS;

  // ============= DEPLOY WETH =============
  console.log("Deploying WETH...");
  const WETH = await ethers.getContractFactory("WETH9");
  const weth = await WETH.deploy();
  await weth.deployed();
  addresses["WETH"] = weth.address;
  console.log("WETH deployed at:", weth.address);

  // ============= DEPLOY FACTORY =============
  console.log("Deploying AtlasFactory (UniswapV2Factory clone)...");
  const Factory = await ethers.getContractFactory("AtlasFactory");
  const factory = await Factory.deploy(multisig); // feeToSetter = multisig
  await factory.deployed();
  addresses["AtlasFactory"] = factory.address;
  console.log("Factory deployed at:", factory.address);

  // ============= FEE CONFIG =============
  console.log("Setting feeTo to multisig...");
  const txFeeTo = await factory.setFeeTo(multisig);
  await txFeeTo.wait();
  console.log("feeTo set to:", multisig);

  // ============= DEPLOY ROUTER =============
  console.log("Deploying AtlasRouter...");
  const Router = await ethers.getContractFactory("AtlasRouter");
  const router = await Router.deploy(factory.address, weth.address);
  await router.deployed();
  addresses["AtlasRouter"] = router.address;
  console.log("Router deployed at:", router.address);

  // ============= SAVE DEPLOYMENTS =============
  fs.writeFileSync("deployed_addresses.json", JSON.stringify(addresses, null, 2));
  console.log("Addresses saved to deployed_addresses.json");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
