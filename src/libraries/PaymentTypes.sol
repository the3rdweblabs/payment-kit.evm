// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

/// @title PaymentTypes
/// @notice Shared errors, events and helpers used across payment-kit.evm
/// @dev Mirrors the duplicate-prevention composite key used by MystenLabs/sui-payment-kit:
///      key = hash(paymentId, amount, token/coinType, receiver)
library PaymentTypes {
    /// @notice address(0) is used to represent the native gas token (ETH, MON, etc.)
    address internal constant NATIVE_TOKEN = address(0);

    error ZeroAmount();
    error ZeroReceiver();
    error DuplicatePayment(bytes32 receiptKey);
    error ReceiptNotExpired(bytes32 receiptKey);
    error ReceiptNotFound(bytes32 receiptKey);
    error NativeValueMismatch(uint256 expected, uint256 sent);
    error NativeNotAccepted();
    error InvalidExpiry();
    error ReceiverNotAllowed(address receiver);

    event PaymentProcessed(
        bytes32 indexed receiptKey,
        bytes32 indexed paymentId,
        address indexed token,
        address receiver,
        address payer,
        uint256 amount,
        uint64 expiresAt,
        bool ephemeral
    );

    event ReceiptPruned(bytes32 indexed receiptKey);
    event DefaultExpirySet(uint64 oldValue, uint64 newValue);
    event ReceiverAllowedSet(address indexed receiver, bool indexed allowed);

    /// @notice Derives the duplicate-prevention key for a payment.
    /// @dev Same composite fields as the Sui version: payment id (nonce), amount,
    ///      token/coin type, and receiver address.
    function receiptKey(bytes32 paymentId, uint256 amount, address token, address receiver)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(paymentId, amount, token, receiver));
    }
}
