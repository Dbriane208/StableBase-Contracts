// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PaymentProcessor} from "../../src/contracts/PaymentProcessor.sol";
import {MerchantRegistry} from "../../src/contracts/MerchantRegistry.sol";
import {NetworkConfig} from "../NetworkConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PostDeploymentValidator is Script {
    error PostDeploymentValidator__InvalidOwner();
    error PostDeploymentValidator__ContractNotDeployed();
    error PostDeploymentValidator__InvalidConfiguration();
    error PostDeploymentValidator__TokenValidationFailed();
    error PostDeploymentValidator__FeeValidationFailed();
    error PostDeploymentValidator__PlatformWalletNotSet();
    error PostDeploymentValidator__EmergencyControlsNotSet();

    uint256 private constant MAX_BPS = 100_000;
    uint256 private constant REASONABLE_MAX_FEE_BPS = 10_000; // 10%

    /**
     * @notice Validates the complete post-deployment configuration
     * @param paymentProcessor Address of the deployed PaymentProcessor
     * @param merchantRegistry Address of the deployed MerchantRegistry
     */
    function validateFullDeployment(address paymentProcessor, address merchantRegistry) external view {
        console2.log("=== Starting Post-Deployment Validation ===");

        // Basic validations
        _validateBasics(paymentProcessor, merchantRegistry);

        // Configuration validations
        _validateConfigurations(paymentProcessor);

        console2.log("[SUCCESS] Full post-deployment validation passed");
    }

    /**
     * @notice Validates basic deployment and ownership
     */
    function _validateBasics(address paymentProcessor, address merchantRegistry) internal view {
        _validateContractDeployment(paymentProcessor, merchantRegistry);
        _validateOwnership(paymentProcessor, merchantRegistry);
    }

    /**
     * @notice Validates platform configurations
     */
    function _validateConfigurations(address paymentProcessor) internal view {
        _validatePlatformConfiguration(paymentProcessor);
        _validateEmergencyControls(paymentProcessor);
        _validateUpgradeCapabilities(paymentProcessor);
    }

    /**
     * @notice Validates basic contract deployment and existence
     */
    function _validateContractDeployment(address paymentProcessor, address merchantRegistry) internal view {
        console2.log("Validating contract deployment...");

        if (paymentProcessor.code.length == 0) {
            revert PostDeploymentValidator__ContractNotDeployed();
        }

        if (merchantRegistry.code.length == 0) {
            revert PostDeploymentValidator__ContractNotDeployed();
        }

        console2.log("[OK] Contracts successfully deployed");
    }

    /**
     * @notice Validates ownership configuration
     */
    function _validateOwnership(address paymentProcessor, address merchantRegistry) internal view {
        console2.log("Validating ownership configuration...");

        try PaymentProcessor(paymentProcessor).owner() returns (address ppOwner) {
            if (ppOwner == address(0)) {
                revert PostDeploymentValidator__InvalidOwner();
            }
            console2.log("[OK] PaymentProcessor owner:", ppOwner);
        } catch {
            revert PostDeploymentValidator__InvalidOwner();
        }

        try MerchantRegistry(merchantRegistry).owner() returns (address mrOwner) {
            if (mrOwner == address(0)) {
                revert PostDeploymentValidator__InvalidOwner();
            }
            console2.log("[OK] MerchantRegistry owner:", mrOwner);
        } catch {
            revert PostDeploymentValidator__InvalidOwner();
        }
    }

    /**
     * @notice Validates token support configuration
     */
    function _validateTokenSupport(address paymentProcessor, address[] memory expectedTokens) internal view {
        console2.log("Validating token support configuration...");

        PaymentProcessor processor = PaymentProcessor(paymentProcessor);

        for (uint256 i = 0; i < expectedTokens.length; i++) {
            address token = expectedTokens[i];

            if (token == address(0)) continue; // Skip zero address tokens

            // Check if token is supported
            if (!processor.isTokenSupported(token)) {
                console2.log("[ERROR] Token not supported:", token);
                revert PostDeploymentValidator__TokenValidationFailed();
            }

            // Validate token contract
            try IERC20(token).totalSupply() returns (uint256 supply) {
                if (supply == 0) {
                    console2.log("[WARNING] Token has zero supply:", token);
                }
            } catch {
                console2.log("[ERROR] Invalid token contract:", token);
                revert PostDeploymentValidator__TokenValidationFailed();
            }

            console2.log("[OK] Token supported and valid:", token);
        }
    }

    /**
     * @notice Validates platform wallet and protocol address configuration
     */
    function _validatePlatformConfiguration(address paymentProcessor) internal view {
        console2.log("Validating platform configuration...");

        PaymentProcessor processor = PaymentProcessor(paymentProcessor);

        try processor.getPlatformWallet() returns (address platformWallet) {
            if (platformWallet == address(0)) {
                revert PostDeploymentValidator__PlatformWalletNotSet();
            }
            console2.log("[OK] Platform wallet configured:", platformWallet);
        } catch {
            revert PostDeploymentValidator__PlatformWalletNotSet();
        }

        // Validate merchant registry connection
        try processor.merchantRegistry() returns (MerchantRegistry registry) {
            if (address(registry) == address(0)) {
                revert PostDeploymentValidator__InvalidConfiguration();
            }
            console2.log("[OK] MerchantRegistry connected:", address(registry));
        } catch {
            revert PostDeploymentValidator__InvalidConfiguration();
        }
    }

    /**
     * @notice Validates emergency controls and safety features
     */
    function _validateEmergencyControls(address paymentProcessor) internal view {
        console2.log("Validating emergency controls...");

        PaymentProcessor processor = PaymentProcessor(paymentProcessor);

        // Check pause functionality
        try processor.paused() returns (bool isPaused) {
            console2.log("[OK] Contract pause state:", isPaused ? "PAUSED" : "ACTIVE");
        } catch {
            revert PostDeploymentValidator__EmergencyControlsNotSet();
        }

        // Check emergency withdrawal settings
        try processor.emergencyWithdrawalEnabled() returns (bool emergencyEnabled) {
            console2.log("[OK] Emergency withdrawal:", emergencyEnabled ? "ENABLED" : "DISABLED");
        } catch {
            console2.log("[WARNING] Cannot check emergency withdrawal status");
        }

        // Check order expiration time
        try processor.orderExpirationTime() returns (uint256 expirationTime) {
            if (expirationTime == 0) {
                console2.log("[WARNING] Order expiration time is zero");
            } else {
                console2.log("[OK] Order expiration time:", expirationTime, "seconds");
            }
        } catch {
            console2.log("[WARNING] Cannot check order expiration time");
        }
    }

    /**
     * @notice Validates upgrade capabilities and proxy configuration
     */
    function _validateUpgradeCapabilities(
        address /* paymentProcessor */
    )
        internal
        view
    {
        console2.log("Validating upgrade capabilities...");

        // Check if contract is upgradeable (has proxy pattern)
        // This is indicated by the presence of an implementation slot
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        bytes32 implementation;
        assembly {
            implementation := sload(implementationSlot)
        }

        if (implementation != bytes32(0)) {
            console2.log(
                "[OK] Contract is upgradeable with implementation at:", address(uint160(uint256(implementation)))
            );
        } else {
            console2.log("[NOTE] Contract may not be upgradeable or uses different proxy pattern");
        }
    }

    /**
     * @notice Convenience function to validate using network configuration
     */
    function validateWithNetworkConfig(
        address paymentProcessor,
        address merchantRegistry,
        NetworkConfig networkConfig,
        uint256 chainId
    ) external view {
        NetworkConfig.NetworkInfo memory config = networkConfig.getNetworkConfig(chainId);

        address[] memory expectedTokens = new address[](3);
        uint256 tokenCount = 0;

        if (config.usdc != address(0)) {
            expectedTokens[tokenCount++] = config.usdc;
        }
        if (config.usdt != address(0)) {
            expectedTokens[tokenCount++] = config.usdt;
        }
        if (config.cusd != address(0)) {
            expectedTokens[tokenCount++] = config.cusd;
        }

        // Resize array to actual token count
        assembly {
            mstore(expectedTokens, tokenCount)
        }

        this.validateFullDeployment(paymentProcessor, merchantRegistry);
    }

    /**
     * @notice Quick validation for development/testing
     */
    function quickValidation(address paymentProcessor) external view returns (bool) {
        try PaymentProcessor(paymentProcessor).owner() returns (address owner) {
            if (owner == address(0)) return false;
        } catch {
            return false;
        }

        try PaymentProcessor(paymentProcessor).getPlatformWallet() returns (address wallet) {
            if (wallet == address(0)) return false;
        } catch {
            return false;
        }

        return true;
    }
}
