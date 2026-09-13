#!/usr/bin/env bash
#
# Build the EIP-712 SpendPermission typed data, signature digest, and calldata.
#
# The manager uses this digest for approveWithSignature/spendWithSignature and
# getHash. It is also the `message` hash produced by eth_signTypedData_v4 over
# the same domain and struct.
#
# Usage:
#   permission-tool.sh digest   --chain 8453 [--manager 0x...] --account 0x... --spender 0x... \
#                               --token 0x... --allowance 100000000 --period 604800 \
#                               --start <unix> --end <unix> [--salt 1] [--extra-data 0x]
#   permission-tool.sh typed    ... same args ...        # prints ready-to-use eth_signTypedData_v4 JSON
#   permission-tool.sh calldata ... same args ... --value 100000000 --signature 0x...
#
# Requires: cast (Foundry).
set -euo pipefail

CHAIN=8453
MANAGER=0x764159aa8a59b3fff39115c64a2b75c9c094ebe2
SALT=1
EXTRA_DATA=0x
MODE=${1:-}
shift || true

ACCOUNT="" SPENDER="" TOKEN="" ALLOWANCE="" PERIOD="" START="" END="" VALUE="" SIGNATURE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --chain) CHAIN="$2"; shift 2;;
    --manager) MANAGER="$2"; shift 2;;
    --account) ACCOUNT="$2"; shift 2;;
    --spender) SPENDER="$2"; shift 2;;
    --token) TOKEN="$2"; shift 2;;
    --allowance) ALLOWANCE="$2"; shift 2;;
    --period) PERIOD="$2"; shift 2;;
    --start) START="$2"; shift 2;;
    --end) END="$2"; shift 2;;
    --salt) SALT="$2"; shift 2;;
    --extra-data) EXTRA_DATA="$2"; shift 2;;
    --value) VALUE="$2"; shift 2;;
    --signature) SIGNATURE="$2"; shift 2;;
    *) echo "unknown argument: $1" >&2; exit 1;;
  esac
done

for name in ACCOUNT SPENDER TOKEN ALLOWANCE PERIOD START END; do
  [ -n "${!name}" ] || { echo "missing --$(echo "$name" | tr 'A-Z_' 'a-z-')" >&2; exit 1; }
done

TYPEHASH=$(cast keccak 'SpendPermission(address account,address spender,address token,uint160 allowance,uint48 period,uint48 start,uint48 end,uint256 salt,bytes extraData)')
STRUCTHASH=$(cast keccak "$(cast abi-encode 'f(bytes32,address,address,address,uint160,uint48,uint48,uint48,uint256,bytes32)' \
  "$TYPEHASH" "$ACCOUNT" "$SPENDER" "$TOKEN" "$ALLOWANCE" "$PERIOD" "$START" "$END" "$SALT" "$(cast keccak "$EXTRA_DATA")")")
DOMAIN=$(cast keccak "$(cast abi-encode 'f(bytes32,bytes32,bytes32,uint256,address)' \
  "$(cast keccak 'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')" \
  "$(cast keccak 'Allowance Spend Permission Manager')" \
  "$(cast keccak '1')" \
  "$CHAIN" "$MANAGER")")
DIGEST=$(cast keccak "$(cast concat-hex 0x1901 "$DOMAIN" "$STRUCTHASH")")

case "$MODE" in
  digest)
    echo "digest=$DIGEST"
    echo "domain_separator=$DOMAIN"
    echo "struct_hash=$STRUCTHASH"
    ;;
  typed)
    # Mask to uint48/uint160/uint256 so signatures cover the same values the contract hashes.
    exec python3 - "$CHAIN" "$MANAGER" "$ACCOUNT" "$SPENDER" "$TOKEN" "$ALLOWANCE" "$PERIOD" "$START" "$END" "$SALT" "$EXTRA_DATA" <<'PY'
import json, sys
chain, manager, account, spender, token, allowance, period, start, end, salt, extra = sys.argv[1:12]
print(json.dumps({
    "types": {
        "EIP712Domain": [
            {"name": "name", "type": "string"},
            {"name": "version", "type": "string"},
            {"name": "chainId", "type": "uint256"},
            {"name": "verifyingContract", "type": "address"},
        ],
        "SpendPermission": [
            {"name": "account", "type": "address"},
            {"name": "spender", "type": "address"},
            {"name": "token", "type": "address"},
            {"name": "allowance", "type": "uint160"},
            {"name": "period", "type": "uint48"},
            {"name": "start", "type": "uint48"},
            {"name": "end", "type": "uint48"},
            {"name": "salt", "type": "uint256"},
            {"name": "extraData", "type": "bytes"},
        ],
    },
    "primaryType": "SpendPermission",
    "domain": {
        "name": "Allowance Spend Permission Manager",
        "version": "1",
        "chainId": int(chain),
        "verifyingContract": manager,
    },
    "message": {
        "account": account,
        "spender": spender,
        "token": token,
        "allowance": str(int(allowance)),
        "period": str(int(period)),
        "start": str(int(start)),
        "end": str(int(end)),
        "salt": str(int(salt)),
        "extraData": extra,
    },
}))
PY
    ;;
  calldata)
    [ -n "$VALUE" ] || { echo "missing --value" >&2; exit 1; }
    [ -n "$SIGNATURE" ] || { echo "missing --signature" >&2; exit 1; }
    PERM="($ACCOUNT,$SPENDER,$TOKEN,$ALLOWANCE,$PERIOD,$START,$END,$SALT,$EXTRA_DATA)"
    echo "spendWithSignature=$(cast calldata 'spendWithSignature((address,address,address,uint160,uint48,uint48,uint48,uint256,bytes),uint160,bytes)' "$PERM" "$VALUE" "$SIGNATURE")"
    echo "approveWithSignature=$(cast calldata 'approveWithSignature((address,address,address,uint160,uint48,uint48,uint48,uint256,bytes),bytes)' "$PERM" "$SIGNATURE")"
    echo "spend=$(cast calldata 'spend((address,address,address,uint160,uint48,uint48,uint48,uint256,bytes),uint160)' "$PERM" "$VALUE")"
    echo "revoke=$(cast calldata 'revoke((address,address,address,uint160,uint48,uint48,uint48,uint256,bytes))' "$PERM")"
    ;;
  *)
    echo "usage: $0 {digest|typed|calldata} --account ... --spender ... --token ... --allowance ... --period ... --start ... --end ..." >&2
    exit 1
    ;;
esac
