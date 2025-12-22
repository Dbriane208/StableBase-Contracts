// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IPaymentProcessor
 * @notice Interface for the Payment Processor
 */
interface IPaymentProcessor {
    /* ##################################################################
                                EVENTS
    ################################################################## */
    /**
     * @dev Emitted when a customer clicks pay
     * @param orderId The ID of the Order
     * @param payer The address of the sender
     * @param merchantId The ID of the merchant
     * @param merchantPayout The address to receive the order
     * @param token The address of the token used eg USDC, USDT
     * @param amount The amount to pay
     * @param status The state of the transaction
     * @param metadataUri The store for offchain data
     */
    event OrderCreated(
        bytes32 indexed orderId,
        address indexed payer,
        bytes32 indexed merchantId,
        address merchantPayout,
        address token,
        uint256 amount,
        OrderStatus status,
        string metadataUri
    );

    /**
     * @dev Emitted when an order is paid
     * @param orderId The ID of the order
     * @param payer The address of the user paying
     * @param amount The amount to pay
     * @param status The state of the transaction
     */
    event OrderPaid(bytes32 indexed orderId, address indexed payer, uint256 amount, OrderStatus status);

    /**
     * @dev Emitted when a payment is settled
     * @param orderId The transaction ID
     * @param merchant The address to receive the order
     * @param payer The address of the user paying
     * @param netAmount The amount to be paid
     * @param fee The platform fee
     * @param status The state of the transaction
     */
    event OrderSettled(
        bytes32 indexed orderId,
        address indexed merchant,
        address payer,
        uint256 netAmount,
        uint256 fee,
        OrderStatus status
    );

    /**
     * @dev Emitted when an order is refunded
     * @param orderId The transaction ID
     * @param payer The address of the user paying
     * @param amount The amount to be paid
     */
    event OrderRefunded(bytes32 indexed orderId, address indexed payer, uint256 amount);

    /**
     * @dev Emitted when an order is cancelled
     * @param orderId The transaction ID
     * @param payer The address of the payer
     * @param amount The amount involved during cancellation
     */
    event OrderCancelled(bytes32 indexed orderId, address indexed payer, uint256 amount);

    /**
     * @notice Emitted when the merchant registry address is updated
     * @param oldRegistry The address of the previous merchant registry contract
     * @param newRegistry The address of the new merchant registry contract
     */
    event MerchantRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /**
     * @notice Emitted when the order expiration time is updated
     * @param oldTime The previous expiration time in seconds
     * @param newTime The new expiration time in seconds
     */
    event OrderExpirationTimeUpdated(uint256 oldTime, uint256 newTime);

    /**
     * @notice Emitted when the maximum slippage in basis points is updated
     * @param oldSlippage The previous maximum slippage value in basis points
     * @param newSlippage The new maximum slippage value in basis points
     */
    event MaxSlippageBpsUpdated(uint256 oldSlippage, uint256 newSlippage);

    /**
     * @notice Emitted when the emergency withdrawal feature is enabled or disabled
     * @param enabled True if emergency withdrawal is enabled, false otherwise
     */
    event EmergencyWithdrawalEnabledUpdated(bool enabled);

    /**
     * @notice Emitted when an emergency withdrawal is executed
     * @param token The address of the token being withdrawn (address(0) for native token)
     * @param to The address receiving the withdrawn funds
     * @param amount The amount of tokens withdrawn
     */
    event EmergencyWithdrawalSuccess(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Emitted when an order expires without being fulfilled
     * @param orderId The unique identifier of the expired order
     * @param payer The address of the user who created the expired order
     */
    event OrderExpired(bytes32 indexed orderId, address indexed payer);
    /* ##################################################################
                               STRUCTS/ENUMS
    ################################################################## */
    /**
     * @dev Enum representing order
     * @param None The default state
     * @param Created The order is created waiting for payment
     * @param Paid The funds are transferred to this contract
     * @param Fulfilled The merchant delivered the order
     * @param Settled The funds are sent to merchant
     * @param Refunded The funds are returned to the payer
     * @param Cancelled The order is cancelled
     */
    enum OrderStatus {
        NONE,
        CREATED,
        PAID,
        SETTLED,
        REFUNDED,
        CANCELLED
    }

    /**
     * @dev Struct representing  an order
     * @param payer The address of the person to pay
     * @param merchantId The ID of the merchant associated with a particular order
     * @param merchantPayout The address to receive payment
     * @param token The token address used for payment
     * @param amount The amount to be paid
     * @param status The state of the transaction
     * @param currentBps The current basis points
     * @param metadataUri The off-chain metadata
     * @param createdAt Timestamp when the order was created
     * @param exists Helper flag
     */
    struct Order {
        address payer;
        address token;
        bytes32 merchantId;
        address merchantPayout;
        uint256 amount;
        bool exists;
        uint96 currentBps;
        uint256 createdAt;
        string metadataUri;
        OrderStatus status;
    }
    /* ##################################################################
                                EXTERNAL CALLS
    ################################################################## */
    /**
     * @notice create an order
     * @param _merchantId The ID of a registered merchant
     * @param _token The address to settle the transaction
     * @param _amount The value to be paid
     * @param _metadataUri The offchain store for the order
     * @return _orderId The ID of the order
     */
    function createOrder(bytes32 _merchantId, address _token, uint256 _amount, string calldata _metadataUri)
        external
        returns (bytes32 _orderId);

    /**
     * @notice pays the order to the contract
     * @param _orderId The ID of the order
     * @return bool the order is paid successful
     */
    function payOrder(bytes32 _orderId) external returns (bool);

    /**
     * @notice fulfills the order from a merchant wallet
     * @param _orderId The ID of the order
     * @return bool the order if fulfilled successful
     */
    function settleOrder(bytes32 _orderId) external returns (bool);

    /**
     * @notice refunds to the specified address
     * @param _orderId The ID of the order
     * @return bool the order is refunded successful
     */
    function refundOrder(bytes32 _orderId) external returns (bool);

    /**
     * @notice cancels an order
     * @param _orderId The ID of the order
     * @return bool the order is canceled successful
     */
    function cancelOrder(bytes32 _orderId) external returns (bool);

    /**
     * @notice Retrieves the complete order details for a given order ID
     * @param _orderId The unique identifier of the order to retrieve
     * @return Order memory structure containing all order information
     */
    function getOrder(bytes32 _orderId) external view returns (Order memory);

    /**
     * @notice Gets the current status of a specific order
     * @param _orderId The unique identifier of the order
     * @return OrderStatus The order's current status
     */
    function getOrderStatus(bytes32 _orderId) external view returns (OrderStatus);

    /**
     * @notice Checks if a token is supported by the payment processor
     * @param _token The address of the token to check
     * @return bool True if the token is supported, false otherwise
     */
    function isTokenSupported(address _token) external view returns (bool);

    /**
     * @notice Gets the token balance for a specific merchant
     * @param _merchant The address of the merchant
     * @param _token The address of the token to check balance for
     * @return uint256 The merchant's balance of the specified token
     */
    function getMerchantTokenBalance(address _merchant, address _token) external view returns (uint256);

    /**
     * @notice Gets the platform's token balance
     * @param _token The address of the token to check balance for
     * @return uint256 The platform's balance of the specified token
     */
    function getPlatformTokenBalance(address _token) external view returns (uint256);

    /**
     * @notice Gets the total token balance held by this contract
     * @param _token The address of the token to check balance for
     * @return uint256 The contract's balance of the specified token
     */
    function getContractTokenBalance(address _token) external view returns (uint256);
}
