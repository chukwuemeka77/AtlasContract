import { ethers, upgrades } from "hardhat";
import fs from "fs";
import dotenv from "dotenv";
dotenv.config();

async function main() {
  const addresses: Record<string, string> = {};

  // Deploy AtlasToken
  const AtlasToken = await ethers.getContractFactory("AtlasToken");
  const token = await AtlasToken.deploy();
  await token.deployed();
  addresses["AtlasToken"] = token.address;
  console.log("AtlasToken deployed:", token.address);

  // Deploy AtlasVault with multisig admin
  const AtlasVault = await ethers.getContractFactory("AtlasVault");
  const vault = await AtlasVault.deploy(process.env.VAULT_ADMIN_ADDRESS || "");
  await vault.deployed();
  addresses["AtlasVault"] = vault.address;

  // Deploy RewardDistributorV2 as upgradeable
  const RewardDistributorV2 = await ethers.getContractFactory("RewardDistributorV2");
  const rewardDistributor = await upgrades.deployProxy(
    RewardDistributorV2,
    [vault.address, token.address],
    { initializer: "initialize" }
  );
  await rewardDistributor.deployed();
  addresses["RewardDistributorV2"] = rewardDistributor.address;

  // Write addresses to JSON
  fs.writeFileSync("deployed_addresses.json", JSON.stringify(addresses, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
