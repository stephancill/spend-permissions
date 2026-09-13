# Deployments

`SpendPermissionManager` is deployed at the same address on every chain using the canonical CREATE2 deployment proxy.

```text
manager address:        0x764159aa8a59b3fff39115c64a2b75c9c094ebe2
create2 deployer:       0x4e59b44847b379578588920cA78FbF26c0B4956C
salt:                   0x0000000000000000000000000000000000000000000000000000000000000000
initcode hash:          0xb79235b56934c3da59a2658ee85b9a08ba2f8df43fc28f0b0e36eb1da01c8012
```

## Deployed

| Chain | Chain ID | Status | Verified | Transaction |
| --- | --- | --- | --- | --- |
| Base Sepolia | 84532 | deployed | yes | `0xe7434cfd8d84d0c74f440f47bdd11e2507c47e4681746f5232f1937a93953d7b` |
| Base | 8453 | deployed | yes | `0xebf38657785a9e9bedad9de0387e799bac2316c39875def291b30ab6fb071e83` |
| Arbitrum One | 42161 | deployed | yes | `0x3c8b10ee1fac42710f94126049ad671ec8858d3b85e2e661becbd92d74654f07` |
| OP Mainnet | 10 | deployed | yes | `0x371fcbde25a3db663495532bd6cdaf7b1d26385242a2960638df32f65c4fb6c1` |
| Polygon | 137 | deployed | yes | `0x6901b4654b0dee598c025fd3259ca47d0ab6db7bb12015fbd7125d00836c6f52` |
| Ethereum | 1 | pending gas funding | — | — |
| BNB Chain | 56 | pending gas funding | — | — |

## Verification

All five deployments are verified as exact matches on their block explorers.

| Chain | Explorer |
| --- | --- |
| Base Sepolia | https://sepolia.basescan.org/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2#code |
| Base | https://basescan.org/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2#code |
| Arbitrum One | https://arbiscan.io/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2#code |
| OP Mainnet | https://optimistic.etherscan.io/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2#code |
| Polygon | https://polygonscan.com/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2#code |

- Deployment used the `deploy` Foundry profile (Solidity 0.8.28, Cancun, optimizer 999,999 runs).
- Each chain's runtime code was compared against the reviewed build artifact. Non-immutable bytes match exactly; the only differences are the immutable slots the compiler patches at deployment, which include the per-chain `address(this)` and the derived EIP-712 domain separator.
- Each deployed contract returns the expected `eip712Domain()` with name `Allowance Spend Permission Manager`, version `1`, the correct chain ID, and the manager as `verifyingContract`.
- The reported deployment gas was approximately 2,535,107 (Arbitrum One).
- The first Arbitrum attempt (`0x3668c972a392e3bcb5bd7507c68472567ff00c020b2b457cce4885cae4a2b197`) was submitted but never included. A replacement transaction with the same calldata was mined at `0x3c8b10ee1fac42710f94126049ad671ec8858d3b85e2e661becbd92d74654f07`. Because the CREATE2 address depends only on the deployer, salt, and init code, the result was unaffected.

## Signature domain

```text
name:              Allowance Spend Permission Manager
version:           1
chainId:           target chain ID
verifyingContract: 0x764159aa8a59b3fff39115c64a2b75c9c094ebe2
```
