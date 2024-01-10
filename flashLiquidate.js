import { createPublicClient, createWalletClient, http, encodePacked } from 'viem'
import { privateKeyToAccount } from 'viem/accounts';
import { optimism } from 'viem/chains'
import UniswapFlashLiquidation from "./out/UniswapFlashLiquidation.sol/UniswapFlashLiquidation.json" assert { type: "json" };

const lpAddress = process.argv[2];

const swapPathArray = process.argv[3].split("/");
const pathAbiParams = ["address"];
for(let i = 1; i < swapPathArray.length; i += 2) {
  pathAbiParams.push("uint24");
  pathAbiParams.push("address");
  if (swapPathArray[i]) {
    swapPathArray[i] = parseInt(swapPathArray[i]);
  }
}
const swapPath = encodePacked(pathAbiParams, swapPathArray);

const minPoolOut = BigInt(Math.floor(parseFloat(process.argv[4]) * (10 ** 18)));

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
    lpAddress, // LP
    swapPath // swap path
  ]
});

console.log(bestProfit);

if (bestProfit.success && bestProfit.profit > minPoolOut) { // > 1 POOL
  const args = [
    lpAddress, // LP
    signer.account.address,
    bestProfit.amountOut,
    (bestProfit.amountIn * 101n) / 100n, // +1% slippage
    (bestProfit.profit * 99n) / 100n, // -1% slippage
    BigInt(Date.now()) / 1000n + 60n, // +1 min
    swapPath // swap path
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