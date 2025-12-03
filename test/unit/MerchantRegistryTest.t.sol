// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MerchantRegistry} from "../src/contracts/MerchantRegistry.sol";

contract MerchantRegistryTest is Test {
    MerchantRegistry registry;

    address private owner = makeAddr("owner");
    address private other = makeAddr("other");
    address private merchantpayoutaddress = makeAddr("payoutWallet");

    function setUp() public {
        registry = new MerchantRegistry();
    }

    function testRegisterMerchant() public {
        vm.prank(owner);

        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        // Check Id - Test that a merchantId was created(non-zero)
        assertTrue(merchantId != bytes32(0));

        // Load stored merchant using the actual generated ID
        MerchantRegistry.Merchant memory m = registry.getMerchantInfo(merchantId);

        // assert
        assertEq(m.owner, owner);
        assertEq(m.payoutWallet, merchantpayoutaddress);
        assertEq(m.metadataURI, "ipfs://metadata.json");
        assertTrue(m.exists);
    }

    function testUpdateMerchant() public {
        //register as owner
        vm.prank(owner);

        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://initialmetadata.json");

        // update as owner
        vm.prank(owner);
        registry.updateMerchant(merchantId, merchantpayoutaddress, "ipfs://updatemetadata.json");

        // Load stored merchant using the actual generated ID
        MerchantRegistry.Merchant memory m = registry.getMerchantInfo(merchantId);

        // assert
        assertEq(m.payoutWallet, merchantpayoutaddress);
        assertEq(m.metadataURI, "ipfs://updatemetadata.json");
    }

    function testRevertWhenPayoutWalletIsZero() public {
        vm.expectRevert(MerchantRegistry.MerchantRegistry__ThrowZeroAddress.selector);
        registry.registerMerchant(address(0), "ipfs://initialmetadata.json");
    }

    function testRevertWhenMerchantNotFound() public {
        vm.expectRevert(MerchantRegistry.MerchantRegistry__MerchantNotFound.selector);

        // update as owner
        vm.prank(owner);
        registry.updateMerchant(bytes32(0), merchantpayoutaddress, "ipfs://updatemetadata.json");
    }

    function testRevertWhenUnauthorizedMerchant() public {
        // register a owner
        vm.prank(owner);
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://metadata.json");

        // update as other
        vm.prank(other);
        vm.expectRevert(MerchantRegistry.MerchantRegistry__UnauthorizedMerchant.selector);

        registry.updateMerchant(merchantId, other, "ipfs://updatemetadata.json");
    }

    function testRevertWhenMetadataUriIsInvalid() public {
        // register a owner
        vm.prank(owner);
        vm.expectRevert(MerchantRegistry.MerchantRegistry__InvalidMetadataUri.selector);
        registry.registerMerchant(merchantpayoutaddress, "");
    }
}
