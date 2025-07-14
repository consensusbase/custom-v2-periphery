import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.6.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 999999
      },
      evmVersion: "istanbul"
    }
  },
  networks: {
    ganache: {
      url: "http://127.0.0.1:7545",
      chainId: 1337,
      accounts: ['']
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test-hardhat",
    cache: "./cache",
    artifacts: "./artifacts"
  }
};

export default config;