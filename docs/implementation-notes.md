# Implementation notes

## Allowance-backed fork

Based on Coinbase Spend Permissions revision `e0004e63edc4e17de7aa978293800ac7a16892e5`.

- The manager spends ERC-20s using the account's existing token allowance. Funds move directly from account to spender.
- Signatures use OpenZeppelin `SignatureChecker` over the manager's EIP-712 digest, supporting both EOAs and deployed ERC-1271 wallets. The domain is `Allowance Spend Permission Manager`, version `1`, with chain ID and verifying contract.
- Accounts with code, including EIP-7702 delegations, use ERC-1271 validation. ERC-6492 deployment wrappers are outside this fork's signature API.
- Signature validity is checked when approving. An ERC-1271 wallet subsequently changing its signature policy does not revoke an already-registered permission; explicit manager revocation or token-allowance removal controls further spending.
- `spendWithSignature` atomically registers a permission and spends. Repeated signatures preserve usage; revoked hashes cannot be reactivated.
- Periods and packed `uint48/uint48/uint160` usage accounting follow upstream. Usage is recorded before token interaction, and failed transfers roll back state.
- Limits meter requested transfer amounts. Token fees, rebases, and rounding may change actual debits or receipts.
- Native transfers, MagicSpend, smart-wallet execution, and the two-hop router are removed, together with their dependencies and tests.
- A token allowance of zero stops transfers without invalidating permissions. Restoring it permits spending under still-valid permissions.
- Upstream MIT attribution and audit PDFs are retained as provenance. The PDFs do not audit this fork.
- Foundry is pinned to Solidity 0.8.28 / Cancun, with optimization enabled and a CI profile of 1,024 runs per fuzz test. The Solady lock entry is corrected to match the actual upstream gitlink revision.
- The viem example includes Zod-validated single and batch typed-data builders. Its isolated Anvil flow compares both hashes against the contract and uses a uniquely named OpenZeppelin-based mock token to avoid upstream `MockERC20` artifact name collisions.
- CI runs Solidity formatting, build and fuzz tests, plus Bun lint, formatting, type checking, and the localhost integration.

## Verification

- `forge fmt` and `forge build --sizes`: pass; the default optimized manager runtime is 9,092 bytes.
- `FOUNDRY_PROFILE=ci forge test -vv`: 115 tests pass, zero failures or skips; 1,024 runs per fuzz test.
- EOA and ERC-1271 coverage includes single and batch approval, atomic spending, invalid/reverting/malformed contract signatures, signature-policy changes, explicit revocation, tampered fields, and cross-chain/cross-contract replay rejection.
- Transfer coverage includes finite allowances, removal/restoration, period resets, independent permissions, balance/allowance failures with rollback, USDT-style residual allowances, missing/false return values, missing token code, transfer fees, and reentrant overspending attempts.
- `forge snapshot --fuzz-seed 0x1 -q`: pass; refreshed gas snapshot for this fork's test suite.
- `bun run lint`, `bun run format:check`, and `bun run typecheck`: pass.
- `bun run example`: pass; single and batch EIP-712 hashes match, 12 mock token units are transferred across two periods, 18 units of the finite token allowance remain, and revocation prevents further spending. This uses only a disposable localhost Anvil node.
- `git diff --check`: pass.
