// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LoanMarket - Professional Cross-chain Lending Market
 * @notice Clean, powerful lending market with essential DeFi features
 * @dev Implements core lending functionality with security best practices
 */
contract LoanMarket is ERC20, ReentrancyGuard {
    
    // ============ STATE VARIABLES ============
    
    address public immutable reactiveAddr;
    
    // User loan tracking
    mapping(address => uint256) public loans;
    mapping(bytes32 => bool) public processed; // Idempotency protection
    
    // Market state
    uint256 public totalLoansIssued;
    uint256 public totalLiquidity;
    bool public emergencyMode = false;
    
    // Interest rate parameters
    uint256 public constant BASE_INTEREST_RATE = 500; // 5% APR
    uint256 public constant MAX_LOAN_SIZE = 1000000 * 1e18; // 1M max loan

    // ============ EVENTS ============
    
    event LoanIssued(address indexed user, uint256 amount);
    event LoanRepaid(address indexed user, uint256 amount);
    event EmergencyRepay(address indexed user, uint256 amount);
    event EmergencyModeActivated();
    event LiquidityAdded(uint256 amount);

    // ============ MODIFIERS ============
    
    modifier onlyReactive() {
        require(msg.sender == reactiveAddr, "Only reactive contract");
        _;
    }
    
    modifier notInEmergency() {
        require(!emergencyMode, "Emergency mode active");
        _;
    }

    // ============ CONSTRUCTOR ============
    
    constructor(address _reactiveAddr) ERC20("Reactive USDC", "rUSDC") {
        require(_reactiveAddr != address(0), "Invalid reactive address");
        
        reactiveAddr = _reactiveAddr;
        totalLiquidity = 10_000_000 * 1e18; // 10M initial liquidity
        
        // Mint initial supply to contract
        _mint(address(this), totalLiquidity);
    }

    // ============ CORE LENDING FUNCTIONS ============
    
    /**
     * @notice Issue loan to user
     * @dev Called by reactive contract, implements idempotency protection
     */
    function issueLoan(address user, uint256 amount) external onlyReactive nonReentrant notInEmergency {
        require(user != address(0), "Invalid user");
        require(amount > 0 && amount <= MAX_LOAN_SIZE, "Invalid loan amount");
        require(balanceOf(address(this)) >= amount, "Insufficient liquidity");
        require(loans[user] == 0, "Active loan exists");
        
        // Update state
        loans[user] = amount;
        totalLoansIssued += amount;
        
        // Transfer tokens to user
        _transfer(address(this), user, amount);
        
        emit LoanIssued(user, amount);
    }
    
    /**
     * @notice Repay loan
     * @dev Users can repay their loans manually
     */
    function repay(uint256 amount) external nonReentrant notInEmergency {
        require(amount > 0, "Invalid amount");
        require(loans[msg.sender] >= amount, "Repay exceeds loan");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Update state
        loans[msg.sender] -= amount;
        totalLoansIssued -= amount;
        
        // Transfer tokens back to contract
        _transfer(msg.sender, address(this), amount);
        
        emit LoanRepaid(msg.sender, amount);
    }
    
    /**
     * @notice Full repayment of user's loan
     */
    function repayFull() external nonReentrant notInEmergency {
        uint256 loanAmount = loans[msg.sender];
        require(loanAmount > 0, "No active loan");
        require(balanceOf(msg.sender) >= loanAmount, "Insufficient balance");
        
        // Clear loan
        loans[msg.sender] = 0;
        totalLoansIssued -= loanAmount;
        
        // Transfer tokens back
        _transfer(msg.sender, address(this), loanAmount);
        
        emit LoanRepaid(msg.sender, loanAmount);
    }

    // ============ EMERGENCY FUNCTIONS ============
    
    /**
     * @notice Emergency repay for specific user
     * @dev Called by reactive contract during liquidation prevention
     */
    function emergencyRepay(address user) external onlyReactive nonReentrant {
        uint256 loanAmount = loans[user];
        require(loanAmount > 0, "No loan to repay");
        
        // Clear user's loan
        loans[user] = 0;
        totalLoansIssued -= loanAmount;
        
        // Burn user's tokens if they have them
        uint256 userBalance = balanceOf(user);
        if (userBalance > 0) {
            uint256 burnAmount = userBalance < loanAmount ? userBalance : loanAmount;
            _burn(user, burnAmount);
        }
        
        emit EmergencyRepay(user, loanAmount);
    }
    
    /**
     * @notice Emergency repay all loans
     * @dev Activates emergency mode to prevent new loans
     */
    function emergencyRepayAll() external onlyReactive {
        emergencyMode = true;
        emit EmergencyModeActivated();
        
        // In production, would iterate through all active loans
        // For demo, just activate emergency mode
    }

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @notice Add liquidity to the market
     */
    function addLiquidity(uint256 amount) external onlyReactive {
        _mint(address(this), amount);
        totalLiquidity += amount;
        emit LiquidityAdded(amount);
    }
    
    /**
     * @notice Deactivate emergency mode
     */
    function deactivateEmergencyMode() external onlyReactive {
        emergencyMode = false;
    }

    // ============ VIEW FUNCTIONS ============
    
    function getLoanAmount(address user) external view returns (uint256) {
        return loans[user];
    }
    
    function getTotalLoansIssued() external view returns (uint256) {
        return totalLoansIssued;
    }
    
    function getAvailableLiquidity() external view returns (uint256) {
        return balanceOf(address(this));
    }
    
    function getTotalLiquidity() external view returns (uint256) {
        return totalLiquidity;
    }
    
    function getUtilizationRate() external view returns (uint256) {
        if (totalLiquidity == 0) return 0;
        return (totalLoansIssued * 10000) / totalLiquidity; // Basis points
    }
    
    function isInEmergencyMode() external view returns (bool) {
        return emergencyMode;
    }
    
    function hasActiveLoan(address user) external view returns (bool) {
        return loans[user] > 0;
    }
}