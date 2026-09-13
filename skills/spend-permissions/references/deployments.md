# Deployments

## Manager

```
0x764159aa8a59b3fff39115c64a2b75c9c094ebe2
```

Deployed deterministically through the canonical CREATE2 proxy at `0x4e59b44847b379578588920cA78FbF26c0B4956C` with salt `0x00…00`, so the address is identical on every chain.

| Chain | Chain ID | Explorer |
| --- | --- | --- |
| Base | 8453 | https://basescan.org/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2 |
| Base Sepolia | 84532 | https://sepolia.basescan.org/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2 |
| Arbitrum One | 42161 | https://arbiscan.io/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2 |
| OP Mainnet | 10 | https://optimistic.etherscan.io/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2 |
| Polygon | 137 | https://polygonscan.com/address/0x764159aa8a59b3fff39115c64a2b75c9c094ebe2 |

Ethereum (1) and BNB Chain (56) are not deployed yet.

All five are verified as exact matches on their explorers.

## RPC

```
https://evm.stupidtech.net/v1/<chainId>
```

Example: `https://evm.stupidtech.net/v1/8453` for Base. Use `cast call` and `cast block` against these endpoints for reads; use txlink for anything that needs a signature.

## Common ERC-20s

| Token | Chain | Address | Decimals |
| --- | --- | --- | --- |
| USDC | Base | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 6 |
| USDC | Base Sepolia | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | 6 |
| USDC | Arbitrum One | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | 6 |
| USDC | OP Mainnet | `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85` | 6 |
| USDC | Polygon | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` | 6 |
| USDT | Polygon | `0xc2132D05D31c914a87C6611C10748AEb04B58e8F` | 6 |
| USDT | Arbitrum One | `0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9` | 6 |
| USDT | OP Mainnet | `0x94b008aA00579c1307B0EF2c499aD98a8ce58e58` | 6 |
| DAI | Base | `0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb` | 18 |
| WETH | Base | `0x4200000000000000000000000000000000000006` | 18 |
| WETH | OP Mainnet | `0x4200000000000000000000000000000000000006` | 18 |

USDT-style tokens require allowance `0` before increasing an existing nonzero allowance (`token.approve(manager, 0)` first).

Always confirm decimals and address on the target chain before building a permission. USDC has 6 decimals, so `100 USDC = 100000000`.

## Signature domain

```
name:              Allowance Spend Permission Manager
version:           1
chainId:           <target chain id>
verifyingContract: 0x764159aa8a59b3fff39115c64a2b75c9c094ebe2
```
