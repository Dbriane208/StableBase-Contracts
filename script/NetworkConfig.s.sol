// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

contract NetworkConfig is Script {
    error NetworkConfig__NetworkNotConfigured();

    struct NetworkInfo {
        uint256 chainId;
        string name;
        address usdc;
        address usdt;
        address cusd;
        uint256 deployerKey;
        string rpcUrl;
        string exploreUrl;
        bool isTestnet;
    }

    mapping(uint256 => NetworkInfo) public networks;

    constructor() {
        _setupNetworks();
    }

    function _setupNetworks() internal {
        // Ethereum Mainnet
        networks[1] = NetworkInfo({
            chainId: 1,
            name: "ethereum",
            usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            usdt: 0xdAC17F958D2ee523a2206206994597C13D831ec7,
            cusd: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("ETHEREUM_RPC_URL"),
            exploreUrl: "https://etherscan.io/",
            isTestnet: false
        });

        // Polygon Mainnet
        networks[137] = NetworkInfo({
            chainId: 137,
            name: "polygon",
            usdc: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359,
            usdt: 0xc2132D05D31c914a87C6611C10748AEb04B58e8F,
            cusd: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("POLYGON_RPC_URL"),
            exploreUrl: "https://polygonscan.com/",
            isTestnet: false
        });

        // Arbitrum One
        networks[42161] = NetworkInfo({
            chainId: 42161,
            name: "arbitrum",
            usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            usdt: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
            cusd: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("ARBITRUM_RPC_URL"),
            exploreUrl: "https://arbiscan.io/",
            isTestnet: false
        });

        // Base Mainnet
        networks[8453] = NetworkInfo({
            chainId: 8453,
            name: "base",
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            usdt: address(0),
            cusd: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("BASE_RPC_URL"),
            exploreUrl: "https://basescan.org/",
            isTestnet: false
        });

        // Celo Mainnet
        networks[42220] = NetworkInfo({
            chainId: 42220,
            name: "celo",
            usdc: 0xcebA9300f2b948710d2653dD7B07f33A8B32118C,
            usdt: 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e,
            cusd: 0x765DE816845861e75A25fCA122bb6898B8B1282a,
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("CELO_RPC_URL"),
            exploreUrl: "https://celoscan.io/",
            isTestnet: false
        });

        // Optimism Mainnet
        networks[10] = NetworkInfo({
            chainId: 10,
            name: "optimism",
            usdc: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
            usdt: 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58,
            cusd: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("OPTIMISM_RPC_URL"),
            exploreUrl: "https://optimistic.etherscan.io/",
            isTestnet: false
        });

        // Lisk Mainnet
        networks[1135] = NetworkInfo({
            chainId: 10,
            name: "lisk",
            usdc: address(0),
            usdt: 0x05D032ac25d322df992303dCa074EE7392C117b9,
            cusd: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("OPTIMISM_RPC_URL"),
            exploreUrl: "https://blockscout.lisk.com/",
            isTestnet: false
        });

        // Testnet configurations
        _setupTestnets();
    }

    function _setupTestnets() internal {
        // Polygon Amoy
        networks[80002] = NetworkInfo({
            chainId: 80002,
            name: "polygon amoy",
            usdc: 0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582,
            usdt: address(0),
            cusd: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("POLYGON_AMOY_RPC_URL"),
            exploreUrl: "https://polygonscan.com/",
            isTestnet: true
        });

        // Arbitrum Sepolia
        networks[421614] = NetworkInfo({
            chainId: 421614,
            name: "arbitrum sepolia",
            usdc: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d,
            usdt: address(0),
            cusd: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("ARBITRUM_SEPOLIA_RPC_URL"),
            exploreUrl: "https://arbiscan.io/",
            isTestnet: true
        });

        // Base Sepolia
        networks[84532] = NetworkInfo({
            chainId: 84532,
            name: "base sepolia",
            usdc: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            usdt: address(0),
            cusd: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY"),
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL"),
            exploreUrl: "https://basescan.org/",
            isTestnet: true
        });
    }

    function getNetworkConfig(uint256 chainId) public view returns (NetworkInfo memory) {
        if (networks[chainId].chainId == 0) {
            revert NetworkConfig__NetworkNotConfigured();
        }
        return networks[chainId];
    }

    function getCurrentNetworkConfig() external view returns (NetworkInfo memory) {
        return getNetworkConfig(block.chainid);
    }

    function getSupportedTokens(uint256 chainId) external view returns (address[] memory) {
        NetworkInfo memory network = getNetworkConfig(chainId);
        address[] memory tokens = new address[](3);
        uint256 count = 0;

        if (network.usdc != address(0)) {
            tokens[count++] == network.usdc;
        }

        if (network.usdt != address(0)) {
            tokens[count++] == network.usdt;
        }

        if (network.cusd != address(0)) {
            tokens[count++] == network.cusd;
        }

        // Resize array to actual count
        assembly {
            mstore(tokens, count)
        }

        return tokens;
    }
}
