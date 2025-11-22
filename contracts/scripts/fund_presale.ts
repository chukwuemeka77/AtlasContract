import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import { SafeERC20 } from "../contracts/utils/SafeERC20.sol"; // optional helper if you have TS bindings
import fs from "fs";

dotenv.config();

const {
  PRESALE_ALLOCATION,
  LP_REWARD_ALLOCATION,
  VAULT_ADMIN_ADDRESS
} = process.env;

// Load deployed addresses
const deployed = JSON.parse(fs.readFileSync("deployed_addresses.json", "utf8"));

async function main() {
  const [deployer] = await ethers.getSigners();

  const token = await ethers.getContractAt("AtlasToken", deployed.AtlasToken);

  // Fund Presale
  const presale = await ethers.getContractAt("AtlasPresale", deployed.AtlasPresale);
  await token.transfer(presale.address, PRESALE_ALLOCATION);
  console.log(`Transferred ${PRESALE_ALLOCATION} tokens to Presale`);

  // Fund Vesting / LP Rewards
  const vesting = await ethers.getContractAt("AtlasVesting", deployed.AtlasVesting);
  await token.transfer(vesting.address, LP_REWARD_ALLOCATION);
  console.log(`Transferred ${LP_REWARD_ALLOCATION} tokens to Vesting / LP rewards`);

  console.log("Funding complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
