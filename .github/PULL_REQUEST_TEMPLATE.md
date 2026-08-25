<!--
  Thank you for contributing! PR titles should follow Conventional Commits:
  feat: | fix: | docs: | perf: | refactor: | test: | chore: (append ! for breaking)
-->

## Description

<!-- What does this PR change and why? Link issues with "Fixes #123". -->

## Type of change

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Refactor / gas optimization
- [ ] Documentation only

## Checklist

- [ ] I have read [CONTRIBUTING.md](../CONTRIBUTING.md)
- [ ] `make ci-local` passes locally (mirrors CI: fmt check, build, tests, via_ir)
- [ ] Added/updated tests that prove my change works (happy path + reverts)
- [ ] NatSpec on all public/external functions
- [ ] If `PaymentRegistry` storage layout changed: gap adjusted and upgrade compatibility explained
- [ ] Gas-sensitive changes include before/after numbers from `make snapshot`
- [ ] README/docs updated where behavior is user-visible
