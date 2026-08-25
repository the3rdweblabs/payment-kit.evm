// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

/// @notice Contract with no receive() and no fallback(), so native-token pushes to it
///         fail and the registry's settlement reverts with "native transfer failed".
///         (ERC20 transfers still succeed - they never require a payable hook.)
contract NonPayableReceiver {
    uint256 public marker;
}
