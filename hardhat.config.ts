import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

dotenv.config();

// Ensure required env variables exist
const {
  PRIVATE_KEY,
  SEPOLIA_RPC_URL,
  BASE_MAINNET_RPC,
  ETHERSCAN_API_KEY,
  BASESCAN_API_KEY
} = process.env;

if (!PRIVATE_KEY) {
  throw new Error("PRIVATE_KEY not set in .env");
}
if (!SEPOLIA_RPC_URL) {
  throw new Error("SEPOLIA_RPC_URL not set in .env");
}
if (!BASE_MAINNET_RPC) {
  throw new Error("BASE_MAINNET_RPC not set in .env");
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 31337,
    },
    sepolia: {
      url: SEPOLIA_RPC_URL,
      accounts: [PRIVATE_KEY],
      chainId: 11155111,
    },
    base: {
      url: BASE_MAINNET_RPC,
      accounts: [PRIVATE_KEY],
      chainId: 8453,
    },
  },
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN_API_KEY || "",
      base: BASESCAN_API_KEY || "",
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./tests",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 200000, // 200s for integration / deployment tests
  },
};

export default config;
