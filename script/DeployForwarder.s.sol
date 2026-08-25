// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {Script} from "forge-std/Script.sol";
import {DeployOutput} from "./DeployOutput.s.sol";
import {ERC2771Forwarder} from "openzeppelin-contracts/contracts/metatx/ERC2771Forwarder.sol";

/// @notice Deploys a single, shared ERC2771Forwarder for a chain. Every PaymentRegistry
///         deployed with this forwarder's address can accept gasless/meta-transaction
///         payments: the payer signs an EIP-712 request off-chain, and any relayer with
///         native gas can submit it on their behalf.
///
/// You normally deploy this ONCE per chain, then pass its address into
/// DeployFactory.s.sol (TRUSTED_FORWARDER env var) or DeployRegistry.s.sol.
///
/// Usage:
///   forge script script/DeployForwarder.s.sol:DeployForwarder \
///     --rpc-url <alias-or-url> --broadcast -vvvv
contract DeployForwarder is DeployOutput {
    function run() external returns (ERC2771Forwarder forwarder) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        forwarder = new ERC2771Forwarder("payment-kit.evm forwarder");
        vm.stopBroadcast();

        console2.log("Chain ID:        ", block.chainid);
        console2.log("ERC2771Forwarder:", address(forwarder));
        console2.log("Set TRUSTED_FORWARDER to this address before deploying the registry/factory.");

        _record(KEY_FORWARDER, address(forwarder));
        _writeDeployments(vm.addr(deployerKey));
    }
}
