// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PaymentRegistry} from "../src/PaymentRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @dev Fuzzed action handler. Every payment goes through try/catch so the ghost
///      accounting mirrors the registry EXACTLY (only successful external calls mutate
///      ghost state), which makes the violation latches deterministic - they can only
///      ever be set if the registry itself breaks its guarantees.
contract RegistryHandler is CommonBase, StdAssertions, StdUtils {
    PaymentRegistry internal immutable REGISTRY;
    MockERC20 internal immutable TOKEN;
    address internal immutable ADMIN;
    address[] internal actors;
    address[] internal receivers;

    // Violation latches - asserted by invariant functions in the parent suite.
    bool public paidWhilePaused;
    bool public doubleSpendDetected;

    /// @notice Mirror of registry.paused(), synced from the source of truth after use.
    bool public pausedMirror;

    /// @notice Ghost copy of expiresAt for receipts this suite successfully created.
    mapping(bytes32 => uint64) internal ghostExpiry;

    /// @notice Keys seen by successful pays; lets `prune` target realistic slots.
    bytes32[] internal touchedKeys;

    /// @notice Handler-local clock used for vm.warp; always equals block.timestamp.
    uint64 public currentTime;

    uint256 internal constant MAX_TOUCHED = 1024;
    uint64 internal constant MAX_WARP_DELTA = 90 days;
    uint64 internal constant DEFAULT_EXPIRY = 30 days;

    constructor(
        PaymentRegistry registry_,
        MockERC20 token_,
        address admin_,
        address[] memory actors_,
        address[] memory receivers_
    ) {
        REGISTRY = registry_;
        TOKEN = token_;
        ADMIN = admin_;
        actors = actors_;
        receivers = receivers_;
        currentTime = uint64(block.timestamp);
    }

    // Actions (fuzz targets)

    function payNative(
        uint256 actorSeed,
        uint256 paymentSeed,
        uint256 receiverSeed,
        uint256 amountRaw,
        uint64 expiryRaw
    ) external {
        _pay(address(0), actorSeed, paymentSeed, receiverSeed, amountRaw, expiryRaw);
    }

    function payToken(uint256 actorSeed, uint256 paymentSeed, uint256 receiverSeed, uint256 amountRaw, uint64 expiryRaw)
        external
    {
        _pay(address(TOKEN), actorSeed, paymentSeed, receiverSeed, amountRaw, expiryRaw);
    }

    function payEphemeralNative(uint256 actorSeed, uint256 paymentSeed, uint256 receiverSeed, uint256 amountRaw)
        external
    {
        _payEphemeral(address(0), actorSeed, paymentSeed, receiverSeed, amountRaw);
    }

    function payEphemeralToken(uint256 actorSeed, uint256 paymentSeed, uint256 receiverSeed, uint256 amountRaw)
        external
    {
        _payEphemeral(address(TOKEN), actorSeed, paymentSeed, receiverSeed, amountRaw);
    }

    function warp(uint64 deltaRaw) external {
        currentTime += uint64(bound(deltaRaw, 1, MAX_WARP_DELTA));
        vm.warp(currentTime);
        _assertNoCustody();
    }

    function togglePause(bool pause_) external {
        if (pause_ && !pausedMirror) {
            vm.prank(ADMIN);
            REGISTRY.pause();
        } else if (!pause_ && pausedMirror) {
            vm.prank(ADMIN);
            REGISTRY.unpause();
        }
        // Sync from the source of truth so the mirror can never drift.
        pausedMirror = REGISTRY.paused();
    }

    function setReceiverAllowed(uint256 receiverSeed, bool allowed) external {
        address recv = receivers[bound(receiverSeed, 0, receivers.length - 1)];
        vm.prank(ADMIN);
        REGISTRY.setReceiverAllowed(recv, allowed);
    }

    function prune(uint256 keyIdxRaw) external {
        if (touchedKeys.length == 0) return;
        bytes32 key = touchedKeys[bound(keyIdxRaw, 0, touchedKeys.length - 1)];

        try REGISTRY.prune(key) {
            delete ghostExpiry[key];
            assertEq(REGISTRY.expiresAt(key), uint64(0), "pruned slot not deleted");
        } catch {}
        _assertNoCustody();
    }

    // Shared internals

    function _pay(
        address tokenAddr,
        uint256 actorSeed,
        uint256 paymentSeed,
        uint256 receiverSeed,
        uint256 amountRaw,
        uint64 expiryRaw
    ) internal {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        address recv = receivers[bound(receiverSeed, 0, receivers.length - 1)];
        uint256 amount = bound(amountRaw, 1 wei, 1 ether);
        uint64 customExpiry = uint64(bound(expiryRaw, 0, REGISTRY.MAX_CUSTOM_EXPIRY_SECONDS()));
        uint64 lifetime = customExpiry == 0 ? DEFAULT_EXPIRY : customExpiry;
        bytes32 pid = keccak256(abi.encode("invariant-pay", paymentSeed));

        vm.prank(actor);
        try REGISTRY.pay{value: amount}(pid, tokenAddr, recv, amount, customExpiry) returns (bytes32 key) {
            if (pausedMirror) paidWhilePaused = true;
            if (_ghostLive(key)) doubleSpendDetected = true;

            // Ghost and storage must agree at write time...
            ghostExpiry[key] = currentTime + lifetime;
            assertEq(REGISTRY.expiresAt(key), currentTime + lifetime, "ghost/storage expiry mismatch");
            _remember(key);
        } catch {}

        _assertNoCustody();
    }

    function _payEphemeral(
        address tokenAddr,
        uint256 actorSeed,
        uint256 paymentSeed,
        uint256 receiverSeed,
        uint256 amountRaw
    ) internal {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        address recv = receivers[bound(receiverSeed, 0, receivers.length - 1)];
        uint256 amount = bound(amountRaw, 1 wei, 1 ether);
        bytes32 pid = keccak256(abi.encode("invariant-ephemeral", paymentSeed));

        vm.prank(actor);
        try REGISTRY.payEphemeral{value: amount}(pid, tokenAddr, recv, amount) returns (bytes32 key) {
            if (pausedMirror) paidWhilePaused = true;
            // Ephemeral writes no receipt - storage must stay untouched.
            assertEq(REGISTRY.expiresAt(key), uint64(0), "ephemeral payment wrote storage");
        } catch {}

        _assertNoCustody();
    }

    function _ghostLive(bytes32 key) internal view returns (bool) {
        uint64 expiry = ghostExpiry[key];
        return expiry != 0 && expiry >= currentTime;
    }

    function _remember(bytes32 key) internal {
        if (touchedKeys.length < MAX_TOUCHED) {
            touchedKeys.push(key);
        } else {
            touchedKeys[uint256(key) % MAX_TOUCHED] = key;
        }
    }

    /// @notice The registry is strictly push-based: nothing may ever rest on it.
    function _assertNoCustody() internal view {
        assertEq(address(REGISTRY).balance, 0, "native residue on registry");
        assertEq(TOKEN.balanceOf(address(REGISTRY)), 0, "token residue on registry");
    }

    // Views used by the parent suite's invariant functions

    function registry() external view returns (PaymentRegistry) {
        return REGISTRY;
    }

    function token() external view returns (MockERC20) {
        return TOKEN;
    }
}

/// @notice Global invariants over arbitrary sequences of payments, prunes, warps, pauses
///         and allowlist changes driven through RegistryHandler.
contract PaymentRegistryInvariantsTest is Test {
    RegistryHandler internal handler;
    PaymentRegistry internal registry;
    MockERC20 internal token;

    address internal admin = makeAddr("admin");

    function setUp() public {
        PaymentRegistry impl = new PaymentRegistry(address(0));
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(PaymentRegistry.initialize, (admin, 30 days)));
        registry = PaymentRegistry(address(proxy));
        token = new MockERC20("Mock NGN Stable", "mNGN");

        // Three funded payers with standing approvals, so most pays succeed.
        address[] memory actors = new address[](3);
        for (uint256 i = 0; i < actors.length; i++) {
            actors[i] = makeAddr(string.concat("actor", vm.toString(i)));
            vm.deal(actors[i], 1_000 ether);
            token.mint(actors[i], 10_000_000e18);
            vm.prank(actors[i]);
            token.approve(address(registry), type(uint256).max);
        }

        // Receivers limited to a pre-registered allowlist.
        address[] memory receiversList = new address[](3);
        for (uint256 i = 0; i < receiversList.length; i++) {
            receiversList[i] = makeAddr(string.concat("receiver", vm.toString(i)));
            vm.prank(admin);
            registry.setReceiverAllowed(receiversList[i], true);
        }

        handler = new RegistryHandler(registry, token, admin, actors, receiversList);

        // Only fuzz through the handler - the registry itself is not a direct target.
        targetContract(address(handler));
    }

    /// @notice No successful payment may ever be observed while the registry is paused.
    ///         The latch is set by the handler if any try/catch'd pay ever succeeds while
    ///         its (always-in-sync) pause mirror claims the registry is paused.
    function invariant_neverPaysWhenPaused() public view {
        assertFalse(handler.paidWhilePaused());
    }

    /// @notice Push-based settlement: after arbitrary pay/prune/warp/pause sequences the
    ///         registry holds no native balance and no token balance. (Within a single
    ///         handler call value is transiently nonzero between transfer-in and push-out,
    ///         but every handler re-checks custody at its end - so it must be zero here.)
    function invariant_registryNeverCustodies() public view {
        assertEq(address(registry).balance, 0, "native residue on registry");
        assertEq(token.balanceOf(address(registry)), 0, "token residue on registry");
    }

    /// @notice Whenever a pay succeeds for a key our ghost accounting says is still live
    ///         (never expired / never pruned / never overwritten by expiry), that is a
    ///         double spend. The handler latches the violation inline on every successful
    ///         call; this invariant fails the run if it was ever tripped.
    function invariant_noDoubleSpendLiveKeys() public view {
        assertFalse(handler.doubleSpendDetected());
    }
}
