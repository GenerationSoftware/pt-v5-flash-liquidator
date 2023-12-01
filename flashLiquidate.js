import { createPublicClient, createWalletClient, http } from 'viem'
import { privateKeyToAccount } from 'viem/accounts';
import { optimism } from 'viem/chains'
import UniswapFlashLiquidation from "./out/UniswapFlashLiquidation.sol/UniswapFlashLiquidation.json" assert { type: "json" };

const flashLiquidatorAddress = "0x5927b63E88764D6250b7801eBfDEb7B6c1ac35d0";

const client = createPublicClient({
  chain: optimism,
  transport: http(process.env.OPTIMISM_RPC_URL),
})

const signer = createWalletClient({
  chain: optimism,
  transport: http(process.env.OPTIMISM_RPC_URL),
  account: privateKeyToAccount("0x" + process.env.PRIVATE_KEY)
})

const bestProfit = await client.readContract({
  address: flashLiquidatorAddress,
  abi: UniswapFlashLiquidation.abi,
  functionName: "findBestQuoteStatic",
  args: [
    process.argv[2], // LP
    process.argv[3] // swap path
  ]
});

console.log(bestProfit);

if (bestProfit.success && bestProfit.profit > 4n * 10n ** 17n) { // > 0.4 POOL
  const args = [
    process.argv[2], // LP
    signer.account.address,
    bestProfit.amountOut,
    (bestProfit.amountIn * 101n) / 100n, // +1%
    (bestProfit.profit * 99n) / 100n, // -1%
    BigInt(Date.now()) / 1000n + 60n, // +1 min
    process.argv[3] // swap path
  ];
  console.log(args);
  const res = await signer.writeContract({
    address: flashLiquidatorAddress,
    abi: UniswapFlashLiquidation.abi,
    functionName: "flashLiquidate",
    args,
    gas: 1_500_000n
  });
  console.log(res);
} else {
  console.log("not profitable...");
}