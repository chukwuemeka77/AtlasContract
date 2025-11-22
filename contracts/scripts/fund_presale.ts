// scripts/fund_presale.ts
import { ethers } from "hardhat";
import fs from "fs";
import * as dotenv from "dotenv";
dotenv.config();

import { BigNumber } from "ethers";

async function main() {
  const deployer = (await ethers.getSigners())[0];
  console.log("Funding presale as:", deployer.address);

  const deployedFile = "deployed_addresses.json";
  if (!fs.existsSync(deployedFile)) throw new Error("deployed_addresses.json not found");

  const addresses = JSON.parse(fs.readFileSync(deployedFile, "utf-8"));
  const atlasTokenAddr = addresses["AtlasToken"];
  const vaultAddr = addresses["AtlasVault"];
  const presaleAddr = addresses["Presale"];
  const vestingAddr = addresses["Vesting"];
  const multicallAddr = addresses["Multicall"];

  if (!atlasTokenAddr || !vaultAddr || !presaleAddr || !vestingAddr || !multicallAddr) {
    throw new Error("Missing required contract addresses in deployed_addresses.json");
  }

  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const atlasToken = AtlasToken.attach(atlasTokenAddr);

  const Vesting = await ethers.getContractFactory("presale/Vesting");
  const vesting = Vesting.attach(vestingAddr);

  const Presale = await ethers.getContractFactory("presale/Presale");
  const presale = Presale.attach(presaleAddr);

  const Multicall = await ethers.getContractFactory("utils/Multicall");
  const multicall = Multicall.attach(multicallAddr);

  // ======== FUND VESTING ========
  const vestingParticipants = JSON.parse(process.env.VESTING_PARTICIPANTS || "[]"); 
  // format: [{address:"0x...", amount:"1000"}, ...]
  if (!vestingParticipants.length) {
    console.warn("No vesting participants provided in .env (VESTING_PARTICIPANTS)");
  } else {
    console.log("Preparing batch vesting allocations...");

    const calls = vestingParticipants.map((p: { address: string; amount: string }) => {
      const amount = ethers.utils.parseUnits(p.amount, 18);
      const data = vesting.interface.encodeFunctionData("setVestingSchedule", [
        p.address,
        amount,
        Math.floor(Date.now() / 1000), // start now
        0, // no cliff
        30 * 24 * 60 * 60, // 1 month duration, adjust as needed
      ]);
      return data;
    });

    if (calls.length > 0) {
      const tx = await multicall.multicall(calls);
      await tx.wait();
      console.log(`✅ Funded ${calls.length} vesting schedules`);
    }
  }

  // ======== FUND LP REWARDS ========
  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000";
  const lpAmount = ethers.utils.parseUnits(LP_REWARDS, 18);

  const tokenBalance = await atlasToken.balanceOf(deployer.address);
  if (tokenBalance.lt(lpAmount)) {
    throw new Error("Not enough token balance to fund LP rewards");
  }

  // Transfer LP allocation to vault safely
  const SafeERC20 = await ethers.getContractFactory("utils/SafeERC20");
  const safeERC20 = SafeERC20.attach(atlasTokenAddr); // not used in ts, just ensure usage in contracts
  const tx = await atlasToken.transfer(vaultAddr, lpAmount);
  await tx.wait();
  console.log(`✅ Transferred ${LP_REWARDS} ATLAS to Vault for LP rewards`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
