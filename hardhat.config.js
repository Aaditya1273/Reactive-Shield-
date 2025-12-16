require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    // Local development (default)
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337
    },
    hardhat: {
      chainId: 31337
    },
    // Sepolia (Origin Chain) - only if private key is provided
    ...(process.env.ORIGIN_PRIVATE_KEY && process.env.ORIGIN_PRIVATE_KEY.length === 66 ? {
      sepolia: {
        url: process.env.ORIGIN_RPC || "https://sepolia.infura.io/v3/YOUR_KEY",
        accounts: [process.env.ORIGIN_PRIVATE_KEY],
        chainId: 11155111
      }
    } : {}),
    // Mumbai (Destination Chain) - only if private key is provided
    ...(process.env.DESTINATION_PRIVATE_KEY && process.env.DESTINATION_PRIVATE_KEY.length === 66 ? {
      mumbai: {
        url: process.env.DESTINATION_RPC || "https://polygon-mumbai.infura.io/v3/YOUR_KEY",
        accounts: [process.env.DESTINATION_PRIVATE_KEY],
        chainId: 80001
      }
    } : {}),
    // Reactive Network - only if private key is provided
    ...(process.env.REACTIVE_PRIVATE_KEY && process.env.REACTIVE_PRIVATE_KEY.length === 66 ? {
      reactive: {
        url: process.env.REACTIVE_RPC || "https://sepolia-rpc.reactive.network",
        accounts: [process.env.REACTIVE_PRIVATE_KEY],
        chainId: 5318008
      }
    } : {})
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.ETHERSCAN_API_KEY,
      polygonMumbai: process.env.POLYGONSCAN_API_KEY
    }
  }
};