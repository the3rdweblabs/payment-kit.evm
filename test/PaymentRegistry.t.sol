// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {PaymentRegistry} from "../src/PaymentRegistry.sol";
import {PaymentTypes} from "../src/libraries/PaymentTypes.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PaymentRegistryUpgradeMock} from "./mocks/PaymentRegistryUpgradeMock.sol";
import {ReentrantAttacker} from "./mocks/ReentrantAttacker.sol";
import {NonPayableReceiver} from "./mocks/NonPayableReceiver.sol";

contract PaymentRegistryTest is Test {
    PaymentRegistry internal registry;
    MockERC20 internal token;

    address internal admin = makeAddr("admin");
    address internal payer = makeAddr("payer");
    address internal receiver = makeAddr("receiver");
    address internal stranger = makeAddr("stranger");
    address internal newOwner = makeAddr("newOwner");

    uint64 internal DEFAULT_EXPIRY = 14 days;

    function setUp() public {
        registry = _deployRegistry(admin, DEFAULT_EXPIRY);

        token = new MockERC20("Mock NGN Stable", "mNGN");
        token.mint(payer, 1_000e18);

        vm.deal(payer, 10 ether);
    }

    /// @dev Deployment recipe: UUPS implementation (forwarder baked into its
    ///      constructor) + ERC1967Proxy initialized in the same tx.
    function _deployRegistry(address admin_, uint64 defaultExpiry_) internal returns (PaymentRegistry) {
        PaymentRegistry impl = new PaymentRegistry(address(0));
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(PaymentRegistry.initialize, (admin_, defaultExpiry_)));
        return PaymentRegistry(address(proxy));
    }

    function _allow(address receiver_) internal {
        vm.prank(admin);
        registry.setReceiverAllowed(receiver_, true);
    }

    // Deployment / initialization

    function test_initialize_revertsOnZeroAdmin() public {
        PaymentRegistry impl = new PaymentRegistry(address(0));

        vm.expectRevert(PaymentRegistry.ZeroAdmin.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(PaymentRegistry.initialize, (address(0), DEFAULT_EXPIRY)));
    }

    function test_initialize_revertsOnInvalidDefaultExpiry() public {
        PaymentRegistry impl = new PaymentRegistry(address(0));
        uint64 tooLong = registry.MAX_CUSTOM_EXPIRY_SECONDS() + 1;

        vm.expectRevert(PaymentTypes.InvalidExpiry.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(PaymentRegistry.initialize, (admin, 0)));

        vm.expectRevert(PaymentTypes.InvalidExpiry.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(PaymentRegistry.initialize, (admin, tooLong)));
    }

    function test_initialize_cannotBeCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        registry.initialize(stranger, 1 days);
    }

    function test_initialize_onRawImplementation_reverts_initializersDisabled() public {
        PaymentRegistry impl = new PaymentRegistry(address(0));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(admin, 1 days);
    }

    // ERC20 payments

    function test_pay_erc20_succeeds_and_recordsReceipt() public {
        bytes32 pid = keccak256("invoice-001");
        uint256 amount = 100e18;
        _allow(receiver);

        vm.startPrank(payer);
        token.approve(address(registry), amount);
        bytes32 key = registry.pay(pid, address(token), receiver, amount, 0);
        vm.stopPrank();

        assertTrue(registry.isProcessed(key));
        assertEq(token.balanceOf(receiver), amount);
        assertEq(registry.expiresAt(key), block.timestamp + DEFAULT_EXPIRY);
    }

    function test_pay_erc20_revertsOnDuplicateWhileLive() public {
        bytes32 pid = keccak256("invoice-002");
        uint256 amount = 50e18;
        _allow(receiver);

        vm.startPrank(payer);
        token.approve(address(registry), amount * 2);
        bytes32 key = registry.pay(pid, address(token), receiver, amount, 0);

        vm.expectRevert(abi.encodeWithSelector(PaymentTypes.DuplicatePayment.selector, key));
        registry.pay(pid, address(token), receiver, amount, 0);
        vm.stopPrank();
    }

    function test_pay_erc20_allowsReuseAfterExpiry_andAfterPrune() public {
        bytes32 pid = keccak256("invoice-003");
        uint256 amount = 10e18;
        _allow(receiver);

        vm.startPrank(payer);
        token.approve(address(registry), amount * 3);
        bytes32 key = registry.pay(pid, address(token), receiver, amount, 1 hours);

        // Still live: reuse reverts.
        vm.expectRevert(abi.encodeWithSelector(PaymentTypes.DuplicatePayment.selector, key));
        registry.pay(pid, address(token), receiver, amount, 1 hours);

        // After expiry the slot frees up on its own.
        uint256 t0 = block.timestamp;
        vm.warp(t0 + 2 hours);
        registry.pay(pid, address(token), receiver, amount, 1 hours);

        // And after an explicit prune it is reusable immediately.
        vm.warp(t0 + 4 hours);
        registry.prune(key);
        registry.pay(pid, address(token), receiver, amount, 1 hours);
        vm.stopPrank();

        assertEq(token.balanceOf(receiver), amount * 3);
    }

    // Native token payments

    function test_pay_native_succeeds() public {
        bytes32 pid = keccak256("invoice-native-001");
        uint256 amount = 1 ether;
        uint256 receiverBalanceBefore = receiver.balance;
        _allow(receiver);

        vm.prank(payer);
        bytes32 key = registry.pay{value: amount}(pid, address(0), receiver, amount, 0);

        assertTrue(registry.isProcessed(key));
        assertEq(receiver.balance, receiverBalanceBefore + amount);
        assertEq(address(registry).balance, 0, "registry must never custody native funds");
    }

    function test_pay_native_revertsOnValueMismatch() public {
        bytes32 key = keccak256("invoice-native-002");
        uint256 amount = 1 ether;
        _allow(receiver);

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(PaymentTypes.NativeValueMismatch.selector, amount, amount - 1));
        registry.pay{value: amount - 1}(key, address(0), receiver, amount, 0);
    }

    function test_pay_native_toNonPayableReceiver_reverts() public {
        NonPayableReceiver brick = new NonPayableReceiver();
        _allow(address(brick));

        vm.deal(payer, 1 ether);
        vm.prank(payer);
        vm.expectRevert(bytes("native transfer failed"));
        registry.pay{value: 1 ether}(keccak256("brick"), address(0), address(brick), 1 ether, 0);
    }

    // Ephemeral mode

    function test_payEphemeral_doesNotPersistReceipt_andAllowsImmediateReuse() public {
        bytes32 key = keccak256("ephemeral-001");
        uint256 amount = 5e18;
        _allow(receiver);

        vm.startPrank(payer);
        token.approve(address(registry), amount * 2);
        registry.payEphemeral(key, address(token), receiver, amount);
        assertFalse(registry.isProcessed(key));
        assertEq(registry.expiresAt(key), 0, "ephemeral payments must not write storage");

        // Same params can be reused immediately since nothing was recorded.
        registry.payEphemeral(key, address(token), receiver, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(receiver), amount * 2);
    }

    // Receiver allowlist

    function test_pay_toOwner_succeedsWithoutRegistration() public {
        uint256 amount = 1 ether;
        uint256 adminBalanceBefore = admin.balance;

        vm.prank(payer);
        bytes32 key = registry.pay{value: amount}(keccak256("to-owner"), address(0), admin, amount, 0);

        assertTrue(registry.isProcessed(key));
        assertEq(admin.balance, adminBalanceBefore + amount);
    }

    function test_pay_erc20_toOwner_succeedsWithoutRegistration() public {
        uint256 amount = 25e18;
        vm.startPrank(payer);
        token.approve(address(registry), amount);
        bytes32 key = registry.pay(paymentId(), address(token), admin, amount, 0);
        vm.stopPrank();
        assertTrue(registry.isProcessed(key));
        assertEq(token.balanceOf(admin), amount);
    }

    function test_pay_toUnregisteredReceiver_reverts() public {
        uint256 amount = 1 ether;

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(PaymentTypes.ReceiverNotAllowed.selector, receiver));
        registry.pay{value: amount}(paymentId(), address(0), receiver, amount, 0);

        // Payers are never gated - the same payment to the owner works.
        vm.prank(payer);
        registry.pay{value: amount}(paymentId(), address(0), admin, amount, 0);
    }

    function test_pay_toAllowedReceiver_succeeds() public {
        _allow(receiver);
        vm.startPrank(payer);
        token.approve(address(registry), 1e18);
        bytes32 key = registry.pay(paymentId(), address(token), receiver, 1e18, 0);
        vm.stopPrank();
        assertTrue(registry.isProcessed(key));
        assertEq(token.balanceOf(receiver), 1e18);
    }

    function test_payEphemeral_enforcesAllowlistIdentically() public {
        // Unregistered: reverts, exactly like `pay`.
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(PaymentTypes.ReceiverNotAllowed.selector, receiver));
        registry.payEphemeral{value: 1 ether}(paymentId(), address(0), receiver, 1 ether);

        // Registered: succeeds.
        _allow(receiver);
        vm.prank(payer);
        registry.payEphemeral{value: 1 ether}(paymentId(), address(0), receiver, 1 ether);
        assertEq(receiver.balance, 1 ether);
    }

    function test_revokedReceiver_isBlockedFromNewPayments_only() public {
        uint256 amount = 5e18;
        _allow(receiver);

        vm.startPrank(payer);
        token.approve(address(registry), amount * 3);
        registry.pay(paymentId(), address(token), receiver, amount, 0);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectEmit(true, true, false, false, address(registry));
        emit PaymentTypes.ReceiverAllowedSet(receiver, false);
        registry.setReceiverAllowed(receiver, false);

        assertFalse(registry.isAllowedReceiver(receiver));

        // New payments are blocked...
        vm.startPrank(payer);
        vm.expectRevert(abi.encodeWithSelector(PaymentTypes.ReceiverNotAllowed.selector, receiver));
        registry.pay(paymentId(), address(token), receiver, amount, 0);

        // ...but already-settled funds are untouched and payers stay unblocked.
        registry.pay(paymentId(), address(token), admin, amount, 0);
        vm.stopPrank();

        assertEq(token.balanceOf(receiver), amount);
    }

    function test_setReceiverAllowed_byNonOwner_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        registry.setReceiverAllowed(receiver, true);
    }

    function test_setReceiverAllowed_zeroAddress_reverts() public {
        vm.prank(admin);
        vm.expectRevert(PaymentTypes.ZeroReceiver.selector);
        registry.setReceiverAllowed(address(0), true);
    }

    function test_setReceiverAllowed_emitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(registry));
        emit PaymentTypes.ReceiverAllowedSet(receiver, true);
        registry.setReceiverAllowed(receiver, true);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(registry));
        emit PaymentTypes.ReceiverAllowedSet(receiver, false);
        registry.setReceiverAllowed(receiver, false);
    }

    function test_isAllowedReceiver_reflectsOwnerEnabledAndDisabledStates() public {
        assertTrue(registry.isAllowedReceiver(admin), "owner implicitly allowed");
        assertFalse(registry.isAllowedReceiver(receiver));

        vm.prank(admin);
        registry.setReceiverAllowed(receiver, true);
        assertTrue(registry.isAllowedReceiver(receiver));

        vm.prank(admin);
        registry.setReceiverAllowed(receiver, false);
        assertFalse(registry.isAllowedReceiver(receiver));

        // Even a deliberate disable of the owner's own address cannot lock them out.
        vm.prank(admin);
        registry.setReceiverAllowed(admin, false);
        assertTrue(registry.isAllowedReceiver(admin), "owner stays allowed");
    }

    // Ownership (Ownable2Step)

    function test_ownership_twoStepTransfer_fullFlow() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, false, address(registry));
        emit Ownable2StepUpgradeable.OwnershipTransferStarted(admin, newOwner);
        registry.transferOwnership(newOwner);

        assertEq(registry.pendingOwner(), newOwner);
        assertEq(registry.owner(), admin, "ownership must not move until accepted");

        vm.prank(newOwner);
        vm.expectEmit(true, true, false, false, address(registry));
        emit OwnableUpgradeable.OwnershipTransferred(admin, newOwner);
        registry.acceptOwnership();

        assertEq(registry.owner(), newOwner);
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_ownership_acceptOwnership_byWrongCaller_reverts() public {
        vm.prank(admin);
        registry.transferOwnership(newOwner);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        registry.acceptOwnership();

        assertEq(registry.owner(), admin);
    }

    function test_ownership_newOwner_canAdminister_oldCannot() public {
        vm.prank(admin);
        registry.transferOwnership(newOwner);
        vm.prank(newOwner);
        registry.acceptOwnership();

        // New owner has full admin rights.
        vm.startPrank(newOwner);
        registry.pause();
        assertTrue(registry.paused());
        registry.unpause();
        registry.setDefaultExpiry(30 days);
        registry.setReceiverAllowed(receiver, true);
        vm.stopPrank();

        // Old admin is fully locked out.
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, admin));
        registry.setDefaultExpiry(7 days);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, admin));
        registry.setReceiverAllowed(receiver, false);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, admin));
        registry.pause();
        vm.stopPrank();

        assertEq(registry.defaultExpirySeconds(), 30 days);
        assertTrue(registry.isAllowedReceiver(receiver));
    }

    // Upgrades (UUPS)

    /// @dev keccak256("eip1967.proxy.implementation") - 1.
    bytes32 internal constant ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function _implementationSlot() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(registry), ERC1967_IMPL_SLOT))));
    }

    function test_upgrade_ownerUpgrades_preservingState_andPaymentsStillWork() public {
        _allow(receiver);
        vm.startPrank(payer);
        token.approve(address(registry), type(uint256).max);
        bytes32 key = registry.pay(paymentId(), address(token), receiver, 1e18, 1 hours);
        vm.stopPrank();

        PaymentRegistryUpgradeMock upgradedImpl = new PaymentRegistryUpgradeMock(address(0));
        vm.prank(admin);
        registry.upgradeToAndCall(address(upgradedImpl), "");

        // The proxy now points at the new implementation, and a function that only
        // exists there is reachable through it - that is what proves the swap.
        assertEq(_implementationSlot(), address(upgradedImpl));
        assertTrue(PaymentRegistryUpgradeMock(address(registry)).onlyInUpgradedImpl());

        // State survives the upgrade: receipt slot, expiry config and allowlist.
        assertEq(registry.defaultExpirySeconds(), DEFAULT_EXPIRY);
        assertEq(registry.expiresAt(key), block.timestamp + 1 hours);
        assertTrue(registry.isProcessed(key));
        assertTrue(registry.isAllowedReceiver(receiver));

        // Payments still process through the new implementation.
        vm.startPrank(payer);
        bytes32 key2 = registry.pay(paymentId(), address(token), receiver, 2e18, 0);
        vm.stopPrank();
        assertTrue(registry.isProcessed(key2));
        assertEq(token.balanceOf(receiver), 3e18);
    }

    function test_upgrade_byNonOwner_reverts() public {
        PaymentRegistryUpgradeMock upgradedImpl = new PaymentRegistryUpgradeMock(address(0));
        address implBefore = _implementationSlot();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        registry.upgradeToAndCall(address(upgradedImpl), "");

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, payer));
        registry.upgradeToAndCall(address(upgradedImpl), "");

        assertEq(_implementationSlot(), implBefore, "implementation must be unchanged");
    }

    // Expiry bounds

    function test_expiry_customExactlyMax_succeeds() public {
        _allow(receiver);
        uint64 maxExpiry = registry.MAX_CUSTOM_EXPIRY_SECONDS();
        assertEq(maxExpiry, 182 days);

        vm.prank(payer);
        bytes32 key = registry.pay{value: 1 ether}(paymentId(), address(0), receiver, 1 ether, maxExpiry);

        assertEq(registry.expiresAt(key), block.timestamp + maxExpiry);
    }

    function test_expiry_customOverMax_reverts() public {
        _allow(receiver);
        uint64 overMax = registry.MAX_CUSTOM_EXPIRY_SECONDS() + 1;

        vm.prank(payer);
        vm.expectRevert(PaymentTypes.InvalidExpiry.selector);
        registry.pay{value: 1 ether}(paymentId(), address(0), receiver, 1 ether, overMax);

        vm.startPrank(payer);
        token.approve(address(registry), 1e18);
        vm.expectRevert(PaymentTypes.InvalidExpiry.selector);
        registry.pay(paymentId(), address(token), receiver, 1e18, overMax);
        vm.stopPrank();
    }

    function test_expiry_zeroCustomFallsBackToDefault() public {
        _allow(receiver);

        vm.startPrank(payer);
        token.approve(address(registry), 1e18);
        bytes32 key = registry.pay(paymentId(), address(token), receiver, 1e18, 0);
        vm.stopPrank();

        assertEq(registry.expiresAt(key), block.timestamp + DEFAULT_EXPIRY);
    }

    function test_setDefaultExpiry_bounds_andEvent() public {
        uint64 oldDefault = registry.defaultExpirySeconds();
        uint64 maxExpiry = registry.MAX_CUSTOM_EXPIRY_SECONDS();

        // Zero is invalid.
        vm.prank(admin);
        vm.expectRevert(PaymentTypes.InvalidExpiry.selector);
        registry.setDefaultExpiry(0);

        // Above the hard cap is invalid.
        vm.prank(admin);
        vm.expectRevert(PaymentTypes.InvalidExpiry.selector);
        registry.setDefaultExpiry(maxExpiry + 1);

        // Exactly at the cap is valid and emits the event.
        vm.prank(admin);
        vm.expectEmit(false, false, false, true, address(registry));
        emit PaymentTypes.DefaultExpirySet(oldDefault, maxExpiry);
        registry.setDefaultExpiry(maxExpiry);

        assertEq(registry.defaultExpirySeconds(), maxExpiry);
    }

    function test_setDefaultExpiry_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        registry.setDefaultExpiry(7 days);

        vm.prank(admin);
        registry.setDefaultExpiry(7 days);
        assertEq(registry.defaultExpirySeconds(), 7 days);
    }

    // Pause

    function test_pause_blocksNativeAndTokenPayments_enforcedPause() public {
        _allow(receiver);
        vm.prank(admin);
        registry.pause();
        assertTrue(registry.paused());

        bytes32 pid = paymentId();
        vm.startPrank(payer);
        token.approve(address(registry), 1e18);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        registry.pay(pid, address(token), receiver, 1e18, 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        registry.pay{value: 1 ether}(pid, address(0), receiver, 1 ether, 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        registry.payEphemeral(pid, address(token), receiver, 1e18);
        vm.stopPrank();
    }

    function test_unpause_restoresPayments() public {
        _allow(receiver);
        vm.startPrank(admin);
        registry.pause();
        registry.unpause();
        vm.stopPrank();
        assertFalse(registry.paused());

        vm.startPrank(payer);
        token.approve(address(registry), 1e18);
        bytes32 key = registry.pay(paymentId(), address(token), receiver, 1e18, 0);
        vm.stopPrank();
        assertTrue(registry.isProcessed(key));
    }

    function test_pause_unpause_nonOwnerReverts() public {
        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        registry.pause();
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        registry.unpause();
        vm.stopPrank();
        assertFalse(registry.paused());
    }

    // Reentrancy

    function test_reentrancy_guardBlocksRecursivePay_outerPaymentSucceeds() public {
        ReentrantAttacker attacker = new ReentrantAttacker(registry);
        _allow(address(attacker));

        attacker.attackNative{value: 1 ether}(keccak256("reentry-catch"), 1 ether);

        assertTrue(attacker.reentryAttempted());
        assertTrue(attacker.reentryBlockedByGuard(), "nonReentrant guard should have blocked re-entry");
        assertEq(attacker.receivedValue(), 1 ether, "attacker got paid exactly once");
        assertEq(address(registry).balance, 0);
    }

    function test_reentrancy_propagatingAttacker_failsWholeSettlement() public {
        ReentrantAttacker attacker = new ReentrantAttacker(registry);
        attacker.setPropagate(true);
        _allow(address(attacker));

        vm.deal(address(this), 2 ether);
        uint256 testerBalanceBefore = address(this).balance;

        vm.expectRevert(bytes("native transfer failed"));
        attacker.attackNative{value: 1 ether}(keccak256("reentry-propagate"), 1 ether);

        // The outer payment rolled back entirely: no funds stuck anywhere.
        assertEq(address(this).balance, testerBalanceBefore, "value returned to caller");
        assertEq(address(registry).balance, 0);
        assertEq(attacker.receivedValue(), 0);
    }

    // Misc regression / helpers

    function test_pay_ethSentAlongsideToken_revertsNativeNotAccepted() public {
        _allow(receiver);
        vm.deal(payer, 1 ether);
        vm.startPrank(payer);
        token.approve(address(registry), 1e18);
        vm.expectRevert(PaymentTypes.NativeNotAccepted.selector);
        registry.pay{value: 1}(paymentId(), address(token), receiver, 1e18, 0);
        vm.stopPrank();
    }

    function test_pay_zeroAmount_reverts() public {
        _allow(receiver);
        vm.prank(payer);
        vm.expectRevert(PaymentTypes.ZeroAmount.selector);
        registry.pay(paymentId(), address(token), receiver, 0, 0);

        vm.prank(payer);
        vm.expectRevert(PaymentTypes.ZeroAmount.selector);
        registry.pay{value: 0}(paymentId(), address(0), receiver, 0, 0);
    }

    function test_pay_zeroReceiver_reverts() public {
        vm.prank(payer);
        vm.expectRevert(PaymentTypes.ZeroReceiver.selector);
        registry.pay{value: 1 wei}(paymentId(), address(0), address(0), 1 wei, 0);

        vm.startPrank(payer);
        token.approve(address(registry), 1e18);
        vm.expectRevert(PaymentTypes.ZeroReceiver.selector);
        registry.pay(paymentId(), address(token), address(0), 1e18, 0);
        vm.stopPrank();
    }

    function test_prune_unknownKey_revertsNotFound_activeKey_revertsNotExpired() public {
        bytes32 unknown = keccak256("never-used");
        vm.expectRevert(abi.encodeWithSelector(PaymentTypes.ReceiptNotFound.selector, unknown));
        registry.prune(unknown);

        _allow(receiver);
        vm.startPrank(payer);
        token.approve(address(registry), 1e18);
        bytes32 key = registry.pay(paymentId(), address(token), receiver, 1e18, 1 hours);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(PaymentTypes.ReceiptNotExpired.selector, key));
        registry.prune(key);
    }

    function test_prune_afterExpiry_deletesSlot_permissionless() public {
        _allow(receiver);
        vm.startPrank(payer);
        token.approve(address(registry), 1e18);
        bytes32 key = registry.pay(paymentId(), address(token), receiver, 1e18, 1 hours);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours + 1 seconds);
        registry.prune(key); // anyone may prune

        assertEq(registry.expiresAt(key), 0);
        assertFalse(registry.isProcessed(key));
    }

    function test_computeKey_matchesKeccakOfEncodedFields() public view {
        bytes32 key = keccak256("key-check");
        uint256 amount = 123 wei;
        address token_ = address(0xBEEF);
        address receiver_ = address(0xC0FFEE);

        bytes32 expected = keccak256(abi.encode(key, amount, token_, receiver_));
        assertEq(registry.computeKey(key, amount, token_, receiver_), expected);
        assertEq(PaymentTypes.receiptKey(key, amount, token_, receiver_), expected);
    }

    function test_paymentProcessed_eventFieldsExact() public {
        _allow(receiver);
        bytes32 pid = keccak256("event-fields");
        uint256 amount = 42e18;
        uint64 customExpiry = 3 days;
        bytes32 key = registry.computeKey(pid, amount, address(token), receiver);
        uint64 expectedExpiry = uint64(block.timestamp) + customExpiry;

        vm.startPrank(payer);
        token.approve(address(registry), amount);
        vm.expectEmit(true, true, true, true, address(registry));
        emit PaymentTypes.PaymentProcessed(key, pid, address(token), receiver, payer, amount, expectedExpiry, false);
        bytes32 returned = registry.pay(pid, address(token), receiver, amount, customExpiry);
        vm.stopPrank();

        assertEq(returned, key);
    }

    function paymentId() internal returns (bytes32) {
        return keccak256(abi.encode("invoice", ++pidCounter));
    }

    uint256 internal pidCounter;
}
