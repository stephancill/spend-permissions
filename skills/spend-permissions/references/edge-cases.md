# Edge cases and lifecycle

## Approval

- `approve` must be called by `account`; `approveWithSignature` and `approveBatchWithSignature` can be submitted by anyone.
- Signatures are validated with OpenZeppelin `SignatureChecker`: ECDSA for EOAs, ERC-1271 for deployed contracts. Accounts with code (including EIP-7702 delegations) go through ERC-1271. ERC-6492 deployment wrappers are not supported.
- Approval is idempotent. Re-approving the same hash emits no new event and never resets usage.
- If a hash is already revoked, approval returns `false` without reverting and leaves it revoked. Revocation always wins over approval.
- `approveWithSignature` is unchecked replay-safe: resubmitting the same signature is a no-op once approved.
- A permission with no usage can be revoked before it is ever approved.

## Batch approvals

- A batch shares `account`, `period`, `start`, and `end` across all entries.
- Each entry produces its own permission hash and is spent individually with the normal functions.
- Return value is `true` only if every entry ends up approved and not revoked. If any entry was already revoked, the call still succeeds for the others but returns `false`.
- Entries are not deduplicated. Duplicate entries are idempotent.
- A malformed entry (zero allowance, invalid time range, etc.) reverts the entire batch.
- `getBatchHash` reverts on an empty batch.

## Spending

- `msg.sender` must equal `permission.spender` for `spend` and `spendWithSignature`; otherwise `InvalidSender`.
- `value` must be nonzero (`ZeroValue`).
- A spend requires: `isValid` (approved, not revoked), `block.timestamp` in `[start, end)`, and `periodSpend + value <= allowance`.
- The period is computed from `start` as fixed windows. Unused budget does not accumulate. A full budget can be spent just before a boundary and again just after.
- `getCurrentPeriod` reverts before `start` (`BeforeSpendPermissionStart`) and at/after `end` (`AfterSpendPermissionEnd`). Use `getLastUpdatedPeriod` for a non-reverting read.
- Usage is recorded before the token call. A revert or `false` return rolls back usage and any approval made in the same call.
- `spendWithSignature` registers and spends atomically. If the transfer fails, the permission is not approved.
- The same signature can be reused for multiple spends within the budget. It cannot reset usage or revive a revoked permission.

## Revocation and replacement

- `revoke` (account) and `revokeAsSpender` (spender) are permanent per hash.
- Revocation takes effect when mined. A spender can still spend its available budget up to that point; this cannot be fully prevented.
- Setting the token allowance to zero stops transfers but does not revoke permissions. Restoring allowance revives still-valid permissions with their prior usage.
- ERC-1271 wallets changing their signature policy do not revoke already-registered permissions. Revoke explicitly or remove token allowance.
- `approveWithRevoke(new, old, expectedLastUpdatedPeriod)` atomically revokes one permission and approves another, from the account. It reverts with `InvalidLastUpdatedPeriod` if the old permission's usage changed since the snapshot, blocking frontrunning of further spend. The two permissions must share `account`; all other fields may differ. Read the snapshot with `getLastUpdatedPeriod`.

## Token behavior

- Limits count the requested `transferFrom` amount, not the amount received.
- Fee-on-transfer tokens deliver less than requested; sender-fee tokens debit more; rebasing/share tokens may round. A successful spend is not an exact-receipt guarantee.
- Standard ERC-20s, including WETH, work with no registry or EIP-2612 requirement. `SafeERC20` handles no-return tokens and rejects failed transfers and addresses with no code.
- USDT-style tokens reject changing a nonzero allowance; approve zero first.
- Native-token sentinels (`0xEeee…EEeE`) and tokens advertising ERC-721 are rejected. ERC-165 checks cannot catch every nonstandard NFT contract.
- The manager holds no tokens between calls and has no payable path.

## Integration notes

- `isValid` only means approved and not revoked. Always also check time, remaining period budget (`getCurrentPeriod`), token allowance, and balance before promising a spend.
- `SpendPermissionUsed` reports incremental usage; period getters report cumulative usage. Index events to track permissions because there is no onchain enumeration.
- Distinct salts create independent permissions. Two permissions for the same token/spender have separate budgets but share the same token allowance.
