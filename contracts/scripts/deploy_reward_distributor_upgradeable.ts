import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  const feeToken = process.env.FEE_TOKEN!;
  const feeCollector = process.env.FEE_COLLECTOR || ethers.constants.AddressZero;
  const owner = process.env.DISTRIBUTOR_OWNER || (await ethers.getSigners())[0].address;

  if (!feeToken) throw new Error("FEE_TOKEN required in .env");

  console.log("Deploying RewardDistributorUpgradeable...");
  const Factory = await ethers.getContractFactory("RewardDistributorUpgradeable");
  const instance = await upgrades.deployProxy(Factory, [feeToken, feeCollector, owner], { initializer: "initialize" });
  await instance.deployed();

  console.log("RewardDistributorUpgradeable deployed at:", instance.address);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
