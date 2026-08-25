// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Script} from "forge-std/Script.sol";
import {DeployOutput} from "./DeployOutput.s.sol";
import {PaymentRegistryFactory} from "../src/PaymentRegistryFactory.sol";

/// @notice Deploys PaymentRegistryFactory (which deploys the PaymentRegistry
///         implementation in its constructor) to whichever chain the RPC/keys
///         in environment points to.
///
/// Set TRUSTED_FORWARDER in environment to the address of an ERC2771Forwarder
/// (see script/DeployForwarder.s.sol) to enable gasless payments on every clone this
/// factory creates. Leave it unset (or 0x0) to disable gasless payments.
///
/// Usage:
///   forge script script/DeployFactory.s.sol:DeployFactory \
///     --rpc-url <alias-or-url> --broadcast --verify -vvvv
contract DeployFactory is DeployOutput {
    function run() external returns (PaymentRegistryFactory factory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));

        vm.startBroadcast(deployerKey);
        factory = new PaymentRegistryFactory(trustedForwarder);
        vm.stopBroadcast();

        console2.log("Chain ID:              ", block.chainid);
        console2.log("TrustedForwarder:      ", trustedForwarder);
        console2.log("PaymentRegistryFactory:", address(factory));
        console2.log("PaymentRegistry impl:  ", factory.implementation());

        _record(KEY_IMPLEMENTATION, factory.implementation());
        _record(KEY_FACTORY, address(factory));
        if (trustedForwarder != address(0)) {
            _record(KEY_FORWARDER, trustedForwarder);
        }
        _writeDeployments(vm.addr(deployerKey));
    }
}
