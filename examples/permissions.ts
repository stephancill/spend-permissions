import { getAddress, isAddress, parseAbi, type Hex } from "viem";
import { z } from "zod";

const addressSchema = z
  .string()
  .refine((value) => isAddress(value), "Invalid address")
  .transform((value) => getAddress(value));
const nonzeroAddressSchema = addressSchema.refine(
  (value) => value !== "0x0000000000000000000000000000000000000000",
  "Address must be nonzero",
);
const hexSchema = z.custom<Hex>(
  (value) => typeof value === "string" && /^0x(?:[0-9a-fA-F]{2})*$/.test(value),
  "Invalid hex bytes",
);
const uint48Schema = z
  .number()
  .int()
  .min(0)
  .max(2 ** 48 - 1);
const timing = {
  period: uint48Schema.min(1),
  start: uint48Schema,
  end: uint48Schema,
};
const details = {
  spender: nonzeroAddressSchema,
  token: nonzeroAddressSchema.refine(
    (value) => value.toLowerCase() !== "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    "Native tokens are unsupported",
  ),
  allowance: z
    .bigint()
    .min(1n)
    .max((1n << 160n) - 1n),
  salt: z
    .bigint()
    .min(0n)
    .max((1n << 256n) - 1n),
  extraData: hexSchema,
};

export const spendPermissionSchema = z
  .object({
    account: nonzeroAddressSchema,
    ...timing,
    ...details,
  })
  .refine(({ start, end }) => start < end, "Start must be before end");

export const spendPermissionBatchSchema = z
  .object({
    account: nonzeroAddressSchema,
    ...timing,
    permissions: z.array(z.object(details)).min(1),
  })
  .refine(({ start, end }) => start < end, "Start must be before end");

export type SpendPermission = z.infer<typeof spendPermissionSchema>;

const permissionDetailsFields = [
  { name: "spender", type: "address" },
  { name: "token", type: "address" },
  { name: "allowance", type: "uint160" },
  { name: "salt", type: "uint256" },
  { name: "extraData", type: "bytes" },
] as const;

export const spendPermissionTypes = {
  SpendPermission: [
    { name: "account", type: "address" },
    { name: "spender", type: "address" },
    { name: "token", type: "address" },
    { name: "allowance", type: "uint160" },
    { name: "period", type: "uint48" },
    { name: "start", type: "uint48" },
    { name: "end", type: "uint48" },
    { name: "salt", type: "uint256" },
    { name: "extraData", type: "bytes" },
  ],
} as const;

function getDomain({ chainId, managerAddress }: { chainId: number; managerAddress: string }) {
  return {
    name: "Allowance Spend Permission Manager",
    version: "1",
    chainId: z.number().int().positive().max(Number.MAX_SAFE_INTEGER).parse(chainId),
    verifyingContract: nonzeroAddressSchema.parse(managerAddress),
  } as const;
}

/** Construct typed data for an EOA or for a wallet's ERC-1271 signing flow. */
export function getSpendPermissionTypedData({
  chainId,
  managerAddress,
  permission,
}: {
  chainId: number;
  managerAddress: string;
  permission: unknown;
}) {
  return {
    domain: getDomain({ chainId, managerAddress }),
    types: spendPermissionTypes,
    primaryType: "SpendPermission",
    message: spendPermissionSchema.parse(permission),
  } as const;
}

/** Construct a batch signature with the same nested-struct hashing as the contract. */
export function getSpendPermissionBatchTypedData({
  chainId,
  managerAddress,
  batch,
}: {
  chainId: number;
  managerAddress: string;
  batch: unknown;
}) {
  return {
    domain: getDomain({ chainId, managerAddress }),
    types: {
      PermissionDetails: permissionDetailsFields,
      SpendPermissionBatch: [
        { name: "account", type: "address" },
        { name: "period", type: "uint48" },
        { name: "start", type: "uint48" },
        { name: "end", type: "uint48" },
        { name: "permissions", type: "PermissionDetails[]" },
      ],
    },
    primaryType: "SpendPermissionBatch",
    message: spendPermissionBatchSchema.parse(batch),
  } as const;
}

export const managerAbi = parseAbi([
  "struct SpendPermission { address account; address spender; address token; uint160 allowance; uint48 period; uint48 start; uint48 end; uint256 salt; bytes extraData; }",
  "struct PermissionDetails { address spender; address token; uint160 allowance; uint256 salt; bytes extraData; }",
  "struct SpendPermissionBatch { address account; uint48 period; uint48 start; uint48 end; PermissionDetails[] permissions; }",
  "struct PeriodSpend { uint48 start; uint48 end; uint160 spend; }",
  "function approve(SpendPermission spendPermission) returns (bool)",
  "function approveWithSignature(SpendPermission spendPermission, bytes signature) returns (bool)",
  "function approveBatchWithSignature(SpendPermissionBatch spendPermissionBatch, bytes signature) returns (bool)",
  "function approveWithRevoke(SpendPermission permissionToApprove, SpendPermission permissionToRevoke, PeriodSpend expectedLastUpdatedPeriod) returns (bool)",
  "function spend(SpendPermission spendPermission, uint160 value)",
  "function spendWithSignature(SpendPermission spendPermission, uint160 value, bytes signature)",
  "function revoke(SpendPermission spendPermission)",
  "function revokeAsSpender(SpendPermission spendPermission)",
  "function getHash(SpendPermission spendPermission) view returns (bytes32)",
  "function getBatchHash(SpendPermissionBatch spendPermissionBatch) view returns (bytes32)",
  "function getCurrentPeriod(SpendPermission spendPermission) view returns (PeriodSpend)",
  "function getLastUpdatedPeriod(SpendPermission spendPermission) view returns (PeriodSpend)",
  "function isApproved(SpendPermission spendPermission) view returns (bool)",
  "function isRevoked(SpendPermission spendPermission) view returns (bool)",
  "function isValid(SpendPermission spendPermission) view returns (bool)",
  "error InvalidSignature()",
  "error UnauthorizedSpendPermission()",
  "error ExceededSpendPermission(uint256 value, uint256 allowance)",
]);
