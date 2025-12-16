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

    event TokenSupportUpdated(bytes32 indexed token, bool supported);
    event ProtocolAddressUpdated(bytes32 indexed what, address indexed platformWallet);

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
     * @dev Checks if a token is supported by the platform
     * @param token The address of the token to check
     * @return bool True if the token is supported, false otherwise
     */

    function isTokenSupported(address token) public view virtual returns (bool) {
        return _isTokenSupported[token] == 1;
    }

    /**
     * @dev Returns the address of the platform wallet that receives fees
     * @return address The platform wallet address
     */

    function getPlatformWallet() public view returns (address) {
        return platformWallet;
    }
}
