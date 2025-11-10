import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  const feeToken = process.env.FEE_TOKEN!;
  const feeCollector = process.env.FEE_COLLECTOR || ethers.constants.AddressZero;
  const deployer = (await ethers.getSigners())[0];

  console.log("Deploying with:", deployer.address);
  console.log("Fee token:", feeToken);
  console.log("Fee collector:", feeCollector);

  if (!feeToken) {
    throw new Error("FEE_TOKEN env var is required");
  }

  const RewardDistributor = await ethers.getContractFactory("RewardDistributor");
  const rd = await RewardDistributor.deploy(feeToken, feeCollector);
  await rd.deployed();

  console.log("RewardDistributor deployed to:", rd.address);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
