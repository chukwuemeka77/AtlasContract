import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import fs from "fs";

dotenv.config();

const deployed = JSON.parse(fs.readFileSync("deployed_addresses.json", "utf8"));
const { LP_DURATION } = process.env; // optional

async function main() {
  const [deployer] = await ethers.getSigners();
  const token = await ethers.getContractAt("AtlasToken", deployed.AtlasToken);
  const vesting = await ethers.getContractAt("AtlasVesting", deployed.AtlasVesting);

  // Example batch LP allocations
  const lpAllocations = [
    { user: "0xUser1", amount: "1000000" },
    { user: "0xUser2", amount: "2000000" },
  ];

  for (const alloc of lpAllocations) {
    const amount = ethers.utils.parseUnits(alloc.amount, 18);
    await token.connect(deployer).approve(vesting.address, amount);
    await vesting.connect(deployer).stake(amount);
  }

  console.log("LP schedules initialized for all users.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
