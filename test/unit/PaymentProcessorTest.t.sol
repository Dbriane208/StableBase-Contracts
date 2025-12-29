// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PaymentProcessor} from "../../src/contracts/PaymentProcessor.sol";
import {MerchantRegistry} from "../../src/contracts/MerchantRegistry.sol";
import {IPaymentProcessor} from "../../src/interfaces/IPaymentProcessor.sol";
import {IMerchantRegistry} from "../../src/interfaces/IMerchantRegistry.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MaliciousERC20} from "../../src/mocks/MaliciousERC20.sol";

contract PaymentProcessorTest is Test {
    PaymentProcessor paymentProcessor;
    MerchantRegistry merchantRegistry;
    ERC20Mock usdcToken;
    ERC20Mock usdtToken;
    ERC20Mock cusdToken;

    address private platformWallet = makeAddr("platformWallet");
    address private owner = makeAddr("owner");
    address private merchant = makeAddr("merchant");
    address private payer = makeAddr("payer");
    address private platformEmergencyWallet = makeAddr("merchantEWallet");

    uint256 constant DEFAULT_PLATFORM_FEE_BPS = 2000; // 2%
    uint256 constant ORDER_EXPIRATION_TIME = 86400; // 24 hours in seconds
    uint256 constant INITIAL_TOKEN_SUPPLY = 1000000e18; // 1M tokens

    function setUp() public {
        // Deploy mock tokens
        usdcToken = new ERC20Mock("USD Coin", "USDC", address(this), INITIAL_TOKEN_SUPPLY);
        usdtToken = new ERC20Mock("USDT Coin", "USDT", address(this), INITIAL_TOKEN_SUPPLY);
        cusdToken = new ERC20Mock("cUSD Coin", "cUSD", address(this), INITIAL_TOKEN_SUPPLY);

        // Deploy MerchantRegistry with proxy
        MerchantRegistry merchantImpl = new MerchantRegistry();
        bytes memory merchantInitData = abi.encodeCall(MerchantRegistry.initialize, (address(this)));
        merchantRegistry = MerchantRegistry(address(new ERC1967Proxy(address(merchantImpl), merchantInitData)));
    }

    /* ##################################################################
                                MODIFIERS
    ################################################################## */
    modifier ownerDeploySetup() {
        // Deploy and setup the contracts properly
        _deployAndSetupPaymentProcessor();

        // Set up MerchantRegistry ownership and register merchant
        _setupMerchantRegistryOwnership();
        _;
    }

    /**
     * @dev Initialization tests
     */
    function testInitialize() public {
        // Deploy PaymentProcessor implementation
        PaymentProcessor impl = new PaymentProcessor();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME, address(this))
        );

        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        // Verify initialization state
        assertEq(paymentProcessor.defaultPlatformFeeBps(), DEFAULT_PLATFORM_FEE_BPS);
        assertEq(address(paymentProcessor.merchantRegistry()), address(merchantRegistry));
        assertEq(paymentProcessor.orderExpirationTime(), ORDER_EXPIRATION_TIME);
        assertEq(paymentProcessor.emergencyWithdrawalEnabled(), false);
        assertEq(paymentProcessor.getPlatformWallet(), platformWallet);
        assertEq(paymentProcessor.owner(), address(this));
        assertEq(paymentProcessor.paused(), false);
    }

    function testInitializeRevertsWithZeroPlatformWallet() public {
        PaymentProcessor impl = new PaymentProcessor();

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (address(0), DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME, address(this))
        );

        vm.expectRevert(PaymentProcessor.PaymentProcessor__ThrowZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithInvalidFeeBps() public {
        PaymentProcessor impl = new PaymentProcessor();
        uint256 invalidFeeBps = 100_001; // Greater than MAX_BPS (100_000)

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, invalidFeeBps, address(merchantRegistry), ORDER_EXPIRATION_TIME, address(this))
        );

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InvalidAmount.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithZeroMerchantRegistry() public {
        PaymentProcessor impl = new PaymentProcessor();

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize, (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(0), ORDER_EXPIRATION_TIME, address(this))
        );

        vm.expectRevert(PaymentProcessor.PaymentProcessor__ThrowZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithInvalidOrderExpirationTime() public {
        PaymentProcessor impl = new PaymentProcessor();
        uint256 invalidExpirationTime = 86401; // Greater than 86400 (24 hours)

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), invalidExpirationTime, address(this))
        );

        vm.expectRevert(PaymentProcessor.PaymentProcessor__OrderExpired.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeCannotBeCalledTwice() public {
        PaymentProcessor impl = new PaymentProcessor();

        // First initialization should succeed
        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME, address(this))
        );
        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        // Second initialization should fail with InvalidInitialization custom error
        vm.expectRevert();
        paymentProcessor.initialize(
            platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME, address(this)
        );
    }

    function testInitializeWithBoundaryValues() public {
        PaymentProcessor impl = new PaymentProcessor();
        uint256 maxValidFeeBps = 100_000; // MAX_BPS
        uint256 maxValidExpirationTime = 86400; // 24 hours

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, maxValidFeeBps, address(merchantRegistry), maxValidExpirationTime, address(this))
        );
        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        assertEq(paymentProcessor.defaultPlatformFeeBps(), maxValidFeeBps);
        assertEq(paymentProcessor.orderExpirationTime(), maxValidExpirationTime);
    }

    function testInitializeWithMinimumValues() public {
        PaymentProcessor impl = new PaymentProcessor();
        uint256 minFeeBps = 0;
        uint256 minExpirationTime = 1; // 1 second

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize, (platformWallet, minFeeBps, address(merchantRegistry), minExpirationTime, address(this))
        );
        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        assertEq(paymentProcessor.defaultPlatformFeeBps(), minFeeBps);
        assertEq(paymentProcessor.orderExpirationTime(), minExpirationTime);
    }

    /* ##################################################################
                                ORDER CREATION TESTS
    ################################################################## */

    /**
     * @dev Order Creation tests
     */
    function testCreateOrderSuccess() public ownerDeploySetup {
        // Use a proper amount - 0.1 tokens (100000000000000000 wei for 18 decimals)
        uint256 amount = toTokenAmount(100, IERC20(address(usdcToken))); // 100 USDC (with 6 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDC as supported token
        paymentProcessor.setTokenSupport(address(usdcToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://ordermetadata.json");

        PaymentProcessor.Order memory o = paymentProcessor.getOrder(orderId);

        assertTrue(o.exists);
        assertEq(uint8(o.status), uint8(IPaymentProcessor.OrderStatus.CREATED));
        assertEq(o.metadataUri, "ipfs://ordermetadata.json");
    }

    /**
     * @dev Verify OrderCreated event emission
     */
    function testCreateOrderEmitsEvent() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdcToken))); // 100 USDC (with 6 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDC as supported token
        paymentProcessor.setTokenSupport(address(usdcToken), 1);

        // Emit the event
        vm.expectEmit(false, true, true, true);

        // Emit the expected template
        emit IPaymentProcessor.OrderCreated(
            bytes32(0),
            address(this),
            merchantId,
            merchant,
            address(usdcToken),
            amount,
            IPaymentProcessor.OrderStatus.CREATED,
            "ipfs://ordermetadata.json"
        );

        // Call the function that must emit the event
        paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://ordermetadata.json");
    }

    /**
     * @dev Order ID uniqueness
     */
    function testCreateOrderGeneratesUniqueId() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdcToken))); // 100 USDC (with 6 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDC as supported token
        paymentProcessor.setTokenSupport(address(usdcToken), 1);
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderIdOne =
            paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://ordermetadata.json");

        bytes32 orderIdTwo =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // assert
        assertNotEq(orderIdOne, orderIdTwo);
    }

    /**
     * @dev Token support validation
     */
    function testCreateOrderRevertsWithUnsupportedToken() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdcToken))); // 100 USDC (with 6 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__TokenNotAllowed.selector);

        paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://ordermetadata.json");
    }

    /**
     * @dev Amount Validation
     */
    function testCreateOrderRevertsWithZeroAmount() public ownerDeploySetup {
        uint256 amount = toTokenAmount(0, IERC20(address(usdcToken))); // 100 USDC (with 6 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDC as supported token
        paymentProcessor.setTokenSupport(address(usdcToken), 1);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InvalidAmount.selector);

        paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://ordermetadata.json");
    }

    /**
     * @dev Metadata URI validation
     */

    function testCreateOrderRevertsWithInvalidMetadata() public ownerDeploySetup {
        uint256 amount = toTokenAmount(10, IERC20(address(usdcToken))); // 100 USDC (with 6 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDC as supported token
        paymentProcessor.setTokenSupport(address(usdcToken), 1);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InvalidMetadataUri.selector);

        paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "");
    }

    /**
     * @dev Merchant validation
     */
    function testCreateOrderRevertsWithUnregisteredMerchant() public ownerDeploySetup {
        bytes32 merchantId = bytes32(0);

        vm.expectRevert(MerchantRegistry.MerchantRegistry__MerchantNotFound.selector);

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);
    }

    /**
     * @dev Pause state validation
     */
    function testCreateOrderRevertsWhenPaused() public {
        PaymentProcessor processor = emergencyTestHelper();

        processor.pause();

        uint256 amount = toTokenAmount(10, IERC20(address(usdcToken))); // 100 USDC (with 6 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDC as supported token
        paymentProcessor.setTokenSupport(address(usdcToken), 1);

        vm.expectRevert();

        paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://ordermetadata.json");
    }

    /**
     * @dev Balance validation
     */
    function testCreateOrderRevertsWithInsufficientBalance() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdcToken))); // 100 USDC

        // Register merchant and setup as owner
        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);
        paymentProcessor.setTokenSupport(address(usdcToken), 1);

        // Switch to payer context for order creation
        vm.startPrank(payer);

        // Ensure payer has insufficient balance (0 or less than required)
        uint256 payerBalance = usdcToken.balanceOf(payer);
        if (payerBalance >= amount) {
            // If payer somehow has enough tokens, transfer them away
            bool ok = usdcToken.transfer(address(0xdead), payerBalance);
            if (!ok) {
                revert PaymentProcessor.PaymentProcessor__TransferFailed();
            }
        }

        // Verify payer has insufficient balance
        assertLt(usdcToken.balanceOf(payer), amount, "Payer should have insufficient balance");

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InsufficientBalance.selector);
        paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://ordermetadata.json");

        vm.stopPrank();
    }

    /* ##################################################################
                                PAYMENT TESTS
    ################################################################## */

    /**
     * @dev Valid payment processing
     */
    function testPayOrderSuccess() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        bool success = paymentProcessor.payOrder(orderId);

        // assert
        assertTrue(success);
    }

    /**
     * Verify OrderPaid event emission
     */
    function testPayOrderEmitsEvent() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        vm.expectEmit(true, true, false, true);

        // Emit the expected
        emit IPaymentProcessor.OrderPaid(orderId, address(this), amount, IPaymentProcessor.OrderStatus.PAID);

        paymentProcessor.payOrder(orderId);
    }

    /**
     * @dev Check if status is CREATED -> PAID
     */
    function testPayOrderUpdatesStatus() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        bool success = paymentProcessor.payOrder(orderId);

        if (success) {
            IPaymentProcessor.OrderStatus status = paymentProcessor.getOrderStatus(orderId);

            assertEq(uint8(status), uint8(IPaymentProcessor.OrderStatus.PAID));
        }
    }

    /**
     * @dev Token transfer validation
     */
    function testPayOrderTransfersTokensToContract() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Record balances before payment
        uint256 payerBalanceBefore = usdtToken.balanceOf(address(this)); // Payer is this test contract
        uint256 contractBalanceBefore = usdtToken.balanceOf(address(paymentProcessor));

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        paymentProcessor.payOrder(orderId);

        // Record balances after payment
        uint256 payerBalanceAfter = usdtToken.balanceOf(address(this));
        uint256 contractBalanceAfter = usdtToken.balanceOf(address(paymentProcessor));

        // Assertions
        assertEq(payerBalanceBefore - payerBalanceAfter, amount, "Payer should have transferred the exact amount");
        assertEq(
            contractBalanceAfter - contractBalanceBefore,
            amount,
            "PaymentProcessor should have received the exact amount"
        );

        // Log for debugging
        console2.log("Payer (test contract) address:", address(this));
        console2.log("Payer balance before payment:", payerBalanceBefore);
        console2.log("Payer balance after payment:", payerBalanceAfter);
        console2.log("Amount transferred:", amount);
    }

    /**
     * @dev Check Order existence check
     */
    function testPayOrderRevertsWithNonExistentOrder() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId = bytes32(0);

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__OrderNotFound.selector);

        paymentProcessor.payOrder(orderId);
    }

    /**
     * @dev Check Status validation (only CREATED)
     */
    function testPayOrderRevertsWithWrongStatus() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        paymentProcessor.payOrder(orderId);

        // Now this should revert because status is no longer CREATED
        usdtToken.approve(address(paymentProcessor), amount);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InvalidStatus.selector);
        paymentProcessor.payOrder(orderId);
    }

    /**
     * @dev Pause state validation
     */
    function testPayOrderRevertsWhenPaused() public ownerDeploySetup {
        PaymentProcessor processor = emergencyTestHelper();

        processor.pause();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId = bytes32(0);

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        vm.expectRevert();

        paymentProcessor.payOrder(orderId);
    }

    /**
     * @dev Order expiration validation
     */
    function testPayOrderRevertsWithExpiredOrder() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        // Create order at current timestamp
        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens
        usdtToken.approve(address(paymentProcessor), amount);

        // Warp time forward beyond expiration (ORDER_EXPIRATION_TIME + 1 second)
        vm.warp(block.timestamp + ORDER_EXPIRATION_TIME + 1);

        // Attempt to pay the expired order
        vm.expectRevert(PaymentProcessor.PaymentProcessor__OrderExpired.selector);
        paymentProcessor.payOrder(orderId);
    }

    /**
     * @dev Payer balance validation
     */
    function testPayOrderRevertsWithInsufficientBalance() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        // Create order at current timestamp
        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Transfer away all tokens from this contract to ensure insufficient balance
        uint256 currentBalance = usdtToken.balanceOf(address(this));
        if (currentBalance > 0) {
            bool ok = usdtToken.transfer(address(0xdead), currentBalance);
            if (!ok) {
                revert PaymentProcessor.PaymentProcessor__TransferFailed();
            }
        }

        // Verify insufficient balance
        assertLt(usdtToken.balanceOf(address(this)), amount, "Payer should have insufficient balance");

        // Approve PaymentProcessor to spend tokens (even though we don't have enough)
        usdtToken.approve(address(paymentProcessor), amount);

        // Expect revert due to insufficient balance
        vm.expectRevert(PaymentProcessor.PaymentProcessor__TransferFailed.selector);
        paymentProcessor.payOrder(orderId);
    }

    /**
     * @dev Token allowance validation
     */
    function testPayOrderRevertsWithInsufficientAllowance() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT
        uint256 lessAmount = toTokenAmount(50, IERC20(address(usdtToken)));

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        // Create order at current timestamp
        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens
        usdtToken.approve(address(paymentProcessor), lessAmount);

        // Expect revert due to insufficient allowance
        vm.expectRevert(PaymentProcessor.PaymentProcessor__TransferFailed.selector);
        paymentProcessor.payOrder(orderId);
    }

    /* ##################################################################
                                SETTLEMENT TESTS
    ################################################################## */

    /**
     * @dev Merchant settlement authorization
     */
    function testSettleOrderByMerchant() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Record balances before payment
        uint256 merchantBalanceBefore = usdtToken.balanceOf(merchant);
        uint256 platformWalletBefore = usdtToken.balanceOf(platformWallet);

        // settle the order
        bool ok = paymentProcessor.settleOrder(orderId);

        // Record balances before payment
        uint256 merchantBalanceAfter = usdtToken.balanceOf(merchant);
        uint256 platformWalletAfter = usdtToken.balanceOf(platformWallet);

        // Log for debugging
        console2.log("Amount transferred:", amount);
        console2.log("Merchant balance before payment:", merchantBalanceBefore);
        console2.log("PlatformWallet balance before payment:", platformWalletBefore);

        console2.log("Merchant balance after payment:", merchantBalanceAfter);
        console2.log("PlatformWallet balance after payment:", platformWalletAfter);

        // Check if the response is true
        assertTrue(ok);
        assertEq(amount, merchantBalanceAfter + platformWalletAfter);
    }

    /**
     * @dev Verify OrderSettled event emission
     */
    function testSettleOrderEmitsEvent() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)
        uint256 netAmount = toTokenAmount(98, IERC20(address(usdtToken)));
        uint256 fee = amount - netAmount;

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        vm.expectEmit(true, true, false, true);

        emit IPaymentProcessor.OrderSettled(
            orderId, merchant, address(this), netAmount, fee, IPaymentProcessor.OrderStatus.SETTLED
        );

        // settle the order
        paymentProcessor.settleOrder(orderId);
    }

    /**
     * @dev Status PAID -> SETTLED
     */
    function testSettleOrderUpdatesStatus() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        PaymentProcessor.Order memory o = paymentProcessor.getOrder(orderId);
        PaymentProcessor.OrderStatus update = paymentProcessor.getOrderStatus(orderId);

        assertEq(uint8(o.status), uint8(update));
    }

    /**
     * @dev Fee calculation validation
     */
    function testSettleOrderCalculatesCorrectFees() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Record balance before settlement
        uint256 merchantBalanceBefore = usdtToken.balanceOf(merchant);
        uint256 platformBalanceBefore = usdtToken.balanceOf(platformWallet);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Record balance after settlement
        uint256 merchantBalanceAfter = usdtToken.balanceOf(merchant);
        uint256 platformBalanceAfter = usdtToken.balanceOf(platformWallet);

        // calculate expected fee (2% deduction)
        uint256 expectedFee = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 expectedMerchantAmount = amount - expectedFee;

        //assertions
        assertEq(
            merchantBalanceAfter - merchantBalanceBefore,
            expectedMerchantAmount,
            "Merchant should receive amount minus platform fee"
        );
        assertEq(
            platformBalanceAfter - platformBalanceBefore, expectedFee, "Platform wallet should receive the platform fee"
        );
        assertEq(
            (merchantBalanceAfter - merchantBalanceBefore) + (platformBalanceAfter - platformBalanceBefore),
            amount,
            "Total distributed should equal original amount"
        );
    }

    /**
     * @dev Merchant payout validation
     */
    function testSettleOrderTransfersToMerchant() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Record balance before settlement
        uint256 merchantBalanceBefore = usdtToken.balanceOf(merchant);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Record balance after settlement
        uint256 merchantBalanceAfter = usdtToken.balanceOf(merchant);

        console2.log("Merchant Balance Before: ", merchantBalanceBefore);
        console2.log("Merchant Balance After: ", merchantBalanceAfter);

        // assert
        assertLt(merchantBalanceBefore, merchantBalanceAfter);
    }

    /**
     * @dev Platform fee validation
     */
    function testSettleOrderTransfersToPlatform() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Record balance before settlement
        uint256 platformBalanceBefore = usdtToken.balanceOf(platformWallet);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Record balance after settlement
        uint256 platformBalanceAfter = usdtToken.balanceOf(platformWallet);

        console2.log("Platform Balance Before: ", platformBalanceBefore);
        console2.log("Platform Balance After: ", platformBalanceAfter);

        // assert
        assertLt(platformBalanceBefore, platformBalanceAfter);
    }

    /**
     * @dev Order existence check
     */
    function testSettleOrderRevertsWithNonExistentOrder() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__OrderNotFound.selector);
        // settle the order
        paymentProcessor.settleOrder(bytes32(0));
    }

    /**
     * @dev Status validation (only PAID)
     */
    function testSettleOrderRevertsWithWrongStatus() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Now this should revert because status is no longer CREATED
        usdtToken.approve(address(paymentProcessor), amount);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InvalidStatus.selector);

        // settle the order
        paymentProcessor.settleOrder(orderId);
    }

    /**
     * @dev Pause state validation
     */
    function testSettleOrderRevertsWhenPaused() public {
        PaymentProcessor processor = emergencyTestHelper();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Pause the contract
        processor.pause();

        // Expect revert when trying to settle while paused
        vm.expectRevert();
        paymentProcessor.settleOrder(orderId);
    }

    /**
     * @dev Authorization validation
     */
    function testSettleOrderRevertsWithUnauthorizedCaller() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Try to settle from unauthorized address (payer instead of merchant/owner)
        vm.prank(payer);
        vm.expectRevert();
        paymentProcessor.settleOrder(orderId);
    }

    /* ##################################################################
                                REFUND TESTS
    ################################################################## */

    /**
     * @dev Merchant and Owner refund authorization
     */
    function testRefundOrderByMerchantAndOwner() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Calculate the amounts that were distributed
        uint256 feeAmount = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 netAmount = amount - feeAmount;

        // Merchant needs to approve the contract to pull back their tokens
        vm.prank(merchant);
        usdtToken.approve(address(paymentProcessor), netAmount);

        // Platform wallet needs to approve the contract to pull back the fee
        vm.prank(platformWallet);
        usdtToken.approve(address(paymentProcessor), feeAmount);

        // refund the order
        bool success = paymentProcessor.refundOrder(orderId);

        PaymentProcessor.Order memory refund = paymentProcessor.getOrder(orderId);

        console2.log("Amount to be refunded: ", refund.amount);

        // assertion
        assertTrue(success);
        assertEq(refund.amount, netAmount + feeAmount);
    }

    /**
     * @dev Verify OrderRefunded event emission
     */
    function testRefundOrderEmitsEvent() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Calculate the amounts that were distributed
        uint256 feeAmount = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 netAmount = amount - feeAmount;

        // Merchant needs to approve the contract to pull back their tokens
        vm.prank(merchant);
        usdtToken.approve(address(paymentProcessor), netAmount);

        // Platform wallet needs to approve the contract to pull back the fee
        vm.prank(platformWallet);
        usdtToken.approve(address(paymentProcessor), feeAmount);

        vm.expectEmit(true, true, false, false);

        emit IPaymentProcessor.OrderRefunded(orderId, address(this), amount);

        // refund the order
        paymentProcessor.refundOrder(orderId);
    }

    /**
     * @dev Status PAID -> REFUNDED
     */
    function testRefundOrderUpdatesStatus() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Calculate the amounts that were distributed
        uint256 feeAmount = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 netAmount = amount - feeAmount;

        // Merchant needs to approve the contract to pull back their tokens
        vm.prank(merchant);
        usdtToken.approve(address(paymentProcessor), netAmount);

        // Platform wallet needs to approve the contract to pull back the fee
        vm.prank(platformWallet);
        usdtToken.approve(address(paymentProcessor), feeAmount);

        // refund the order
        paymentProcessor.refundOrder(orderId);

        PaymentProcessor.OrderStatus status = paymentProcessor.getOrderStatus(orderId);

        PaymentProcessor.Order memory o = paymentProcessor.getOrder(orderId);

        // assertions
        assertEq(uint8(status), uint8(o.status));
        assertEq(uint8(status), uint8(IPaymentProcessor.OrderStatus.REFUNDED));
    }

    /**
     * @dev Order existence check
     */
    function testRefundOrderRevertsWithNonExistentOrder() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Calculate the amounts that were distributed
        uint256 feeAmount = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 netAmount = amount - feeAmount;

        // Merchant needs to approve the contract to pull back their tokens
        vm.prank(merchant);
        usdtToken.approve(address(paymentProcessor), netAmount);

        // Platform wallet needs to approve the contract to pull back the fee
        vm.prank(platformWallet);
        usdtToken.approve(address(paymentProcessor), feeAmount);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__OrderNotFound.selector);

        // refund the order
        paymentProcessor.refundOrder(bytes32(0));
    }

    /**
     * @dev Status validation - should revert when status is CREATED (not PAID or SETTLED)
     */
    function testRefundOrderRevertsWithWrongStatus() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Order is in CREATED status - refund should fail
        vm.expectRevert(PaymentProcessor.PaymentProcessor__InvalidStatus.selector);

        // Try to refund an order that hasn't been paid yet (status is CREATED)
        paymentProcessor.refundOrder(orderId);
    }

    /**
     * @dev Status validation - should revert when trying to refund an already refunded order
     */
    function testRefundOrderRevertsWhenAlreadyRefunded() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // First refund should succeed
        paymentProcessor.refundOrder(orderId);

        // Verify status is now REFUNDED
        PaymentProcessor.OrderStatus status = paymentProcessor.getOrderStatus(orderId);
        assertEq(uint8(status), uint8(IPaymentProcessor.OrderStatus.REFUNDED));

        // Second refund attempt should fail
        vm.expectRevert(PaymentProcessor.PaymentProcessor__InvalidStatus.selector);
        paymentProcessor.refundOrder(orderId);
    }

    /**
     * @dev Pause state validation
     */
    function testRefundOrderRevertsWhenPaused() public {
        PaymentProcessor processor = emergencyTestHelper();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Calculate the amounts that were distributed
        uint256 feeAmount = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 netAmount = amount - feeAmount;

        // Merchant needs to approve the contract to pull back their tokens
        vm.prank(merchant);
        usdtToken.approve(address(paymentProcessor), netAmount);

        // Platform wallet needs to approve the contract to pull back the fee
        vm.prank(platformWallet);
        usdtToken.approve(address(paymentProcessor), feeAmount);

        processor.pause();

        // the paymentProcessor is paused
        vm.expectRevert();

        // refund the order
        paymentProcessor.refundOrder(orderId);
    }

    /**
     * @dev Authorization validation
     */
    function testRefundOrderRevertsWithUnauthorizedCaller() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // settle the order
        paymentProcessor.settleOrder(orderId);

        // Calculate the amounts that were distributed
        uint256 feeAmount = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 netAmount = amount - feeAmount;

        // Merchant needs to approve the contract to pull back their tokens
        vm.prank(merchant);
        usdtToken.approve(address(paymentProcessor), netAmount);

        // Platform wallet needs to approve the contract to pull back the fee
        vm.prank(platformWallet);
        usdtToken.approve(address(paymentProcessor), feeAmount);

        vm.prank(payer);
        vm.expectRevert();

        // refund the order
        paymentProcessor.refundOrder(orderId);
    }

    /* ##################################################################
                                CANCELLATION TESTS
    ################################################################## */
    /**
     * @dev Payer(address(this)) cancellation authorization
     */
    function testCancelOrderByPayer() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Merchant should be able to cancel their own order
        paymentProcessor.cancelOrder(orderId);

        // Verify the order was cancelled
        PaymentProcessor.OrderStatus status = paymentProcessor.getOrderStatus(orderId);

        // assert
        assertEq(uint8(status), uint8(IPaymentProcessor.OrderStatus.CANCELLED));
    }

    /**
     * @dev Merchant cannot cancel order - only payer can cancel
     */
    function testCancelOrderRevertsWhenCalledByMerchant() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Merchant should NOT be able to cancel - only payer can
        vm.prank(merchant);
        vm.expectRevert(PaymentProcessor.PaymentProcessor__UnauthorizedAccess.selector);
        paymentProcessor.cancelOrder(orderId);
    }

    /**
     * @dev Verify Order cancelled event emission
     */
    function testCancelOrderEmitsEvent() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        vm.expectEmit(true, true, false, true);

        emit IPaymentProcessor.OrderCancelled(orderId, address(this), amount);

        // cancel the order
        paymentProcessor.cancelOrder(orderId);
    }

    /**
     * @dev Status CREATED -> CANCELLED
     */
    function testCancelOrderUpdatesStatus() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // cancel the order
        paymentProcessor.cancelOrder(orderId);

        // Verify the order was cancelled
        PaymentProcessor.OrderStatus status = paymentProcessor.getOrderStatus(orderId);

        // assert
        assertEq(uint8(status), uint8(IPaymentProcessor.OrderStatus.CANCELLED));
    }

    /**
     * @dev Order existence check
     */
    function testCancelOrderRevertsWithNonExistentOrder() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        vm.expectRevert(PaymentProcessor.PaymentProcessor__OrderNotFound.selector);

        // cancel the order
        paymentProcessor.cancelOrder(bytes32(0));
    }

    /**
     * @dev Status validation (only CREATED)
     */
    function testCancelOrderRevertsWithWrongStatus() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // cancel the order
        paymentProcessor.cancelOrder(orderId);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InvalidStatus.selector);

        // cancel the order
        paymentProcessor.cancelOrder(orderId);
    }

    /**
     * @dev Pause state validation
     */
    function testCancelOrderRevertsWhenPaused() public {
        PaymentProcessor processor = emergencyTestHelper();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // pause th contract
        processor.pause();

        vm.expectRevert();

        // cancel the order
        paymentProcessor.cancelOrder(orderId);
    }

    /**
     * @dev Authorization validation
     */
    function testCancelOrderRevertsWithUnauthorizedCaller() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        vm.prank(merchant);
        vm.expectRevert(PaymentProcessor.PaymentProcessor__UnauthorizedAccess.selector);
        // cancel the order
        paymentProcessor.cancelOrder(orderId);
    }

    /* ##################################################################
                                EMERGENCY FUNCTION TESTS
    ################################################################## */
    /**
     * @dev Emergency flag toggle
     */
    function testSetEmergencyWithdrawalEnabledEmit() public ownerDeploySetup {
        vm.expectEmit(false, false, false, true);
        emit IPaymentProcessor.EmergencyWithdrawalEnabledUpdated(true);
        paymentProcessor.setEmergencyWithdrawalEnabled(true);
    }

    /**
     * @dev Owner-Only validation
     */
    function testSetEmergencyWithdrawalEnabledRevertsWhenNotOwner() public ownerDeploySetup {
        vm.prank(payer);
        vm.expectRevert();
        paymentProcessor.setEmergencyWithdrawalEnabled(true);
    }

    /* ##################################################################
                                ADMIN FUNCTION TESTS
    ################################################################## */
    /**
     * @dev Registry address update - successful update
     */
    function testUpdateMerchantRegistry() public ownerDeploySetup {
        // Deploy a new MerchantRegistry with owner
        MerchantRegistry newMerchantRegistryImpl = new MerchantRegistry();
        bytes memory newMerchantInitData = abi.encodeCall(MerchantRegistry.initialize, (address(this)));
        MerchantRegistry newMerchantRegistry =
            MerchantRegistry(address(new ERC1967Proxy(address(newMerchantRegistryImpl), newMerchantInitData)));

        // Get old registry address
        address oldRegistry = address(paymentProcessor.merchantRegistry());

        // Expect the event to be emitted
        vm.expectEmit(true, true, false, false);
        emit IPaymentProcessor.MerchantRegistryUpdated(oldRegistry, address(newMerchantRegistry));

        // Update the merchant registry
        paymentProcessor.updateMerchantRegistry(address(newMerchantRegistry));

        // Verify the registry was updated
        assertEq(address(paymentProcessor.merchantRegistry()), address(newMerchantRegistry));
        assertNotEq(address(paymentProcessor.merchantRegistry()), oldRegistry);
    }

    /**
     * @dev Registry address update - reverts with zero address
     */
    function testUpdateMerchantRegistryRevertsWithZeroAddress() public ownerDeploySetup {
        vm.expectRevert(PaymentProcessor.PaymentProcessor__ThrowZeroAddress.selector);
        paymentProcessor.updateMerchantRegistry(address(0));
    }

    /**
     * @dev Registry address update - reverts when called by non-owner
     */
    function testUpdateMerchantRegistryRevertsWithNonOwner() public ownerDeploySetup {
        // Deploy a new MerchantRegistry with owner
        MerchantRegistry newMerchantRegistryImpl = new MerchantRegistry();
        bytes memory newMerchantInitData = abi.encodeCall(MerchantRegistry.initialize, (address(this)));
        MerchantRegistry newMerchantRegistry =
            MerchantRegistry(address(new ERC1967Proxy(address(newMerchantRegistryImpl), newMerchantInitData)));

        // Try to update from non-owner address
        vm.prank(payer);
        vm.expectRevert();
        paymentProcessor.updateMerchantRegistry(address(newMerchantRegistry));
    }

    /**
     * @dev Emergency token withdrawal
     */
    function testEmergencyWithdrawEmitSuccess() public {
        PaymentProcessor processor = emergencyTestHelper();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Get the actual contract balance to withdraw
        uint256 contractBalance = usdtToken.balanceOf(address(paymentProcessor));
        console2.log("Contract's balance: ", contractBalance);

        // Enable emergency withdrawal and pause
        paymentProcessor.setEmergencyWithdrawalEnabled(true);

        processor.pause();

        vm.expectEmit(true, true, false, true);
        emit IPaymentProcessor.EmergencyWithdrawalSuccess(address(usdtToken), platformEmergencyWallet, contractBalance);

        paymentProcessor.emergencyWithdraw(address(usdtToken), platformEmergencyWallet, contractBalance);
    }

    /**
     * @dev Enable flag validation
     */
    function testEmergencyWithdrawRevertsWhenDisabled() public {
        PaymentProcessor processor = emergencyTestHelper();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Get the actual contract balance to withdraw
        uint256 contractBalance = usdtToken.balanceOf(address(paymentProcessor));

        processor.pause();

        paymentProcessor.setEmergencyWithdrawalEnabled(false);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__EmergencyDisabled.selector);

        paymentProcessor.emergencyWithdraw(address(usdtToken), platformEmergencyWallet, contractBalance);
    }

    /**
     * @dev Owner-only validation
     */
    function testEmergencyWithdrawRevertsWhenNotOwner() public {
        PaymentProcessor processor = emergencyTestHelper();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Get the actual contract balance to withdraw
        uint256 contractBalance = usdtToken.balanceOf(address(paymentProcessor));

        processor.pause();

        paymentProcessor.setEmergencyWithdrawalEnabled(true);

        vm.prank(payer);

        vm.expectRevert();

        paymentProcessor.emergencyWithdraw(address(usdtToken), platformEmergencyWallet, contractBalance);
    }

    /**
     * @dev Address validation
     */
    function testEmergencyWithdrawRevertsWithZeroAddress() public {
        PaymentProcessor processor = emergencyTestHelper();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        // Get the actual contract balance to withdraw
        uint256 contractBalance = usdtToken.balanceOf(address(paymentProcessor));

        processor.pause();

        paymentProcessor.setEmergencyWithdrawalEnabled(true);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__ThrowZeroAddress.selector);
        paymentProcessor.emergencyWithdraw(address(usdtToken), address(0), contractBalance);
    }

    /**
     * @dev Balance validation
     */
    function testEmergencyWithdrawRevertsWithInsufficientBalance() public {
        PaymentProcessor processor = emergencyTestHelper();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)
        uint256 exceedAmount = amount + amount;

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        processor.pause();

        paymentProcessor.setEmergencyWithdrawalEnabled(true);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InsufficientBalance.selector);
        paymentProcessor.emergencyWithdraw(address(usdtToken), platformEmergencyWallet, exceedAmount);
    }

    /**
     * @dev Token validation
     */
    function testEmergencyWithdrawRevertsWithInvalidToken() public {
        PaymentProcessor processor = emergencyTestHelper();

        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)
        uint256 exceedAmount = amount + amount;

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Approve PaymentProcessor to spend tokens on behalf of this contract (the payer)
        usdtToken.approve(address(paymentProcessor), amount);

        // pay the order
        paymentProcessor.payOrder(orderId);

        processor.pause();

        paymentProcessor.setEmergencyWithdrawalEnabled(true);

        vm.expectRevert(PaymentProcessor.PaymentProcessor__TokenNotAllowed.selector);
        paymentProcessor.emergencyWithdraw(address(0), platformEmergencyWallet, exceedAmount);
    }

    /* ##################################################################
                                VIEW FUNCTIONS TESTS
    ################################################################## */

    /**
     * @dev Order data retrieval
     */
    function testGetOrderReturnsCorrectData() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Get the order and verify its fields
        PaymentProcessor.Order memory o = paymentProcessor.getOrder(orderId);

        // verify each field of the order
        assertEq(o.merchantId, merchantId, "Merchant ID should match");
        assertEq(o.payer, address(this), "Payer should be zero address (not paid yet)");
        assertEq(o.token, address(usdtToken), "Token address should match");
        assertEq(o.amount, amount, "Amount should match");
        assertEq(uint8(o.status), uint8(IPaymentProcessor.OrderStatus.CREATED), "Status should be CREATED");
        assertGt(o.createdAt, 0, "Created timestamp should be set");
    }

    /**
     * @dev Token support status check
     */
    function testIsTokenSupportedReturnsCorrectStatus() public ownerDeploySetup {
        // Initially, no tokens are supported
        assertFalse(paymentProcessor.isTokenSupported(address(usdtToken)), "USDT should not be supported initially");
        assertFalse(paymentProcessor.isTokenSupported(address(usdcToken)), "USDC should not be supported initially");
        assertFalse(paymentProcessor.isTokenSupported(address(cusdToken)), "cUSD should not be supported initially");

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);
        assertTrue(paymentProcessor.isTokenSupported(address(usdtToken)), "USDT should be supported after adding");
        assertFalse(paymentProcessor.isTokenSupported(address(usdcToken)), "USDC should still not be supported");

        // Add USDC as supported token
        paymentProcessor.setTokenSupport(address(usdcToken), 1);
        assertTrue(paymentProcessor.isTokenSupported(address(usdcToken)), "USDC should be supported after adding");
        assertTrue(paymentProcessor.isTokenSupported(address(usdtToken)), "USDT should still be supported");

        // Remove USDT support
        paymentProcessor.setTokenSupport(address(usdtToken), 0);
        assertFalse(paymentProcessor.isTokenSupported(address(usdtToken)), "USDT should not be supported after removal");
        assertTrue(paymentProcessor.isTokenSupported(address(usdcToken)), "USDC should still be supported");

        // Check zero address returns false
        assertFalse(paymentProcessor.isTokenSupported(address(0)), "Zero address should not be supported");
    }

    /**
     * @dev Balance calculation for the contract - verifies getContractTokenBalance returns correct balance
     */
    function testContractTokenBalance() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Initially, contract should have zero balance
        assertEq(
            paymentProcessor.getContractTokenBalance(address(usdtToken)),
            0,
            "Contract should have zero balance initially"
        );

        usdtToken.approve(address(paymentProcessor), amount);

        paymentProcessor.payOrder(orderId);

        // After payment, contract should hold the full amount before settlement
        uint256 contractBalanceAfterPayment = usdtToken.balanceOf(address(paymentProcessor));
        uint256 viewBalanceAfterPayment = paymentProcessor.getContractTokenBalance(address(usdtToken));

        assertEq(contractBalanceAfterPayment, amount, "Contract should hold full payment amount");
        assertEq(viewBalanceAfterPayment, contractBalanceAfterPayment, "View function should match actual balance");

        paymentProcessor.settleOrder(orderId);

        // After settlement, contract balance should be zero (all tokens distributed)
        uint256 contractBalanceAfterSettlement = usdtToken.balanceOf(address(paymentProcessor));
        uint256 viewBalanceAfterSettlement = paymentProcessor.getContractTokenBalance(address(usdtToken));

        assertEq(contractBalanceAfterSettlement, 0, "Contract should have zero balance after settlement");
        assertEq(
            viewBalanceAfterSettlement,
            contractBalanceAfterSettlement,
            "View function should match actual balance after settlement"
        );
    }

    /**
     * @dev Balance calculation for merchants - verifies getMerchantTokenBalance returns correct balance
     */
    function testMerchantTokenBalance() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Initially, merchant should have zero balance
        assertEq(
            paymentProcessor.getMerchantTokenBalance(merchant, address(usdtToken)),
            0,
            "Merchant should have zero balance initially"
        );

        usdtToken.approve(address(paymentProcessor), amount);

        paymentProcessor.payOrder(orderId);

        paymentProcessor.settleOrder(orderId);

        // After settlement, verify merchant received payment minus platform fee
        uint256 expectedFee = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 expectedMerchantAmount = amount - expectedFee;

        uint256 merchantBalance = usdtToken.balanceOf(merchant);
        uint256 viewBalance = paymentProcessor.getMerchantTokenBalance(merchant, address(usdtToken));

        assertEq(merchantBalance, expectedMerchantAmount, "Merchant should receive amount minus platform fee");
        assertEq(viewBalance, merchantBalance, "View function should match actual merchant balance");
    }

    /**
     * @dev Balance calculation for platform - verifies getPlatformTokenBalance returns correct balance
     */
    function testPlatformTokenBalance() public ownerDeploySetup {
        uint256 amount = toTokenAmount(100, IERC20(address(usdtToken))); // 100 USDT (with 18 decimals)

        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");

        // Verify the merchant
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add USDT as supported token
        paymentProcessor.setTokenSupport(address(usdtToken), 1);

        bytes32 orderId =
            paymentProcessor.createOrder(merchantId, address(usdtToken), amount, "ipfs://ordermetadata.json");

        // Initially, platform should have zero balance
        assertEq(
            paymentProcessor.getPlatformTokenBalance(address(usdtToken)),
            0,
            "Platform should have zero balance initially"
        );

        usdtToken.approve(address(paymentProcessor), amount);

        paymentProcessor.payOrder(orderId);

        paymentProcessor.settleOrder(orderId);

        // After settlement, verify platform received the correct fee
        uint256 expectedFee = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;

        uint256 platformBalance = usdtToken.balanceOf(platformWallet);
        uint256 viewBalance = paymentProcessor.getPlatformTokenBalance(address(usdtToken));

        assertEq(platformBalance, expectedFee, "Platform should receive the platform fee");
        assertEq(viewBalance, platformBalance, "View function should match actual platform balance");
    }

    /* ##################################################################
                                REENTRANCY TESTS
    ################################################################## */
    /**
     * @dev Reentrancy protection - verifies nonReentrant modifier prevents reentrancy attacks on payOrder
     * @notice This test creates a malicious ERC20 token that attempts reentrancy during transferFrom
     */
    function testCreateOrderPreventsReentrancy() public ownerDeploySetup {
        // Deploy malicious ERC20 token with attacker as initial holder
        uint256 amount = 100e18;
        MaliciousERC20 maliciousToken = new MaliciousERC20("Malicious Token", "MAL", payer, amount * 2);

        // Set the payment processor address in the malicious token
        maliciousToken.setPaymentProcessor(address(paymentProcessor));

        // Register and verify merchant
        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add malicious token as supported token
        paymentProcessor.setTokenSupport(address(maliciousToken), 1);

        // Payer creates an order
        vm.startPrank(payer);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(maliciousToken), amount, "ipfs://order.json");

        // Payer approves the payment processor to spend tokens
        maliciousToken.approve(address(paymentProcessor), amount);

        // Configure the malicious token to attack during transferFrom
        maliciousToken.setAttackParameters(true, orderId);

        // Attempt to pay the order - the malicious token will try to reenter payOrder
        // This should revert with ReentrancyGuard error
        vm.expectRevert();
        paymentProcessor.payOrder(orderId);

        vm.stopPrank();
    }

    /**
     * @dev Reentrancy protection - verifies nonReentrant modifier prevents reentrancy attacks on settleOrder
     * @notice This test creates a malicious ERC20 token that attempts reentrancy during transfer
     */
    function testSettleOrderPreventsReentrancy() public ownerDeploySetup {
        // Deploy malicious ERC20 token with payer as initial holder
        uint256 amount = 100e18;
        MaliciousERC20 maliciousToken = new MaliciousERC20("Malicious Token", "MAL", payer, amount * 2);

        // Set the payment processor address in the malicious token
        maliciousToken.setPaymentProcessor(address(paymentProcessor));

        // Register and verify merchant
        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add malicious token as supported token
        paymentProcessor.setTokenSupport(address(maliciousToken), 1);

        // Payer creates an order
        vm.startPrank(payer);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(maliciousToken), amount, "ipfs://order.json");

        // Payer approves the payment processor to spend tokens
        maliciousToken.approve(address(paymentProcessor), amount);

        // First, pay the order WITHOUT attack
        paymentProcessor.payOrder(orderId);
        vm.stopPrank();

        // NOW configure the attack for settleOrder
        maliciousToken.setAttackParameters(true, orderId);

        // Settle as owner/test contract (not payer)
        // This should revert with ReentrancyGuard error when malicious token tries to reenter
        vm.expectRevert();
        paymentProcessor.settleOrder(orderId);
    }

    /**
     * @dev Reentrancy protection - verifies nonReentrant modifier prevents reentrancy attacks on refundOrder
     * @notice This test creates a malicious ERC20 token that attempts reentrancy during transfer
     */
    function testRefundOrderPreventsReentrancy() public ownerDeploySetup {
        // Deploy malicious ERC20 token with payer as initial holder
        uint256 amount = 100e18;
        MaliciousERC20 maliciousToken = new MaliciousERC20("Malicious Token", "MAL", payer, amount * 2);

        // Set the payment processor address in the malicious token
        maliciousToken.setPaymentProcessor(address(paymentProcessor));

        // Register and verify merchant
        bytes32 merchantId = merchantRegistry.registerMerchant(merchant, "ipfs://metadata.json");
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Add malicious token as supported token
        paymentProcessor.setTokenSupport(address(maliciousToken), 1);

        // Payer creates an order
        vm.startPrank(payer);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(maliciousToken), amount, "ipfs://order.json");

        // Payer approves the payment processor to spend tokens
        maliciousToken.approve(address(paymentProcessor), amount);

        // First, pay the order WITHOUT attack
        paymentProcessor.payOrder(orderId);
        vm.stopPrank();

        // NOW configure the attack for refundOrder
        maliciousToken.setAttackParameters(true, orderId);

        // Call refund as owner (test contract)
        vm.expectRevert();
        paymentProcessor.refundOrder(orderId);
    }

    /* ##################################################################
                                HELPER FUNCTIONS
    ################################################################## */
    /**
     *@dev  helper function to manipulate the amount to be in supported tokens
     */
    function toTokenAmount(uint256 amount, IERC20 token) internal view returns (uint256) {
        uint8 decimals = ERC20Mock(address(token)).decimals();
        return amount * (10 ** decimals);
    }

    /**
     * @dev Helper function to deploy and setup PaymentProcessor with proper ownership
     * @notice After deployment, the deployer (this test contract) should become the owner,
     * After intializating since we're using ownable2stepupgrade which at first sets the owner address to zero
     * We need to give [this test contract] the ownership
     */
    function _deployAndSetupPaymentProcessor() internal {
        // Deploy PaymentProcessor implementation
        PaymentProcessor impl = new PaymentProcessor();

        // Deploy proxy with initialization (this test contract is the owner)
        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME, address(this))
        );

        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));
    }

    /**
     * @dev Helper function to setup MerchantRegistry ownership
     * Owner is set to address(this) during initialization in setUp()
     */
    function _setupMerchantRegistryOwnership() internal {
        // Owner is already set to address(this) during initialization
        // This helper is kept for compatibility but no action needed
    }

    function emergencyTestHelper() internal returns (PaymentProcessor) {
        _setupMerchantRegistryOwnership();

        // Deploy PaymentProcessor implementation
        PaymentProcessor impl = new PaymentProcessor();

        // Deploy proxy with initialization (this test contract is the owner)
        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME, address(this))
        );

        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        return paymentProcessor;
    }
}
