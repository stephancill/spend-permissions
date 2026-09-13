---
name: spend-permissions
description: Request, use, and manage allowance-backed ERC-20 spend permissions for EOA and ERC-1271 wallets. Use when a user or app wants to grant recurring ERC-20 spending authority (for example "let this app spend 100 USDC per week on Base"), sign or verify a spend-permission EIP-712 payload, execute or automate a spend, check a permission's remaining budget, or revoke a permission. Covers generating signatures and transaction calldata with Foundry `cast`, executing with txlink, and reading chain state from evm.stupidtech.net.
---

# Spend Permissions

Grant a spender recurring, bounded authority to pull ERC-20 tokens from an account using the account's ordinary token allowance.

Two independent authorizations are always required:

1. **Token allowance** — the account calls `token.approve(manager, amount)`. This is per token, shared by all permissions, and does not reset.
2. **Spend permission** — the account signs an EIP-712 `SpendPermission` naming one spender, one token, and a per-period budget.

A spender can move funds only when **both** cover the amount, and only within the permission's time window.

## Fixed deployment

Same manager address on every chain:

```text
manager: 0x764159aa8a59b3fff39115c64a2b75c9c094ebe2
```

Signatures use this EIP-712 domain:

```text
name:              Allowance Spend Permission Manager
version:           1
chainId:           target chain id
verifyingContract: 0x764159aa8a59b3fff39115c64a2b75c9c094ebe2
```

Live on Base, Base Sepolia, Arbitrum One, OP Mainnet, and Polygon. See [references/deployments.md](references/deployments.md) for chain IDs and common token addresses. RPCs use `https://evm.stupidtech.net/v1/<chainId>`.

## Permission fields

| Field | Type | Meaning |
| --- | --- | --- |
| `account` | address | Account funding the spend (the token holder) |
| `spender` | address | Only address allowed to execute spends; also the recipient |
| `token` | ERC-20 address | Token being spent; native/ERC-721 rejected |
| `allowance` | uint160 | Max **requested** amount per period, in raw token units |
| `period` | uint48 | Reset interval in seconds |
| `start` / `end` | uint48 | Validity window; `start` inclusive, `end` exclusive |
| `salt` | uint256 | Distinguishes otherwise-identical permissions |
| `extraData` | bytes | Signed metadata; the manager never interprets it |

Periods are fixed windows anchored to `start` (`[start, start+period)`, then the next window, etc.). Unused budget never rolls over. Total spend is capped at `type(uint160).max`.

## Workflow

### 0. Gather inputs

Resolve addresses and amounts before building anything. Confirm the token, chain ID, account, and **the spender's address** (the permission is useless to any other caller).

```sh
RPC=https://evm.stupidtech.net/v1/8453
MANAGER=0x764159aa8a59b3fff39115c64a2b75c9c094ebe2
USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913   # Base USDC, 6 decimals
ACCOUNT=0xYourAccount
SPENDER=0xAppSpender

# uint48 max, used as "no expiry" for end
END=281474976710655

# Start at the latest block time; add lead time if the tx may be delayed
START=$(cast block latest --field timestamp --rpc-url $RPC)
```

Token amounts are raw units. Always convert with `cast to-unit` / `parseUnits` semantics:

```sh
cast to-unit 100e6 wei      # 100 USDC at 6 decimals -> 100000000
```

### 1. Account approves the token to the manager

```sh
cast calldata 'approve(address,uint256)' $MANAGER 100000000
```

Send with txlink (one `eth_sendTransaction` to the USDC contract):

```sh
curl -sS -X POST https://txlink.stupidtech.net/api/requests \
  -H 'content-type: application/json' \
  --data '{"address":"0xYourAccount","method":"eth_sendTransaction","chainId":8453,"params":{"to":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","data":"<approve calldata>","value":"0x0"}}'
```

The response contains `url` (open it for the user) and `statusUrl` (poll until `status` is `completed`). Token allowance is a finite, shared budget; a permission can spend across periods only while it remains.

### 2. Account signs the permission (offchain)

Build the digest, the typed data, and the calldata with the bundled script. It reproduces `getHash` exactly.

```sh
scripts/permission-tool.sh digest \
  --chain 8453 --account $ACCOUNT --spender $SPENDER --token $USDC \
  --allowance 100000000 --period 604800 --start $START --end $END --salt 1
```

**Verify before signing:** the printed `digest` must equal the onchain value.

```sh
cast call $MANAGER \
  'getHash((address,address,address,uint160,uint48,uint48,uint48,uint256,bytes))' \
  "($ACCOUNT,$SPENDER,$USDC,100000000,604800,$START,$END,1,0x)" \
  --rpc-url $RPC
```

Sign with the account. For an EOA, use `eth_signTypedData_v4` and the JSON from the script:

```sh
scripts/permission-tool.sh typed \
  --chain 8453 --account $ACCOUNT --spender $SPENDER --token $USDC \
  --allowance 100000000 --period 604800 --start $START --end $END --salt 1
```

```sh
# txlink stored request for the signature
curl -sS -X POST https://txlink.stupidtech.net/api/requests \
  -H 'content-type: application/json' \
  --data "$(python3 - <<'PY'
import json, subprocess
typed = json.loads(subprocess.run(
    ["scripts/permission-tool.sh","typed","--chain","8453","--account","$ACCOUNT",
     "--spender","$SPENDER","--token","$USDC","--allowance","100000000",
     "--period","604800","--start","$START","--end","$END","--salt","1"],
    capture_output=True, text=True, check=True).stdout)
print(json.dumps({"address":"$ACCOUNT","method":"eth_signTypedData_v4",
                  "chainId":8453,"params":{"typedData":typed}}))
PY
)"
```

`eth_signTypedData_v4` returns a signature over exactly the digest computed in step 2. Store the `SpendPermission` field values, their signature, chain ID, and the manager address; the spender needs all of them.

For an ERC-1271 contract wallet, produce whatever signature its `isValidSignature(bytes32,bytes)` expects for the same digest, and set `account` to the wallet's address. Note that the token approval in step 1 must also come from the wallet contract.

### 3. Spender spends

`msg.sender` must equal `permission.spender`. The first spend can register the permission and spend atomically:

```sh
scripts/permission-tool.sh calldata \
  --chain 8453 --account $ACCOUNT --spender $SPENDER --token $USDC \
  --allowance 100000000 --period 604800 --start $START --end $END --salt 1 \
  --value 100000000 --signature 0x<signature>
```

Use the emitted `spendWithSignature=` calldata. Send it to the manager from the spender's wallet through txlink (`eth_sendTransaction`, `to` = manager). After approval, later spends use the `spend=` calldata (no signature required) or `spendWithSignature` with the same signature again — replaying cannot reset usage or undo revocation.

Every spend must satisfy: caller is `spender`, permission approved and not revoked, current time inside `[start, end)`, requested value + period spend <= `allowance`, and enough token allowance and balance.

### 4. Check and manage

```sh
# current period boundaries and cumulative spend (reverts before start / after end)
cast call $MANAGER 'getCurrentPeriod((address,address,address,uint160,uint48,uint48,uint48,uint256,bytes))' \
  "($ACCOUNT,$SPENDER,$USDC,100000000,604800,$START,$END,1,0x)" --rpc-url $RPC

# stored status: approved and not revoked
cast call $MANAGER 'isValid((address,address,address,uint160,uint48,uint48,uint48,uint256,bytes))' \
  "($ACCOUNT,$SPENDER,$USDC,100000000,604800,$START,$END,1,0x)" --rpc-url $RPC

# funding checks
cast call $USDC 'allowance(address,address)(uint256)' $ACCOUNT $MANAGER --rpc-url $RPC
cast call $USDC 'balanceOf(address)(uint256)' $ACCOUNT --rpc-url $RPC
```

`isValid` does **not** check time, budget, allowance, or balance. Always simulate or read all four before promising a spend.

**Revoke** (account, permanently cancels that permission hash; also works before it is ever used):

```sh
cast calldata 'revoke((address,address,address,uint160,uint48,uint48,uint48,uint256,bytes))' \
  "($ACCOUNT,$SPENDER,$USDC,100000000,604800,$START,$END,1,0x)"
```

**Revoke as spender**: same calldata with `revokeAsSpender((...))`, sent by the spender.

**Pause all spending for a token**: `token.approve(manager, 0)`. This stops transfers but does not revoke permissions; restoring allowance reactivates still-valid ones with their existing usage.

**Replace a permission atomically**: send `approveWithRevoke(new, old, expectedLastUpdatedPeriod)` from the account. Read `expectedLastUpdatedPeriod` from `getLastUpdatedPeriod`. It reverts if the old permission's usage changed.

## Critical pitfalls

- **Caller must be the exact `spender`.** A signature is worthless to any other address. This is the most common integration error.
- **Two budgets.** A spend needs both enough token allowance and enough period budget. Approving 100 USDC once does not fund a 100-USDC/period permission indefinitely.
- **Requested, not received.** Limits meter the requested `transferFrom` amount. Fee-on-transfer tokens may deliver less, sender-fee tokens may debit more, and rebasing tokens may round.
- **Signatures are reusable.** Reuse authorizes further spends inside the same budget; it is not one-time. Track payment IDs offchain to avoid duplicate charges on retries.
- **Revocation is permanent per hash** and can cancel a signed-but-unused permission. Restoring token allowance cannot revive a revoked hash.
- **Amounts are per period.** For "per month", choose a fixed number of seconds (30 days = 2592000, 31 days = 2678400); there is no calendar-month concept.
- **Nonzero salt matters.** Changing any field, including `salt`, creates a different, independent permission. Use a unique salt per grant.
- **Native tokens and ERC-721s are unsupported.** Use WETH as an ERC-20 if needed.
- **ERC-1271 policy changes do not revoke registered permissions.** Use the manager's revocation API or remove the token allowance.

## References

- [references/api.md](references/api.md) — full function list, selectors, struct layouts, errors
- [references/deployments.md](references/deployments.md) — deployed addresses, chain IDs, common ERC-20s, RPC base URL
- [references/edge-cases.md](references/edge-cases.md) — lifecycle details, batch approvals, replacement, token quirks
- `scripts/permission-tool.sh` — computes the EIP-712 digest, typed data, and calldata with exact parity to the contract
