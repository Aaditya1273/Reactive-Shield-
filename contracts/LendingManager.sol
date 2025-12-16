// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LendingManager - Professional Reactive Smart Contract
 * @notice Clean, powerful reactive contract for cross-chain lending automation
 * @dev Implements core reactive patterns with essential security features
 */
contract LendingManager {
    
    // ============ IMMUTABLE STATE ============
    
    address public immutable systemContract;
    address public immutable originVault;
    address public immutable destMarket;
    
    uint256 public immutable originChainId = 11155111; // Sepolia
    uint256 public immutable destChainId = 80001; // Mumbai
    
    // ============ CONSTANTS ============
    
    uint256 public constant LTV = 70; // 70% Loan-to-Value
    uint256 public constant LIQUIDATION_THRESHOLD = 1800; // $1800 ETH
    uint256 public constant EMERGENCY_THRESHOLD = 1700; // $1700 ETH
    uint256 public constant GAS_LIMIT = 500000;
    uint256 public constant EMERGENCY_GAS_LIMIT = 800000;

    // ============ STATE VARIABLES ============
    
    // User positions
    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public userLoans;
    mapping(bytes32 => bool) public processed; // Idempotency protection
    
    // Price management
    uint256 public currentPrice = 2000; // ETH price in USD
    uint256 public lastPriceUpdate;
    
    // Emergency controls
    bool public emergencyMode = false;
    uint256 public totalPositions = 0;

    // ============ EVENTS ============
    
    event Callback(uint256 chainId, address contractAddr, uint256 gasLimit, bytes payload);
    event LoanIssued(address indexed user, uint256 collateralAmount, uint256 loanAmount);
    event EmergencyTriggered(address indexed user, uint256 amount, string reason);
    event PriceUpdate(uint256 oldPrice, uint256 newPrice);

    // ============ MODIFIERS ============
    
    modifier onlySystem() {
        require(msg.sender == systemContract, "Only system contract");
        _;
    }
    
    modifier notInEmergency() {
        require(!emergencyMode, "Emergency mode active");
        _;
    }

    // ============ CONSTRUCTOR ============
    
    constructor(address _system, address _vault, address _market) {
        require(_system != address(0), "Invalid system contract");
        require(_vault != address(0), "Invalid vault address");
        require(_market != address(0), "Invalid market address");
        
        systemContract = _system;
        originVault = _vault;
        destMarket = _market;
        lastPriceUpdate = block.timestamp;
    }

    // ============ CORE REACTIVE FUNCTION ============
    
    /**
     * @notice Main reactive function - handles all cross-chain events
     * @dev Implements idempotency and routes events to appropriate handlers
     */
    function react(
        uint256 chainId,
        address _contract,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        bytes calldata data
    ) external onlySystem {
        
        // Idempotency protection
        bytes32 eventHash = keccak256(abi.encodePacked(chainId, _contract, topic0, data));
        require(!processed[eventHash], "Event already processed");
        processed[eventHash] = true;
        
        // Handle Deposit events from Origin Vault
        if (chainId == originChainId && _contract == originVault) {
            _handleDeposit(data);
        }
        // Handle Price Update events
        else if (bytes32(topic0) == keccak256("PriceUpdate(uint256)")) {
            _handlePriceUpdate(data);
        }
    }

    // ============ EVENT HANDLERS ============
    
    /**
     * @notice Handle deposit events from origin chain
     * @dev Calculates loan amount and triggers issuance
     */
    function _handleDeposit(bytes calldata data) internal notInEmergency {
        (address user, uint256 amount, uint256 gasBuffer, uint256 timestamp) = 
            abi.decode(data, (address, uint256, uint256, uint256));
        
        // Calculate loan amount (70% LTV)
        uint256 loanAmount = (amount * currentPrice * LTV) / (100 * 1e18);
        
        // Update user position
        userDeposits[user] += amount;
        userLoans[user] += loanAmount;
        totalPositions++;
        
        // Trigger loan issuance on destination chain
        bytes memory payload = abi.encodeWithSignature(
            "issueLoan(address,uint256)", 
            user, 
            loanAmount
        );
        
        emit Callback(destChainId, destMarket, GAS_LIMIT, payload);
        emit LoanIssued(user, amount, loanAmount);
    }
    
    /**
     * @notice Handle price update events
     * @dev Triggers emergency protocol if price drops too low
     */
    function _handlePriceUpdate(bytes calldata data) internal {
        uint256 newPrice = abi.decode(data, (uint256));
        uint256 oldPrice = currentPrice;
        
        currentPrice = newPrice;
        lastPriceUpdate = block.timestamp;
        
        emit PriceUpdate(oldPrice, newPrice);
        
        // Check for emergency conditions
        if (newPrice < EMERGENCY_THRESHOLD) {
            _triggerEmergencyProtocol("PRICE_CRASH");
        }
    }

    // ============ EMERGENCY FUNCTIONS ============
    
    /**
     * @notice Trigger emergency protocol for all positions
     * @dev Initiates emergency repay and withdrawal across chains
     */
    function _triggerEmergencyProtocol(string memory reason) internal {
        emergencyMode = true;
        
        // Emergency repay all loans on destination
        bytes memory repayPayload = abi.encodeWithSignature("emergencyRepayAll()");
        emit Callback(destChainId, destMarket, EMERGENCY_GAS_LIMIT, repayPayload);
        
        // Emergency withdraw all collateral on origin
        bytes memory withdrawPayload = abi.encodeWithSignature("toggleEmergencyMode()");
        emit Callback(originChainId, originVault, EMERGENCY_GAS_LIMIT, withdrawPayload);
        
        emit EmergencyTriggered(address(0), 0, reason);
    }
    
    /**
     * @notice Trigger emergency for specific user
     * @dev Used for individual liquidation prevention
     */
    function triggerEmergencyForUser(address user) external {
        require(userDeposits[user] > 0, "No deposit found");
        
        bytes32 txHash = keccak256(abi.encodePacked(block.timestamp, user));
        
        // Emergency repay user's loan
        bytes memory repayPayload = abi.encodeWithSignature("emergencyRepay(address)", user);
        emit Callback(destChainId, destMarket, EMERGENCY_GAS_LIMIT, repayPayload);
        
        // Emergency withdraw user's collateral
        bytes memory withdrawPayload = abi.encodeWithSignature(
            "emergencyWithdraw(address,uint256,bytes32)", 
            user, 
            userDeposits[user], 
            txHash
        );
        emit Callback(originChainId, originVault, EMERGENCY_GAS_LIMIT, withdrawPayload);
        
        emit EmergencyTriggered(user, userDeposits[user], "USER_LIQUIDATION_PREVENTION");
        
        // Clear user position
        userDeposits[user] = 0;
        userLoans[user] = 0;
    }
    
    /**
     * @notice Manual price update for demo purposes
     * @dev In production, this would come from oracle events
     */
    function updatePrice(uint256 newPrice) external {
        require(newPrice > 0, "Invalid price");
        
        uint256 oldPrice = currentPrice;
        currentPrice = newPrice;
        lastPriceUpdate = block.timestamp;
        
        emit PriceUpdate(oldPrice, newPrice);
        
        // Check for emergency conditions
        if (newPrice < EMERGENCY_THRESHOLD && oldPrice >= EMERGENCY_THRESHOLD) {
            _triggerEmergencyProtocol("MANUAL_PRICE_CRASH");
        }
    }

    // ============ VIEW FUNCTIONS ============
    
    function getUserDeposit(address user) external view returns (uint256) {
        return userDeposits[user];
    }
    
    function getUserLoan(address user) external view returns (uint256) {
        return userLoans[user];
    }
    
    function getCurrentPrice() external view returns (uint256) {
        return currentPrice;
    }
    
    function getHealthFactor(address user) external view returns (uint256) {
        if (userLoans[user] == 0) return type(uint256).max;
        
        uint256 collateralValue = (userDeposits[user] * currentPrice) / 1e18;
        return (collateralValue * 100) / userLoans[user];
    }
    
    function isProcessed(bytes32 eventHash) external view returns (bool) {
        return processed[eventHash];
    }

    // ============ ADMIN FUNCTIONS ============
    
    function deactivateEmergencyMode() external onlySystem {
        emergencyMode = false;
    }
}