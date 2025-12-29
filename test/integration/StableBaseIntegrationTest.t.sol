// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PaymentProcessor} from "../../src/contracts/PaymentProcessor.sol";
import {MerchantRegistry} from "../../src/contracts/MerchantRegistry.sol";
import {IMerchantRegistry} from "../../src/interfaces/IMerchantRegistry.sol";
import {IPaymentProcessor} from "../../src/interfaces/IPaymentProcessor.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title StableBase Complete Integration Test Suite
 * @notice Comprehensive integration tests for StableBase payment processing platform
 */
contract StableBaseIntegrationComplete is Test {
    // Contracts
    PaymentProcessor public paymentProcessor;
    MerchantRegistry public merchantRegistry;
    ERC20Mock public usdcToken;
    ERC20Mock public usdtToken;

    // Test addresses
    address public platformWallet = makeAddr("platformWallet");
    address public owner = makeAddr("owner");
    address public merchant1 = makeAddr("merchant1");
    address public merchant2 = makeAddr("merchant2");
    address public customer1 = makeAddr("customer1");
    address public customer2 = makeAddr("customer2");

    // Constants
    uint256 constant DEFAULT_PLATFORM_FEE_BPS = 2000; // 2%
    uint256 constant ORDER_EXPIRATION_TIME = 86400; // 24 hours
    uint256 constant INITIAL_TOKEN_SUPPLY = 1_000_000e18;
    uint256 constant CUSTOMER_INITIAL_BALANCE = 10_000e18;

    function setUp() public {
        // Deploy MerchantRegistry with owner
        MerchantRegistry merchantImpl = new MerchantRegistry();
        bytes memory merchantInitData = abi.encodeCall(MerchantRegistry.initialize, (owner));
        merchantRegistry = MerchantRegistry(address(new ERC1967Proxy(address(merchantImpl), merchantInitData)));

        // Deploy PaymentProcessor with owner
        PaymentProcessor paymentImpl = new PaymentProcessor();
        bytes memory paymentInitData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME, owner)
        );
        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(paymentImpl), paymentInitData)));

        // Deploy tokens
        usdcToken = new ERC20Mock("USD Coin", "USDC", address(this), INITIAL_TOKEN_SUPPLY);
        usdtToken = new ERC20Mock("Tether USD", "USDT", address(this), INITIAL_TOKEN_SUPPLY);

        // Enable tokens
        vm.startPrank(owner);
        paymentProcessor.setTokenSupport(address(usdcToken), 1);
        paymentProcessor.setTokenSupport(address(usdtToken), 1);
        vm.stopPrank();

        // Fund customers
        bool ok;
        ok = usdcToken.transfer(customer1, CUSTOMER_INITIAL_BALANCE);
        ok = usdcToken.transfer(customer2, CUSTOMER_INITIAL_BALANCE);
        ok = usdtToken.transfer(customer1, CUSTOMER_INITIAL_BALANCE);
        if (!ok) {
            revert PaymentProcessor.PaymentProcessor__TransferFailed();
        }
    }

    // Helper function to register and verify a merchant
    function _registerAndVerifyMerchant(address merchantAddr) internal returns (bytes32) {
        vm.prank(merchantAddr);
        bytes32 merchantId = merchantRegistry.registerMerchant(merchantAddr, "ipfs://metadata");

        vm.prank(owner);
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        return merchantId;
    }

    // ============================================
    // MERCHANT REGISTRATION & VERIFICATION FLOW
    // ============================================

    function testIntegration_MerchantOnboardingFlow() public {
        // Register merchant
        vm.prank(merchant1);
        bytes32 merchantId = merchantRegistry.registerMerchant(merchant1, "ipfs://merchant1");

        // Check pending status
        IMerchantRegistry.Merchant memory m = merchantRegistry.getMerchantInfo(merchantId);
        assertEq(uint256(m.verificationStatus), uint256(IMerchantRegistry.VerificationStatus.PENDING));

        // Verify merchant
        vm.prank(owner);
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        // Check verified
        m = merchantRegistry.getMerchantInfo(merchantId);
        assertEq(uint256(m.verificationStatus), uint256(IMerchantRegistry.VerificationStatus.VERIFIED));

        // Create order
        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        vm.stopPrank();

        assertTrue(orderId != bytes32(0));
    }

    function testIntegration_MerchantRegistrationWithInvalidData() public {
        // Zero address wallet
        vm.prank(merchant1);
        vm.expectRevert();
        merchantRegistry.registerMerchant(address(0), "ipfs://metadata");

        // Empty metadata
        vm.prank(merchant1);
        vm.expectRevert();
        merchantRegistry.registerMerchant(merchant1, "");
    }

    function testIntegration_MerchantProfileUpdate() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        address newWallet = makeAddr("newWallet");
        vm.prank(merchant1);
        merchantRegistry.updateMerchant(merchantId, newWallet, "ipfs://updated");

        IMerchantRegistry.Merchant memory m = merchantRegistry.getMerchantInfo(merchantId);
        assertEq(m.payoutWallet, newWallet);
        assertEq(m.metadataURI, "ipfs://updated");
    }

    function testIntegration_UnverifiedMerchantCannotReceivePayments() public {
        vm.prank(merchant1);
        bytes32 merchantId = merchantRegistry.registerMerchant(merchant1, "ipfs://merchant1");

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        vm.expectRevert();
        paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        vm.stopPrank();
    }

    function testIntegration_MerchantVerificationStatusTransitions() public {
        vm.prank(merchant1);
        bytes32 merchantId = merchantRegistry.registerMerchant(merchant1, "ipfs://merchant1");

        // PENDING -> VERIFIED
        vm.prank(owner);
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);
        IMerchantRegistry.Merchant memory m = merchantRegistry.getMerchantInfo(merchantId);
        assertEq(uint256(m.verificationStatus), uint256(IMerchantRegistry.VerificationStatus.VERIFIED));

        // VERIFIED -> SUSPENDED
        vm.prank(owner);
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.SUSPENDED);
        m = merchantRegistry.getMerchantInfo(merchantId);
        assertEq(uint256(m.verificationStatus), uint256(IMerchantRegistry.VerificationStatus.SUSPENDED));

        // SUSPENDED -> VERIFIED
        vm.prank(owner);
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);
        m = merchantRegistry.getMerchantInfo(merchantId);
        assertEq(uint256(m.verificationStatus), uint256(IMerchantRegistry.VerificationStatus.VERIFIED));
    }

    function testIntegration_SuspendedMerchantCannotProcessOrders() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        // Suspend merchant
        vm.prank(owner);
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.SUSPENDED);

        // Try to create order
        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        vm.expectRevert();
        paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        vm.stopPrank();
    }

    // ============================================
    // TOKEN MANAGEMENT & SUPPORT TESTS
    // ============================================

    function testIntegration_AddNewSupportedToken() public {
        ERC20Mock newToken = new ERC20Mock("New Token", "NEW", address(this), INITIAL_TOKEN_SUPPLY);

        assertFalse(paymentProcessor.isTokenSupported(address(newToken)));

        vm.prank(owner);
        paymentProcessor.setTokenSupport(address(newToken), 1);

        assertTrue(paymentProcessor.isTokenSupported(address(newToken)));
    }

    function testIntegration_DisableSupportedToken() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        // Create order with USDC
        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        vm.stopPrank();

        // Disable USDC
        vm.prank(owner);
        paymentProcessor.setTokenSupport(address(usdcToken), 0);

        // Existing order still works
        vm.prank(customer1);
        paymentProcessor.payOrder(orderId);

        // New order fails
        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        vm.expectRevert();
        paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order2");
        vm.stopPrank();
    }

    function testIntegration_PaymentWithUnsupportedToken() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);
        ERC20Mock unsupportedToken = new ERC20Mock("Unsupported", "UNS", customer1, 10000e18);

        vm.startPrank(customer1);
        unsupportedToken.approve(address(paymentProcessor), 1000e18);
        vm.expectRevert();
        paymentProcessor.createOrder(merchantId, address(unsupportedToken), 1000e18, "ipfs://order");
        vm.stopPrank();
    }

    function testIntegration_MultipleStablecoinsConcurrentUsage() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        // Create orders with different tokens
        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        usdtToken.approve(address(paymentProcessor), 1000e18);

        bytes32 orderId1 = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order1");
        bytes32 orderId2 = paymentProcessor.createOrder(merchantId, address(usdtToken), 1000e18, "ipfs://order2");

        // Pay all orders
        paymentProcessor.payOrder(orderId1);
        paymentProcessor.payOrder(orderId2);
        vm.stopPrank();

        assertTrue(orderId1 != bytes32(0) && orderId2 != bytes32(0));
    }

    // ============================================
    // COMPLETE ORDER LIFECYCLE TESTS
    // ============================================

    function testIntegration_SuccessfulOrderLifecycle() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);
        uint256 amount = 1000e18;
        uint256 fee = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 netAmount = amount - fee;

        uint256 merchantBalanceBefore = usdcToken.balanceOf(merchant1);
        uint256 platformBalanceBefore = usdcToken.balanceOf(platformWallet);

        // Create order
        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), amount);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://order");

        // Pay order
        paymentProcessor.payOrder(orderId);
        vm.stopPrank();

        // Settle order
        vm.prank(merchant1);
        paymentProcessor.settleOrder(orderId);

        // Verify balances
        assertEq(usdcToken.balanceOf(merchant1), merchantBalanceBefore + netAmount);
        assertEq(usdcToken.balanceOf(platformWallet), platformBalanceBefore + fee);
    }

    function testIntegration_OrderCreationByCustomer() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);

        vm.expectEmit(false, true, false, true);
        emit IPaymentProcessor.OrderCreated(
            bytes32(0),
            customer1,
            merchantId,
            merchant1,
            address(usdcToken),
            1000e18,
            IPaymentProcessor.OrderStatus.CREATED,
            "ipfs://order"
        );

        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        vm.stopPrank();

        assertTrue(orderId != bytes32(0));
    }

    function testIntegration_CustomerPaymentOnOrder() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");

        uint256 balanceBefore = usdcToken.balanceOf(customer1);
        paymentProcessor.payOrder(orderId);
        uint256 balanceAfter = usdcToken.balanceOf(customer1);
        vm.stopPrank();

        assertEq(balanceBefore - balanceAfter, 1000e18);
        assertEq(usdcToken.balanceOf(address(paymentProcessor)), 1000e18);
    }

    function testIntegration_OrderSettlementAndFundDistribution() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);
        uint256 amount = 1000e18;
        uint256 fee = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        uint256 netAmount = amount - fee;

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), amount);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://order");
        paymentProcessor.payOrder(orderId);
        vm.stopPrank();

        uint256 merchantBalanceBefore = usdcToken.balanceOf(merchant1);
        uint256 platformBalanceBefore = usdcToken.balanceOf(platformWallet);

        vm.prank(merchant1);
        paymentProcessor.settleOrder(orderId);

        assertEq(usdcToken.balanceOf(merchant1) - merchantBalanceBefore, netAmount);
        assertEq(usdcToken.balanceOf(platformWallet) - platformBalanceBefore, fee);
    }

    function testIntegration_OrderWithCustomPlatformFee() public {
        // Note: This would require adding custom fee functionality to the contract
        // For now, we'll test with default fee
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);
        uint256 amount = 1000e18;

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), amount);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), amount, "ipfs://order");
        paymentProcessor.payOrder(orderId);
        vm.stopPrank();

        vm.prank(merchant1);
        paymentProcessor.settleOrder(orderId);

        // Verify default fee was applied
        uint256 expectedFee = (amount * DEFAULT_PLATFORM_FEE_BPS) / 100_000;
        assertEq(usdcToken.balanceOf(platformWallet), expectedFee);
    }

    function testIntegration_MultipleOrdersSameMerchantSingleBlock() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 3000e18);

        bytes32 orderId1 = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order1");
        bytes32 orderId2 = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order2");
        bytes32 orderId3 = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order3");
        vm.stopPrank();

        assertTrue(orderId1 != orderId2 && orderId2 != orderId3 && orderId1 != orderId3);
    }

    function testIntegration_OrderExpirationMechanism() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        vm.stopPrank();

        // Fast forward past expiration
        vm.warp(block.timestamp + ORDER_EXPIRATION_TIME + 1);

        vm.prank(customer1);
        vm.expectRevert();
        paymentProcessor.payOrder(orderId);
    }

    function testIntegration_PaymentOnExpiredOrder() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        vm.stopPrank();

        vm.warp(block.timestamp + ORDER_EXPIRATION_TIME + 1);

        vm.prank(customer1);
        vm.expectRevert();
        paymentProcessor.payOrder(orderId);
    }
}
