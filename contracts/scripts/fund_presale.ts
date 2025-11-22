// scripts/fund_presale.ts
import { ethers } from "hardhat";
import fs from "fs";
import path from "path";
import * as dotenv from "dotenv";
dotenv.config();

const deployedFile = path.join(__dirname, "..", "deployed_addresses.json");

async function main() {
  if (!fs.existsSync(deployedFile)) throw new Error("deployed_addresses.json not found");
  const addresses = JSON.parse(fs.readFileSync(deployedFile, "utf8"));

  const [deployer] = await ethers.getSigners();
  console.log("Funding presale and LP allocations as:", deployer.address);

  // Load contracts
  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasToken = AtlasToken.attach(addresses["AtlasToken"]);

  const AtlasVault = await ethers.getContractFactory("vaults/AtlasVault");
  const vault = AtlasVault.attach(addresses["AtlasVault"]);

  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = Vesting.attach(addresses["Vesting"]);

  const Presale = await ethers.getContractFactory("presale/Presale");
  const presale = Presale.attach(addresses["AtlasPresale"]);

  const LPRewardSink = await ethers.getContractFactory("rewards/LPRewardSink");
  const lpSink = LPRewardSink.attach(addresses["LiquidityLP"]);

  // Allocations
  const decimals = await atlasToken.decimals().catch(() => 18);
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000";
  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000";

  const presaleAmountUnits = ethers.utils.parseUnits(PRESALE_ALLOCATION, decimals);
  const lpAmountUnits = ethers.utils.parseUnits(LP_REWARDS, decimals);

  // === 1) Fund Vesting schedules ===
  console.log("\n1) Funding Vesting Schedules...");

  const vestingBeneficiaries = JSON.parse(process.env.VESTING_BENEFICIARIES || "[]");
  const vestingAmounts = JSON.parse(process.env.VESTING_AMOUNTS || "[]");

  if (vestingBeneficiaries.length !== vestingAmounts.length) {
    throw new Error("VESTING_BENEFICIARIES and VESTING_AMOUNTS length mismatch");
  }

  for (let i = 0; i < vestingBeneficiaries.length; i++) {
    const beneficiary = vestingBeneficiaries[i];
    const amount = ethers.utils.parseUnits(vestingAmounts[i], decimals);

    // Transfer tokens from deployer to vesting contract
    const txApprove = await atlasToken.approve(vesting.address, amount);
    await txApprove.wait();

    const txSchedule = await vesting.setVestingSchedule(
      beneficiary,
      amount,
      Math.floor(Date.now() / 1000), // start now
      0, // cliff
      30 * 24 * 60 * 60 // duration 30 days default
    );
    await txSchedule.wait();
    console.log(`Set vesting for ${beneficiary}: ${vestingAmounts[i]} tokens`);
  }

  // === 2) Fund Presale ===
  console.log("\n2) Funding Presale Contract...");
  const txApprovePresale = await atlasToken.approve(presale.address, presaleAmountUnits);
  await txApprovePresale.wait();
  const txFundPresale = await atlasToken.transfer(presale.address, presaleAmountUnits);
  await txFundPresale.wait();
  console.log(`Transferred ${PRESALE_ALLOCATION} tokens to Presale contract`);

  // === 3) Fund LP Rewards ===
  console.log("\n3) Funding LP Reward Sink...");
  const txApproveLP = await atlasToken.approve(lpSink.address, lpAmountUnits);
  await txApproveLP.wait();
  const txFundLP = await atlasToken.transfer(lpSink.address, lpAmountUnits);
  await txFundLP.wait();
  console.log(`Transferred ${LP_REWARDS} tokens to LPRewardSink`);

  console.log("\n✅ Funding complete");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Funding failed:", err);
    process.exit(1);
  });
