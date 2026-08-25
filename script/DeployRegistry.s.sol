// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployOutput} from "./DeployOutput.s.sol";
import {PaymentRegistry} from "../src/PaymentRegistry.sol";

/// @notice Deploys a standalone, UUPS-upgradeable PaymentRegistry (implementation +
///         ERC1967Proxy) directly owned by the deployer. Useful when you want one dedicated
///         registry per chain rather than going through the factory.
///
/// Set TRUSTED_FORWARDER in your environment to the address of an ERC2771Forwarder
/// (see script/DeployForwarder.s.sol) to enable gasless payments. Leave unset for none.
/// Optionally set DEFAULT_EXPIRY_SECONDS (default: 30 days, max: 182 days).
///
/// After deploying, remember to enable your payout addresses:
///   cast send $REGISTRY "setReceiverAllowed(address,bool)" $MERCHANT true --private-key $PK
///
/// Usage:
///   forge script script/DeployRegistry.s.sol:DeployRegistry \
///     --rpc-url <alias-or-url> --broadcast --verify -vvvv
contract DeployRegistry is DeployOutput {
    function run() external returns (PaymentRegistry registry) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address trustedForwarder = vm.envOr("TRUSTED_FORWARDER", address(0));
        address deployer = vm.addr(deployerKey);
        uint64 defaultExpirySeconds = uint64(vm.envOr("DEFAULT_EXPIRY_SECONDS", uint64(30 days)));

        vm.startBroadcast(deployerKey);
        address impl = address(new PaymentRegistry(trustedForwarder));
        bytes memory initData = abi.encodeCall(PaymentRegistry.initialize, (deployer, defaultExpirySeconds));
        registry = PaymentRegistry(address(new ERC1967Proxy(impl, initData)));
        vm.stopBroadcast();

        console2.log("Chain ID:        ", block.chainid);
        console2.log("TrustedForwarder:", trustedForwarder);
        console2.log("Implementation:  ", impl);
        console2.log("PaymentRegistry: ", address(registry));
        console2.log("Owner:           ", registry.owner());

        _record(KEY_IMPLEMENTATION, impl);
        _record(KEY_REGISTRY, address(registry));
        if (trustedForwarder != address(0)) {
            _record(KEY_FORWARDER, trustedForwarder);
        }
        _writeDeployments(deployer);
    }
}
