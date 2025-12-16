// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import {PaymentProcessor} from "../../src/contracts/PaymentProcessor.sol";
import {MerchantRegistry} from "../../src/contracts/MerchantRegistry.sol";
import {IPaymentProcessor} from "../../src/interfaces/IPaymentProcessor.sol";
import {IMerchantRegistry} from "../../src/interfaces/IMerchantRegistry.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        bytes memory merchantInitData = abi.encodeCall(MerchantRegistry.initialize, ());
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
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME)
        );

        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        // Verify initialization state
        assertEq(paymentProcessor.defaultPlatformFeeBps(), DEFAULT_PLATFORM_FEE_BPS);
        assertEq(address(paymentProcessor.merchantRegistry()), address(merchantRegistry));
        assertEq(paymentProcessor.orderExpirationTime(), ORDER_EXPIRATION_TIME);
        assertEq(paymentProcessor.emergencyWithdrawalEnabled(), false);
        assertEq(paymentProcessor.getPlatformWallet(), platformWallet);
        // Note: Ownable2Step initializes with zero owner by default, ownership needs to be explicitly transferred
        assertEq(paymentProcessor.paused(), false);
    }

    function testInitializeRevertsWithZeroPlatformWallet() public {
        PaymentProcessor impl = new PaymentProcessor();

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (address(0), DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME)
        );

        vm.expectRevert(PaymentProcessor.PaymentProcessor__ThrowZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithInvalidFeeBps() public {
        PaymentProcessor impl = new PaymentProcessor();
        uint256 invalidFeeBps = 100_001; // Greater than MAX_BPS (100_000)

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, invalidFeeBps, address(merchantRegistry), ORDER_EXPIRATION_TIME)
        );

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InvalidAmount.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithZeroMerchantRegistry() public {
        PaymentProcessor impl = new PaymentProcessor();

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize, (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(0), ORDER_EXPIRATION_TIME)
        );

        vm.expectRevert(PaymentProcessor.PaymentProcessor__ThrowZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeRevertsWithInvalidOrderExpirationTime() public {
        PaymentProcessor impl = new PaymentProcessor();
        uint256 invalidExpirationTime = 86401; // Greater than 86400 (24 hours)

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), invalidExpirationTime)
        );

        vm.expectRevert(PaymentProcessor.PaymentProcessor__OrderExpired.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function testInitializeCannotBeCalledTwice() public {
        PaymentProcessor impl = new PaymentProcessor();

        // First initialization should succeed
        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME)
        );
        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        // Second initialization should fail with InvalidInitialization custom error
        vm.expectRevert();
        paymentProcessor.initialize(
            platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME
        );
    }

    function testInitializeWithBoundaryValues() public {
        PaymentProcessor impl = new PaymentProcessor();
        uint256 maxValidFeeBps = 100_000; // MAX_BPS
        uint256 maxValidExpirationTime = 86400; // 24 hours

        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, maxValidFeeBps, address(merchantRegistry), maxValidExpirationTime)
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
            PaymentProcessor.initialize, (platformWallet, minFeeBps, address(merchantRegistry), minExpirationTime)
        );
        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        assertEq(paymentProcessor.defaultPlatformFeeBps(), minFeeBps);
        assertEq(paymentProcessor.orderExpirationTime(), minExpirationTime);
    }

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
        _setupMerchantRegistryOwnership();

        // Deploy PaymentProcessor implementation
        PaymentProcessor impl = new PaymentProcessor();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME)
        );

        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        address currentOwner = paymentProcessor.owner();

        if (currentOwner == address(0)) {
            // Try using the deployment script's pattern with a foundry cheatcode
            vm.prank(address(0)); // Pretend to be address(0) to bypass ownership check
            paymentProcessor.transferOwnership(address(this));
            paymentProcessor.acceptOwnership();
        } else if (currentOwner != address(this)) {
            // If someone else is the owner, transfer to this contract
            vm.prank(currentOwner);
            paymentProcessor.transferOwnership(address(this));
            paymentProcessor.acceptOwnership();
        }

        paymentProcessor.pause();

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
            usdcToken.transfer(address(0xdead), payerBalance);
        }

        // Verify payer has insufficient balance
        assertLt(usdcToken.balanceOf(payer), amount, "Payer should have insufficient balance");

        vm.expectRevert(PaymentProcessor.PaymentProcessor__InsufficientBalance.selector);
        paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://ordermetadata.json");

        vm.stopPrank();
    }

    /**
     * @notice PAYMNENT TESTS
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
        _setupMerchantRegistryOwnership();

        // Deploy PaymentProcessor implementation
        PaymentProcessor impl = new PaymentProcessor();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME)
        );

        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        address currentOwner = paymentProcessor.owner();

        if (currentOwner == address(0)) {
            // Try using the deployment script's pattern with a foundry cheatcode
            vm.prank(address(0)); // Pretend to be address(0) to bypass ownership check
            paymentProcessor.transferOwnership(address(this));
            paymentProcessor.acceptOwnership();
        } else if (currentOwner != address(this)) {
            // If someone else is the owner, transfer to this contract
            vm.prank(currentOwner);
            paymentProcessor.transferOwnership(address(this));
            paymentProcessor.acceptOwnership();
        }

        paymentProcessor.pause();

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
            usdtToken.transfer(address(0xdead), currentBalance);
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

    /**
     * @notice SETTLEMENT TESTS
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
           _setupMerchantRegistryOwnership();

           // Deploy PaymentProcessor implementation
           PaymentProcessor impl = new PaymentProcessor();

           // Deploy proxy with initialization
           bytes memory initData = abi.encodeCall(
              PaymentProcessor.initialize,
              (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME)
           );

           paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

           address currentOwner = paymentProcessor.owner();

           if (currentOwner == address(0)) {
              // Try using the deployment script's pattern with a foundry cheatcode
              vm.prank(address(0)); // Pretend to be address(0) to bypass ownership check
              paymentProcessor.transferOwnership(address(this));
              paymentProcessor.acceptOwnership();
           } else if (currentOwner != address(this)) {
              // If someone else is the owner, transfer to this contract
              vm.prank(currentOwner);
              paymentProcessor.transferOwnership(address(this));
              paymentProcessor.acceptOwnership();
           }

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
           paymentProcessor.pause();

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

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME)
        );

        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(impl), initData)));

        address currentOwner = paymentProcessor.owner();

        if (currentOwner == address(0)) {
            // Try using the deployment script's pattern with a foundry cheatcode
            vm.prank(address(0)); // Pretend to be address(0) to bypass ownership check
            paymentProcessor.transferOwnership(address(this));
            paymentProcessor.acceptOwnership();
        } else if (currentOwner != address(this)) {
            // If someone else is the owner, transfer to this contract
            vm.prank(currentOwner);
            paymentProcessor.transferOwnership(address(this));
            paymentProcessor.acceptOwnership();
        }
    }

    /**
     * @dev Helper function to setup MerchantRegistry ownership
     */
    function _setupMerchantRegistryOwnership() internal {
        address currentOwner = merchantRegistry.owner();

        if (currentOwner == address(0)) {
            // If no owner is set, transfer ownership to this contract
            vm.prank(address(0));
            merchantRegistry.transferOwnership(address(this));
            merchantRegistry.acceptOwnership();
        } else if (currentOwner != address(this)) {
            // If someone else is the owner, transfer to this contract
            vm.prank(currentOwner);
            merchantRegistry.transferOwnership(address(this));
            merchantRegistry.acceptOwnership();
        }
    }
}
