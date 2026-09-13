# Project instructions

- This is a Foundry Solidity project for allowance-backed ERC-20 spend permissions with EOA and ERC-1271 signatures.
- Before changing code, read `docs/implementation-notes.md`, `docs/SpendPermissionAccounting.md`, and any relevant planning documentation in `docs/`.
- Update `docs/implementation-notes.md` with implementation decisions and verification results before committing. Keep these notes free of personal information.
- Use OpenZeppelin and Solady library components rather than custom cryptography or token-transfer helpers.
- Preserve checks-effects-interactions: record spending before calling an ERC-20. Failed transfers must roll back all permission changes.
- Use named imports, custom errors, named Solidity call arguments where supported, and NatSpec for public APIs and new tests.
- Keep tests in `test/src/<Area>/`, shared fixtures in `test/base/`, and mocks in `test/mocks/`. Exercise real token balances and allowances in transfer tests.
- Run `forge fmt`, `forge build --sizes`, and `forge test -vv` after Solidity changes. Run Foundry commands on the host, outside a sandbox.
- Use Bun for the viem example. Run its configured lint, format, typecheck, and integration checks after TypeScript changes. Validate external inputs with Zod.
- Use `onchain` and `offchain` in documentation. Put documentation other than this file and the README in `docs/`.
- Never commit `.env.local`, private keys, or generated build artifacts.
- Preserve the upstream MIT license and attribution. Upstream audit reports describe upstream revisions, not this fork.
- Use conventional commit messages.
