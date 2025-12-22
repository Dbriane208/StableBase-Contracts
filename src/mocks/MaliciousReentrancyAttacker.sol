// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PaymentProcessor} from "../contracts/PaymentProcessor.sol";

/**
 * @title MaliciousReentrancyAttacker
 * @notice Mock contract to test reentrancy protection in PaymentProcessor
 * @dev This contract attempts to recursively call createOrder to test the nonReentrant modifier
 */
contract MaliciousReentrancyAttacker {
    PaymentProcessor public paymentProcessor;
    bytes32 public merchantId;
    address public token;
    uint256 public amount;
    string public metadataUri;
    bool public attacking;

    constructor(address _paymentProcessor) {
        paymentProcessor = PaymentProcessor(_paymentProcessor);
    }

    function setup(bytes32 _merchantId, address _token, uint256 _amount, string memory _metadataUri) external {
        merchantId = _merchantId;
        token = _token;
        amount = _amount;
        metadataUri = _metadataUri;
    }

    function attack() external {
        attacking = true;
        // First call to createOrder
        paymentProcessor.createOrder(merchantId, token, amount, metadataUri);
    }

    // This fallback will be triggered if the PaymentProcessor tries to interact with this contract
    // We'll use it to attempt reentrancy
    fallback() external payable {
        if (attacking) {
            attacking = false; // Prevent infinite loop in our test
            // Attempt to call createOrder again (reentrancy attempt)
            paymentProcessor.createOrder(merchantId, token, amount, metadataUri);
        }
    }

    receive() external payable {
        if (attacking) {
            attacking = false;
            paymentProcessor.createOrder(merchantId, token, amount, metadataUri);
        }
    }
}

