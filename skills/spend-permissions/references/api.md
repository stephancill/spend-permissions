# Spend Permission API

Manager: `0x764159aa8a59b3fff39115c64a2b75c9c094ebe2` on every supported chain.

## Structs

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

struct PeriodSpend {
    uint48 start;
    uint48 end;
    uint160 spend;
}

struct PermissionDetails {
    address spender;
    address token;
    uint160 allowance;
    uint256 salt;
    bytes extraData;
}

struct SpendPermissionBatch {
    address account;
    uint48 period;
    uint48 start;
    uint48 end;
    PermissionDetails[] permissions;
}
```

## Functions

| Selector | Signature |
| --- | --- |
| `0x33211c30` | `approve(SpendPermission) returns (bool)` |
| `0xb9ffc8e1` | `approveWithSignature(SpendPermission, bytes) returns (bool)` |
| `0x9ecae456` | `approveBatchWithSignature(SpendPermissionBatch, bytes) returns (bool)` |
| `0x7000882d` | `approveWithRevoke(SpendPermission, SpendPermission, PeriodSpend) returns (bool)` |
| `0x415a9735` | `spend(SpendPermission, uint160)` |
| `0xaa769dd8` | `spendWithSignature(SpendPermission, uint160, bytes)` |
| `0x78792f76` | `revoke(SpendPermission)` |
| `0xb2c2b019` | `revokeAsSpender(SpendPermission)` |
| `0xe0a00b79` | `getHash(SpendPermission) view returns (bytes32)` |
| `0xbb53ffc0` | `getBatchHash(SpendPermissionBatch) view returns (bytes32)` |
| `0x2c18d42e` | `getCurrentPeriod(SpendPermission) view returns (PeriodSpend)` |
| `0x54ab90c2` | `getLastUpdatedPeriod(SpendPermission) view returns (PeriodSpend)` |
| `0x9e16b82f` | `isApproved(SpendPermission) view returns (bool)` |
| `0x3a3c58e8` | `isRevoked(SpendPermission) view returns (bool)` |
| `0x7fae20b5` | `isValid(SpendPermission) view returns (bool)` |
| `0x84b0196e` | `eip712Domain() view returns (bytes1,string,string,uint256,address,bytes32,uint256[])` |

Typehash constants (public, useful for building hashes manually):

- `SPEND_PERMISSION_TYPEHASH = keccak256("SpendPermission(address account,address spender,address token,uint160 allowance,uint48 period,uint48 start,uint48 end,uint256 salt,bytes extraData)")`
- `SPEND_PERMISSION_BATCH_TYPEHASH = keccak256("SpendPermissionBatch(address account,uint48 period,uint48 start,uint48 end,PermissionDetails[] permissions)PermissionDetails(address spender,address token,uint160 allowance,uint256 salt,bytes extraData)")`

## Hash construction

Single permission (matches `getHash`):

```text
structHash = keccak256(abi.encode(
  SPEND_PERMISSION_TYPEHASH, account, spender, token, allowance,
  period, start, end, salt, keccak256(extraData)))
digest = keccak256(0x1901 || domainSeparator || structHash)
```

Domain separator:

```text
domainSeparator = keccak256(abi.encode(
  keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
  keccak256("Allowance Spend Permission Manager"),
  keccak256("1"),
  chainId,
  manager))
```

Batch: build each `PermissionDetails` struct hash with `PERMISSION_DETAILS_TYPEHASH = keccak256("PermissionDetails(address spender,address token,uint160 allowance,uint256 salt,bytes extraData)")`, concatenate them, and hash as the batch struct's `permissions` member. The batch has its own digest and signature; each resulting permission is then spent individually.

`scripts/permission-tool.sh digest` performs the single-permission computation and prints `digest`, `domain_separator`, and `struct_hash`.

## Events

```solidity
event SpendPermissionApproved(bytes32 indexed hash, SpendPermission spendPermission);
event SpendPermissionRevoked(bytes32 indexed hash, SpendPermission spendPermission);
event SpendPermissionUsed(
    bytes32 indexed hash, address indexed account, address indexed spender,
    address token, PeriodSpend periodSpend);
```

- `SpendPermissionUsed.periodSpend.spend` is the **incremental** amount for that call.
- `getCurrentPeriod` / `getLastUpdatedPeriod` return **cumulative** period usage.
- The contract does not enumerate permissions. Discover them by indexing approval/revocation events.

## Errors

| Selector | Error |
| --- | --- |
| `0xe1130dba` | `InvalidSender(address,address)` |
| `0x8baa579f` | `InvalidSignature()` |
| `0x282b9f97` | `UnauthorizedSpendPermission()` |
| `0xfd1ebc88` | `ExceededSpendPermission(uint256,uint256)` |
| `0x00a170cd` | `BeforeSpendPermissionStart(uint48,uint48)` |
| `0x4f0a481c` | `AfterSpendPermissionEnd(uint48,uint48)` |
| `0xb27ed7ef` | `SpendValueOverflow(uint256)` |
| `0x7c946ed7` | `ZeroValue()` |
| `0xad1991f5` | `ZeroToken()` |
| `0x1fac5b74` | `ZeroSpender()` |
| `0x8e01c48b` | `ZeroAllowance()` |
| `0x586e5acb` | `ZeroPeriod()` |
| `0x3a352008` | `InvalidStartEnd(uint48,uint48)` |
| `0xb10b947e` | `NativeTokenNotSupported()` |
| `0x712327f0` | `ERC721TokenNotSupported(address)` |
| `0xeca16db2` | `EmptySpendPermissionBatch()` |
| `0x4ce7715a` | `MismatchedAccounts(address,address)` |
| `0x5346b99e` | `InvalidLastUpdatedPeriod((uint48,uint48,uint160),(uint48,uint48,uint160))` |
| `0x5274afe7` | `SafeERC20FailedOperation(address)` |

## Approval validation rules

`_approve` (used by `approve`, `approveWithSignature`, `approveBatchWithSignature`, `approveWithRevoke`) enforces:

- `token != address(0)` (`ZeroToken`)
- `token != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` (`NativeTokenNotSupported`)
- token does not advertise ERC-721 (`ERC721TokenNotSupported`)
- `spender != address(0)` (`ZeroSpender`)
- `period != 0` (`ZeroPeriod`)
- `allowance != 0` (`ZeroAllowance`)
- `start < end` (`InvalidStartEnd`)

It returns `false` without reverting when the permission hash is already revoked, and is idempotent when already approved. `approveBatchWithSignature` does not deduplicate entries; duplicate entries are idempotent. A malformed entry reverts the whole batch.
