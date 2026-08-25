// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {PaymentRegistry} from "../../src/PaymentRegistry.sol";

/// @notice Stand-in "next" implementation used to exercise UUPS upgrades in tests.
///         Identical to PaymentRegistry except for a marker function, so a real upgrade
///         can be observed from behind the proxy.
/// @dev    Upgrade verification relies on the ERC-1967 implementation slot plus the
///         marker function below, which only exists in this mock.
contract PaymentRegistryUpgradeMock is PaymentRegistry {
    constructor(address trustedForwarder_) PaymentRegistry(trustedForwarder_) {}

    /// @notice Only reachable through a proxy pointing at THIS implementation.
    function onlyInUpgradedImpl() external pure returns (bool) {
        return true;
    }
}
