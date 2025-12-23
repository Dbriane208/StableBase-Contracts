// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TokensManager} from "../contracts/TokensManager.sol";

/**
 * @title TokensManagerMock
 * @notice Mock contract for testing TokensManager functionality
 * @dev Exposes internal functions as public for testing
 */
contract TokensManagerMock is TokensManager {
    /**
     * @dev Public initialize function for testing
     * @param _maxBps Maximum basis points (should be 100,000)
     * @param _platformWallet Address of the platform wallet
     */
    function initialize(uint256 _maxBps, address _platformWallet) external {
        _tokensManagerInit(_maxBps, _platformWallet);
    }

    /**
     * @dev Public wrapper for _setTokenSupport
     */
    function setTokenSupport(address token, uint256 status) external {
        _setTokenSupport(token, status);
    }

    /**
     * @dev Public wrapper for _updateProtocolAddress
     */
    function updateProtocolAddress(bytes32 what, address value) external {
        _updateProtocolAddress(what, value);
    }

    /**
     * @dev Public getter for maxBps (for testing)
     */
    function getMaxBps() external view returns (uint256) {
        return maxBps;
    }
}
