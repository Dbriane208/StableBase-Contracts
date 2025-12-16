// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MerchantRegistry} from "../../src/contracts/MerchantRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MerchantRegistryTest is Test {
    MerchantRegistry registry;

    address private owner = makeAddr("owner");
    address private other = makeAddr("other");
    address private merchantpayoutaddress = makeAddr("payoutWallet");

    function setUp() public {
        // Deploy implementation
        MerchantRegistry impl = new MerchantRegistry();

        // Deploy proxy initialized
        bytes memory initData = abi.encodeCall(MerchantRegistry.initialize, ());
        registry = MerchantRegistry(address(new ERC1967Proxy(address(impl), initData)));

        // Note: Owner will be address(0) after initialization
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

    function testUpdateMerchant() public {
        bytes32 merchantId = registry.registerMerchant(merchantpayoutaddress, "ipfs://initial.json");

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
}
