// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import {
    UniswapFlashLiquidation,
    ILiquidationPair,
    IUniswapV3StaticQuoter,
    IV3SwapRouter,
    IERC20
} from "../../src/UniswapFlashLiquidation.sol";

contract UniswapFlashLiquidationTest is Test {
    uint256 public optimismFork;
    address alice;

    // pUSDC.e liquidation pair on Optimism
    ILiquidationPair public liquidationPair = ILiquidationPair(0xe7680701a2794E6E0a38aC72630c535B9720dA5b);

    // Bridged USDC address on Optimism
    address constant USDCE = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

    // WETH address on Optimism
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // Uniswap V3 quoter contract
    IUniswapV3StaticQuoter public quoter;

    // Uniswap V3 Swap Router
    IV3SwapRouter public router;

    UniswapFlashLiquidation public flashLiquidation;

    function setUp() public {
        uint256 _blockNumber = 112811454;
        console2.log("block number:", _blockNumber);
        optimismFork = vm.createFork(vm.rpcUrl("optimism"), _blockNumber);
        console2.log("fork created");

        alice = makeAddr("alice");

        vm.selectFork(optimismFork);
        assertEq(block.number, _blockNumber);

        console2.log("fork selected");

        quoter = IUniswapV3StaticQuoter(0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE);
        router = IV3SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        flashLiquidation = new UniswapFlashLiquidation(quoter, router);
    }

    function testFlashLiquidate() external {
        address _tokenIn = liquidationPair.tokenIn();
        address _tokenOut = liquidationPair.tokenOut();

        // bytes memory _swapPath = abi.encodePacked(
        //     _tokenOut,
        //     uint24(100), // 0.01% fee tier
        //     USDCE,
        //     uint24(10000), // 1% fee tier
        //     _tokenIn
        // );

        bytes memory _swapPath = abi.encodePacked(
            _tokenOut,
            uint24(100), // 0.01% fee tier
            USDCE,
            uint24(500), // 0.05% fee tier
            WETH,
            uint24(3000), // 0.30% fee tier
            _tokenIn
        );

        UniswapFlashLiquidation.ProfitInfo memory profitInfo = flashLiquidation.getProfitInfoStatic(
            5977934,
            liquidationPair,
            _swapPath
        );
        console2.log("amount out", profitInfo.amountOut);
        console2.log("amount in", profitInfo.amountIn);
        console2.log("profit", profitInfo.profit);
        console2.log("success", profitInfo.success);

        uint256 _gasStartSearch = gasleft();
        UniswapFlashLiquidation.ProfitInfo memory bestProfitInfo = flashLiquidation.findBestQuoteStatic(
            liquidationPair,
            _swapPath
        );
        console2.log("gas used for search:", _gasStartSearch - gasleft());
        console2.log("best amount out", bestProfitInfo.amountOut);
        console2.log("best amount in", bestProfitInfo.amountIn);
        console2.log("best profit", bestProfitInfo.profit);
        console2.log("best is success", bestProfitInfo.success);

        assertGe(bestProfitInfo.profit, profitInfo.profit);

        uint256 _gasStart = gasleft();
        uint256 _tokenInProfit = flashLiquidation.flashLiquidate(
            liquidationPair,
            alice,
            bestProfitInfo.amountOut,
            bestProfitInfo.amountIn,
            bestProfitInfo.profit,
            block.timestamp + 300, // current timestamp + 5 minutes
            _swapPath
        );
        console2.log("gas used:", _gasStart - gasleft());

        assertEq(IERC20(_tokenIn).balanceOf(alice), _tokenInProfit);

        UniswapFlashLiquidation.ProfitInfo memory newBestProfitInfo = flashLiquidation.findBestQuoteStatic(
            liquidationPair,
            _swapPath
        );
        assertEq(newBestProfitInfo.success, false);
    }
}
