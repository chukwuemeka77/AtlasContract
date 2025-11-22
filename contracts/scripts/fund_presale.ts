// scripts/fund_presale.ts
import { ethers } from "hardhat";
import fs from "fs";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  const deployed = JSON.parse(fs.readFileSync("deployments/deployed_addresses.json", "utf8"));
  const atlasTokenAddr = deployed["AtlasToken"];
  const presaleAddr = deployed["Presale"];
  const lpSinkAddr = deployed["LPRewardSink"];

  const [deployer] = await ethers.getSigners();
  const atlasToken = await ethers.getContractAt("AtlasToken", atlasTokenAddr);

  const presaleAllocation = ethers.utils.parseUnits("600000000", 18);
  const lpAllocation = ethers.utils.parseUnits("400000000", 18);

  console.log("Funding Presale & LP reward allocations...");

  // Presale
  await atlasToken.transfer(presaleAddr, presaleAllocation);
  console.log(`Presale funded: ${ethers.utils.formatUnits(presaleAllocation)} tokens`);

  // LP Rewards
  await atlasToken.transfer(lpSinkAddr, lpAllocation);
  console.log(`LP rewards funded: ${ethers.utils.formatUnits(lpAllocation)} tokens`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
