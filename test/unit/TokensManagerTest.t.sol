// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TokensManagerMock} from "../../src/mocks/TokensManagerMock.sol";
import {TokensManager} from "../../src/contracts/TokensManager.sol";

contract TokensManagerTest is Test {
    TokensManagerMock tokensManager;

    address private platformWallet = makeAddr("platformWallet");
    address private newPlatformWallet = makeAddr("newPlatformWallet");
    address private token1 = makeAddr("token1");
    address private token2 = makeAddr("token2");
    uint256 constant DEFAULT_MAX_BPS = 100_000;

    function setUp() public {
        // Deploy the mock contract
        tokensManager = new TokensManagerMock();

        // Initialize with maxBps and platformWallet
        tokensManager.initialize(DEFAULT_MAX_BPS, platformWallet);
    }

    /* ##################################################################
                                INITIALIZATION TESTS
    ################################################################## */

    /**
     * @dev Test successful initialization
     */
    function testTokensManagerInitSuccess() public {
        // Verify maxBps was set correctly
        assertEq(tokensManager.getMaxBps(), DEFAULT_MAX_BPS, "MaxBps should be set to 100,000");

        // Verify platformWallet was set correctly
        assertEq(tokensManager.getPlatformWallet(), platformWallet, "Platform wallet should be set correctly");
    }

    /**
     * @dev Test initialization reverts with zero address
     */
    function testTokensManagerInitRevertsWithZeroAddress() public {
        TokensManagerMock newManager = new TokensManagerMock();

        vm.expectRevert(TokensManager.TokensManager__ThrowZeroAddress.selector);
        newManager.initialize(DEFAULT_MAX_BPS, address(0));
    }

    /* ##################################################################
                                TOKEN SUPPORT TESTS
    ################################################################## */

    /**
     * @dev Test setting token support to enabled (1)
     */
    function testSetTokenSupportEnabled() public {
        // Initially token should not be supported
        assertFalse(tokensManager.isTokenSupported(token1), "Token should not be supported initially");

        // Enable token support
        tokensManager.setTokenSupport(token1, 1);

        // Verify token is now supported
        assertTrue(tokensManager.isTokenSupported(token1), "Token should be supported after enabling");
    }

    /**
     * @dev Test setting token support to disabled (0)
     */
    function testSetTokenSupportDisabled() public {
        // Enable token first
        tokensManager.setTokenSupport(token1, 1);
        assertTrue(tokensManager.isTokenSupported(token1), "Token should be supported");

        // Disable token support
        tokensManager.setTokenSupport(token1, 0);

        // Verify token is no longer supported
        assertFalse(tokensManager.isTokenSupported(token1), "Token should not be supported after disabling");
    }

    /**
     * @dev Test setting token support emits event
     */
    function testSetTokenSupportEmitsEvent() public {
        // Calculate expected event parameter
        bytes32 expectedTokenHash = keccak256(abi.encodePacked("token", token1));

        // Expect TokenSupportUpdated event
        vm.expectEmit(true, false, false, true);
        emit TokensManager.TokenSupportUpdated(expectedTokenHash, true);

        tokensManager.setTokenSupport(token1, 1);
    }

    /**
     * @dev Test setting token support reverts with zero address
     */
    function testSetTokenSupportRevertsWithZeroAddress() public {
        vm.expectRevert(TokensManager.TokensManager__ThrowZeroAddress.selector);
        tokensManager.setTokenSupport(address(0), 1);
    }

    /**
     * @dev Test setting token support reverts with invalid status
     */
    function testSetTokenSupportRevertsWithInvalidStatus() public {
        // Status should be 0 or 1, anything else should revert
        vm.expectRevert(TokensManager.TokensManager__InvalidStatus.selector);
        tokensManager.setTokenSupport(token1, 2);

        vm.expectRevert(TokensManager.TokensManager__InvalidStatus.selector);
        tokensManager.setTokenSupport(token1, 999);
    }

    /**
     * @dev Test multiple tokens can be supported independently
     */
    function testMultipleTokenSupport() public {
        // Enable token1
        tokensManager.setTokenSupport(token1, 1);
        assertTrue(tokensManager.isTokenSupported(token1), "Token1 should be supported");
        assertFalse(tokensManager.isTokenSupported(token2), "Token2 should not be supported");

        // Enable token2
        tokensManager.setTokenSupport(token2, 1);
        assertTrue(tokensManager.isTokenSupported(token1), "Token1 should still be supported");
        assertTrue(tokensManager.isTokenSupported(token2), "Token2 should now be supported");

        // Disable token1
        tokensManager.setTokenSupport(token1, 0);
        assertFalse(tokensManager.isTokenSupported(token1), "Token1 should not be supported");
        assertTrue(tokensManager.isTokenSupported(token2), "Token2 should still be supported");
    }

    /* ##################################################################
                                PROTOCOL ADDRESS TESTS
    ################################################################## */

    /**
     * @dev Test updating platform wallet address
     */
    function testUpdatePlatformWallet() public {
        // Get initial platform wallet
        assertEq(tokensManager.getPlatformWallet(), platformWallet, "Initial platform wallet should match");

        // Update to new platform wallet
        tokensManager.updateProtocolAddress("platform", newPlatformWallet);

        // Verify update
        assertEq(tokensManager.getPlatformWallet(), newPlatformWallet, "Platform wallet should be updated");
    }

    /**
     * @dev Test updating protocol address emits event
     */
    function testUpdateProtocolAddressEmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit TokensManager.ProtocolAddressUpdated("platform", newPlatformWallet);

        tokensManager.updateProtocolAddress("platform", newPlatformWallet);
    }

    /**
     * @dev Test updating protocol address reverts with zero address
     */
    function testUpdateProtocolAddressRevertsWithZeroAddress() public {
        vm.expectRevert(TokensManager.TokensManager__ThrowZeroAddress.selector);
        tokensManager.updateProtocolAddress("platform", address(0));
    }

    /**
     * @dev Test updating protocol address reverts with same address
     */
    function testUpdateProtocolAddressRevertsWithSameAddress() public {
        vm.expectRevert(TokensManager.TokensManager__WalletAlreadySet.selector);
        tokensManager.updateProtocolAddress("platform", platformWallet);
    }

    /**
     * @dev Test updating protocol address reverts with invalid type
     */
    function testUpdateProtocolAddressRevertsWithInvalidType() public {
        vm.expectRevert(TokensManager.TokensManager__InvalidStatus.selector);
        tokensManager.updateProtocolAddress("invalid", newPlatformWallet);

        vm.expectRevert(TokensManager.TokensManager__InvalidStatus.selector);
        tokensManager.updateProtocolAddress("merchant", newPlatformWallet);
    }

    /* ##################################################################
                                VIEW FUNCTION TESTS
    ################################################################## */

    /**
     * @dev Test isTokenSupported returns correct value
     */
    function testIsTokenSupportedView() public {
        // Check unsupported token
        assertFalse(tokensManager.isTokenSupported(token1), "Unsupported token should return false");

        // Enable and check
        tokensManager.setTokenSupport(token1, 1);
        assertTrue(tokensManager.isTokenSupported(token1), "Supported token should return true");

        // Check zero address returns false
        assertFalse(tokensManager.isTokenSupported(address(0)), "Zero address should return false");
    }

    /**
     * @dev Test getPlatformWallet returns correct address
     */
    function testGetPlatformWalletView() public {
        assertEq(tokensManager.getPlatformWallet(), platformWallet, "Should return initial platform wallet");

        // Update and verify
        tokensManager.updateProtocolAddress("platform", newPlatformWallet);
        assertEq(tokensManager.getPlatformWallet(), newPlatformWallet, "Should return updated platform wallet");
    }
}
