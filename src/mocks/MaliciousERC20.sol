// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPaymentProcessor} from "../interfaces/IPaymentProcessor.sol";

/**
 * @title MaliciousERC20
 * @notice Malicious ERC20 token that attempts reentrancy during transferFrom
 * @dev This token triggers a reentrancy attack when transferFrom is called
 */
contract MaliciousERC20 is ERC20 {
    address public attacker;
    address public paymentProcessor;
    bool public shouldAttack;
    bytes32 public targetOrderId;

    constructor(string memory name, string memory symbol, address _attacker, uint256 initialSupply)
        ERC20(name, symbol)
    {
        attacker = _attacker;
        _mint(_attacker, initialSupply);
    }

    function setPaymentProcessor(address _paymentProcessor) external {
        paymentProcessor = _paymentProcessor;
    }

    function setAttackParameters(bool _shouldAttack, bytes32 _targetOrderId) external {
        shouldAttack = _shouldAttack;
        targetOrderId = _targetOrderId;
    }

    /**
     * @dev Override transferFrom to trigger reentrancy attack
     * When the PaymentProcessor calls transferFrom during payOrder,
     * we'll attempt to call payOrder again before the first call completes
     */
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        // Only attack once to prevent infinite recursion
        if (shouldAttack && msg.sender == paymentProcessor && from == attacker) {
            shouldAttack = false; // Disable further attacks

            // Attempt reentrancy by calling payOrder again
            // This should fail due to nonReentrant modifier
            IPaymentProcessor(paymentProcessor).payOrder(targetOrderId);
        }

        return super.transferFrom(from, to, amount);
    }

    /**
     * @dev Override transfer to trigger reentrancy attack
     * When the PaymentProcessor calls transfer during settleOrder,
     * we'll attempt to call settleOrder again before the first call completes
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        // Only attack once to prevent infinite recursion
        if (shouldAttack && msg.sender == paymentProcessor) {
            shouldAttack = false; // Disable further attacks

            // Attempt reentrancy by calling settleOrder again
            // This should fail due to nonReentrant modifier
            IPaymentProcessor(paymentProcessor).settleOrder(targetOrderId);
        }
        return super.transfer(to, amount);
    }
}
