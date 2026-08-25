// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {PaymentRegistry} from "../../src/PaymentRegistry.sol";

/// @notice Malicious receiver that re-enters PaymentRegistry.pay from its receive hook
///         while the registry is still settling the original native payment.
///
/// Two modes:
///  - propagate == false (default): the reentrant call is wrapped in try/catch and the
///    outcome recorded, so tests can prove the nonReentrant guard blocked it while the
///    outer payment still succeeds.
///  - propagate == true: the revert bubbles up raw, so the settlement transfer to this
///    contract fails and the whole outer payment reverts ("native transfer failed").
contract ReentrantAttacker {
    bytes4 internal constant REENTRANT_SELECTOR = PaymentRegistry.ReentrancyGuardReentrantCall.selector;

    PaymentRegistry internal immutable REGISTRY;

    bool public propagate;
    bool public reentryAttempted;
    bool public reentryBlockedByGuard;
    uint256 public receivedValue;

    constructor(PaymentRegistry registry_) {
        REGISTRY = registry_;
    }

    function setPropagate(bool propagate_) external {
        propagate = propagate_;
    }

    /// @dev Must be called with msg.value == amount; the registry pushes `amount` back to
    ///      this contract mid-call, which triggers receive() -> re-entry attempt.
    function attackNative(bytes32 paymentId, uint256 amount) external payable {
        require(msg.value == amount, "attacker: value mismatch");
        REGISTRY.pay{value: amount}(paymentId, address(0), address(this), amount, 0);
    }

    receive() external payable {
        receivedValue += msg.value;
        reentryAttempted = true;

        if (!propagate) {
            // Any parameters work: the guard fires before any business logic.
            try REGISTRY.pay(keccak256("reenter"), address(0), address(this), 1 wei, 0) {
                reentryBlockedByGuard = false; // re-entry succeeded - guard would be broken
            } catch (bytes memory reason) {
                // Casting to bytes4 is safe: revert data for a custom error is at
                // least 4 bytes long, and a shorter payload simply won't match.
                // forge-lint: disable-next-line(unsafe-typecast)
                reentryBlockedByGuard = (bytes4(reason) == REENTRANT_SELECTOR);
            }
        } else {
            REGISTRY.pay(keccak256("reenter"), address(0), address(this), 1 wei, 0);
        }
    }
}
