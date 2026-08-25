// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @notice Shared deployment-output helper.
///
/// Every deploy script extends this and records its contract addresses with
/// {_record}, then calls {_writeDeployments} once at the end. The result is a
/// single JSON artifact per chain/network:
///
///   deployments/{chain}-{network}.json
///     e.g. deployments/monad-testnet.json, deployments/base-mainnet.json
///
/// Keys accumulate across separate runs (deploy forwarder today, factory
/// tomorrow -> both end up in the same file). Unknown chains fall back to
/// deployments/chain-{chainid}.json so nothing is ever silently dropped.
abstract contract DeployOutput is Script {
    string constant KEY_FORWARDER = "forwarder";
    string constant KEY_IMPLEMENTATION = "implementation";
    string constant KEY_FACTORY = "factory";
    string constant KEY_REGISTRY = "registry";

    string[] private s_keys;
    address[] private s_values;

    /// @dev Record an output address under `key` for this run.
    function _record(string memory key, address value) internal {
        s_keys.push(key);
        s_values.push(value);
    }

    /// @dev Merge recorded addresses (plus chain metadata) into
    ///      deployments/{network}.json. Only writes to disk on real broadcasts
    ///      - dry runs (simulate-*) leave existing artifacts untouched.
    function _writeDeployments(address deployer) internal {
        string memory slug = _networkName();
        string memory path = string.concat("deployments/", slug, ".json");

        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast) && !vm.isContext(VmSafe.ForgeContext.ScriptResume)) {
            console2.log("Dry run - deployment file not written:", path);
            return;
        }

        // Start from whatever previous runs left behind so a partial deploy
        // never wipes its siblings.
        address forwarder = _existing(path, ".forwarder");
        address implementation = _existing(path, ".implementation");
        address factory = _existing(path, ".factory");
        address registry = _existing(path, ".registry");

        for (uint256 i = 0; i < s_keys.length; i++) {
            string memory k = s_keys[i];
            if (_eq(k, KEY_FORWARDER)) {
                forwarder = s_values[i];
            } else if (_eq(k, KEY_IMPLEMENTATION)) {
                implementation = s_values[i];
            } else if (_eq(k, KEY_FACTORY)) {
                factory = s_values[i];
            } else if (_eq(k, KEY_REGISTRY)) {
                registry = s_values[i];
            }
        }

        string memory obj = "deployment";
        vm.serializeAddress(obj, KEY_FORWARDER, forwarder);
        vm.serializeAddress(obj, KEY_IMPLEMENTATION, implementation);
        vm.serializeAddress(obj, KEY_FACTORY, factory);
        vm.serializeAddress(obj, KEY_REGISTRY, registry);
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeString(obj, "network", slug);
        vm.serializeAddress(obj, "deployer", deployer);
        vm.serializeUint(obj, "block", block.number);
        string memory json = vm.serializeUint(obj, "timestamp", block.timestamp);

        vm.writeJson(json, path);
        console2.log("Deployment file:", path);
    }

    /// @dev chainId -> "{chain}-{network}" slug. Order matches foundry.toml.
    function _networkName() internal view returns (string memory) {
        uint256 id = block.chainid;
        if (id == 1) return "ethereum-mainnet";
        if (id == 11155111) return "ethereum-testnet"; // Sepolia
        if (id == 56) return "bnb-mainnet";
        if (id == 97) return "bnb-testnet";
        if (id == 42161) return "arbitrum-mainnet"; // Arbitrum One
        if (id == 421614) return "arbitrum-testnet"; // Arbitrum Sepolia
        if (id == 8453) return "base-mainnet";
        if (id == 84532) return "base-testnet"; // Base Sepolia
        if (id == 10) return "op-mainnet";
        if (id == 11155420) return "op-testnet"; // OP Sepolia
        if (id == 143) return "monad-mainnet";
        if (id == 10143) return "monad-testnet";
        if (id == 999) return "hyperliquid-mainnet"; // HyperEVM
        if (id == 998) return "hyperliquid-testnet";
        if (id == 4663) return "robinhood-mainnet";
        if (id == 46630) return "robinhood-testnet";
        if (id == 196) return "xlayer-mainnet";
        if (id == 195) return "xlayer-testnet";
        if (id == 677) return "botchain-mainnet";
        if (id == 968) return "botchain-testnet";
        if (id == 31337) return "localnet";
        return string.concat("chain-", vm.toString(id));
    }

    function _existing(string memory path, string memory dotKey) private view returns (address out) {
        try vm.readFile(path) returns (string memory raw) {
            try vm.parseJsonAddress(raw, dotKey) returns (address a) {
                out = a;
            } catch {}
        } catch {}
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
