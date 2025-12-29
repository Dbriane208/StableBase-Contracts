// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {PaymentProcessor} from "../../src/contracts/PaymentProcessor.sol";
import {MerchantRegistry} from "../../src/contracts/MerchantRegistry.sol";
import {IMerchantRegistry} from "../../src/interfaces/IMerchantRegistry.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title GasOptimizationTest
 * @notice Gas optimization and efficiency tests for StableBase contracts
 * @dev Measures gas consumption for various operations and compares scenarios
 */
contract GasOptimizationTest is Test {
    PaymentProcessor public paymentProcessor;
    MerchantRegistry public merchantRegistry;
    ERC20Mock public usdcToken;
    ERC20Mock public usdtToken;

    address public platformWallet = makeAddr("platformWallet");
    address public owner = makeAddr("owner");
    address public merchant1 = makeAddr("merchant1");
    address public merchant2 = makeAddr("merchant2");
    address public customer1 = makeAddr("customer1");
    address public customer2 = makeAddr("customer2");

    uint256 constant DEFAULT_PLATFORM_FEE_BPS = 2000;
    uint256 constant ORDER_EXPIRATION_TIME = 86400;
    uint256 constant INITIAL_TOKEN_SUPPLY = 1_000_000e18;
    uint256 constant CUSTOMER_INITIAL_BALANCE = 100_000e18;

    function setUp() public {
        // Deploy contracts with owner set during initialization
        MerchantRegistry merchantImpl = new MerchantRegistry();
        bytes memory merchantInitData = abi.encodeCall(MerchantRegistry.initialize, (owner));
        merchantRegistry = MerchantRegistry(address(new ERC1967Proxy(address(merchantImpl), merchantInitData)));

        PaymentProcessor paymentImpl = new PaymentProcessor();
        bytes memory paymentInitData = abi.encodeCall(
            PaymentProcessor.initialize,
            (platformWallet, DEFAULT_PLATFORM_FEE_BPS, address(merchantRegistry), ORDER_EXPIRATION_TIME, owner)
        );
        paymentProcessor = PaymentProcessor(address(new ERC1967Proxy(address(paymentImpl), paymentInitData)));

        // Deploy and enable tokens
        usdcToken = new ERC20Mock("USD Coin", "USDC", address(this), INITIAL_TOKEN_SUPPLY);
        usdtToken = new ERC20Mock("Tether USD", "USDT", address(this), INITIAL_TOKEN_SUPPLY);

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

    function _registerAndVerifyMerchant(address merchantAddr) internal returns (bytes32) {
        vm.prank(merchantAddr);
        bytes32 merchantId = merchantRegistry.registerMerchant(merchantAddr, "ipfs://metadata");

        vm.prank(owner);
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        return merchantId;
    }

    // ============================================
    // MERCHANT REGISTRATION GAS TESTS
    // ============================================

    /// @notice Test gas cost of merchant registration
    function testGas_MerchantRegistration() public {
        uint256 gasBefore = gasleft();

        vm.prank(merchant1);
        merchantRegistry.registerMerchant(merchant1, "ipfs://merchant-metadata");

        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for merchant registration:", gasUsed);

        // Assert reasonable gas usage (should be < 200k gas)
        assertLt(gasUsed, 200_000, "Merchant registration should use less than 200k gas");
    }

    /// @notice Test gas cost of merchant verification status update
    function testGas_MerchantVerification() public {
        vm.prank(merchant1);
        bytes32 merchantId = merchantRegistry.registerMerchant(merchant1, "ipfs://metadata");

        uint256 gasBefore = gasleft();

        vm.prank(owner);
        merchantRegistry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for merchant verification:", gasUsed);

        assertLt(gasUsed, 100_000, "Merchant verification should use less than 100k gas");
    }

    /// @notice Test gas cost of merchant profile update
    function testGas_MerchantProfileUpdate() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        address newWallet = makeAddr("newWallet");
        uint256 gasBefore = gasleft();

        vm.prank(merchant1);
        merchantRegistry.updateMerchant(merchantId, newWallet, "ipfs://updated-metadata");

        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for merchant profile update:", gasUsed);

        assertLt(gasUsed, 150_000, "Merchant profile update should use less than 150k gas");
    }

    // ============================================
    // ORDER LIFECYCLE GAS TESTS
    // ============================================

    /// @notice Test gas cost of order creation
    function testGas_OrderCreation() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);

        uint256 gasBefore = gasleft();
        paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order-metadata");
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console.log("Gas used for order creation:", gasUsed);
        assertLt(gasUsed, 280_000, "Order creation should use less than 280k gas");
    }

    /// @notice Test gas cost of order payment
    function testGas_OrderPayment() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");

        uint256 gasBefore = gasleft();
        paymentProcessor.payOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console.log("Gas used for order payment:", gasUsed);
        assertLt(gasUsed, 150_000, "Order payment should use less than 150k gas");
    }

    /// @notice Test gas cost of order settlement
    function testGas_OrderSettlement() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        paymentProcessor.payOrder(orderId);
        vm.stopPrank();

        uint256 gasBefore = gasleft();
        vm.prank(merchant1);
        paymentProcessor.settleOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for order settlement:", gasUsed);
        assertLt(gasUsed, 150_000, "Order settlement should use less than 150k gas");
    }

    /// @notice Test gas cost of complete order lifecycle
    function testGas_CompleteOrderLifecycle() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);

        uint256 gasStart = gasleft();

        // Create order
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");

        // Pay order
        paymentProcessor.payOrder(orderId);
        vm.stopPrank();

        // Settle order
        vm.prank(merchant1);
        paymentProcessor.settleOrder(orderId);

        uint256 totalGasUsed = gasStart - gasleft();

        console.log("Gas used for complete order lifecycle:", totalGasUsed);
        assertLt(totalGasUsed, 500_000, "Complete order lifecycle should use less than 500k gas");
    }

    // ============================================
    // REFUND GAS TESTS
    // ============================================

    /// @notice Test gas cost of order refund
    function testGas_OrderRefund() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        paymentProcessor.payOrder(orderId);
        vm.stopPrank();

        uint256 gasBefore = gasleft();
        vm.prank(merchant1);
        paymentProcessor.refundOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for order refund:", gasUsed);
        assertLt(gasUsed, 150_000, "Order refund should use less than 150k gas");
    }

    /// @notice Test gas cost of order cancellation
    function testGas_OrderCancellation() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        bytes32 orderId = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");

        uint256 gasBefore = gasleft();
        paymentProcessor.cancelOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console.log("Gas used for order cancellation:", gasUsed);
        assertLt(gasUsed, 100_000, "Order cancellation should use less than 100k gas");
    }

    // ============================================
    // BATCH OPERATIONS GAS TESTS
    // ============================================

    /// @notice Compare gas cost of multiple individual order creations vs batch
    function testGas_MultipleOrdersIndividual() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 10000e18);

        uint256 gasStart = gasleft();

        for (uint256 i = 0; i < 10; i++) {
            paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        }

        uint256 totalGasUsed = gasStart - gasleft();
        vm.stopPrank();

        console.log("Gas used for 10 individual order creations:", totalGasUsed);
        console.log("Average gas per order:", totalGasUsed / 10);
    }

    /// @notice Test gas efficiency of multiple order settlements
    function testGas_MultipleOrderSettlements() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);
        bytes32[] memory orderIds = new bytes32[](10);

        // Create and pay 10 orders
        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 10000e18);
        for (uint256 i = 0; i < 10; i++) {
            orderIds[i] = paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
            paymentProcessor.payOrder(orderIds[i]);
        }
        vm.stopPrank();

        // Measure gas for settling all orders
        uint256 gasStart = gasleft();
        vm.startPrank(merchant1);
        for (uint256 i = 0; i < 10; i++) {
            paymentProcessor.settleOrder(orderIds[i]);
        }
        vm.stopPrank();
        uint256 totalGasUsed = gasStart - gasleft();

        console.log("Gas used for 10 order settlements:", totalGasUsed);
        console.log("Average gas per settlement:", totalGasUsed / 10);
    }

    // ============================================
    // TOKEN SUPPORT GAS TESTS
    // ============================================

    /// @notice Test gas cost of enabling token support
    function testGas_EnableTokenSupport() public {
        ERC20Mock newToken = new ERC20Mock("New Token", "NEW", address(this), INITIAL_TOKEN_SUPPLY);

        uint256 gasBefore = gasleft();
        vm.prank(owner);
        paymentProcessor.setTokenSupport(address(newToken), 1);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for enabling token support:", gasUsed);
        assertLt(gasUsed, 100_000, "Enabling token support should use less than 100k gas");
    }

    /// @notice Test gas cost of disabling token support
    function testGas_DisableTokenSupport() public {
        uint256 gasBefore = gasleft();
        vm.prank(owner);
        paymentProcessor.setTokenSupport(address(usdcToken), 0);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for disabling token support:", gasUsed);
        assertLt(gasUsed, 100_000, "Disabling token support should use less than 100k gas");
    }

    // ============================================
    // COMPARATIVE GAS ANALYSIS
    // ============================================

    /// @notice Compare gas costs across different order amounts
    function testGas_OrderAmountComparison() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 100e18; // Small order
        amounts[1] = 1000e18; // Medium order
        amounts[2] = 10000e18; // Large order
        amounts[3] = 50000e18; // Very large order
        amounts[4] = 1e18; // Tiny order

        console.log("\n=== Gas Cost by Order Amount ===");

        for (uint256 i = 0; i < amounts.length; i++) {
            vm.startPrank(customer1);
            usdcToken.approve(address(paymentProcessor), amounts[i]);

            uint256 gasBefore = gasleft();
            paymentProcessor.createOrder(merchantId, address(usdcToken), amounts[i], "ipfs://order");
            uint256 gasUsed = gasBefore - gasleft();

            vm.stopPrank();

            console.log("Amount:", amounts[i] / 1e18, "tokens - Gas used:", gasUsed);
        }
    }

    /// @notice Compare gas costs across different tokens
    function testGas_DifferentTokensComparison() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        console.log("\n=== Gas Cost by Token Type ===");

        // USDC
        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 1000e18);
        uint256 gasUsdc = gasleft();
        paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order");
        gasUsdc = gasUsdc - gasleft();
        vm.stopPrank();

        // USDT
        vm.startPrank(customer1);
        usdtToken.approve(address(paymentProcessor), 1000e18);
        uint256 gasUsdt = gasleft();
        paymentProcessor.createOrder(merchantId, address(usdtToken), 1000e18, "ipfs://order");
        gasUsdt = gasUsdt - gasleft();
        vm.stopPrank();

        console.log("USDC order creation gas:", gasUsdc);
        console.log("USDT order creation gas:", gasUsdt);
    }

    /// @notice Compare first order vs subsequent orders (COLD vs WARM storage)
    function testGas_ColdVsWarmStorage() public {
        bytes32 merchantId = _registerAndVerifyMerchant(merchant1);

        console.log("\n=== Cold vs Warm Storage Access ===");

        // First order (COLD storage)
        vm.startPrank(customer1);
        usdcToken.approve(address(paymentProcessor), 10000e18);

        uint256 gasCold = gasleft();
        paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order1");
        gasCold = gasCold - gasleft();

        // Second order (WARM storage)
        uint256 gasWarm = gasleft();
        paymentProcessor.createOrder(merchantId, address(usdcToken), 1000e18, "ipfs://order2");
        gasWarm = gasWarm - gasleft();

        vm.stopPrank();

        console.log("First order (cold storage):", gasCold);
        console.log("Second order (warm storage):", gasWarm);
        console.log("Gas savings:", gasCold - gasWarm);

        assertGt(gasCold, gasWarm, "Cold storage should cost more than warm storage");
    }

    // ============================================
    // ADMIN OPERATIONS GAS TESTS
    // ============================================

    /// @notice Test gas cost of pausing contract
    function testGas_PauseContract() public {
        uint256 gasBefore = gasleft();
        vm.prank(owner);
        paymentProcessor.pause();
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for pausing contract:", gasUsed);
        assertLt(gasUsed, 50_000, "Pausing should use less than 50k gas");
    }

    /// @notice Test gas cost of unpausing contract
    function testGas_UnpauseContract() public {
        vm.prank(owner);
        paymentProcessor.pause();

        uint256 gasBefore = gasleft();
        vm.prank(owner);
        paymentProcessor.unpause();
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for unpausing contract:", gasUsed);
        assertLt(gasUsed, 50_000, "Unpausing should use less than 50k gas");
    }

    /// @notice Test gas cost of updating platform wallet
    function testGas_UpdatePlatformWallet() public {
        address newWallet = makeAddr("newPlatformWallet");

        uint256 gasBefore = gasleft();
        vm.prank(owner);
        paymentProcessor.updateProtocolAddress("platform", newWallet);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for updating platform wallet:", gasUsed);
        assertLt(gasUsed, 100_000, "Updating platform wallet should use less than 100k gas");
    }

    /// @notice Test gas cost of updating merchant registry
    function testGas_UpdateMerchantRegistry() public {
        // Deploy new registry with owner
        MerchantRegistry newMerchantImpl = new MerchantRegistry();
        bytes memory newInitData = abi.encodeCall(MerchantRegistry.initialize, (owner));
        MerchantRegistry newRegistry =
            MerchantRegistry(address(new ERC1967Proxy(address(newMerchantImpl), newInitData)));

        uint256 gasBefore = gasleft();
        vm.prank(owner);
        paymentProcessor.updateMerchantRegistry(address(newRegistry));
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for updating merchant registry:", gasUsed);
        assertLt(gasUsed, 100_000, "Updating merchant registry should use less than 100k gas");
    }
}
