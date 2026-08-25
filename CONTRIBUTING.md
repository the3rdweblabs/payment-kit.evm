# Contributing to payment-kit.evm

First off, thank you for considering a contribution. This project is an
open-source, EVM-compatible port of [MystenLabs/sui-payment-kit](https://github.com/MystenLabs/sui-payment-kit),
and every PR - from a one-line doc fix to a new payment primitive - is welcome.

## Ways to contribute

- **Bug reports** - open an issue using the bug report template
- **Feature requests** - open an issue using the feature request template
- **Documentation** - typos, clarifications, examples, translations
- **New chains** - see [Adding a chain](#adding-a-chain)
- **Code** - new features, refactors, gas optimizations, test coverage

For security vulnerabilities, **do not open a public issue** - follow
[SECURITY.md](./SECURITY.md).

## Development setup

Prerequisites: [Foundry](https://book.getfoundry.sh/getting-started/installation) and git.

```bash
# clone with submodules (forge-std + OpenZeppelin)
git clone --recursive https://github.com/the3rdweblabs/payment-kit.evm
cd payment-kit.evm

# or, if you cloned without --recursive:
git submodule update --init --recursive

make build
make test
```

The full suite (including invariant campaigns) takes roughly a minute.

## Commands

| Command | What it does |
|---|---|
| `make ci-local` | **Run everything CI runs** - fmt check, build, tests, via_ir profile. Use this before every push. |
| `make build` | Compile with Solc `0.8.36` (pinned in `foundry.toml`) |
| `make test` | Run the full test suite verbosely (`-vvv`) |
| `make fmt` | Format all Solidity sources with `forge fmt` |
| `make clean` | Remove build artifacts |
| `FOUNDRY_PROFILE=via_ir make build` | Build through the IR pipeline (CI parity) |
| `make snapshot` | Generate a gas usage report (written to `.gas-snapshot`) |

## Code style

- Formatting is enforced by `forge fmt` in CI - run `make fmt` before committing.
- Every public/external function needs NatSpec (`@notice`, `@param`, `@return`).
- Custom errors: `UpperCamelCase`, named after what went wrong
  (`ZeroAmount`, `ReceiverNotAllowed`). Declare them next to the code that
  throws them.
- Events: past tense (`PaymentProcessed`, `ReceiptPruned`).
- Internal helpers live close to their callers; keep the file layout
  documented at the top of `src/PaymentRegistry.sol`.
- Storage layout changes to `PaymentRegistry` are breaking: they require a
  matching `__gap` adjustment and an explicit upgrade-compatibility note in
  the PR description.

## Testing rules

Every change that touches `src/` must come with tests:

1. **Happy path** proving the new behavior.
2. **Revert cases** for each new error condition (`vm.expectRevert`).
3. **State assertions** where relevant (e.g. "registry never custodies funds").

All existing tests must pass, including the invariant suite in
`test/PaymentRegistryInvariants.t.sol`. If your change makes an invariant
fail, the invariant wins - fix the contract, not the test, unless you can
argue convincingly in the PR why the guarantee no longer applies.

Gas-sensitive changes should include before/after numbers from `make snapshot`.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/) - releases
are automated by release-please, which parses commit messages to decide the
next version and write the changelog:

```
feat: add batch payments            -> minor bump
fix: prune reverts on unknown key   -> patch bump
docs: expand gasless section        -> no release
perf: cache receipt key derivation  -> patch bump
feat!: change pay() signature       -> major bump (breaking)
```

Scope suffixes are optional but encouraged for clarity: `fix(factory):`,
`test(registry):`, etc.

## Pull requests

1. Fork, then create a feature branch from `main`.
2. Keep PRs small and focused - one logical change per PR.
3. Fill out the PR template; tick every checkbox that applies.
4. Make sure CI is green locally first: **`make ci-local`** - it mirrors the
   GitHub Actions workflow exactly (formatting check, build, full test suite,
   via_ir profile), so if it passes on your machine, CI will pass.
5. New behavior needs new tests (see rules above); bug fixes need a test that
   fails without the fix.
6. A maintainer will review; address feedback in follow-up commits.
7. PRs are squash-merged - the PR title becomes the commit message, so give it
   a conventional-commit title.

## Adding a chain

1. Add two entries (mainnet/testnet) under `[rpc_endpoints]` in `foundry.toml`,
   using the `${ENV_VAR:-public-fallback}` pattern so deploys work without `.env`.
2. Add `[etherscan]` entries if the explorer supports verification.
3. Add the four make targets per network in the `Makefile`
   (`simulate-forwarder-*`, `simulate-factory-*`, `deploy-forwarder-*`,
   `deploy-factory-*`), keeping the chain order comment in sync.
4. Add the chain to the table in `README.md`.
5. Simulate before you broadcast: `make simulate-factory-{chain}-testnet`.

## Licensing

By contributing you agree that your contributions will be licensed under the
[GPL-3.0 license](./LICENSE) that covers this project.
