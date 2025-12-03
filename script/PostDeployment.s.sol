// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PaymentProcessor} from "../src/contracts/PaymentProcessor.sol";
import {NetworkConfig} from "./NetworkConfig.s.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract PostDeployment is Script {
    using stdJson for string;

    NetworkConfig public networkConfig;

    function setUp() public {
        networkConfig = new NetworkConfig();
    }

    function run() external {
        NetworkConfig.NetworkInfo memory config = networkConfig.getCurrentNetworkConfig();
        
        // Load deployment addresses
        string memory deploymentFile = string(
            abi.encodePacked("./deployments/", config.name, "/deployment.json")
        );
        string memory json = vm.readFile(deploymentFile);
        
        address paymentProcessor = json.readAddress(".paymentProcessor");
        
        console2.log("=== Post-Deployment Configuration ===");
        console2.log("Network:", config.name);
        console2.log("PaymentProcessor:", paymentProcessor);

        vm.startBroadcast(config.deployerKey);

        // 1. Set supported tokens
        _setSupportedTokens(paymentProcessor, config);

        // 2. Set token fee settings
        _setTokenFeeSettings(paymentProcessor, config);

        // 3. Update protocol addresses (if needed)
        _updateProtocolAddresses(paymentProcessor);

        vm.stopBroadcast();

        console2.log("=== Post-Deployment Configuration Complete ===");
    }

    function _setSupportedTokens(
        address paymentProcessor,
        NetworkConfig.NetworkInfo memory config
    ) internal {
        console2.log("Setting supported tokens...");
        
        PaymentProcessor processor = PaymentProcessor(paymentProcessor);
        
        if (config.usdc != address(0)) {
            processor.setTokenSupport(config.usdc, 1);
            console2.log("USDC supported:", config.usdc);
        }
        
        if (config.usdt != address(0)) {
            processor.setTokenSupport(config.usdt, 1);
            console2.log("USDT supported:", config.usdt);
        }
        
        if (config.cusd != address(0)) {
            processor.setTokenSupport(config.cusd, 1);
            console2.log("cUSD supported:", config.cusd);
        }
    }

    function _setTokenFeeSettings(
        address paymentProcessor,
        NetworkConfig.NetworkInfo memory config
    ) internal {
        console2.log("Setting token fee settings...");
        
        PaymentProcessor processor = PaymentProcessor(paymentProcessor);
        uint256 defaultFeeBps = vm.envUint("DEFAULT_PLATFORM_FEE_BPS");
        
        if (config.usdc != address(0)) {
            processor.setTokenFeeSettings(config.usdc, defaultFeeBps);
        }
        
        if (config.usdt != address(0)) {
            processor.setTokenFeeSettings(config.usdt, defaultFeeBps);
        }
        
        if (config.cusd != address(0)) {
            // Lower fees for cUSD to encourage adoption
            processor.setTokenFeeSettings(config.cusd, defaultFeeBps / 2);
        }
    }

    function _updateProtocolAddresses(address paymentProcessor) internal {
        console2.log("Updating protocol addresses...");
        
        PaymentProcessor processor = PaymentProcessor(paymentProcessor);
        address platformWallet = vm.envAddress("PLATFORM_WALLET");
        
        processor.updateProtocolAddress("platform", platformWallet);
        console2.log("Platform wallet updated:", platformWallet);
    }
}