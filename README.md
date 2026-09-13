# Allowance Spend Permissions

Recurring ERC-20 spending permissions for **EOAs and ERC-1271 wallets**, funded by ordinary token allowances.

Forked from [Coinbase Spend Permissions](https://github.com/coinbase/spend-permissions) at [`e0004e6`](https://github.com/coinbase/spend-permissions/tree/e0004e63edc4e17de7aa978293800ac7a16892e5).

## How it works

1. The account calls `token.approve(manager, amount)` on each ERC-20 it wants to make available. A finite allowance works; unlimited approval is optional.
2. The account signs an EIP-712 permission naming a spender, token, per-period allowance, start/end times, and salt.
3. The spender calls `spendWithSignature(permission, value, signature)` to register the permission and spend atomically.
4. Subsequent calls to `spend(permission, value)` use the registered permission. Only the named spender can make either spending call.
5. The manager records usage and calls `token.transferFrom(account, spender, value)` through OpenZeppelin `SafeERC20`. Tokens travel directly from account to spender.

The ERC-20 allowance is shared across permissions for that account/token/manager. Each permission has its own recurring budget. A spend must fit both allowances and the account's balance.

## Permission format

```solidity
struct SpendPermission {
    address account;
    address spender;
    address token;
    uint160 allowance;
    uint48 period;
    uint48 start;
    uint48 end;
    uint256 salt;
    bytes extraData;
}
```

Amounts are in the token's smallest units. Times are Unix seconds. `start` is inclusive and `end` is exclusive. Periods are fixed intervals anchored to `start`, not rolling windows or calendar months; unused allowance does not carry over.

`salt` differentiates permissions. Changing any field creates an independent permission, rather than updating an existing one. `extraData` is signed metadata; the manager does not interpret it or use it to choose a recipient.

### Signatures

The EIP-712 domain is:

```text
name:              Allowance Spend Permission Manager
version:           1
chainId:           target chain ID
verifyingContract: deployed manager address
```

OpenZeppelin `SignatureChecker` validates ordinary EOA signatures and deployed wallets' ERC-1271 signatures. Accounts with code, including EIP-7702 delegations, use ERC-1271 validation. ERC-6492 deployment wrappers are not supported.

EOAs sign this typed data directly. Contract wallets supply the signature their ERC-1271 implementation expects for the same digest. The signature authorizes a reusable permission, not one particular payment. Replaying it cannot reset usage or undo revocation.

## API

| Function | Purpose |
| --- | --- |
| `approve(permission)` | Account directly registers a permission |
| `approveWithSignature(permission, signature)` | Anyone registers an EOA or ERC-1271 signed permission |
| `approveBatchWithSignature(batch, signature)` | Registers a batch sharing account, period, start, and end |
| `spend(permission, value)` | Named spender uses an approved permission |
| `spendWithSignature(permission, value, signature)` | Named spender registers and spends atomically |
| `revoke(permission)` | Account permanently revokes a permission hash |
| `revokeAsSpender(permission)` | Named spender permanently revokes its permission |
| `approveWithRevoke(new, old, expectedLastUpdatedPeriod)` | Account replaces a permission if the old usage still matches |
| `getHash` / `getBatchHash` | EIP-712 digests for signatures and indexing |
| `getCurrentPeriod` / `getLastUpdatedPeriod` | Current or last recorded usage |
| `isApproved` / `isRevoked` / `isValid` | Stored authorization status |

Approval functions return `false` for previously revoked permissions. Batch approval may approve valid entries while returning `false` if another entry is revoked; malformed entries revert the whole batch. Duplicate entries are idempotent.

`isValid` checks approval and revocation only. It does not check time bounds, remaining period budget, token allowance, or balance. `SpendPermissionUsed` reports the incremental requested amount; the period getters report cumulative usage. Discover permissions through approval/revocation events; the contract does not enumerate them.

## Revocation and token behavior

- `revoke` can cancel a signed permission before it has been submitted. Its hash stays revoked permanently.
- Setting a token's allowance to zero stops transfers but does not revoke permissions. Restoring allowance makes still-valid permissions usable again, with their existing period usage.
- ERC-1271 signature-policy changes do not revoke already-registered permissions. Use the manager's revocation API or remove the token allowance.
- Revocation takes effect when executed; an authorized spender can still use its available budget before the revocation transaction executes.
- Standard ERC-20s, including WETH, work without a token registry or EIP-2612 support. `SafeERC20` accommodates no-return tokens and rejects failed transfers and targets without code. USDT-style approvals may require the account to approve zero before increasing an existing token allowance.
- Limits count the **requested transfer amount**. Fee-on-transfer tokens may deliver less, sender-fee tokens may debit more, and rebasing/share-based tokens may round. A successful call is not an exact-receipt guarantee for such tokens.
- Native-token sentinels and tokens advertising the ERC-721 interface are rejected. ERC-165 checks cannot identify every nonstandard NFT contract.

## Develop and verify

Install Foundry v1.7.1 and Bun v1.3.14, then:

```sh
git submodule update --init
bun install --frozen-lockfile
forge fmt --check
forge build --sizes
FOUNDRY_PROFILE=ci forge test -vv
bun run lint
bun run format:check
bun run typecheck
bun run example
```

`bun run example` starts a disposable Anvil node on an available localhost port, deploys the manager and a mock ERC-20, and checks typed-data hashing, finite approval, signing, spending limits, period reset, and revocation. It shuts down its node afterward. Run `forge build` first to generate artifacts.

Reusable typed-data builders, input schemas, and an ABI are in [`examples/permissions.ts`](examples/permissions.ts); the complete flow is in [`examples/local.ts`](examples/local.ts). The helpers work with viem EOA clients or wallet-specific ERC-1271 signing flows.

## Deployment and upstream compatibility

The sole production contract is [`src/SpendPermissionManager.sol`](src/SpendPermissionManager.sol). It has no constructor arguments, owner, proxy, or external validator deployment. No public deployment addresses are published yet. Use the `deploy` Foundry profile to build production verification artifacts.

This fork changes the execution model and EIP-712 domain. Coinbase's existing token approvals, signatures, deployment addresses, smart-wallet ownership setup, MagicSpend flows, and router are not compatible with it.

The upstream [audit reports](audits/) are retained as historical references; they do not audit this fork. See [accounting](docs/SpendPermissionAccounting.md), [workflows](docs/workflows.md), and [implementation notes](docs/implementation-notes.md) for details.

## License

[MIT](LICENSE.md), preserving Coinbase's copyright and attribution.
