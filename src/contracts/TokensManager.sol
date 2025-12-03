// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract TokensManager {
    error TokensManager__ThrowZeroAddress();
    error TokensManager__InvalidStatus();
    error TokensManager__WalletAlreadySet();
    error TokensManager__TokenNotSupported();
    error TokensManager__InvalidProviderToMerchant();
    error TokensManager__InvalidBps();

    uint256 internal maxBps;
    address internal platformWallet;

    // token => bool(1 supported, 0 not)
    mapping(address => uint256) internal _isTokenSupported;
    uint256[50] private _gap;

    /**
     * @notice Token-specific fee settings  (platform fee in BPS)
     * @param platformFeeBps Portion going to platform in basis points (out of maxBps)
     */
    struct TokenFeeSettings {
        uint256 platformFeeBps;
    }

    mapping(address => TokenFeeSettings) internal _tokenFeeSettings;

    event TokenSupportUpdated(bytes32 indexed token, bool supported);
    event ProtocolAddressUpdated(bytes32 indexed what, address indexed platformWallet);
    event TokenFeeSettingsUpdated(address indexed token, uint256 platformFeeBps);

    function _tokensManagerInit(uint256 _maxBps, address _platformWallet) internal {
        maxBps = _maxBps;
        if (_platformWallet == address(0)) {
            revert TokensManager__ThrowZeroAddress();
        }
        platformWallet = _platformWallet;
    }

    /* ##################################################################
                                OWNER FUNCTIONS
    ################################################################## */
    /**
     * @notice enable/disable a token (supported stablecoin)
     */
    function _setTokenSupport(address token, uint256 status) internal {
        if (token == address(0)) {
            revert TokensManager__ThrowZeroAddress();
        }

        if (status != 0 && status != 1) {
            revert TokensManager__InvalidStatus();
        }

        _isTokenSupported[token] = status;

        emit TokenSupportUpdated(keccak256(abi.encodePacked("token", token)), status == 1);
    }

    /**
     * @notice update protocol address types (only "platform" for now)
     */
    function _updateProtocolAddress(bytes32 what, address value) internal {
        if (value == address(0)) {
            revert TokensManager__ThrowZeroAddress();
        }

        if (what == "platform") {
            if (platformWallet == value) revert TokensManager__WalletAlreadySet();
            platformWallet = value;
            emit ProtocolAddressUpdated(what, value);
        } else {
            // Reject unknown protocol address types
            revert TokensManager__InvalidStatus();
        }
    }

    /**
     * @notice set token specific fee (in BPS)
     */
    function _setTokenFeeSettings(address token, uint256 platformFeeBps) internal {
        if (_isTokenSupported[token] != 1) {
            revert TokensManager__TokenNotSupported();
        }

        if (platformFeeBps > maxBps) {
            revert TokensManager__InvalidBps();
        }

        // Ensure no overflow in fee calculations
        if (maxBps == 0) {
            revert TokensManager__InvalidBps();
        }

        _tokenFeeSettings[token] = TokenFeeSettings({platformFeeBps: platformFeeBps});

        emit TokenFeeSettingsUpdated(token, platformFeeBps);
    }

    /**
     * @dev Gets token-specific fee settings
     * @param token The token address to query
     * @return TokenFeeSettings struct containing all fee settings for the token
     */
    function getTokenFeeSettings(address token) external view returns (TokenFeeSettings memory) {
        return _tokenFeeSettings[token];
    }

    /**
     * @dev Checks if a token is supported by the platform
     * @param token The address of the token to check
     * @return bool True if the token is supported, false otherwise
     */

    function isTokenSupported(address token) public view virtual returns (bool) {
        return _isTokenSupported[token] == 1;
    }
    /**
     * @dev Returns the platform fee in basis points for a specific token
     * @param token The address of the token to get the fee for
     * @return uint256 The platform fee in basis points (1 basis point = 0.01%)
     */

    function tokenPlatformFeeBps(address token) public view returns (uint256) {
        return _tokenFeeSettings[token].platformFeeBps;
    }

    /**
     * @dev Returns the address of the platform wallet that receives fees
     * @return address The platform wallet address
     */

    function getPlatformWallet() public view returns (address) {
        return platformWallet;
    }
}
