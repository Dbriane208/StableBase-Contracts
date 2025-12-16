// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPaymentProcessor} from "../interfaces/IPaymentProcessor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {TokensManager} from "./TokensManager.sol";
import {IMerchantRegistry} from "../interfaces/IMerchantRegistry.sol";
import {MerchantRegistry} from "./MerchantRegistry.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

/**
 * @title PaymentProcessor
 * @notice Perfom the main payment operations
 * @dev Responsibilities: Accept stablecoin payments, forward stablecoins to merchant wallet,
 * take a platform fee and emit events
 */
contract PaymentProcessor is
    IPaymentProcessor,
    ReentrancyGuard,
    TokensManager,
    PausableUpgradeable,
    Ownable2StepUpgradeable
{
    error PaymentProcessor__ThrowZeroAddress();
    error PaymentProcessor__InvalidAmount();
    error PaymentProcessor__InvalidMetadataUri();
    error PaymentProcessor__TokenNotAllowed();
    error PaymentProcessor__OrderAlreadyExists();
    error PaymentProcessor__OrderNotFound();
    error PaymentProcessor__InvalidStatus();
    error PaymentProcessor__UnauthorizedPayer();
    error PaymentProcessor__TransferFailed();
    error PaymentProcessor__OrderExpired();
    error PaymentProcessor__InsufficientBalance();
    error PaymentProcessor__UnverifiedMerchant();
    error PaymentProcessor__EmergencyWithdrawalFailed();

    // orders mapping
    mapping(bytes32 => Order) private order;
    mapping(address => uint256) private _nonce;
    uint256[47] private _gap; // Reduced to accommodate new variables

    // default platform fee in BPS when token -specific isn't set
    uint256 public defaultPlatformFeeBps;

    // Order expiration time in seconds (default 24 hours)
    uint256 public orderExpirationTime;

    // Emergency withdrawal enabled flag
    bool public emergencyWithdrawalEnabled;

    MerchantRegistry public merchantRegistry;

    //// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize function
     */
    function initialize(
        address _platformWallet,
        uint256 _defaultPlatformFeeBps,
        address _merchantRegistry,
        uint256 _orderExpirationTime
    ) external initializer {
        maxBps = 100_000;

        if (_platformWallet == address(0)) {
            revert PaymentProcessor__ThrowZeroAddress();
        }
        if (_defaultPlatformFeeBps > maxBps) {
            revert PaymentProcessor__InvalidAmount();
        }
        if (_merchantRegistry == address(0)) {
            revert PaymentProcessor__ThrowZeroAddress();
        }
        if (_orderExpirationTime > 86400) {
            revert PaymentProcessor__OrderExpired();
        }

        // initialize inherited contracts
        __Ownable2Step_init();
        __Pausable_init();
        _tokensManagerInit(maxBps, _platformWallet);

        // initialize state
        defaultPlatformFeeBps = _defaultPlatformFeeBps;
        merchantRegistry = MerchantRegistry(_merchantRegistry);
        orderExpirationTime = _orderExpirationTime;
        emergencyWithdrawalEnabled = false;
    }

    /* ========== MODIFIERS ========== */
    modifier onlyExisting(bytes32 orderId) {
        _onlyExisting(orderId);
        _;
    }

    function _onlyExisting(bytes32 orderId) internal view {
        if (!order[orderId].exists) revert PaymentProcessor__OrderNotFound();
    }

    /* ##################################################################
                                OWNER FUNCTIONS
    ################################################################## */
    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpase the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /* ##################################################################
                                USER CALLS
    ################################################################## */
    /**
     * @dev See {createOrder - IPaymentProcessor}
     * create an order referencing a merchantId (merchant must be registered)
     */
    function createOrder(bytes32 _merchantId, address _token, uint256 _amount, string calldata _metadataUri)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 _orderId)
    {
        // Checks that are required
        _createOrderChecks(_token, _amount, _metadataUri);

        // Check user has sufficient balance
        if (IERC20(_token).balanceOf(msg.sender) < _amount) {
            revert PaymentProcessor__InsufficientBalance();
        }

        // ensure merchant exist and cache payout wallet
        MerchantRegistry.Merchant memory m = merchantRegistry.getMerchantInfo(_merchantId);
        if (!m.exists) {
            revert PaymentProcessor__InvalidStatus();
        }

        // Only allow orders for verified merchants
        if (m.verificationStatus != IMerchantRegistry.VerificationStatus.VERIFIED) {
            revert PaymentProcessor__UnverifiedMerchant();
        }

        // increase nonce to avoid replay attacks
        _nonce[msg.sender]++;

        // generate transaction id for the transaction with chainid
        // Include timestamp to further reduce collision probability
        _orderId = keccak256(abi.encode(msg.sender, _nonce[msg.sender], block.chainid, block.timestamp));

        // This should never happen with proper nonce management, but safety check
        if (order[_orderId].exists) {
            revert PaymentProcessor__OrderAlreadyExists();
        }

        order[_orderId] = Order({
            payer: msg.sender,
            token: _token,
            merchantId: _merchantId,
            merchantPayout: m.payoutWallet,
            amount: _amount,
            exists: true,
            currentBps: uint64(100000), // MAX_BPS
            createdAt: block.timestamp,
            metadataUri: _metadataUri,
            status: OrderStatus.CREATED
        });

        // emit order created event
        emit OrderCreated(
            _orderId, msg.sender, _merchantId, m.payoutWallet, _token, _amount, OrderStatus.CREATED, _metadataUri
        );
    }

    /**
     * @dev See{payOrder - IPayment Processor}
     * @notice Pay an order: payer must have approved this contract
     * Payer pays (must have approved)
     */
    function payOrder(bytes32 _orderId) external nonReentrant whenNotPaused onlyExisting(_orderId) returns (bool) {
        Order storage o = order[_orderId];

        // Checks
        if (o.status != OrderStatus.CREATED) {
            revert PaymentProcessor__InvalidStatus();
        }

        if (msg.sender != o.payer) {
            revert PaymentProcessor__UnauthorizedPayer();
        }

        // Check if order has expired
        if (block.timestamp > o.createdAt + orderExpirationTime) {
            o.status = OrderStatus.CANCELLED;
            emit OrderExpired(_orderId, o.payer);
            revert PaymentProcessor__OrderExpired();
        }

        uint256 amount = o.amount;
        address token = o.token;

        // Effects: mark PAID before interactions
        o.status = OrderStatus.PAID;

        // Interactions : pull funds from payer
        // Using try-catch for better error handling
        try IERC20(token).transferFrom(msg.sender, address(this), amount) returns (bool success) {
            if (!success) {
                revert PaymentProcessor__TransferFailed();
            }
        } catch {
            revert PaymentProcessor__TransferFailed();
        }

        // emit paid event
        emit OrderPaid(_orderId, msg.sender, amount, OrderStatus.PAID);

        return true;
    }

    /**
     * @dev See {settleOrder - IPaymentProcessor}
     * @notice Settle and order : transfer funds to merchant minus fee
     * Can be called by merchant or platform to support automated flows
     */
    function settleOrder(bytes32 _orderId) external nonReentrant whenNotPaused onlyExisting(_orderId) returns (bool) {
        Order storage o = order[_orderId];

        // Checks
        if (o.status != OrderStatus.PAID) {
            revert PaymentProcessor__InvalidStatus();
        }

        // allow merchant payout wallet or platform owner to trigger settlement
        if (msg.sender != o.merchantPayout && msg.sender != owner()) {
            revert PaymentProcessor__UnauthorizedPayer();
        }

        uint256 amount = o.amount;
        address token = o.token;

        // Use default platform fee (2%)
        uint256 platformBps = defaultPlatformFeeBps;

        // Calculate fees and net
        uint256 feeAmount = 0;
        if (maxBps > 0) {
            feeAmount = (amount * platformBps) / maxBps;
        }
        uint256 netAmount = amount - feeAmount;

        // Effects
        o.status = OrderStatus.SETTLED;

        // Interactions: transfer net to merchant, fee to platformWallet
        if (netAmount > 0) {
            bool netOk = IERC20(token).transfer(o.merchantPayout, netAmount);
            if (!netOk) {
                revert PaymentProcessor__TransferFailed();
            }
        }

        if (feeAmount > 0) {
            address platformAddr = getPlatformWallet();
            bool feeOk = IERC20(token).transfer(platformAddr, feeAmount);
            if (!feeOk) {
                revert PaymentProcessor__TransferFailed();
            }
        }

        // emit settled event
        emit OrderSettled(_orderId, o.merchantPayout, msg.sender, netAmount, feeAmount, OrderStatus.SETTLED);

        return true;
    }

    /**
     * @notice Refund a PAID (but not settled) order back to payer
     * @dev Can be called by owner(platform) or merchant
     */
    function refundOrder(bytes32 _orderId) external nonReentrant whenNotPaused onlyExisting(_orderId) returns (bool) {
        Order storage o = order[_orderId];

        if (o.status != OrderStatus.PAID) revert PaymentProcessor__InvalidStatus();

        // Only merchant or owner can refund
        if (msg.sender != o.merchantPayout && msg.sender != owner()) revert PaymentProcessor__UnauthorizedPayer();

        uint256 amount = o.amount;
        address token = o.token;

        // EFFECTS
        o.status = OrderStatus.REFUNDED;

        // INTERACTIONS: return funds to payer
        bool ok = IERC20(token).transfer(o.payer, amount);
        if (!ok) revert PaymentProcessor__TransferFailed();

        emit OrderRefunded(_orderId, o.payer, amount);

        return true;
    }

    /**
     * @notice Cancel an order that was CREATED [no funds moved]
     * Only payer can cancel
     */
    function cancelOrder(bytes32 _orderId) external nonReentrant whenNotPaused onlyExisting(_orderId) returns (bool) {
        Order storage o = order[_orderId];

        if (o.status != OrderStatus.CREATED) {
            revert PaymentProcessor__InvalidStatus();
        }
        if (msg.sender != o.payer) {
            revert PaymentProcessor__UnauthorizedPayer();
        }

        o.status = OrderStatus.CANCELLED;

        emit OrderCancelled(_orderId, o.payer, o.amount);

        return true;
    }

    /**
     * @notice Batch cancel multiple orders (merchant only)
     * @param orderIds Array of order IDs to cancel
     */
    function batchCancelOrders(bytes32[] calldata orderIds) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < orderIds.length; i++) {
            bytes32 orderId = orderIds[i];
            if (!order[orderId].exists) continue;

            Order storage o = order[orderId];
            if (o.status != OrderStatus.CREATED) continue;
            if (msg.sender != o.payer) continue;

            o.status = OrderStatus.CANCELLED;
            emit OrderCancelled(orderId, o.payer, o.amount);
        }
    }

    /* ##################################################################
                                INTERNAL FUNCTIONS
    ################################################################## */

    /**
     * @dev Internal function to handle order creation checks
     * @param _token The address of the token being traded
     * @param _amount The amount of tokens being traded
     * @param _metadataUri The metadata URI for the order
     */
    function _createOrderChecks(address _token, uint256 _amount, string calldata _metadataUri) internal view {
        if (_token == address(0)) {
            revert PaymentProcessor__ThrowZeroAddress();
        }
        if (_isTokenSupported[_token] != 1) {
            revert PaymentProcessor__TokenNotAllowed();
        }

        if (_amount == 0) {
            revert PaymentProcessor__InvalidAmount();
        }

        // Validate minimum amount based on token decimals
        // For 6 decimal tokens (USDC, USDT): minimum 0.01 (10000 units)
        uint8 decimals;
        try IERC20Metadata(_token).decimals() returns (uint8 _decimals) {
            decimals = _decimals;
        } catch {
            // Default to 18 if decimals() call fails
            decimals = 18;
        }

        uint256 minAmount;
        if (decimals == 6) {
            minAmount = 10000; // 0.01 for 6 decimal tokens
        } else if (decimals == 18) {
            minAmount = 10 ** 16; // 0.01 for 18 decimal tokens
        } else {
            // For other decimal places, calculate minimum as 0.01
            minAmount = 10 ** (decimals - 2);
        }

        if (_amount < minAmount) {
            revert PaymentProcessor__InvalidAmount();
        }

        // Enhanced validation: check for reasonable amount limits
        // Prevent extremely large amounts that could cause overflow
        if (_amount > type(uint128).max) {
            revert PaymentProcessor__InvalidAmount();
        }

        if (bytes(_metadataUri).length == 0) {
            revert PaymentProcessor__InvalidMetadataUri();
        }

        // Validate metadata URI length to prevent gas issues
        if (bytes(_metadataUri).length > 512) {
            revert PaymentProcessor__InvalidMetadataUri();
        }
    }

    /* ##################################################################
                                ADMIN FUNCTIONS
    ################################################################## */
    /**
     * @dev Emitted when the merchant registry is updated
     * @param oldRegistry The address of the previous deployed contract
     * @param newRegistry The address of the new deployed contract
     */
    event MerchantRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event OrderExpirationTimeUpdated(uint256 oldTime, uint256 newTime);
    event MaxSlippageBpsUpdated(uint256 oldSlippage, uint256 newSlippage);
    event EmergencyWithdrawalEnabledUpdated(bool enabled);
    event EmergencyWithdrawal(address indexed token, address indexed to, uint256 amount);
    event OrderExpired(bytes32 indexed orderId, address indexed payer);

    function updateMerchantRegistry(address newRegistry) external onlyOwner {
        if (newRegistry == address(0)) {
            revert PaymentProcessor__ThrowZeroAddress();
        }
        address oldRegistry = address(merchantRegistry);
        merchantRegistry = MerchantRegistry(newRegistry);
        emit MerchantRegistryUpdated(oldRegistry, newRegistry);
    }

    /**
     * @dev Emitted when the Default Platform Fee is overriden
     * @param oldBps The previous fee the platform charged
     * @param newBps The new fee the platform charged
     */
    event DefaultPlatformFeeBpsUpdated(uint256 oldBps, uint256 newBps);

    function updateDefaultPlatformFeeBps(uint256 newBps) external onlyOwner {
        if (newBps > maxBps) {
            revert PaymentProcessor__InvalidAmount();
        }
        uint256 oldBps = defaultPlatformFeeBps;
        defaultPlatformFeeBps = newBps;
        emit DefaultPlatformFeeBpsUpdated(oldBps, newBps);
    }

    function setTokenSupport(address token, uint256 status) external onlyOwner {
        _setTokenSupport(token, status);
    }

    function updateProtocolAddress(bytes32 what, address value) external onlyOwner {
        _updateProtocolAddress(what, value);
    }

    /**
     * @notice Enable/disable emergency withdrawal functionality
     * @param enabled Whether emergency withdrawal should be enabled
     */
    function setEmergencyWithdrawalEnabled(bool enabled) external onlyOwner {
        emergencyWithdrawalEnabled = enabled;
        emit EmergencyWithdrawalEnabledUpdated(enabled);
    }

    /**
     * @notice Emergency withdrawal function for contract funds
     * @param token The token to withdraw
     * @param to The address to withdraw to
     * @param amount The amount to withdraw
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (!emergencyWithdrawalEnabled) {
            revert PaymentProcessor__InvalidStatus();
        }
        if (to == address(0)) {
            revert PaymentProcessor__ThrowZeroAddress();
        }

        if (token != address(0)) {
            // Withdraw ERC20 token
            bool success = IERC20(token).transfer(to, amount);
            if (!success) {
                revert PaymentProcessor__EmergencyWithdrawalFailed();
            }
        }

        emit EmergencyWithdrawal(token, to, amount);
    }

    /**
     * @notice Update order expiration time
     * @param newExpirationTime New expiration time in seconds
     */
    function updateOrderExpirationTime(uint256 newExpirationTime) external onlyOwner {
        if (newExpirationTime == 0) {
            revert PaymentProcessor__InvalidAmount();
        }
        uint256 oldTime = orderExpirationTime;
        orderExpirationTime = newExpirationTime;
        emit OrderExpirationTimeUpdated(oldTime, newExpirationTime);
    }

    /* ##################################################################
                                GETTER FUNCTIONS
    ################################################################## */
    /**
     * @notice update merchantRegistry address - if you upgrade registry
     */
    function getOrder(bytes32 orderId) external view returns (Order memory) {
        return order[orderId];
    }

    /**
     * @notice get the order status
     */
    function getOrderStatus(bytes32 orderId) external view returns (OrderStatus) {
        if (!order[orderId].exists) {
            revert PaymentProcessor__OrderNotFound();
        }
        return order[orderId].status;
    }

    /**
     * @dev See {isTokenSupported - IPaymentProcessor}
     */
    function isTokenSupported(address _token) public view override(IPaymentProcessor, TokensManager) returns (bool) {
        return TokensManager.isTokenSupported(_token);
    }

    /**
     * @notice Returns the ERC20 token balance of a merchant wallet (for dashboard display)
     * @param merchant The merchant address
     * @param token The ERC20 token address (e.g. USDC)
     */
    function getMerchantTokenBalance(address merchant, address token) external view returns (uint256) {
        if (merchant == address(0) || token == address(0)) {
            revert PaymentProcessor__ThrowZeroAddress();
        }
        return IERC20(token).balanceOf(merchant);
    }

    /**
     * @notice Returns the ERC20 token balance of the platform wallet (total value held by platform wallet)
     * @param token The ERC20 token address
     */
    function getPlatformTokenBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            revert PaymentProcessor__TokenNotAllowed();
        }
        return IERC20(token).balanceOf(getPlatformWallet());
    }

    /**
     * @notice Returns the ERC20 token balance held by this contract (pending settlements / escrow)
     * @param token The ERC20 token address
     */
    function getContractTokenBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            revert PaymentProcessor__TokenNotAllowed();
        }
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Check if an order has expired
     * @param orderId The order ID to check
     * @return expired Whether the order has expired
     */
    function isOrderExpired(bytes32 orderId) external view returns (bool expired) {
        if (!order[orderId].exists) return false;
        Order memory o = order[orderId];
        if (o.status != OrderStatus.CREATED) return false;
        return block.timestamp > o.createdAt + orderExpirationTime;
    }

    /**
     * @notice Get order creation timestamp
     * @param orderId The order ID
     * @return createdAt The timestamp when order was created
     */
    function getOrderCreatedAt(bytes32 orderId) external view returns (uint256 createdAt) {
        if (!order[orderId].exists) {
            revert PaymentProcessor__OrderNotFound();
        }
        return order[orderId].createdAt;
    }

    /**
     * @notice Get remaining time before order expires
     * @param orderId The order ID
     * @return remainingTime Seconds until expiration (0 if expired)
     */
    function getOrderRemainingTime(bytes32 orderId) external view returns (uint256 remainingTime) {
        if (!order[orderId].exists) {
            revert PaymentProcessor__OrderNotFound();
        }
        Order memory o = order[orderId];
        if (o.status != OrderStatus.CREATED) return 0;

        uint256 expiryTime = o.createdAt + orderExpirationTime;
        if (block.timestamp >= expiryTime) return 0;
        return expiryTime - block.timestamp;
    }

    /**
     * @notice Calculate fee for a given amount and token
     * @param amount The amount to calculate fee for
     * @return feeAmount The calculated fee amount
     * @return netAmount The net amount after fee deduction
     */
    function calculateFee(uint256 amount) external view returns (uint256 feeAmount, uint256 netAmount) {
        // Always use default platform fee (2%)
        uint256 platformBps = defaultPlatformFeeBps;

        if (maxBps > 0) {
            feeAmount = (amount * platformBps) / maxBps;
        } else {
            feeAmount = 0;
        }
        netAmount = amount - feeAmount;
    }
}
