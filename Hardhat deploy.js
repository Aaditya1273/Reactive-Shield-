const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
  console.log("🛡️ REACTIVE SHIELD - PROFESSIONAL DEPLOYMENT");
  console.log("==============================================");
  
  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log("🔑 Deploying with account:", deployer.address);
  console.log("💰 Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");
  
  // Configuration
  const WETH_ADDR = process.env.WETH_ADDR || "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9"; // Sepolia WETH
  const SYSTEM_CONTRACT = process.env.SYSTEM_CONTRACT_ADDR || "0x0000000000000000000000000000000000FFFFFF";
  
  console.log("\n📋 Configuration:");
  console.log("- WETH Address:", WETH_ADDR);
  console.log("- System Contract:", SYSTEM_CONTRACT);
  console.log("- Network:", (await ethers.provider.getNetwork()).name);
  
  try {
    // Phase 1: Deploy Vault (Origin Chain)
    console.log("\n📦 Phase 1: Deploying Vault...");
    const Vault = await ethers.getContractFactory("Vault");
    console.log("⏳ Deploying Vault contract...");
    
    const vault = await Vault.deploy(deployer.address, WETH_ADDR); // Use deployer as temp reactive addr
    await vault.waitForDeployment();
    const vaultAddress = await vault.getAddress();
    
    console.log("✅ Vault deployed successfully!");
    console.log("📍 Address:", vaultAddress);
    
    // Phase 2: Deploy LoanMarket (Destination Chain)
    console.log("\n📦 Phase 2: Deploying LoanMarket...");
    const LoanMarket = await ethers.getContractFactory("LoanMarket");
    console.log("⏳ Deploying LoanMarket contract...");
    
    const loanMarket = await LoanMarket.deploy(deployer.address); // Use deployer as temp reactive addr
    await loanMarket.waitForDeployment();
    const loanMarketAddress = await loanMarket.getAddress();
    
    console.log("✅ LoanMarket deployed successfully!");
    console.log("📍 Address:", loanMarketAddress);
    
    // Phase 3: Deploy LendingManager (Reactive Network)
    console.log("\n📦 Phase 3: Deploying LendingManager...");
    const LendingManager = await ethers.getContractFactory("LendingManager");
    console.log("⏳ Deploying LendingManager contract...");
    
    const lendingManager = await LendingManager.deploy(SYSTEM_CONTRACT, vaultAddress, loanMarketAddress);
    await lendingManager.waitForDeployment();
    const lendingManagerAddress = await lendingManager.getAddress();
    
    console.log("✅ LendingManager deployed successfully!");
    console.log("📍 Address:", lendingManagerAddress);
    
    // Phase 4: Contract Verification
    console.log("\n🔍 Phase 4: Contract Verification...");
    
    // Verify Vault
    const vaultCollateralToken = await vault.collateralToken();
    const vaultReactiveAddr = await vault.reactiveAddr();
    console.log("✅ Vault verification:");
    console.log("  - Collateral Token:", vaultCollateralToken);
    console.log("  - Reactive Address:", vaultReactiveAddr);
    
    // Verify LoanMarket
    const loanMarketName = await loanMarket.name();
    const loanMarketSymbol = await loanMarket.symbol();
    const loanMarketReactiveAddr = await loanMarket.reactiveAddr();
    console.log("✅ LoanMarket verification:");
    console.log("  - Token Name:", loanMarketName);
    console.log("  - Token Symbol:", loanMarketSymbol);
    console.log("  - Reactive Address:", loanMarketReactiveAddr);
    
    // Verify LendingManager
    const lmSystemContract = await lendingManager.systemContract();
    const lmOriginVault = await lendingManager.originVault();
    const lmDestMarket = await lendingManager.destMarket();
    const lmCurrentPrice = await lendingManager.getCurrentPrice();
    console.log("✅ LendingManager verification:");
    console.log("  - System Contract:", lmSystemContract);
    console.log("  - Origin Vault:", lmOriginVault);
    console.log("  - Dest Market:", lmDestMarket);
    console.log("  - Current Price: $" + lmCurrentPrice);
    
    // Phase 5: Generate Deployment Results
    console.log("\n📄 Phase 5: Generating Deployment Results...");
    
    const deploymentResults = {
      timestamp: new Date().toISOString(),
      deployer: deployer.address,
      network: (await ethers.provider.getNetwork()).name,
      chainId: (await ethers.provider.getNetwork()).chainId.toString(),
      contracts: {
        vault: {
          address: vaultAddress,
          name: "Vault",
          description: "Origin chain collateral management"
        },
        loanMarket: {
          address: loanMarketAddress,
          name: "LoanMarket", 
          description: "Destination chain lending market"
        },
        lendingManager: {
          address: lendingManagerAddress,
          name: "LendingManager",
          description: "Reactive network coordination"
        }
      },
      eventTopics: {
        deposit: ethers.keccak256(ethers.toUtf8Bytes("Deposit(address,uint256,uint256,uint256)")),
        priceUpdate: ethers.keccak256(ethers.toUtf8Bytes("PriceUpdate(uint256,uint256)"))
      },
      configuration: {
        wethAddress: WETH_ADDR,
        systemContract: SYSTEM_CONTRACT,
        minGasBuffer: "0.01 ETH",
        ltvRatio: "70%",
        liquidationThreshold: "$1800",
        emergencyThreshold: "$1700"
      }
    };
    
    // Save deployment results
    fs.writeFileSync('deployment-results.json', JSON.stringify(deploymentResults, null, 2));
    console.log("✅ Deployment results saved to deployment-results.json");
    
    // Generate environment variables for .env
    const envVars = `
# Generated Deployment Addresses - ${new Date().toISOString()}
VAULT_ADDR=${vaultAddress}
LENDING_MANAGER_ADDR=${lendingManagerAddress}
LOAN_MARKET_ADDR=${loanMarketAddress}

# Event Topics
DEPOSIT_TOPIC=${deploymentResults.eventTopics.deposit}
PRICE_UPDATE_TOPIC=${deploymentResults.eventTopics.priceUpdate}
`;
    
    fs.writeFileSync('.env.deployment', envVars);
    console.log("✅ Environment variables saved to .env.deployment");
    
    // Phase 6: Final Summary
    console.log("\n🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!");
    console.log("=====================================");
    console.log("📊 Summary:");
    console.log(`- Total Contracts Deployed: 3`);
    const finalBalance = await ethers.provider.getBalance(deployer.address);
    console.log(`- Final Balance: ${ethers.formatEther(finalBalance)} ETH`);
    console.log(`- Deployment Time: ${new Date().toLocaleString()}`);
    
    console.log("\n📍 Contract Addresses:");
    console.log("┌─────────────────┬──────────────────────────────────────────────┐");
    console.log("│ Contract        │ Address                                      │");
    console.log("├─────────────────┼──────────────────────────────────────────────┤");
    console.log(`│ Vault           │ ${vaultAddress} │`);
    console.log(`│ LoanMarket      │ ${loanMarketAddress} │`);
    console.log(`│ LendingManager  │ ${lendingManagerAddress} │`);
    console.log("└─────────────────┴──────────────────────────────────────────────┘");
    
    console.log("\n🔧 Next Steps:");
    console.log("1. Copy addresses from .env.deployment to your main .env file");
    console.log("2. Run 'npm run verify-deployment' to verify contracts");
    console.log("3. Run 'npm run demo' to test the complete workflow");
    console.log("4. Record transaction hashes for bounty submission");
    
    console.log("\n🏆 READY FOR BOUNTY SUBMISSION!");
    
  } catch (error) {
    console.error("\n❌ DEPLOYMENT FAILED!");
    console.error("Error:", error.message);
    
    if (error.code === 'INSUFFICIENT_FUNDS') {
      console.error("💡 Solution: Add more ETH to your deployer account");
    } else if (error.code === 'NETWORK_ERROR') {
      console.error("💡 Solution: Check your RPC URL and network connection");
    } else {
      console.error("💡 Check the error details above and try again");
    }
    
    process.exit(1);
  }
}

// Execute deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment script failed:", error);
    process.exit(1);
  });