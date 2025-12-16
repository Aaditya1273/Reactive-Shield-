// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Vault - Professional Origin Chain Collateral Manager
 * @notice Secure vault with gas debt handling and idempotency protection
 * @dev Implements all vulnerability fixes identified in bounty analysis
 */
contract Vault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ STATE VARIABLES ============
    
    address public immutable reactiveAddr;
    IERC20 public immutable collateralToken;
    
    // Core mappings
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public gasBuffer;
    mapping(bytes32 => bool) public processed; // Idempotency protection
    
    // Gas debt handling
    uint256 public constant MIN_GAS_BUFFER = 0.01 ether;
    uint256 public totalGasPool;
    
    // Emergency controls
    bool public emergencyMode = false;
    uint256 public totalValueLocked;

    // ============ EVENTS ============
    
    event Deposit(
        address indexed user, 
        uint256 amount, 
        uint256 gasBuffer,
        uint256 timestamp
    );
    
    event EmergencyWithdraw(
        address indexed user, 
        uint256 amount, 
        bytes32 indexed txHash
    );
    
    event GasBufferRefund(address indexed user, uint256 amount);
    event EmergencyModeToggled(bool enabled);

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
    
    constructor(address _reactiveAddr, address _collateralToken) {
        require(_reactiveAddr != address(0), "Invalid reactive address");
        require(_collateralToken != address(0), "Invalid token address");
        
        reactiveAddr = _reactiveAddr;
        collateralToken = IERC20(_collateralToken);
    }

    // ============ CORE FUNCTIONS ============
    
    /**
     * @notice Deposit collateral with gas buffer for cross-chain operations
     * @param amount Amount of collateral to deposit
     * @dev Implements gas debt handling vulnerability fix
     */
    function deposit(uint256 amount) external payable nonReentrant notInEmergency {
        require(amount > 0, "Invalid amount");
        require(msg.value >= MIN_GAS_BUFFER, "Insufficient gas buffer");
        
        // Transfer collateral
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update state
        collateral[msg.sender] += amount;
        gasBuffer[msg.sender] += msg.value;
        totalValueLocked += amount;
        totalGasPool += msg.value;
        
        emit Deposit(msg.sender, amount, msg.value, block.timestamp);
    }
    
    /**
     * @notice Emergency withdrawal triggered by reactive contract
     * @dev Implements idempotency protection vulnerability fix
     */
    function emergencyWithdraw(
        address user,
        uint256 amount,
        bytes32 txHash
    ) external onlyReactive nonReentrant {
        // Idempotency check - prevents double-spending
        require(!processed[txHash], "Already processed");
        processed[txHash] = true;
        
        // Validate withdrawal
        require(collateral[user] >= amount, "Insufficient collateral");
        require(gasBuffer[user] > 0, "No gas buffer");
        
        // Execute withdrawal
        collateral[user] -= amount;
        totalValueLocked -= amount;
        
        collateralToken.safeTransfer(user, amount);
        
        // Refund gas buffer
        uint256 refund = gasBuffer[user];
        gasBuffer[user] = 0;
        totalGasPool -= refund;
        
        payable(user).transfer(refund);
        
        emit EmergencyWithdraw(user, amount, txHash);
        emit GasBufferRefund(user, refund);
    }
    
    /**
     * @notice Regular withdrawal (when not in emergency)
     */
    function withdraw(uint256 amount) external nonReentrant notInEmergency {
        require(collateral[msg.sender] >= amount, "Insufficient collateral");
        
        collateral[msg.sender] -= amount;
        totalValueLocked -= amount;
        
        collateralToken.safeTransfer(msg.sender, amount);
    }

    // ============ ADMIN FUNCTIONS ============
    
    function toggleEmergencyMode() external onlyReactive {
        emergencyMode = !emergencyMode;
        emit EmergencyModeToggled(emergencyMode);
    }

    // ============ VIEW FUNCTIONS ============
    
    function getCollateral(address user) external view returns (uint256) {
        return collateral[user];
    }
    
    function getGasBuffer(address user) external view returns (uint256) {
        return gasBuffer[user];
    }
    
    function getTotalValueLocked() external view returns (uint256) {
        return totalValueLocked;
    }
    
    function isProcessed(bytes32 txHash) external view returns (bool) {
        return processed[txHash];
    }
}