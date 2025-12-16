// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PaymentProcessor} from "../../src/contracts/PaymentProcessor.sol";
import {MerchantRegistry} from "../../src/contracts/MerchantRegistry.sol";
import {NetworkConfig} from "../NetworkConfig.s.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract EmergencyPause is Script {
    error EmergencyPause__PauseCanCelled();
    using stdJson for string;

    function run() external {
        NetworkConfig networkConfig = new NetworkConfig();
        NetworkConfig.NetworkInfo memory config = networkConfig.getCurrentNetworkConfig();

        // Load deployment addresses
        string memory deploymentFile = string(abi.encodePacked("./deployments/", config.name, "/deployment.json"));
        string memory json = vm.readFile(deploymentFile);

        address paymentProcessor = json.readAddress(".paymentProcessor");
        address merchantRegistry = json.readAddress(".merchantRegistry");

        console2.log("=== EMERGENCY PAUSE ===");
        console2.log("Network:", config.name);
        console2.log("This will pause all contract operations!");
        console2.log("Type 'CONFIRM' to proceed:");

        string memory confirmation = vm.readLine("Type 'yes' to confirm: ");
        if (keccak256(bytes(confirmation)) != keccak256(bytes("CONFIRM"))) {
            revert EmergencyPause__PauseCanCelled();
        }

        vm.startBroadcast(config.deployerKey);

        // Pause contracts
        PaymentProcessor(paymentProcessor).pause();
        MerchantRegistry(merchantRegistry).pause();

        vm.stopBroadcast();

        console2.log("=== CONTRACTS PAUSED ===");
        console2.log("All operations have been halted");
    }
}
