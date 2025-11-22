// scripts/fund_presale.ts
import fs from "fs";
import path from "path";
import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  const deployedFile = path.join(__dirname, "..", "deployments", "deployed_addresses.json");
  if (!fs.existsSync(deployedFile)) throw new Error("deployed_addresses.json not found. Run deploy_all.ts first.");

  const addresses = JSON.parse(fs.readFileSync(deployedFile, "utf-8"));
  const deployer = (await ethers.getSigners())[0];
  console.log("Funding presale and LP from Vault as:", deployer.address);

  const AtlasToken = await ethers.getContractFactory("token/AtlasToken");
  const token = AtlasToken.attach(addresses["AtlasToken"]);

  const AtlasVault = await ethers.getContractFactory("vaults/AtlasVault");
  const vault = AtlasVault.attach(addresses["AtlasVault"]);

  const Presale = await ethers.getContractFactory("presale/Presale");
  const presale = Presale.attach(addresses["Presale"]);

  const LP_REWARDS = process.env.LP_REWARD_ALLOCATION || "1000000000";
  const PRESALE_ALLOCATION = process.env.PRESALE_ALLOCATION || "300000000";

  const decimals = await token.decimals().catch(() => 18);
  const lpAmount = ethers.utils.parseUnits(LP_REWARDS, decimals);
  const presaleAmount = ethers.utils.parseUnits(PRESALE_ALLOCATION, decimals);

  // Fund Presale
  try {
    if ((vault as any).transfer) {
      await (vault as any).transfer(presale.address, presaleAmount);
      console.log(`Transferred ${PRESALE_ALLOCATION} tokens from Vault → Presale`);
    } else {
      // fallback: use ERC20 transfer from deployer
      await token.transfer(presale.address, presaleAmount);
      console.log(`Transferred ${PRESALE_ALLOCATION} tokens from deployer → Presale`);
    }
  } catch (err: any) {
    console.warn("Presale funding failed:", err.message);
  }

  // Fund LP Rewards (send to Vault or LP sink)
  const LPRewardSinkAddress = addresses["LPRewardSink"];
  try {
    if ((vault as any).transfer) {
      await (vault as any).transfer(LPRewardSinkAddress, lpAmount);
      console.log(`Transferred ${LP_REWARDS} tokens from Vault → LPRewardSink`);
    } else {
      await token.transfer(LPRewardSinkAddress, lpAmount);
      console.log(`Transferred ${LP_REWARDS} tokens from deployer → LPRewardSink`);
    }
  } catch (err: any) {
    console.warn("LPReward funding failed:", err.message);
  }

  console.log("✅ Presale & LP funding complete");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
