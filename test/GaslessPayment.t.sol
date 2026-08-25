// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC2771Forwarder} from "openzeppelin-contracts/contracts/metatx/ERC2771Forwarder.sol";
import {PaymentRegistry} from "../src/PaymentRegistry.sol";
import {PaymentTypes} from "../src/libraries/PaymentTypes.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Proves the ERC-2771 gasless payment path works end to end:
///         the payer (`signer`) never sends a transaction and holds zero native gas token;
///         a separate `relayer` account (which does hold gas) submits the forwarded call,
///         and the registry still correctly attributes the payment - pulling the ERC20
///         tokens from the signer, not the relayer - while enforcing the receiver
///         allowlist against the *relayed* payment too.
contract GaslessPaymentTest is Test {
    ERC2771Forwarder internal forwarder;
    PaymentRegistry internal registry;
    MockERC20 internal token;

    uint256 internal signerKey = 0xA11CE;
    address internal signer; // the payer - signs but never sends a tx, holds 0 native gas
    address internal relayer = makeAddr("relayer"); // pays gas, has no stake in the payment
    address internal admin = makeAddr("admin");
    address internal receiver = makeAddr("receiver");
    address internal strangerReceiver = makeAddr("strangerReceiver");

    uint64 internal DEFAULT_EXPIRY = 14 days;

    bytes32 internal constant FORWARD_REQUEST_TYPEHASH = keccak256(
        "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)"
    );

    function setUp() public {
        signer = vm.addr(signerKey);

        forwarder = new ERC2771Forwarder("payment-kit.evm forwarder");

        // UUPS implementation with the forwarder baked in + initialized proxy.
        PaymentRegistry impl = new PaymentRegistry(address(forwarder));
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(PaymentRegistry.initialize, (admin, DEFAULT_EXPIRY)));
        registry = PaymentRegistry(address(proxy));

        token = new MockERC20("Mock NGN Stable", "mNGN");

        token.mint(signer, 1_000e18);

        // Allowlist: only the owner (admin) or explicitly enabled receivers can be paid.
        vm.prank(admin);
        registry.setReceiverAllowed(receiver, true);

        vm.deal(relayer, 10 ether);
        // Deliberately NOT funding `signer` with any native gas - that's the point.
        assertEq(signer.balance, 0);
    }

    function _signedRequest(bytes memory data, uint256 value)
        internal
        view
        returns (ERC2771Forwarder.ForwardRequestData memory)
    {
        uint256 nonce = forwarder.nonces(signer);
        uint48 deadline = uint48(block.timestamp + 1 hours);

        bytes32 structHash = keccak256(
            abi.encode(
                FORWARD_REQUEST_TYPEHASH, signer, address(registry), value, 300_000, nonce, deadline, keccak256(data)
            )
        );
        bytes32 digest = _hashTypedData(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        return ERC2771Forwarder.ForwardRequestData({
            from: signer,
            to: address(registry),
            value: value,
            gas: 300_000,
            deadline: deadline,
            data: data,
            signature: abi.encodePacked(r, s, v)
        });
    }

    /// @dev Mirrors OZ's EIP712._hashTypedDataV4 using the forwarder's own domain separator.
    function _hashTypedData(bytes32 structHash) internal view returns (bytes32) {
        bytes32 domainSeparator = _domainSeparator();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _domainSeparator() internal view returns (bytes32) {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            forwarder.eip712Domain();

        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
    }

    function test_gaslessErc20Payment_signerPaysNoGas_relayerSubmits() public {
        bytes32 paymentId = keccak256("gasless-invoice-001");
        uint256 amount = 100e18;

        // Signer approves the registry directly (approvals are a separate concern from
        // gas - in production this would itself be done via a permit signature, or a
        // one-time approval funded by the dApp).
        vm.prank(signer);
        token.approve(address(registry), amount);

        bytes memory callData = abi.encodeCall(PaymentRegistry.pay, (paymentId, address(token), receiver, amount, 0));
        ERC2771Forwarder.ForwardRequestData memory request = _signedRequest(callData, 0);

        // Relayer submits the tx (and would pay real gas on any live chain); signer never
        // sends a transaction and never needs a native balance.
        vm.prank(relayer);
        forwarder.execute(request);

        assertEq(signer.balance, 0, "signer should never have needed native gas");
        assertEq(token.balanceOf(receiver), amount, "payment should have settled");
        assertEq(token.balanceOf(signer), 900e18, "tokens pulled from signer, not relayer");

        bytes32 key = registry.computeKey(paymentId, amount, address(token), receiver);
        assertTrue(registry.isProcessed(key));
    }

    function test_gaslessPayment_payerAttributedAs_msgSender() public {
        bytes32 paymentId = keccak256("gasless-invoice-attrib");
        uint256 amount = 10e18;

        vm.prank(signer);
        token.approve(address(registry), amount);

        bytes memory callData = abi.encodeCall(PaymentRegistry.pay, (paymentId, address(token), receiver, amount, 0));
        ERC2771Forwarder.ForwardRequestData memory request = _signedRequest(callData, 0);

        // The PaymentProcessed.payer field must resolve to the real signer (ERC-2771
        // _msgSender), not the relayer.
        bytes32 key = registry.computeKey(paymentId, amount, address(token), receiver);
        vm.expectEmit(true, true, true, true, address(registry));
        emit PaymentTypes.PaymentProcessed(
            key, paymentId, address(token), receiver, signer, amount, uint64(block.timestamp) + DEFAULT_EXPIRY, false
        );

        vm.prank(relayer);
        forwarder.execute(request);
    }

    function test_gaslessPayment_toUnregisteredReceiver_reverts() public {
        bytes32 paymentId = keccak256("gasless-invoice-blocked");
        uint256 amount = 10e18;

        vm.prank(signer);
        token.approve(address(registry), amount);

        // strangerReceiver was never allowed - the relayed call must fail inside the
        // registry (allowlist is enforced regardless of who submits the tx).
        bytes memory callData =
            abi.encodeCall(PaymentRegistry.pay, (paymentId, address(token), strangerReceiver, amount, 0));
        ERC2771Forwarder.ForwardRequestData memory request = _signedRequest(callData, 0);

        vm.prank(relayer);
        vm.expectRevert();
        forwarder.execute(request);

        assertEq(token.balanceOf(strangerReceiver), 0);
        assertFalse(registry.isProcessed(registry.computeKey(paymentId, amount, address(token), strangerReceiver)));
    }

    function test_gaslessPayment_revertsOnDuplicate() public {
        bytes32 paymentId = keccak256("gasless-invoice-002");
        uint256 amount = 10e18;

        vm.prank(signer);
        token.approve(address(registry), amount * 2);

        bytes memory callData = abi.encodeCall(PaymentRegistry.pay, (paymentId, address(token), receiver, amount, 0));

        vm.prank(relayer);
        forwarder.execute(_signedRequest(callData, 0));

        // Second forwarded request for the same payment (fresh nonce, same paymentId/amount/
        // token/receiver) must still hit the registry's duplicate check. Build the request
        // first - expectRevert() only catches the very next external call, and _signedRequest
        // itself makes a view call to the forwarder.
        ERC2771Forwarder.ForwardRequestData memory secondRequest = _signedRequest(callData, 0);

        vm.prank(relayer);
        vm.expectRevert();
        forwarder.execute(secondRequest);

        assertEq(token.balanceOf(receiver), amount, "duplicate should not have settled twice");
    }

    function test_directCall_stillWorksWithoutForwarder() public {
        // Sanity check: the gasless path is additive - direct calls (bypassing the
        // forwarder entirely) still behave exactly as in the non-meta-tx test suite.
        address directPayer = makeAddr("directPayer");
        token.mint(directPayer, 50e18);

        vm.startPrank(directPayer);
        token.approve(address(registry), 50e18);
        bytes32 key = registry.pay(keccak256("direct-001"), address(token), receiver, 50e18, 0);
        vm.stopPrank();

        assertTrue(registry.isProcessed(key));
        assertEq(token.balanceOf(receiver), 50e18);
    }
}
