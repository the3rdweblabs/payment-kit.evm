# Security Policy

## Reporting a vulnerability

The payment-kit.evm contracts are intended to hold and route real value.
Please report security vulnerabilities **privately** - do not open a public
issue for anything you believe is exploitable.

Preferred channels:

1. Open a private GitHub Security Advisory on this repository (recommended), or
2. Email [the3rdweblabs@gmail.com](mailto:the3rdweblabs@gmail.com).

Please include:

- A clear description of the issue and how to reproduce it (minimal PoC if possible)
- The affected component (`PaymentRegistry`, `PaymentRegistryFactory`, deploy scripts)
- The commit / version you tested against
- Any relevant logs or transaction hashes

**Never** include private keys, seeds, or other live secrets in a report.

## What's in scope

- Reentrancy or double-payment paths through `pay`/`payEphemeral`
- Receiver-allowlist bypasses
- Upgrade-mechanism weaknesses (UUPS authorization, storage collisions)
- Duplicate-prevention bypasses (receipt key collisions, expiry races)
- Prune/expiry griefing
- Gas-griefing that could brick settlement flows
- ERC-2771 forwarder trust assumptions

Out of scope: misconfigured deployments by integrators (wrong owner, leaked
private keys), and bugs in third-party dependencies reported upstream.

## Handling and timeline

- Acknowledgment within 72 hours
- Triage and severity assessment within 7 days
- Fix or mitigation timeline communicated once triaged
- Coordinated disclosure after the fix ships; credit given to reporters who ask for it
