// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {NetworkConfig} from "./NetworkConfig.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract Upgrade is Script {
    using stdJson for string;

    enum UpgradeType {
        PAYMENT_PROCESSOR,
        MERCHANT_REGISTRY,
        BOTH
    }

    function run() external {
        NetworkConfig networkConfig = new NetworkConfig();
        NetworkConfig.NetworkInfo memory config = networkConfig.getCurrentNetworkConfig();

        // Load deployment addresses
        string memory deploymentFile = string(abi.encodePacked("./deployments/", config.name, "/deployment.json"));

        string memory json = vm.readFile(deploymentFile);

        address paymentProcessorProxy = json.readAddress(".paymentProcessor");
        address merchantRegistryProxy = json.readAddress(".merchantRegistry");

        console2.log("=== Contract Upgrade ===");
        console2.log("Network:", config.name);
        console2.log("PaymentProcessor Proxy:", paymentProcessorProxy);
        console2.log("MerchantRegistry Proxy:", merchantRegistryProxy);

        // Interactive upgrade type selection
        console2.log("\nSelect upgrade type:");
        console2.log("1. PaymentProcessor only");
        console2.log("2. MerchantRegistry only");
        console2.log("3. Both contracts");

        string memory choice = vm.readLine("Enter your choice: ");
        UpgradeType upgradeType;

        if (keccak256(bytes(choice)) == keccak256(bytes("1"))) {
            upgradeType = UpgradeType.PAYMENT_PROCESSOR;
        } else if (keccak256(bytes(choice)) == keccak256(bytes("2"))) {
            upgradeType = UpgradeType.MERCHANT_REGISTRY;
        } else {
            upgradeType = UpgradeType.BOTH;
        }

        vm.startBroadcast(config.deployerKey);

        if (upgradeType == UpgradeType.PAYMENT_PROCESSOR || upgradeType == UpgradeType.BOTH) {
            _upgradePaymentProcessor(paymentProcessorProxy);
        }

        if (upgradeType == UpgradeType.MERCHANT_REGISTRY || upgradeType == UpgradeType.BOTH) {
            _upgradeMerchantRegistry(merchantRegistryProxy);
        }

        vm.stopBroadcast();

        console2.log("=== Upgrade Completed ===");
    }

    function _upgradePaymentProcessor(address proxy) internal {
        console2.log("Upgrading PaymentProcessor...");

        Upgrades.upgradeProxy(proxy, "PaymentProcessor.sol", "");

        address newImpl = Upgrades.getImplementationAddress(proxy);
        console2.log("New PaymentProcessor implementation: ", newImpl);

        // Update deployment file
        _updateDeploymentFile("paymentProcessorImpl", newImpl);
    }

    function _upgradeMerchantRegistry(address proxy) internal {
        console2.log("Upgrading MerchantRegistry...");

        Upgrades.upgradeProxy(proxy, "MerchantRegistry.sol", "");

        address newImpl = Upgrades.getImplementationAddress(proxy);
        console2.log("New MerchantRegistry implementation:", newImpl);

        // Update deployment file
        _updateDeploymentFile("merchantRegistryImpl", newImpl);
    }

    function _updateDeploymentFile(string memory key, address newAddress) internal {
        NetworkConfig networkConfig = new NetworkConfig();
        NetworkConfig.NetworkInfo memory config = networkConfig.getCurrentNetworkConfig();

        string memory deploymentFile = string(abi.encodePacked("./deployments/", config.name, "/deployment.json"));

        // Read existing deployment data
        string memory json = vm.readFile(deploymentFile);

        // Parse existing JSON and update the specific key
        string memory updatedJson = vm.serializeAddress("deployment", key, newAddress);

        // Add other existing keys to maintain the full deployment structure
        address paymentProcessor = json.readAddress(".paymentProcessor");
        address merchantRegistry = json.readAddress(".merchantRegistry");
        address paymentProcessorImpl = json.readAddress(".paymentProcessorImpl");
        address merchantRegistryImpl = json.readAddress(".merchantRegistryImpl");

        // Serialize all data back to JSON
        updatedJson = vm.serializeAddress("deployment", "paymentProcessor", paymentProcessor);
        updatedJson = vm.serializeAddress("deployment", "merchantRegistry", merchantRegistry);
        updatedJson = vm.serializeAddress(
            "deployment",
            "paymentProcessorImpl",
            keccak256(bytes(key)) == keccak256(bytes("paymentProcessorImpl")) ? newAddress : paymentProcessorImpl
        );
        updatedJson = vm.serializeAddress(
            "deployment",
            "merchantRegistryImpl",
            keccak256(bytes(key)) == keccak256(bytes("merchantRegistryImpl")) ? newAddress : merchantRegistryImpl
        );

        // Write updated JSON back to file
        vm.writeFile(deploymentFile, updatedJson);

        console2.log("Updated", key, "to:", newAddress);
    }
}
