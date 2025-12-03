// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PaymentProcessor} from "../../src/contracts/PaymentProcessor.sol";
import {MerchantRegistry} from "../../src/contracts/MerchantRegistry.sol";
import {TokensManager} from "../../src/contracts/TokensManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeploymentValidator is Script {
    error DeploymentValidator__InvalidOwner();
    error DeploymentValidator__ContractNotDeployed();
    error DeploymentValidator__InvalidDefaultPlatformFee();
    error DeploymentValidator__InterfaceValidationFailed();
    error DeploymentValidator__TokenNotSupported();
    error DeploymentValidator__InvalidFeeSettings();
    error DeploymentValidator__InvalidTokenContract();

    uint256 private constant MAX_BPS = 100_000;

    function validateDeployment(address paymentProcessor, address merchantRegistry) external view returns (bool) {
        console2.log("Validating deployment...");

        /**
         * @dev Basic contract existence checks
         */
        if (paymentProcessor.code.length == 0 || merchantRegistry.code.length == 0) {
            revert DeploymentValidator__ContractNotDeployed();
        }

        /**
         * @dev Interface compliance checks
         */
        if (!_validatePaymentProcessor(paymentProcessor) || !_validateMerchantRegistry(merchantRegistry)) {
            revert DeploymentValidator__InterfaceValidationFailed();
        }
        
        return true;
    }

    function _validatePaymentProcessor(address processor) internal view returns (bool) {
        try PaymentProcessor(processor).owner() returns (address owner) {
            if (owner == address(0)) {
                revert DeploymentValidator__InvalidOwner();
            }
        } catch {
            return false;
        }

        try PaymentProcessor(processor).defaultPlatformFeeBps() returns (uint256 fee) {
            if (fee >= MAX_BPS) {
                revert DeploymentValidator__InvalidDefaultPlatformFee();
            }
        } catch {
            return false;
        }

        return true;
    }

    function _validateMerchantRegistry(address registry) internal view returns (bool) {
        try MerchantRegistry(registry).owner() returns (address owner) {
            if (owner == address(0)) {
                revert DeploymentValidator__InvalidOwner();
            }
        } catch {
            return false;
        }

        return true;
    }

    function validateTokenConfiguration(address paymentProcessor, address[] memory tokens)
        external
        view
        returns (bool)
    {
        PaymentProcessor processor = PaymentProcessor(paymentProcessor);

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            // Check if token is supported
            if (!processor.isTokenSupported(token)) {
                revert DeploymentValidator__TokenNotSupported();
            }

            // Check if token has fee settings
            TokensManager.TokenFeeSettings memory feeSettings = processor.getTokenFeeSettings(token);
            if (feeSettings.platformFeeBps == 0 && feeSettings.platformFeeBps >= MAX_BPS) {
                revert DeploymentValidator__InvalidFeeSettings();
            }

            // Check if token contract is valid
            try IERC20(token).totalSupply() returns (
                uint256
            ) {
            //Token contract is valid
            }
            catch {
                revert DeploymentValidator__InvalidTokenContract();
            }
        }

        return true;
    }
}
