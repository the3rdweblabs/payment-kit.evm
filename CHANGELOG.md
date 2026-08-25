# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0](https://github.com/the3rdweblabs/payment-kit.evm/compare/v1.0.0...v1.1.0) (2026-08-25)


### Features

* **factory:** add CREATE2 factory for deterministic registry deploys ([8dd05a0](https://github.com/the3rdweblabs/payment-kit.evm/commit/8dd05a0043c60e1edf90174f1c6736a1f58afbed))
* **registry:** add UUPS-upgradeable PaymentRegistry with receiver allowlist ([a7119f9](https://github.com/the3rdweblabs/payment-kit.evm/commit/a7119f9e8b2bbc8aacc7d8401d42bbfec129021d))
* **script:** add registry, forwarder, and factory deployment scripts ([30dae81](https://github.com/the3rdweblabs/payment-kit.evm/commit/30dae81739ee6c7d518988002b2a253f2f7209d4))

## [Unreleased]

- Initial release: `PaymentRegistry` (UUPS-upgradeable, receiver allowlist,
  pause switch, ERC-2771 gasless support), `PaymentRegistryFactory`
  (CREATE2 + ERC-1967 proxies), multi-chain deploy tooling.
