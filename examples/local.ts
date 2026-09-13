import assert from "node:assert/strict";
import { createServer } from "node:net";
import {
  createPublicClient,
  createTestClient,
  createWalletClient,
  erc20Abi,
  hashTypedData,
  http,
  parseAbi,
  parseUnits,
  type Hash,
  type Hex,
} from "viem";
import { mnemonicToAccount } from "viem/accounts";
import { foundry } from "viem/chains";
import { z } from "zod";
import {
  getSpendPermissionBatchTypedData,
  getSpendPermissionTypedData,
  managerAbi,
} from "./permissions";

// Public Anvil development mnemonic, used only on the disposable localhost node spawned below.
const mnemonic = "test test test test test test test test test test test junk";

async function getAvailablePort() {
  const server = createServer();
  return new Promise<number>((resolve, reject) => {
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      assert(address && typeof address === "object");
      server.close((error) => (error ? reject(error) : resolve(address.port)));
    });
  });
}

async function getBytecode({ artifact }: { artifact: string }) {
  const data: unknown = await Bun.file(new URL(`../out/${artifact}`, import.meta.url)).json();
  return z
    .object({
      bytecode: z.object({
        object: z.custom<Hex>(
          (value) => typeof value === "string" && /^0x[0-9a-fA-F]+$/.test(value),
        ),
      }),
    })
    .parse(data).bytecode.object;
}

const port = await getAvailablePort();
const anvil = Bun.spawn(
  ["anvil", "--host", "127.0.0.1", "--port", String(port), "--hardfork", "cancun", "--silent"],
  {
    stdout: "ignore",
    stderr: "pipe",
  },
);

try {
  const transport = http(`http://127.0.0.1:${port}`, { retryCount: 0, timeout: 1000 });
  const publicClient = createPublicClient({ chain: foundry, transport, pollingInterval: 50 });
  let ready = false;
  for (let attempt = 0; attempt < 100; attempt++) {
    if (anvil.exitCode !== null) throw new Error(await new Response(anvil.stderr).text());
    try {
      assert.equal(await publicClient.getChainId(), foundry.id);
      ready = true;
      break;
    } catch {
      await Bun.sleep(50);
    }
  }
  assert(ready, "Anvil did not become ready");

  const owner = mnemonicToAccount(mnemonic, { addressIndex: 0 });
  const spender = mnemonicToAccount(mnemonic, { addressIndex: 1 });
  const ownerClient = createWalletClient({ account: owner, chain: foundry, transport });
  const spenderClient = createWalletClient({ account: spender, chain: foundry, transport });
  const testClient = createTestClient({ mode: "anvil", chain: foundry, transport });

  async function confirmed({ hash }: { hash: Hash }) {
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    assert.equal(receipt.status, "success");
    return receipt;
  }

  const managerReceipt = await confirmed({
    hash: await ownerClient.deployContract({
      abi: managerAbi,
      bytecode: await getBytecode({
        artifact: "SpendPermissionManager.sol/SpendPermissionManager.json",
      }),
    }),
  });
  assert(managerReceipt.contractAddress);
  const managerAddress = managerReceipt.contractAddress;

  const tokenAbi = [
    ...erc20Abi,
    ...parseAbi(["function mint(address to, uint256 value)"]),
  ] as const;
  const tokenReceipt = await confirmed({
    hash: await ownerClient.deployContract({
      abi: tokenAbi,
      bytecode: await getBytecode({ artifact: "MockAllowanceToken.sol/MockAllowanceToken.json" }),
    }),
  });
  assert(tokenReceipt.contractAddress);
  const tokenAddress = tokenReceipt.contractAddress;

  await confirmed({
    hash: await ownerClient.writeContract({
      address: tokenAddress,
      abi: tokenAbi,
      functionName: "mint",
      args: [owner.address, parseUnits("30", 6)],
    }),
  });

  // The ERC-20 approval is a separate, finite allowance shared by all permissions for this token.
  await confirmed({
    hash: await ownerClient.writeContract({
      address: tokenAddress,
      abi: tokenAbi,
      functionName: "approve",
      args: [managerAddress, parseUnits("30", 6)],
    }),
  });

  const start = Number((await publicClient.getBlock()).timestamp);
  const typedData = getSpendPermissionTypedData({
    managerAddress,
    chainId: foundry.id,
    permission: {
      account: owner.address,
      spender: spender.address,
      token: tokenAddress,
      allowance: parseUnits("10", 6),
      period: 86400,
      start,
      end: start + 3 * 86400,
      salt: 123n,
      extraData: "0x112233",
    },
  });
  const permission = typedData.message;
  const onchainHash = await publicClient.readContract({
    address: managerAddress,
    abi: managerAbi,
    functionName: "getHash",
    args: [permission],
  });
  assert.equal(hashTypedData(typedData), onchainHash);

  const batchData = getSpendPermissionBatchTypedData({
    managerAddress,
    chainId: foundry.id,
    batch: {
      account: owner.address,
      period: permission.period,
      start,
      end: permission.end,
      permissions: [permission, { ...permission, salt: 124n, extraData: "0xabcd" }],
    },
  });
  assert.equal(
    hashTypedData(batchData),
    await publicClient.readContract({
      address: managerAddress,
      abi: managerAbi,
      functionName: "getBatchHash",
      args: [batchData.message],
    }),
  );

  const signature = await ownerClient.signTypedData(typedData);
  await confirmed({
    hash: await spenderClient.writeContract({
      address: managerAddress,
      abi: managerAbi,
      functionName: "spendWithSignature",
      args: [permission, parseUnits("4", 6), signature],
    }),
  });
  await confirmed({
    hash: await spenderClient.writeContract({
      address: managerAddress,
      abi: managerAbi,
      functionName: "spend",
      args: [permission, parseUnits("6", 6)],
    }),
  });
  await assert.rejects(
    publicClient.simulateContract({
      address: managerAddress,
      abi: managerAbi,
      functionName: "spendWithSignature",
      args: [permission, 1n, signature],
      account: spender.address,
    }),
    /ExceededSpendPermission/,
  );

  // The next period restores the permission budget, but not the master token allowance.
  await testClient.increaseTime({ seconds: 86400 });
  await testClient.mine({ blocks: 1 });
  await confirmed({
    hash: await spenderClient.writeContract({
      address: managerAddress,
      abi: managerAbi,
      functionName: "spend",
      args: [permission, parseUnits("2", 6)],
    }),
  });
  assert.equal(
    await publicClient.readContract({
      address: tokenAddress,
      abi: tokenAbi,
      functionName: "balanceOf",
      args: [spender.address],
    }),
    parseUnits("12", 6),
  );
  assert.equal(
    await publicClient.readContract({
      address: tokenAddress,
      abi: tokenAbi,
      functionName: "allowance",
      args: [owner.address, managerAddress],
    }),
    parseUnits("18", 6),
  );
  assert.equal(
    (
      await publicClient.readContract({
        address: managerAddress,
        abi: managerAbi,
        functionName: "getCurrentPeriod",
        args: [permission],
      })
    ).spend,
    parseUnits("2", 6),
  );

  await confirmed({
    hash: await ownerClient.writeContract({
      address: managerAddress,
      abi: managerAbi,
      functionName: "revoke",
      args: [permission],
    }),
  });
  await assert.rejects(
    publicClient.simulateContract({
      address: managerAddress,
      abi: managerAbi,
      functionName: "spend",
      args: [permission, 1n],
      account: spender.address,
    }),
    /UnauthorizedSpendPermission/,
  );

  console.log(
    "Local integration passed: typed-data hashes, approval, signing, spending, period reset, and revocation.",
  );
  console.log({
    managerAddress,
    tokenAddress,
    transferred: "12 USD",
    remainingTokenAllowance: "18 USD",
  });
} finally {
  anvil.kill();
  await anvil.exited;
}
