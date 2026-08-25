# payment-kit.evm

An open-source, EVM-compatible port of [MystenLabs/sui-payment-kit](https://github.com/MystenLabs/sui-payment-kit), by [THE3RDWEBLABS](https://github.com/the3rdweblabs). Deployable to any EVM L1 or L2 - Ethereum, Base, Arbitrum, Monad, and beyond.

Same guarantees as the Sui original: exact-amount payment verification, duplicate prevention via a composite key, optional persistent receipts with expiration, and an ephemeral no-storage mode. Other contracts call the registry directly, in the same transaction - no off-chain indexer is required for correctness.

## Overview

The EVM Payment Kit is a Solidity smart contract framework (built with Foundry) that enables developers to integrate secure, verifiable payments into their EVM applications. It provides a flexible architecture for payment processing with optional receipt persistence, configurable expiration policies, and built-in duplicate prevention - mirroring the design of the original [Sui Payment Kit](https://github.com/MystenLabs/sui-payment-kit), translated to the object model of the EVM.

## Key Features

- **Secure Payment Processing**: Built-in duplicate prevention and exact amount verification
- **Payment Registries**: Registries process payments and manage receipt lifetime - funds are pushed straight to the receiver, so the registry never custodies balances
- **Receiver Allowlisting**: Settlement targets must be the registry owner or explicitly enabled - anyone may pay, but only vetted receivers can get paid
- **Flexible Receipt Management**: Optional receipt persistence with configurable expiration (per-registry default plus per-payment custom lifetimes, hard-capped at 182 days)
- **Event-Driven Architecture**: All payments emit events for off-chain tracking
- **Admin Controls**: Owner-based access control (two-step ownership) for registry management, including a pause circuit breaker
- **Modular Design**: Factory-spawned instances sharing one implementation, with UUPS upgrades
- **Multi-Token Support**: Generic implementation supports the native gas token and any ERC-20
- **Gasless Payments**: ERC-2771 meta-transaction support - users sign off-chain, a relayer pays gas

## How It Works

The EVM Payment Kit consists of three main components:

1. **Payment Processing Core**: Handles token transfers and validation
2. **Registry System**: Persistent storage for payment receipts
3. **Configuration Layer**: Dynamic, upgradeable registry configuration management

### Duplicate Prevention

Payment Kit prevents duplicate payments using a composite key derived from:

- Payment ID (nonce)
- Amount
- Token Type
- Receiver Address

This ensures the same payment cannot be processed twice while its receipt is still live.

Duplicate prevention is only enforced when processing payments via a `PaymentRegistry`. If duplicate prevention is not necessary there is an Ephemeral payment option (`payEphemeral()`).

## Contracts

| Contract | Purpose |
|---|---|
| [`PaymentRegistry.sol`](src/PaymentRegistry.sol) | Core payment processing + registry (UUPS-upgradeable). Duplicate prevention, receipt expiry, receiver allowlist, admin config, pause switch. |
| [`PaymentRegistryFactory.sol`](src/PaymentRegistryFactory.sol) | Deploys ERC-1967 UUPS proxies of a shared `PaymentRegistry` implementation via CREATE2, so any merchant/app can spin up their own registry instance cheaply - and upgrades flow from one implementation. |
| [`IPaymentRegistry.sol`](src/interfaces/IPaymentRegistry.sol) | Interface other contracts call directly to process or check payments. |
| [`PaymentTypes.sol`](src/libraries/PaymentTypes.sol) | Shared errors, events, and the receipt-key derivation. |

`PaymentRegistry` is ERC-2771 aware (`ERC2771ContextUpgradeable`), so it supports gasless / meta-transaction payments out of the box - see [Gasless payments](#gasless-payments) below.

## Sui -> EVM design mapping

| sui-payment-kit | payment-kit.evm |
|---|---|
| Shared `Registry` object | A deployed `PaymentRegistry` instance (direct deploy, or a factory proxy) |
| Capability-based admin control | OZ `Ownable2Step` (+ UUPS owner-gated upgrades) |
| Composite duplicate key: `(nonce, amount, coin type, receiver)` | `keccak256(paymentId, amount, token, receiver)` |
| Generic coin type | `token == address(0)` for the native gas token, otherwise any `IERC20` |
| Configuration layer | `onlyOwner` setters (`setDefaultExpiry`, `setReceiverAllowed`, `pause`/`unpause`) |
| Receiver capability check | Receiver allowlist: settlement targets must be the owner or explicitly allowed (`setReceiverAllowed`) |
| Ephemeral payment option | `payEphemeral()` - same transfer, no storage write |
| Cheap object creation | `PaymentRegistryFactory` (CREATE2 + ERC-1967 proxies) |

**The one real architectural difference:** Sui's storage-rebate model makes long-lived receipts close to free; EVM storage is not. `PaymentRegistry` handles this with a reusable `expiresAt` mapping (one `SSTORE` per receipt) plus a permissionless `prune()` so expired receipts can be cleared once they're no longer needed. No off-chain indexing is required for the duplicate-prevention logic itself - that stays fully on-chain, same as the Sui version.

## Quick start

```bash
forge install
cp .env.example .env   # fill in PRIVATE_KEY + RPC URLs
forge build
forge test -vvv
```

## Deploying

Every chain below is pre-configured in `foundry.toml` under `[rpc_endpoints]`, with public fallback RPCs defined in the `Makefile` (`?=` defaults), so all make targets work even with an empty `.env`. Add your own provider URLs (see `.env.example`) for higher rate limits.

| Chain | Network | Chain ID | `make` slug |
|---|---|---|---|
| Ethereum | mainnet / Sepolia | 1 / 11155111 | `ethereum-mainnet` / `ethereum-testnet` |
| BNB Smart Chain | mainnet / testnet | 56 / 97 | `bnb-mainnet` / `bnb-testnet` |
| Arbitrum One | mainnet / Arbitrum Sepolia | 42161 / 421614 | `arbitrum-mainnet` / `arbitrum-testnet` |
| Base | mainnet / Base Sepolia | 8453 / 84532 | `base-mainnet` / `base-testnet` |
| OP Mainnet | mainnet / OP Sepolia | 10 / 11155420 | `op-mainnet` / `op-testnet` |
| **Monad** (primary target) | mainnet / testnet | 143 / 10143 | `monad-mainnet` / `monad-testnet` |
| Hyperliquid (HyperEVM) | mainnet / testnet | 999 / 998 | `hyperliquid-mainnet` / `hyperliquid-testnet` |
| Robinhood Chain (Orbit L2) | mainnet / testnet | 4663 / 46630 | `robinhood-mainnet` / `robinhood-testnet` |
| X Layer (OKX) | mainnet / testnet | 196 / 195 | `xlayer-mainnet` / `xlayer-testnet` |
| BOT Chain | mainnet / testnet | 677 / 968 | `botchain-mainnet` / `botchain-testnet` |

Every network gets four targets: `simulate-forwarder-*`, `simulate-factory-*` (dry runs - nothing broadcast) and `deploy-forwarder-*`, `deploy-factory-*` (real broadcasts):

```bash
# Monad testnet (start here): dry run first, then broadcast
make simulate-forwarder-monad-testnet
make simulate-factory-monad-testnet
make deploy-forwarder-monad-testnet
make deploy-factory-monad-testnet
```

The same pattern works for every chain/network above:

```bash
make simulate-factory-base-testnet
make deploy-factory-base-mainnet      # when you're ready for the real thing
```

Each deploy script writes its contract addresses to a JSON artifact keyed by chain and network:

```
deployments/
├── monad-testnet.json     { forwarder, implementation, factory, chainId, ... }
├── base-mainnet.json
└── ...
```

Keys accumulate across runs on the same network (forwarder today, factory tomorrow -> both land in one file), so downstream tooling can always read addresses from `deployments/{chain}-{network}.json`.

### Creating a registry from the factory

Once the factory is deployed, anyone can spin up their own registry cheaply:

```solidity
factory.createRegistry(
    adminAddress,      // owner of the new registry
    30 days,           // default receipt lifetime
    keccak256("my-app") // salt - deterministic address
);
```

## Integration

### Install

```bash
forge install the3rdweblabs/payment-kit.evm
```

Add the remapping to your `remappings.txt`:

```
payment-kit.evm/=lib/payment-kit.evm/
```

### Import

You only need the interface - no need to import the full implementation:

```solidity
import {IPaymentRegistry} from "payment-kit.evm/src/interfaces/IPaymentRegistry.sol";
```

The interface is just function signatures ([`IPaymentRegistry.sol`](src/interfaces/IPaymentRegistry.sol)) - your contract compiles against it and calls the deployed registry at runtime.

### How it works on-chain

Payment-kit deploys a **factory** once per chain. The factory creates cheap proxy registries on demand. Your contract calls the registry at the address you pass in your constructor - there's no code copying, just an external `CALL` to the deployed address.

```
Factory (deployed once)          Your contract
    │                                │
    ├── createRegistry() ──→ Proxy   │
    │                     (your      │
    │                      registry) │
    │                                │
    └──────────────────────────── registry.pay(...) ──→ executes on-chain
```

### Local testing

Deploy a registry in your test `setUp()` using the factory:

```solidity
import {Test} from "forge-std/Test.sol";
import {PaymentRegistryFactory} from "payment-kit.evm/src/PaymentRegistryFactory.sol";
import {IPaymentRegistry} from "payment-kit.evm/src/interfaces/IPaymentRegistry.sol";

contract MyTest is Test {
    IPaymentRegistry registry;

    function setUp() public {
        PaymentRegistryFactory factory = new PaymentRegistryFactory(address(0));
        factory.createRegistry(address(this), 30 days, keccak256("test"));
        registry = IPaymentRegistry(factory.getRegistry(address(this), keccak256("test")));
    }

    function test_pay_works() public {
        // your test using registry.pay(...)
    }
}
```

See [`test/PaymentRegistry.t.sol`](test/PaymentRegistry.t.sol) for real examples, including [gasless payments](test/GaslessPayment.t.sol) and [invariant tests](test/PaymentRegistryInvariants.t.sol).

### Production (point to deployed factory)

The factory is already deployed on every supported chain. You don't deploy payment-kit yourself - you call the factory to create your registry, then pass that address to your contract.

**Step 1:** Create your registry from the deployed factory:

```solidity
// call this on the factory at the address from deployments/monad-testnet.json
PaymentRegistryFactory(factory).createRegistry(
    address(this),        // owner of the registry
    30 days,              // default receipt lifetime
    keccak256("my-app")   // salt - deterministic address
);
```

**Step 2:** Pass the registry address to your contract's constructor:

```solidity
import {IPaymentRegistry} from "payment-kit.evm/src/interfaces/IPaymentRegistry.sol";

contract MyCheckout {
    IPaymentRegistry public immutable registry;

    constructor(address registry_) {
        registry = IPaymentRegistry(registry_);
    }

    function checkout(bytes32 orderId, address token, uint256 amount) external payable {
        registry.pay{value: msg.value}(orderId, token, address(this), amount, 0);
    }
}
```

The factory address is listed in [`deployments/monad-testnet.json`](deployments/monad-testnet.json):

```bash
cat deployments/monad-testnet.json
# { "factory": "0x5dE60c9D93b3b9031dd04647cBb92b92209B1884", ... }
```

See [Deploying](#deploying) for the full list of supported chains.

### Source files

| File | Purpose |
|---|---|
| [`src/PaymentRegistry.sol`](src/PaymentRegistry.sol) | Core contract - duplicate prevention, receipt expiry, receiver allowlist, UUPS upgrades |
| [`src/PaymentRegistryFactory.sol`](src/PaymentRegistryFactory.sol) | CREATE2 factory - deploys cheap proxy registries sharing one implementation |
| [`src/interfaces/IPaymentRegistry.sol`](src/interfaces/IPaymentRegistry.sol) | Interface other contracts import |
| [`src/libraries/PaymentTypes.sol`](src/libraries/PaymentTypes.sol) | Shared errors, events, receipt-key derivation |
| [`test/PaymentRegistry.t.sol`](test/PaymentRegistry.t.sol) | Full test suite - payments, duplicates, upgrades, allowlist |
| [`test/GaslessPayment.t.sol`](test/GaslessPayment.t.sol) | ERC-2771 meta-transaction example with duplicate prevention |
| [`test/PaymentRegistryInvariants.t.sol`](test/PaymentRegistryInvariants.t.sol) | Invariant campaigns - no double-spend, no custodial risk |
| [`test/PaymentRegistryFactory.t.sol`](test/PaymentRegistryFactory.t.sol) | Factory creation and proxy behavior |

## Gas payment model

By default, whoever calls `pay()`/`payEphemeral()` pays gas (`msg.sender`), same UX as calling a Sui entry function.

## Gasless payments

`PaymentRegistry` extends OZ's `ERC2771Context`. When a call arrives via a trusted `ERC2771Forwarder`, `_msgSender()` resolves to the original signer - not the relayer that broadcast the transaction - so a payer with zero native gas token can still sign a payment and have someone else's relayer submit it. This is the fix for the NGN-stablecoin UX problem: end users shouldn't need to hold ETH/MON just to pay in a stablecoin.

This is fully additive - direct calls (no forwarder) work exactly as before.

**1. Deploy a shared forwarder once per chain:**

```bash
make deploy-forwarder-monad-testnet
```

**2. Pass its address in when deploying the factory or a standalone registry** (set `TRUSTED_FORWARDER` in `.env`, or export it inline):

```bash
TRUSTED_FORWARDER=0xYourForwarderAddress make deploy-factory-monad-testnet
```

Pass `address(0)` (or leave `TRUSTED_FORWARDER` unset) to disable gasless payments for a given deploy - it's an opt-in per registry, baked into the implementation contract at deploy time.

**3. Payer signs, relayer submits:**

```solidity
// off-chain, payer signs an EIP-712 ForwardRequest targeting registry.pay(...)
// any relayer (funded with native gas) then calls:
forwarder.execute(signedRequest);
// -> registry sees _msgSender() == payer, pulls ERC20 tokens from the payer,
//    the relayer's wallet is the only one that spent gas
```

See [`test/GaslessPayment.t.sol`](test/GaslessPayment.t.sol) for a full worked example, including duplicate-prevention still holding under the gasless path.

## License

This project is licensed under the [GNU General Public License v3.0](./LICENSE).
