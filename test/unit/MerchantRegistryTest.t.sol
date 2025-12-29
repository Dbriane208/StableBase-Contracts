// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MerchantRegistry} from "../../src/contracts/MerchantRegistry.sol";
import {IMerchantRegistry} from "../../src/interfaces/IMerchantRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MerchantRegistryTest is Test {
    MerchantRegistry registry;

    address private owner = makeAddr("owner");
    address private other = makeAddr("other");
    address private merchantpayoutaddress = makeAddr("payoutWallet");

    function setUp() public {
        // Deploy implementation
        MerchantRegistry impl = new MerchantRegistry();

        // Deploy proxy initialized with owner
        bytes memory initData = abi.encodeCall(MerchantRegistry.initialize, (owner));
        registry = MerchantRegistry(address(new ERC1967Proxy(address(impl), initData)));
    }

    /* ##################################################################
                                MODIFIERS
    ################################################################## */
    modifier merchantOwnership() {
        _setUpMerchantOwnership();
        _;
    }

    function _setUpMerchantOwnership() internal {
        // Owner is set to 'owner' during initialization
        // Transfer ownership to this test contract if needed
        address currentOwner = registry.owner();

        if (currentOwner != address(this)) {
            // Transfer ownership from 'owner' to this contract
            vm.prank(currentOwner);
            registry.transferOwnership(address(this));
            registry.acceptOwnership();
        }
    }

    function testRegisterMerchant() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        assertTrue(merchantId != bytes32(0));

        MerchantRegistry.Merchant memory m = registry.getMerchantInfo(merchantId);

        assertEq(m.owner, address(this)); // The test contract is the merchant owner
        assertEq(m.payoutWallet, merchantpayoutaddress);
        assertEq(m.metadataURI, "ipfs://metadata.json");
        assertTrue(m.exists);
    }

    function testUpdateMerchant() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://initial.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://updated.json");

        MerchantRegistry.Merchant memory m = registry.getMerchantInfo(merchantId);

        assertEq(m.metadataURI, "ipfs://updated.json");
    }

    function testRevertWhenPayoutWalletIsZero() public {
        vm.expectRevert(MerchantRegistry.MerchantRegistry__ThrowZeroAddress.selector);
        registry.registerMerchant(address(0), "ipfs://initialmetadata.json");
    }

    function testRevertWhenMerchantNotFound() public {
        vm.expectRevert(MerchantRegistry.MerchantRegistry__MerchantNotFound.selector);

        registry.updateMerchant(bytes32(0), merchantpayoutaddress, "ipfs://updatemetadata.json");
    }

    function testRevertWhenUnauthorizedMerchant() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        vm.prank(other);
        vm.expectRevert(MerchantRegistry.MerchantRegistry__UnauthorizedMerchant.selector);
        registry.updateMerchant(merchantId, other, "ipfs://updatemetadata.json");
    }

    function testRevertWhenMetadataUriIsInvalid() public {
        vm.expectRevert(MerchantRegistry.MerchantRegistry__InvalidMetadataUri.selector);
        registry.registerMerchant(merchantpayoutaddress, "");
    }

    /* ##################################################################
                        MERCHANT REGISTRATION TESTS
    ################################################################## */

    /**
     * @dev Test merchant registration sets correct initial verification status (PENDING)
     */
    function testRegisterMerchantInitialVerificationStatus() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        IMerchantRegistry.VerificationStatus m = registry.getMerchantVerificationStatus(merchantId);

        assertEq(uint8(m), uint8(IMerchantRegistry.VerificationStatus.PENDING));
    }

    /**
     * @dev Test merchant registration sets correct timestamp
     */
    function testRegisterMerchantCreationTimestamp() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        assertEq(block.timestamp, registry.getMerchantCreatedAt(merchantId));
    }

    /**
     * @dev Test same user can register multiple merchants
     */
    function testRegisterMultipleMerchantsBySameOwner() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");
        bytes32 merchantIdTwo = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadatatwo.json");

        MerchantRegistry.Merchant memory m = registry.getMerchantInfo(merchantId);
        MerchantRegistry.Merchant memory m2 = registry.getMerchantInfo(merchantIdTwo);

        assertEq(m.owner, m2.owner);
    }

    /**
     * @dev Test merchant ID uniqueness for different users
     */
    function testMerchantIdUniqueness() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        vm.prank(other);
        bytes32 merchantIdTwo = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadatatwo.json");

        assertNotEq(merchantId, merchantIdTwo);
    }

    /**
     * @dev Test merchant registration reverts when paused
     */
    function testRegisterMerchantRevertsWhenPaused() public merchantOwnership {
        registry.pause();

        vm.expectRevert();
        registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");
    }

    /* ##################################################################
                        MERCHANT UPDATE TESTS
    ################################################################## */

    /**
     * @dev Test update merchant emits correct event
     */
    function testUpdateMerchantEmitsEvent() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        vm.expectEmit(true, false, false, false);

        emit IMerchantRegistry.MerchantUpdated(merchantId);

        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://merchantmetadata.json");
    }

    /**
     * @dev Test update merchant preserves verification status
     */
    function testUpdateMerchantPreservesVerificationStatus() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        vm.expectEmit(true, false, false, false);

        emit IMerchantRegistry.MerchantUpdated(merchantId);

        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://merchantmetadata.json");

        IMerchantRegistry.VerificationStatus m = registry.getMerchantVerificationStatus(merchantId);

        assertEq(uint8(m), uint8(IMerchantRegistry.VerificationStatus.VERIFIED));
    }

    /**
     * @dev Test update merchant reverts with zero payout wallet
     */
    function testUpdateMerchantRevertsWithZeroPayoutWallet() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        vm.expectRevert(MerchantRegistry.MerchantRegistry__ThrowZeroAddress.selector);

        registry.updateMerchant(merchantId, address(0), "ipfs://merchantmetadata.json");
    }

    /**
     * @dev Test update merchant reverts with invalid metadata URI
     */
    function testUpdateMerchantRevertsWithInvalidMetadataUri() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        vm.expectRevert(MerchantRegistry.MerchantRegistry__InvalidMetadataUri.selector);

        registry.updateMerchant(merchantId, merchantpayoutaddress, "");
    }

    /**
     * @dev Test update merchant reverts when paused
     */
    function testUpdateMerchantRevertsWhenPaused() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        registry.pause();

        vm.expectRevert();

        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://merchantmetadata.json");
    }

    /* ##################################################################
                    VERIFICATION STATUS TESTS
    ################################################################## */

    /**
     * @dev Test owner can update verification status to REJECTED
     */
    function testUpdateVerificationStatusRevertsWhenRejected() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.REJECTED);

        vm.expectRevert(MerchantRegistry.MerchantRegistry__UnverifiedMerchant.selector);

        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://merchantmetadata.json");
    }

    /**
     * @dev Test owner can update verification status to SUSPENDED
     */
    function testUpdateVerificationStatusRevertsWhenSuspended() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.SUSPENDED);

        vm.expectRevert(MerchantRegistry.MerchantRegistry__UnverifiedMerchant.selector);

        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://merchantmetadata.json");
    }

    /**
     * @dev Test update verification status reverts for non-existent merchant
     */
    function testUpdateVerificationStatusRevertsForNonExistentMerchant() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        vm.expectRevert(MerchantRegistry.MerchantRegistry__MerchantNotFound.selector);

        registry.updateMerchant(bytes32(0), merchantpayoutaddress, "ipfs://merchantmetadata.json");
    }

    /**
     * @dev Test update verification status reverts when not owner
     */
    function testUpdateVerificationStatusRevertsWhenNotOwner() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        vm.prank(other);

        vm.expectRevert(MerchantRegistry.MerchantRegistry__UnauthorizedMerchant.selector);

        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://merchantmetadata.json");
    }

    /**
     * @dev Test update verification status reverts when paused
     */
    function testUpdateVerificationStatusRevertsWhenPaused() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        registry.pause();

        vm.expectRevert();

        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://merchantmetadata.json");
    }

    /**
     * @dev Test verification status can be updated multiple times
     */
    function testUpdateVerificationStatusMultipleTimes() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        // Initially PENDING
        IMerchantRegistry.VerificationStatus status = registry.getMerchantVerificationStatus(merchantId);
        assertEq(uint8(status), uint8(IMerchantRegistry.VerificationStatus.PENDING));

        // Update to VERIFIED
        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);
        status = registry.getMerchantVerificationStatus(merchantId);
        assertEq(uint8(status), uint8(IMerchantRegistry.VerificationStatus.VERIFIED));

        // Update to SUSPENDED
        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.SUSPENDED);
        status = registry.getMerchantVerificationStatus(merchantId);
        assertEq(uint8(status), uint8(IMerchantRegistry.VerificationStatus.SUSPENDED));

        // Update to REJECTED
        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.REJECTED);
        status = registry.getMerchantVerificationStatus(merchantId);
        assertEq(uint8(status), uint8(IMerchantRegistry.VerificationStatus.REJECTED));

        // Update back to VERIFIED
        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);
        status = registry.getMerchantVerificationStatus(merchantId);
        assertEq(uint8(status), uint8(IMerchantRegistry.VerificationStatus.VERIFIED));
    }

    /* ##################################################################
                        VIEW FUNCTION TESTS
    ################################################################## */

    /**
     * @dev Test getMerchantInfo returns correct data
     */
    function testGetMerchantInfoReturnsCorrectData() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        MerchantRegistry.Merchant memory m = registry.getMerchantInfo(merchantId);

        assertEq(m.owner, address(this));
        assertEq(m.payoutWallet, merchantpayoutaddress);
        assertEq(m.metadataURI, "ipfs://metadata.json");
        assertTrue(m.exists);
        assertEq(uint8(m.verificationStatus), uint8(IMerchantRegistry.VerificationStatus.PENDING));
        assertEq(m.createdAt, block.timestamp);
    }

    /**
     * @dev Test getMerchantInfo reverts for non-existent merchant
     */
    function testGetMerchantInfoRevertsForNonExistent() public {
        vm.expectRevert(MerchantRegistry.MerchantRegistry__MerchantNotFound.selector);
        registry.getMerchantInfo(bytes32(0));
    }

    /**
     * @dev Test isMerchantVerified returns true for verified merchant
     */
    function testIsMerchantVerifiedReturnsTrue() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        assertTrue(registry.isMerchantVerified(merchantId));
    }

    /**
     * @dev Test isMerchantVerified returns false for pending merchant
     */
    function testIsMerchantVerifiedReturnsFalseForPending() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        assertFalse(registry.isMerchantVerified(merchantId));
    }

    /**
     * @dev Test isMerchantVerified returns false for rejected merchant
     */
    function testIsMerchantVerifiedReturnsFalseForRejected() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.REJECTED);

        assertFalse(registry.isMerchantVerified(merchantId));
    }

    /**
     * @dev Test isMerchantVerified returns false for non-existent merchant
     */
    function testIsMerchantVerifiedReturnsFalseForNonExistent() public view {
        assertFalse(registry.isMerchantVerified(bytes32(0)));
    }

    /**
     * @dev Test getMerchantVerificationStatus returns correct status
     */
    function testGetMerchantVerificationStatusReturnsCorrectStatus() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        // Initially PENDING
        IMerchantRegistry.VerificationStatus status = registry.getMerchantVerificationStatus(merchantId);
        assertEq(uint8(status), uint8(IMerchantRegistry.VerificationStatus.PENDING));

        // Update to VERIFIED
        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);
        status = registry.getMerchantVerificationStatus(merchantId);
        assertEq(uint8(status), uint8(IMerchantRegistry.VerificationStatus.VERIFIED));
    }

    /**
     * @dev Test getMerchantVerificationStatus reverts for non-existent merchant
     */
    function testGetMerchantVerificationStatusRevertsForNonExistent() public {
        vm.expectRevert(MerchantRegistry.MerchantRegistry__MerchantNotFound.selector);
        registry.getMerchantVerificationStatus(bytes32(0));
    }

    /**
     * @dev Test getMerchantCreatedAt returns correct timestamp
     */
    function testGetMerchantCreatedAtReturnsCorrectTimestamp() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        assertEq(registry.getMerchantCreatedAt(merchantId), block.timestamp);
    }

    /**
     * @dev Test getMerchantCreatedAt reverts for non-existent merchant
     */
    function testGetMerchantCreatedAtRevertsForNonExistent() public {
        vm.expectRevert(MerchantRegistry.MerchantRegistry__MerchantNotFound.selector);
        registry.getMerchantCreatedAt(bytes32(0));
    }

    /* ##################################################################
                        PAUSABLE TESTS
    ################################################################## */

    /**
     * @dev Test owner can pause the contract
     */
    function testOwnerCanPauseContract() public merchantOwnership {
        registry.pause();

        vm.expectRevert();

        registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");
    }

    /**
     * @dev Test owner can unpause the contract
     */
    function testOwnerCanUnpauseContract() public merchantOwnership {
        registry.pause();

        vm.expectRevert();

        registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.unpause();

        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.REJECTED);
    }

    /**
     * @dev Test pause reverts when not owner
     */
    function testPauseRevertsWhenNotOwner() public merchantOwnership {
        vm.prank(other);
        vm.expectRevert();
        registry.pause();
    }

    /**
     * @dev Test unpause reverts when not owner
     */
    function testUnpauseRevertsWhenNotOwner() public {
        vm.prank(other);
        vm.expectRevert();
        registry.unpause();
    }

    /**
     * @dev Test paused state prevents merchant registration
     */
    function testPausedStatePreventsRegistration() public merchantOwnership {
        registry.pause();

        vm.expectRevert();

        registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");
    }

    /**
     * @dev Test paused state prevents merchant updates
     */
    function testPausedStatePreventsUpdates() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);

        registry.pause();

        vm.expectRevert();

        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://merchantmetadata.json");
    }

    /**
     * @dev Test paused state prevents verification updates
     */
    function testPausedStatePreventsVerificationUpdates() public merchantOwnership {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        registry.pause();

        vm.expectRevert();

        registry.updateMerchantVerificationStatus(merchantId, IMerchantRegistry.VerificationStatus.VERIFIED);
    }

    /* ##################################################################
                        INITIALIZATION TESTS
    ################################################################## */

    /**
     * @dev Test contract initializes with correct state
     */
    function testContractInitializesCorrectly() public view {
        // Owner should be address(0) initially
        assertEq(registry.owner(), address(0));

        // Contract should not be paused
        assertFalse(registry.paused());
    }

    /**
     * @dev Test contract cannot be initialized twice
     */
    function testCannotInitializeTwice() public {
        vm.expectRevert();
        registry.initialize(owner);
    }

    /**
     * @dev Test implementation contract cannot be initialized
     */
    function testImplementationCannotBeInitialized() public {
        MerchantRegistry impl = new MerchantRegistry();

        vm.expectRevert();
        impl.initialize(owner);
    }
}
