// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PaymentProcessor} from "../../src/contracts/PaymentProcessor.sol";
import {NetworkConfig} from "../NetworkConfig.s.sol";
import {TokenConfig} from "../TokenConfig.s.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract SetTokenFeeSettings is Script {
    using stdJson for string;

    function run() external {
        NetworkConfig networkConfig = new NetworkConfig();
        TokenConfig tokenConfig = new TokenConfig();
        NetworkConfig.NetworkInfo memory config = networkConfig.getCurrentNetworkConfig();
        
        // Load deployment addresses
        string memory deploymentFile = string(
            abi.encodePacked("./deployments/", config.name, "/deployment.json")
        );
        string memory json = vm.readFile(deploymentFile);
        address paymentProcessor = json.readAddress(".paymentProcessor");
        
        vm.startBroadcast(config.deployerKey);
        
        _setTokenFeeSettings(paymentProcessor, config, tokenConfig);
        
        vm.stopBroadcast();
        
        console2.log("Token fee settings configuration completed");
    }

    function _setTokenFeeSettings(
        address paymentProcessor,
        NetworkConfig.NetworkInfo memory config,
        TokenConfig tokenConfig
    ) internal {
        PaymentProcessor processor = PaymentProcessor(paymentProcessor);
        
        if (config.usdc != address(0)) {
            TokenConfig.TokenInfo memory usdcInfo = tokenConfig.getTokenInfo(config.chainId, "USDC");
            processor.setTokenFeeSettings(config.usdc, usdcInfo.platformFeeBps);
            console2.log("USDC fee set to:", usdcInfo.platformFeeBps, "bps");
        }
        
        if (config.usdt != address(0)) {
            TokenConfig.TokenInfo memory usdtInfo = tokenConfig.getTokenInfo(config.chainId, "USDT");
            processor.setTokenFeeSettings(config.usdt, usdtInfo.platformFeeBps);
            console2.log("USDT fee set to:", usdtInfo.platformFeeBps, "bps");
        }
        
        if (config.cusd != address(0)) {
            TokenConfig.TokenInfo memory cusdInfo = tokenConfig.getTokenInfo(config.chainId, "cUSD");
            processor.setTokenFeeSettings(config.cusd, cusdInfo.platformFeeBps);
            console2.log("cUSD fee set to:", cusdInfo.platformFeeBps, "bps");
        }
    }
}