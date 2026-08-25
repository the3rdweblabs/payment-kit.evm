// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {PaymentRegistryFactory} from "../src/PaymentRegistryFactory.sol";
import {PaymentRegistry} from "../src/PaymentRegistry.sol";
import {PaymentTypes} from "../src/libraries/PaymentTypes.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PaymentRegistryFactoryTest is Test {
    PaymentRegistryFactory internal factory;
    address internal admin = makeAddr("admin");

    function setUp() public {
        factory = new PaymentRegistryFactory(address(0));
    }

    function test_factory_deploysSharedInertImplementation() public {
        address impl = factory.implementation();
        assertTrue(impl != address(0), "implementation deployed in constructor");
        assertEq(factory.trustedForwarder(), address(0));

        PaymentRegistry implContract = PaymentRegistry(impl);

        // The shared implementation is inert: initializers are disabled.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implContract.initialize(admin, 1 days);
    }

    function test_createRegistry_deploysProxiedRegistryOwnedByAdmin() public {
        bytes32 salt = keccak256("the3rdweblabs-store-1");
        uint64 expiry = 14 days;

        address predicted = factory.predictRegistryAddress(admin, expiry, salt);

        vm.expectEmit(true, true, false, true, address(factory));
        emit PaymentRegistryFactory.RegistryCreated(predicted, admin, salt);
        address registryAddr = factory.createRegistry(admin, expiry, salt);

        assertEq(registryAddr, predicted, "CREATE2 prediction must match");

        PaymentRegistry registry = PaymentRegistry(registryAddr);
        assertEq(registry.owner(), admin);
        assertEq(registry.defaultExpirySeconds(), expiry);
    }

    function test_createRegistry_revertsOnSaltReuse() public {
        bytes32 salt = keccak256("the3rdweblabs-store-2");
        factory.createRegistry(admin, 14 days, salt);

        vm.expectRevert();
        factory.createRegistry(admin, 14 days, salt);
    }

    function test_createRegistry_revertsOnInvalidInitParams() public {
        // Zero admin -> initialize reverts inside the proxy constructor.
        vm.expectRevert(PaymentRegistry.ZeroAdmin.selector);
        factory.createRegistry(address(0), 1 days, keccak256("bad-admin"));

        // Zero default expiry -> initialize reverts inside the proxy constructor.
        vm.expectRevert(PaymentTypes.InvalidExpiry.selector);
        factory.createRegistry(admin, 0, keccak256("bad-expiry"));
    }

    function test_proxiedRegistry_processesPayments_withAllowlistGating() public {
        bytes32 salt = keccak256("the3rdweblabs-store-3");
        address registryAddr = factory.createRegistry(admin, 30 days, salt);
        PaymentRegistry registry = PaymentRegistry(registryAddr);

        MockERC20 token = new MockERC20("Mock NGN Stable", "mNGN");
        address payer = makeAddr("payer");
        address receiver = makeAddr("receiver");
        token.mint(payer, 100e18);

        // Payments to unregistered receivers are blocked even through a factory proxy.
        vm.startPrank(payer);
        token.approve(registryAddr, 100e18);
        vm.expectRevert(abi.encodeWithSelector(PaymentTypes.ReceiverNotAllowed.selector, receiver));
        registry.pay(keccak256("proxy-invoice-0"), address(token), receiver, 100e18, 0);
        vm.stopPrank();

        vm.prank(admin);
        registry.setReceiverAllowed(receiver, true);

        vm.startPrank(payer);
        bytes32 key = registry.pay(keccak256("proxy-invoice-1"), address(token), receiver, 100e18, 0);
        vm.stopPrank();

        assertTrue(registry.isProcessed(key));
        assertEq(token.balanceOf(receiver), 100e18);
    }

    function test_predictRegistryAddress_isDeterministic_perParams() public view {
        bytes32 salt = keccak256("determinism");
        address a = factory.predictRegistryAddress(admin, 1 days, salt);
        address b = factory.predictRegistryAddress(admin, 1 days, salt);
        address c = factory.predictRegistryAddress(admin, 2 days, salt); // different initData

        assertEq(a, b);
        assertTrue(a != c, "different init data must yield a different address");
    }
}
