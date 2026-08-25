// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PaymentRegistry} from "./PaymentRegistry.sol";

/// @title PaymentRegistryFactory
/// @notice Deploys UUPS-proxied PaymentRegistry instances (ERC-1967 proxies pointing at one
///         shared implementation), so any merchant/app can spin up their own registry
///         without paying full contract-deployment gas each time - loosely mirroring how
///         creating a new shared Registry object on Sui is cheap.
///
///         Unlike the old EIP-1167 clones, proxies are upgradeable: the registry owner can
///         later upgrade their instance to a new implementation via the UUPS hook, and the
///         trusted forwarder is baked into the shared implementation's bytecode (immutables
///         survive delegatecall), so every registry from this factory trusts the same
///         forwarder until an upgrade swaps implementations.
contract PaymentRegistryFactory {
    address public immutable implementation;

    /// @notice The ERC-2771 forwarder every registry created by this factory trusts for
    ///         meta-transactions. Shared across all instances since it is baked into the
    ///         shared implementation.
    address public immutable trustedForwarder;

    event RegistryCreated(address indexed registry, address indexed admin, bytes32 salt);

    /// @param trustedForwarder_ ERC-2771 forwarder address (e.g. an ERC2771Forwarder deployed
    ///        via script/DeployForwarder.s.sol), or address(0) to disable gasless payments.
    constructor(address trustedForwarder_) {
        trustedForwarder = trustedForwarder_;
        implementation = address(new PaymentRegistry(trustedForwarder_));
    }

    /// @notice Deploys a new proxy registry owned by `admin`, initialized with the given
    ///         default expiry. Merchants are enabled afterwards by the admin via
    ///         PaymentRegistry.setReceiverAllowed (one tx per merchant).
    /// @param admin Address that will own/administer the new registry.
    /// @param defaultExpirySeconds Default receipt lifetime for the new registry.
    /// @param salt Arbitrary salt for deterministic (CREATE2) deployment.
    function createRegistry(address admin, uint64 defaultExpirySeconds, bytes32 salt)
        external
        returns (address registry)
    {
        bytes memory initData = _initData(admin, defaultExpirySeconds);
        registry = address(new ERC1967Proxy{salt: salt}(implementation, initData));
        emit RegistryCreated(registry, admin, salt);
    }

    /// @notice Predicts the address a registry would be deployed to for a given salt.
    function predictRegistryAddress(address admin, uint64 defaultExpirySeconds, bytes32 salt)
        external
        view
        returns (address)
    {
        bytes memory initData = _initData(admin, defaultExpirySeconds);
        bytes32 codeHash =
            keccak256(abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initData)));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
    }

    function _initData(address admin, uint64 defaultExpirySeconds) private pure returns (bytes memory) {
        return abi.encodeCall(PaymentRegistry.initialize, (admin, defaultExpirySeconds));
    }
}
