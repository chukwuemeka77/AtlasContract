import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import fs from "fs";

dotenv.config();

const { LP_DURATION, PRESALE_VESTING_MONTHS, PRESALE_TGE_PERCENT } = process.env;

if (!LP_DURATION) throw new Error("LP_DURATION not set in .env");

const deployed = JSON.parse(fs.readFileSync("deployed_addresses.json", "utf8"));

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Funding presale and LP schedules using deployer:", deployer.address);

  const token = await ethers.getContractAt("AtlasToken", deployed.AtlasToken);
  const vesting = await ethers.getContractAt("AtlasVesting", deployed.AtlasVesting);
  const presale = await ethers.getContractAt("AtlasPresale", deployed.AtlasPresale);
  const reward = await ethers.getContractAt("RewardDistributor", deployed.RewardDistributor);

  // -------------------------------
  // 1️⃣ Fund Presale Allocations
  // -------------------------------
  const presaleAllocations = [
    { user: "0xUser1", amount: ethers.utils.parseUnits("1000000", 18) },
    { user: "0xUser2", amount: ethers.utils.parseUnits("2000000", 18) },
  ];

  for (const alloc of presaleAllocations) {
    // Use safeTransfer for each allocation
    const tx = await token.transfer(presale.address, alloc.amount);
    await tx.wait();
    await presale.setVesting(alloc.user, alloc.amount, Number(PRESALE_VESTING_MONTHS), Number(PRESALE_TGE_PERCENT));
    console.log(`Presale funded for ${alloc.user}: ${alloc.amount.toString()}`);
  }

  // -------------------------------
  // 2️⃣ Fund LP & Staking Rewards
  // -------------------------------
  const lpAllocations = [
    { user: "0xUser3", amount: ethers.utils.parseUnits("500000", 18) },
    { user: "0xUser4", amount: ethers.utils.parseUnits("500000", 18) },
  ];

  for (const alloc of lpAllocations) {
    const tx = await token.transfer(reward.address, alloc.amount);
    await tx.wait();
    await reward.setSchedule(alloc.user, alloc.amount, Number(LP_DURATION));
    console.log(`LP/staking reward set for ${alloc.user}: ${alloc.amount.toString()}`);
  }

  console.log("✅ Presale and LP schedules funded successfully!");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
