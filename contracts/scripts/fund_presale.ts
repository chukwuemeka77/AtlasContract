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

  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasToken = AtlasToken.attach(addresses["AtlasToken"]);

  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = Vesting.attach(addresses["Vesting"]);

  const Presale = await ethers.getContractFactory("presale/Presale");
  const presale = Presale.attach(addresses["AtlasPresale"]);

  const LPRewardSink = await ethers.getContractFactory("rewards/LPRewardSink");
  const lpSink = LPRewardSink.attach(addresses["LiquidityLP"]);

  const Multicall = await ethers.getContractFactory("utils/Multicall");
  const multicall = await Multicall.deploy();
  await multicall.deployed();
  console.log("Multicall deployed at:", multicall.address);

  const decimals = await atlasToken.decimals().catch(() => 18);
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000";
  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000";

  const presaleAmountUnits = ethers.utils.parseUnits(PRESALE_ALLOCATION, decimals);
  const lpAmountUnits = ethers.utils.parseUnits(LP_REWARDS, decimals);

  // === 1) Batch Vesting schedules ===
  console.log("\n1) Funding Vesting Schedules with Multicall...");

  const vestingBeneficiaries = JSON.parse(process.env.VESTING_BENEFICIARIES || "[]");
  const vestingAmounts = JSON.parse(process.env.VESTING_AMOUNTS || "[]");

  if (vestingBeneficiaries.length !== vestingAmounts.length) {
    throw new Error("VESTING_BENEFICIARIES and VESTING_AMOUNTS length mismatch");
  }

  const calls: string[] = [];
  const start = Math.floor(Date.now() / 1000);
  const cliff = 0;
  const duration = 30 * 24 * 60 * 60; // 30 days default

  for (let i = 0; i < vestingBeneficiaries.length; i++) {
    const beneficiary = vestingBeneficiaries[i];
    const amount = ethers.utils.parseUnits(vestingAmounts[i], decimals);
    const data = vesting.interface.encodeFunctionData("setVestingSchedule", [
      beneficiary,
      amount,
      start,
      cliff,
      duration,
    ]);
    calls.push(data);
  }

  // approve total for vesting contract
  const totalVesting = vestingAmounts.reduce(
    (acc: any, amt: any) => acc.add(ethers.utils.parseUnits(amt, decimals)),
    ethers.BigNumber.from(0)
  );
  await atlasToken.approve(vesting.address, totalVesting);
  console.log("Approved tokens for Vesting contract:", totalVesting.toString());

  const txMulticall = await multicall.multicall(calls);
  await txMulticall.wait();
  console.log(`Vesting schedules set for ${vestingBeneficiaries.length} beneficiaries`);

  // === 2) Fund Presale ===
  console.log("\n2) Funding Presale Contract...");
  await atlasToken.approve(presale.address, presaleAmountUnits);
  await atlasToken.transfer(presale.address, presaleAmountUnits);
  console.log(`Transferred ${PRESALE_ALLOCATION} tokens to Presale`);

  // === 3) Fund LP Rewards ===
  console.log("\n3) Funding LP Reward Sink...");
  await atlasToken.approve(lpSink.address, lpAmountUnits);
  await atlasToken.transfer(lpSink.address, lpAmountUnits);
  console.log(`Transferred ${LP_REWARDS} tokens to LPRewardSink`);

  console.log("\n✅ All funding complete with multicall batching for vesting");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Funding failed:", err);
    process.exit(1);
  });
