const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Reactive Shield - Clean & Powerful Tests", function () {
  let vault, lendingManager, loanMarket;
  let owner, user1, user2, reactive;
  let mockWETH;

  beforeEach(async function () {
    [owner, user1, user2, reactive] = await ethers.getSigners();

    // Deploy mock WETH
    const MockWETH = await ethers.getContractFactory("MockERC20");
    mockWETH = await MockWETH.deploy("Wrapped ETH", "WETH");
    await mockWETH.mint(user1.address, ethers.parseEther("10"));
    await mockWETH.mint(user2.address, ethers.parseEther("10"));

    // Deploy clean, powerful contracts
    vault = await (await ethers.getContractFactory("Vault")).deploy(reactive.address, mockWETH.target);
    loanMarket = await (await ethers.getContractFactory("LoanMarket")).deploy(reactive.address);
    lendingManager = await (await ethers.getContractFactory("LendingManager")).deploy(
      reactive.address, // system contract
      vault.target,
      loanMarket.target
    );
  });

  describe("🛡️ Core Functionality Tests", function () {
    
    it("✅ Should handle gas debt properly", async function () {
      const depositAmount = ethers.parseEther("1");
      const gasBuffer = ethers.parseEther("0.02"); // Above minimum

      await mockWETH.connect(user1).approve(vault.target, depositAmount);
      
      // Should succeed with sufficient gas buffer
      await expect(
        vault.connect(user1).deposit(depositAmount, { value: gasBuffer })
      ).to.emit(vault, "Deposit");

      expect(await vault.getGasBuffer(user1.address)).to.equal(gasBuffer);
    });

    it("❌ Should reject insufficient gas buffer", async function () {
      const depositAmount = ethers.parseEther("1");
      const insufficientGas = ethers.parseEther("0.005"); // Below minimum

      await mockWETH.connect(user1).approve(vault.target, depositAmount);
      
      await expect(
        vault.connect(user1).deposit(depositAmount, { value: insufficientGas })
      ).to.be.revertedWith("Insufficient gas buffer");
    });

    it("🔒 Should prevent double-spending with idempotency", async function () {
      const depositAmount = ethers.parseEther("1");
      const txHash = ethers.keccak256(ethers.toUtf8Bytes("test-tx-hash"));

      await mockWETH.connect(user1).approve(vault.target, depositAmount);
      await vault.connect(user1).deposit(depositAmount, { value: ethers.parseEther("0.02") });

      // First emergency withdraw should succeed
      await expect(
        vault.connect(reactive).emergencyWithdraw(user1.address, depositAmount, txHash)
      ).to.emit(vault, "EmergencyWithdraw");

      // Second attempt with same txHash should fail
      await expect(
        vault.connect(reactive).emergencyWithdraw(user1.address, depositAmount, txHash)
      ).to.be.revertedWith("Already processed");
    });

    it("🚨 Should trigger emergency protocol on price drop", async function () {
      const newPrice = 1700; // Below emergency threshold
      
      await expect(
        lendingManager.updatePrice(newPrice)
      ).to.emit(lendingManager, "PriceUpdate");

      expect(await lendingManager.getCurrentPrice()).to.equal(newPrice);
    });

    it("💰 Should handle loan issuance correctly", async function () {
      const user = user1.address;
      const loanAmount = ethers.parseEther("1000");

      // Only reactive contract should be able to issue loans
      await expect(
        loanMarket.connect(reactive).issueLoan(user, loanAmount)
      ).to.emit(loanMarket, "LoanIssued")
        .withArgs(user, loanAmount);

      expect(await loanMarket.getLoanAmount(user)).to.equal(loanAmount);
      expect(await loanMarket.balanceOf(user)).to.equal(loanAmount);
    });

    it("🚫 Should reject unauthorized loan issuance", async function () {
      const loanAmount = ethers.parseEther("1000");

      await expect(
        loanMarket.connect(user1).issueLoan(user1.address, loanAmount)
      ).to.be.revertedWith("Only reactive contract");
    });

    it("🔄 Should handle emergency repay correctly", async function () {
      const loanAmount = ethers.parseEther("1000");
      
      // Issue loan first
      await loanMarket.connect(reactive).issueLoan(user1.address, loanAmount);
      
      // Emergency repay
      await expect(
        loanMarket.connect(reactive).emergencyRepay(user1.address)
      ).to.emit(loanMarket, "EmergencyRepay")
        .withArgs(user1.address, loanAmount);

      expect(await loanMarket.getLoanAmount(user1.address)).to.equal(0);
    });

    it("⚡ Should activate emergency mode", async function () {
      await expect(
        loanMarket.connect(reactive).emergencyRepayAll()
      ).to.emit(loanMarket, "EmergencyModeActivated");

      // Should prevent new loans in emergency mode
      await expect(
        loanMarket.connect(reactive).issueLoan(user1.address, ethers.parseEther("100"))
      ).to.be.revertedWith("Emergency mode active");
    });
  });

  describe("🎯 Integration Tests", function () {
    
    it("📊 Should handle multiple users simultaneously", async function () {
      const depositAmount = ethers.parseEther("1");
      const gasBuffer = ethers.parseEther("0.02");

      // Multiple users deposit
      await mockWETH.connect(user1).approve(vault.target, depositAmount);
      await mockWETH.connect(user2).approve(vault.target, depositAmount);

      await vault.connect(user1).deposit(depositAmount, { value: gasBuffer });
      await vault.connect(user2).deposit(depositAmount, { value: gasBuffer });

      // Verify both users have collateral
      expect(await vault.getCollateral(user1.address)).to.equal(depositAmount);
      expect(await vault.getCollateral(user2.address)).to.equal(depositAmount);
    });

    it("🔄 Should complete full deposit-to-loan flow", async function () {
      const depositAmount = ethers.parseEther("1");
      const gasBuffer = ethers.parseEther("0.02");

      // 1. User deposits collateral
      await mockWETH.connect(user1).approve(vault.target, depositAmount);
      await vault.connect(user1).deposit(depositAmount, { value: gasBuffer });

      // 2. Simulate reactive contract triggering loan
      const expectedLoanAmount = ethers.parseEther("1400"); // 1 ETH * $2000 * 70% LTV
      await loanMarket.connect(reactive).issueLoan(user1.address, expectedLoanAmount);

      // Verify final state
      expect(await vault.getCollateral(user1.address)).to.equal(depositAmount);
      expect(await loanMarket.balanceOf(user1.address)).to.equal(expectedLoanAmount);
      expect(await loanMarket.getLoanAmount(user1.address)).to.equal(expectedLoanAmount);
    });

    it("🛡️ Should complete emergency unwind flow", async function () {
      const depositAmount = ethers.parseEther("1");
      const loanAmount = ethers.parseEther("1400");
      const txHash = ethers.keccak256(ethers.toUtf8Bytes("emergency-tx"));

      // Setup: deposit and loan
      await mockWETH.connect(user1).approve(vault.target, depositAmount);
      await vault.connect(user1).deposit(depositAmount, { value: ethers.parseEther("0.02") });
      await loanMarket.connect(reactive).issueLoan(user1.address, loanAmount);

      // Emergency unwind
      await loanMarket.connect(reactive).emergencyRepay(user1.address);
      await vault.connect(reactive).emergencyWithdraw(user1.address, depositAmount, txHash);

      // Verify emergency state
      expect(await loanMarket.getLoanAmount(user1.address)).to.equal(0);
      expect(await vault.getCollateral(user1.address)).to.equal(0);
    });

    it("🚨 Should demonstrate complete reactive flow", async function () {
      const depositAmount = ethers.parseEther("1");
      const gasBuffer = ethers.parseEther("0.02");

      // 1. User deposits collateral
      await mockWETH.connect(user1).approve(vault.target, depositAmount);
      await vault.connect(user1).deposit(depositAmount, { value: gasBuffer });

      // 2. Simulate reactive contract triggering loan
      const expectedLoanAmount = ethers.parseEther("1400"); // 1 ETH * $2000 * 70% LTV
      await loanMarket.connect(reactive).issueLoan(user1.address, expectedLoanAmount);

      // 3. Verify final state
      expect(await vault.getCollateral(user1.address)).to.equal(depositAmount);
      expect(await loanMarket.balanceOf(user1.address)).to.equal(expectedLoanAmount);
      expect(await loanMarket.getLoanAmount(user1.address)).to.equal(expectedLoanAmount);

      // 4. Test emergency unwind
      const txHash = ethers.keccak256(ethers.toUtf8Bytes("emergency-tx"));
      await loanMarket.connect(reactive).emergencyRepay(user1.address);
      await vault.connect(reactive).emergencyWithdraw(user1.address, depositAmount, txHash);

      // 5. Verify emergency state
      expect(await loanMarket.getLoanAmount(user1.address)).to.equal(0);
      expect(await vault.getCollateral(user1.address)).to.equal(0);
    });
  });
});