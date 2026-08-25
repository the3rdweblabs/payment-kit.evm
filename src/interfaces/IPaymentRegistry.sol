// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

/// @title IPaymentRegistry
/// @notice Minimal interface other contracts can call directly, in the same transaction,
///         to process a payment or check whether one has already been processed.
///         No off-chain indexer is required for correctness.
interface IPaymentRegistry {
    /// @notice Process a payment with a persistent, duplicate-checked receipt.
    /// @param paymentId Caller-supplied nonce identifying this payment.
    /// @param token ERC20 token address, or address(0) for the native gas token.
    /// @param receiver Address the funds are sent to.
    /// @param amount Exact amount that must be transferred.
    /// @param customExpiry Seconds-from-now the receipt should live for. Pass 0 to use
    ///        the registry's default expiry.
    /// @return key The receipt key that can be queried later via isProcessed().
    function pay(bytes32 paymentId, address token, address receiver, uint256 amount, uint64 customExpiry)
        external
        payable
        returns (bytes32 key);

    /// @notice Process a payment without writing a persistent receipt (no duplicate protection).
    ///         Cheapest option, matches the "Ephemeral" mode in sui-payment-kit.
    function payEphemeral(bytes32 paymentId, address token, address receiver, uint256 amount)
        external
        payable
        returns (bytes32 key);

    /// @notice Returns true if a receipt exists for `key` and has not expired.
    function isProcessed(bytes32 key) external view returns (bool);

    /// @notice Deletes an expired receipt, reclaiming storage. Permissionless.
    function prune(bytes32 key) external;

    /// @notice Convenience view to compute the receipt key off-chain or from another contract.
    function computeKey(bytes32 paymentId, uint256 amount, address token, address receiver)
        external
        pure
        returns (bytes32);
}
