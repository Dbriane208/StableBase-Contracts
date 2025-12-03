// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

contract TokenConfig is Script {
    struct TokenInfo {
        address tokenAddress;
        string symbol;
        uint8 decimals;
        uint256 platformFeeBps;
        bool isStablecoin;
    }

    mapping(uint256 => mapping(string => TokenInfo)) public tokenConfigs;

    constructor() {
        _setupTokenConfigs();
    }

    function _setupTokenConfigs() internal {
        // Ethereum Mainnet Tokens
        tokenConfigs[1]["USDC"] = TokenInfo({
            tokenAddress: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            symbol: "USDC",
            decimals: 6,
            platformFeeBps: 2000, // 2%
            isStablecoin: true
        });

        tokenConfigs[1]["USDT"] = TokenInfo({
            tokenAddress: 0xdAC17F958D2ee523a2206206994597C13D831ec7,
            symbol: "USDT",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });

        // Polygon Tokens
        tokenConfigs[137]["USDC"] = TokenInfo({
            tokenAddress: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359,
            symbol: "USDC",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });

        tokenConfigs[137]["USDT"] = TokenInfo({
            tokenAddress: 0xc2132D05D31c914a87C6611C10748AEb04B58e8F,
            symbol: "USDT",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });

        // Celo Tokens
        tokenConfigs[42220]["USDC"] = TokenInfo({
            tokenAddress: 0xcebA9300f2b948710d2653dD7B07f33A8B32118C,
            symbol: "USDC",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });

        tokenConfigs[42220]["USDT"] = TokenInfo({
            tokenAddress: 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e,
            symbol: "USDT",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });

        tokenConfigs[42220]["cUSD"] = TokenInfo({
            tokenAddress: 0x765DE816845861e75A25fCA122bb6898B8B1282a,
            symbol: "cUSD",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });

        // Optimisim Tokens
        tokenConfigs[10]["USDC"] = TokenInfo({
            tokenAddress: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
            symbol: "USDC",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });

        tokenConfigs[10]["USDT"] = TokenInfo({
            tokenAddress: 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58,
            symbol: "USDT",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });

        // Base Token
        tokenConfigs[8453]["USDC"] = TokenInfo({
            tokenAddress: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            symbol: "USDC",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });

        // Lisk Token
        tokenConfigs[1135]["USDT"] = TokenInfo({
            tokenAddress: 0x05D032ac25d322df992303dCa074EE7392C117b9,
            symbol: "USDT",
            decimals: 6,
            platformFeeBps: 2000,
            isStablecoin: true
        });
    }

    function getTokenInfo(uint256 chainId,string memory symbol) external view returns (TokenInfo memory) {
        return tokenConfigs[chainId][symbol];
    }

    // Implement function to getAllTokensForChain
    function getAllTokensForChain(uint256 chainId) external view returns (TokenInfo[] memory) {
        // Count tokens for this chain
        uint256 count = 0;
        string[] memory symbols = new string[](10); // Adjust size as needed
        
        // Define known symbols to check
        symbols[0] = "USDC";
        symbols[1] = "USDT";
        symbols[2] = "cUSD";
        
        // Count existing tokens
        for (uint256 i = 0; i < 3; i++) {
            if (tokenConfigs[chainId][symbols[i]].tokenAddress != address(0)) {
                count++;
            }
        }
        
        // Create result array
        TokenInfo[] memory tokens = new TokenInfo[](count);
        uint256 index = 0;
        
        // Populate result array
        for (uint256 i = 0; i < 3; i++) {
            if (tokenConfigs[chainId][symbols[i]].tokenAddress != address(0)) {
                tokens[index] = tokenConfigs[chainId][symbols[i]];
                index++;
            }
        }
        
        return tokens;
    }
}
