# Spend Permission Accounting

## Onchain Accounting

Tracking asset expenditure accurately is important for enforcing user-approved limits. Given the fragility and complications with doing this accounting offchain and the severity of inaccuracies, we designed for fully onchain accounting. Onchain accounting enables us to have higher confidence in its reliability and keep our system trust-minimized.
The accounting for each spend permission is stored in a single slot, via a mapping keyed by the hash of its struct values.
A spend permission contains 3 entity values:

1. `account`: user whose tokens will be spent
1. `spender`: app who is able to spend tokens
1. `token`: ERC-20 contract

A spend permission contains 4 accounting values:

1. `start`: time this permission is valid starting at
1. `end`: time this permission is valid until
1. `period`: duration of a recurring interval that resets the `spender`'s allowance
1. `allowance`: amount of tokens spendable per period

## Recurring Accounting

Spend permissions allow an app to request to spend user assets on a recurring basis (e.g. 10 USDC / month). As apps spend user assets, the recurring logic automatically increments and enforces the allowance for the current period. Once enough time passes to enter the next period, the allowance usage is reset to zero and the app can keep spending up to the same allowance.

This design allows users and apps to have reduced friction in approving asset use, while still giving the user control to manage risk and keep asset allowance small upfront. This design is also intuitive for users and can easily support recurring models like subscriptions, automated trading strategies, and payroll.

The start time and period set a deterministic schedule for when allowance usage resets to zero. The end time enforces when the permission can no longer be used and does not have to correlate with a clean period boundary.
Consider this example configuration:

```
start = 0
end = 1000
period = 100
allowance = 100
```

This configuration would produce the following period-size ranges each with their own allowance:

```
[0, 99], [100, 199], [200, 299], ...
```

When a new spend is attempted, the contract first determines what the current period range is. If the current time falls within the period of last stored use, we simply check if this new usage will exceed the allowance.

```
new spend=25 @ t=0
period = [0, 99]
allowance = 0 + 25 = 25,
overspend = 25 > 100 = false

new spend=25 @ t=50
period = [0, 99]
allowance = 25 + 25 = 50
overspend = 50 > 100 = false
```

If the current time exceeds the period of last stored use, that means we are in a new period and should reset the allowance to zero and then add our new attempted spend.

```
new spend=25 @ t=0
period = [0, 99]
allowance = 0 + 25 = 25,
overspend = 25 > 100 = false

new spend=25 @ t=150
period = [100, 199]
allowance = 0 + 25 = 25
overspend = 25 > 100 = false
```

## ERC-20 allowance and transfer accounting

The account separately approves the manager on the ERC-20. This token allowance is shared across all permissions for the account/token/manager and does not reset with the recurring period. For a standard token, each spend is limited by the current period's remaining budget, the remaining token allowance, and the account's balance.

Usage counts the requested `transferFrom` amount in raw token units. It does not measure balance differences. Token-specific transfer fees, rebases, and rounding can change actual debits or receipts. No token decimals or price oracle is consulted by the manager.

Usage is updated before the external token call. A revert or false token return rolls back that update and any approval made by `spendWithSignature`. The manager transfers directly from account to spender and never needs to hold tokens between calls.

Unused budget does not accumulate. The full allowance can be used immediately before a period boundary and again immediately after it. Separate permission hashes have separate budgets, even if the token and spender are the same. Repeated approvals of the same hash do not reset usage.

`SpendPermissionUsed.periodSpend.spend` is the incremental spend in that event. `getCurrentPeriod` and `getLastUpdatedPeriod` return cumulative period usage. `isValid` only checks approved/not-revoked status.
