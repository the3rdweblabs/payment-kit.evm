// SPDX-License-Identifier: GPL-3.0
// Copyright (c) 2026 The3rdWebLabs (https://github.com/the3rdweblabs)
// Project: EVM Payment kit (https://github.com/the3rdweblabs/payment-kit.evm)
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC2771ContextUpgradeable} from "openzeppelin-contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PaymentTypes} from "./libraries/PaymentTypes.sol";
import {IPaymentRegistry} from "./interfaces/IPaymentRegistry.sol";

/// @title PaymentRegistry
/// @notice EVM port of MystenLabs/sui-payment-kit's Registry + Payment Processing Core.
///
/// Design notes (Sui -> EVM mapping):
///  - Sui's shared Registry object          -> a UUPS-proxy instance of this contract
///                                              (deploy directly, or via PaymentRegistryFactory
///                                              which deploys ERC1967Proxies pointing at one
///                                              shared implementation)
///  - Sui capability-based admin control    -> OZ Ownable2Step (propose/accept ownership)
///  - Composite duplicate-prevention key    -> keccak256(paymentId, amount, token, receiver)
///  - Generic coin type support             -> `token == address(0)` for native gas token,
///                                              otherwise any IERC20
///  - Configuration layer                   -> onlyOwner setters on this contract
///  - Ephemeral payment (no registry write) -> `payEphemeral`
///
/// Access model:
///  Anyone may CALL `pay` - payers never need permission. But funds can only land on a
///  receiver that the registry owner controls: either the owner itself or an address
///  explicitly enabled via `setReceiverAllowed`. This lets one owner run a single registry
///  that processes many independent merchants/payees while keeping outsiders out.
///
/// Gasless payments: this contract is ERC-2771 aware. The trusted forwarder is baked into
/// the implementation's constructor (immutables survive delegatecall), so every proxy of
/// an implementation shares its forwarder; upgrading to a differently-constructed
/// implementation is also how the forwarder can be rotated.
///
/// Upgradeability: UUPS (ERC-1967). Upgrades are authorized by the owner only. Storage
/// follows append-only discipline - new state must be added after `__gap`, and `__gap`
/// shrunk accordingly, so proxied deployments stay compatible.
contract PaymentRegistry is
    IPaymentRegistry,
    Initializable,
    ERC2771ContextUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Hard cap on custom (and default) receipt lifetimes - ~6 months. Prevents
    ///         permanently squatting a receipt key via an absurd expiry.
    uint64 public constant MAX_CUSTOM_EXPIRY_SECONDS = 182 days;

    // Reentrancy guard states (own implementation: OZ v5 dropped the upgradeable wrapper
    // and the base contract initializes its namespaced slot in a constructor, which
    // proxies never execute - so we own the guard in our regular storage layout instead).
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    /// @notice receiptKey => unix timestamp the receipt expires at. 0 means "unused".
    mapping(bytes32 => uint64) public expiresAt;

    /// @notice Default receipt lifetime applied when a caller passes customExpiry = 0.
    uint64 public defaultExpirySeconds;

    /// @notice Receivers explicitly enabled by the owner. The owner's own address is
    ///         always implicitly allowed (see isAllowedReceiver).
    mapping(address => bool) private _allowedReceivers;

    /// @notice Reentrancy guard state; initialized to _NOT_ENTERED in initialize().
    uint256 private _status;

    /// @notice Reserve slots for future state so upgraded implementations stay
    ///         storage-compatible with existing proxies. Shrink when adding variables.
    uint256[48] private __gap;

    error ZeroAdmin();

    /// @param trustedForwarder_ Address of the ERC-2771 forwarder allowed to relay
    ///        meta-transactions on behalf of payers. Baked into this implementation's
    ///        bytecode; pass address(0) to disable gasless payments entirely.
    constructor(address trustedForwarder_) ERC2771ContextUpgradeable(trustedForwarder_) {
        // The implementation contract behind the proxies is inert: it must never be
        // initialized directly.
        _disableInitializers();
    }

    /// @dev Used by PaymentRegistryFactory and standalone deploy scripts to configure a
    ///      freshly deployed proxy.
    function initialize(address admin_, uint64 defaultExpirySeconds_) external initializer {
        if (admin_ == address(0)) revert ZeroAdmin();
        if (defaultExpirySeconds_ == 0 || defaultExpirySeconds_ > MAX_CUSTOM_EXPIRY_SECONDS) {
            revert PaymentTypes.InvalidExpiry();
        }

        __Ownable_init(admin_);
        __Ownable2Step_init();
        __Pausable_init();

        defaultExpirySeconds = defaultExpirySeconds_;
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    error ReentrancyGuardReentrantCall();

    // Admin / config layer

    function setDefaultExpiry(uint64 newDefaultExpirySeconds) external onlyOwner {
        if (newDefaultExpirySeconds == 0 || newDefaultExpirySeconds > MAX_CUSTOM_EXPIRY_SECONDS) {
            revert PaymentTypes.InvalidExpiry();
        }
        emit PaymentTypes.DefaultExpirySet(defaultExpirySeconds, newDefaultExpirySeconds);
        defaultExpirySeconds = newDefaultExpirySeconds;
    }

    /// @notice Enable or disable `receiver_` as a payout destination through this registry.
    ///         Disabling only blocks NEW payments; settled funds were pushed out instantly
    ///         and are unaffected.
    function setReceiverAllowed(address receiver_, bool allowed_) external onlyOwner {
        if (receiver_ == address(0)) revert PaymentTypes.ZeroReceiver();
        _allowedReceivers[receiver_] = allowed_;
        emit PaymentTypes.ReceiverAllowedSet(receiver_, allowed_);
    }

    /// @notice True if payments may settle to `receiver_`: the owner itself, or an
    ///         explicitly enabled address.
    function isAllowedReceiver(address receiver_) public view returns (bool) {
        return receiver_ == owner() || _allowedReceivers[receiver_];
    }

    /// @notice Emergency stop switch for the whole registry. Funds are push-based and never
    ///         custodied, so pausing only blocks NEW payments until unpause.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Upgrade layer

    /// ERC-2771 context resolution: explicit overrides keep the diamond unambiguous
    /// (ContextUpgradeable is reached via both ERC2771ContextUpgradeable and Ownable).
    function _msgSender() internal view override(ERC2771ContextUpgradeable, ContextUpgradeable) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view override(ERC2771ContextUpgradeable, ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        pure
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (uint256)
    {
        return 20;
    }

    /// @notice UUPS hook: only the owner may upgrade the implementation of any proxy.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Payment processing core

    /// @inheritdoc IPaymentRegistry
    function pay(bytes32 paymentId, address token, address receiver, uint256 amount, uint64 customExpiry)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (bytes32 key)
    {
        key = PaymentTypes.receiptKey(paymentId, amount, token, receiver);

        // Duplicate check: only a fresh or expired slot can be (re)used.
        if (expiresAt[key] >= block.timestamp) {
            revert PaymentTypes.DuplicatePayment(key);
        }

        uint64 lifetime = customExpiry == 0 ? defaultExpirySeconds : customExpiry;
        if (customExpiry > MAX_CUSTOM_EXPIRY_SECONDS) revert PaymentTypes.InvalidExpiry();

        // CEI: claim the slot before the external transfer so reentrant calls observe it.
        uint64 expiry = uint64(block.timestamp) + lifetime;
        expiresAt[key] = expiry;

        _settle(token, receiver, amount);

        emit PaymentTypes.PaymentProcessed(key, paymentId, token, receiver, _msgSender(), amount, expiry, false);
    }

    /// @inheritdoc IPaymentRegistry
    function payEphemeral(bytes32 paymentId, address token, address receiver, uint256 amount)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (bytes32 key)
    {
        key = PaymentTypes.receiptKey(paymentId, amount, token, receiver);

        _settle(token, receiver, amount);

        // No storage write: cheapest path, no duplicate protection, matches the Sui
        // kit's "Ephemeral payment option".
        emit PaymentTypes.PaymentProcessed(key, paymentId, token, receiver, _msgSender(), amount, 0, true);
    }

    /// @inheritdoc IPaymentRegistry
    function isProcessed(bytes32 key) public view returns (bool) {
        return expiresAt[key] >= block.timestamp;
    }

    /// @inheritdoc IPaymentRegistry
    function prune(bytes32 key) external {
        uint64 expiry = expiresAt[key];
        if (expiry == 0) revert PaymentTypes.ReceiptNotFound(key);
        if (expiry >= block.timestamp) revert PaymentTypes.ReceiptNotExpired(key);
        delete expiresAt[key];
        emit PaymentTypes.ReceiptPruned(key);
    }

    /// @inheritdoc IPaymentRegistry
    function computeKey(bytes32 paymentId, uint256 amount, address token, address receiver)
        external
        pure
        returns (bytes32)
    {
        return PaymentTypes.receiptKey(paymentId, amount, token, receiver);
    }

    // Internal

    function _settle(address token, address receiver, uint256 amount) internal {
        if (amount == 0) revert PaymentTypes.ZeroAmount();
        if (receiver == address(0)) revert PaymentTypes.ZeroReceiver();
        if (!isAllowedReceiver(receiver)) revert PaymentTypes.ReceiverNotAllowed(receiver);

        if (token == PaymentTypes.NATIVE_TOKEN) {
            if (msg.value != amount) revert PaymentTypes.NativeValueMismatch(amount, msg.value);
            (bool ok,) = receiver.call{value: amount}("");
            require(ok, "native transfer failed");
        } else {
            if (msg.value != 0) revert PaymentTypes.NativeNotAccepted();
            IERC20(token).safeTransferFrom(_msgSender(), receiver, amount);
        }
    }
}
