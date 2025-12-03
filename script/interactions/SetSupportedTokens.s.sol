// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PaymentProcessor} from "../../src/contracts/PaymentProcessor.sol";
import {NetworkConfig} from "../NetworkConfig.s.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract SetSupportedTokens is Script {
    using stdJson for string;

    function run() external {
        NetworkConfig networkConfig = new NetworkConfig();
        NetworkConfig.NetworkInfo memory config = networkConfig.getCurrentNetworkConfig();

        // Loading deployment addresses
        string memory deploymentFile = string(
            abi.encodePacked("./deployments/",config.name,"/deployment.json")
        );
        string memory json = vm.readFile(deploymentFile);
        address paymentProcessor = json.readAddress(".paymentProcessor");

        vm.startBroadcast(config.deployerKey);

        _setSupportedTokens(paymentProcessor,config);

        vm.stopBroadcast();

        console2.log("Supported tokens configuration completed");
    }

    function _setSupportedTokens(address paymentProcessor,NetworkConfig.NetworkInfo memory config) internal {
        PaymentProcessor processor = PaymentProcessor(paymentProcessor);

        address[] memory tokens = new address[](3);
        uint256[] memory statuses = new uint256[](3);
        uint256 count = 0;

        if(config.usdc != address(0)){
            tokens[count] = config.usdc;
            statuses[count] = 1; // supported
            count++;
            console2.log("Adding USDC support: ", config.usdc);
        }

        if(config.usdt != address(0)){
            tokens[count] = config.usdt;
            statuses[count] = 1;
            count++;
            console2.log("Adding USDT support: ", config.usdt);
        }

        if(config.cusd != address(0)){
            tokens[count] = config.cusd;
            statuses[count] = 1;
            count++;
            console2.log("Adding cUSD support: ", config.cusd);
        }

        // Batch update token support
        for (uint256 i =0; i< count; i++) {
            processor.setTokenSupport(tokens[i], statuses[i]);
        }
    }

}