// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {PaymentProcessor} from "../src/contracts/PaymentProcessor.sol";
import {MerchantRegistry} from "../src/contracts/MerchantRegistry.sol";
import {NetworkConfig} from "./NetworkConfig.s.sol";
import {DeploymentValidator} from "./utils/DeploymentValidator.s.sol";

contract Deploy is Script {
    error Deploy__DeploymentValidationFailed();

    struct DeploymentResult {
        address paymentProcessor;
        address merchantRegistry;
        address paymentProcessorImpl;
        address merchantRegistryImpl;
        uint256 chainId;
        string networkName;
    }

    NetworkConfig public networkConfig;
    DeploymentValidator public validator;

    function setUp() public {
        networkConfig = new NetworkConfig();
        validator = new DeploymentValidator();
    }

    function run() external returns (DeploymentResult memory) {
        NetworkConfig.NetworkInfo memory config = networkConfig.getCurrentNetworkConfig();

        console2.log("==== StableBase Deployment ===");
        console2.log("Network: ", config.name);
        console2.log("Chain ID: ", config.chainId);
        console2.log("Platform Wallet: ", vm.envAddress("PLATFORM_WALLET"));
        console2.log("Initial Owner: ", vm.envAddress("INITIAL_OWNER"));

        // Confirm deployment
        vm.startBroadcast(config.deployerKey);
        DeploymentResult memory result = _deployContracts(config);
        vm.stopBroadcast();

        // Validate deployment
        bool isValid = validator.validateDeployment(result.paymentProcessor, result.merchantRegistry);
        if (!isValid) {
            revert Deploy__DeploymentValidationFailed();
        }

        // Save deployment addresses
        _saveDeploymentData(result);

        console2.log("=== Deployment Successful ===");
        console2.log("PaymentProcessor Proxy: ", result.paymentProcessor);
        console2.log("MerchantRegistry Proxy: ", result.merchantRegistry);
        console2.log("PaymentProcessor Implementation: ", result.paymentProcessorImpl);
        console2.log("MerchantRegistry Implementation: ", result.merchantRegistryImpl);

        return result;
    }

    function _deployContracts(NetworkConfig.NetworkInfo memory config)
        internal
        returns (DeploymentResult memory result)
    {
        address platformWallet = vm.envAddress("PLATFORM_WALLET");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        uint256 defaultPlatformFeeBps = vm.envUint("DEFAULT_PLATFORM_FEE_BPS");
        uint256 orderExpirationTime = vm.envUint("ORDER_EXPIRATION_TIME");

        // Deploy MerchantRegistry
        console2.log("Deploying MerchantRegistry...");
        Options memory opts;
        opts.unsafeAllow = "constructor,missing-public-upgradeto";
        address merchantRegistryProxy =
            Upgrades.deployUUPSProxy("MerchantRegistry.sol", abi.encodeCall(MerchantRegistry.initialize, (initialOwner)), opts);

        // Deploy PaymentProcessor
        console2.log("Deploying PaymentProcessor...");
        address paymentProcessorProxy = Upgrades.deployUUPSProxy(
            "PaymentProcessor.sol",
            abi.encodeCall(
                PaymentProcessor.initialize,
                (platformWallet, defaultPlatformFeeBps, merchantRegistryProxy, orderExpirationTime, initialOwner)
            ),
            opts
        );

        // Note: Ownership is now set during initialization, no need to transfer separately
        if (initialOwner != msg.sender) {
            console2.log("Ownership set to: ", initialOwner);
        }

        result = DeploymentResult({
            paymentProcessor: paymentProcessorProxy,
            merchantRegistry: merchantRegistryProxy,
            paymentProcessorImpl: Upgrades.getImplementationAddress(paymentProcessorProxy),
            merchantRegistryImpl: Upgrades.getImplementationAddress(merchantRegistryProxy),
            chainId: config.chainId,
            networkName: config.name
        });
    }

    function _saveDeploymentData(DeploymentResult memory result) internal {
        string memory deploymentData = string(
            abi.encodePacked(
                "{\n",
                '  "chainId": ',
                vm.toString(result.chainId),
                ",\n",
                '  "networkName": "',
                result.networkName,
                '",\n',
                '  "paymentProcessor": "',
                vm.toString(result.paymentProcessor),
                '",\n',
                '  "merchantRegistry": "',
                vm.toString(result.merchantRegistry),
                '",\n',
                '  "paymentProcessorImpl": "',
                vm.toString(result.paymentProcessorImpl),
                '",\n',
                '  "merchantRegistryImpl": "',
                vm.toString(result.merchantRegistryImpl),
                '",\n',
                '  "deployedAt": ',
                vm.toString(block.timestamp),
                "\n",
                "}"
            )
        );

        string memory fileName = string(abi.encodePacked("./deployments/", result.networkName, "/deployment.json"));
        vm.writeFile(fileName, deploymentData);
    }
}
