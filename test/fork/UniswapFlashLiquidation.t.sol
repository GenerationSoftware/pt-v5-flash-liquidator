// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";

import { IUniswapV3StaticQuoter } from "../interfaces/IUniswapV3StaticQuoter.sol";

import {
    UniswapFlashLiquidation,
    ILiquidationPair,
    IUniversalRouter,
    IERC20
} from "../../src/UniswapFlashLiquidation.sol";

contract UniswapFlashLiquidationTest is Test {
    uint256 public optimismFork;
    address alice;

    // pUSDC.e liquidation pair on Optimism
    ILiquidationPair public liquidationPair = ILiquidationPair(0xe7680701a2794E6E0a38aC72630c535B9720dA5b);

    // Bridged USDC address on Optimism
    address constant USDCE = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

    // Uniswap V3 quoter contract
    IUniswapV3StaticQuoter public uniswapV3Quoter = IUniswapV3StaticQuoter(0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE);

    // Uniswap Universal Router v1.2 on Optimism
    IUniversalRouter public universalRouter = IUniversalRouter(0xeC8B0F7Ffe3ae75d7FfAb09429e3675bb63503e4);
    bytes1 constant V3_SWAP_EXACT_IN = bytes1(0x00);

    UniswapFlashLiquidation public flashLiquidation;

    function setUp() public {
        uint256 _blockNumber = 112101787;
        optimismFork = vm.createFork(vm.rpcUrl("optimism"), _blockNumber);

        alice = makeAddr("alice");

        vm.selectFork(optimismFork);
        assertEq(block.number, _blockNumber);

        flashLiquidation = new UniswapFlashLiquidation(universalRouter);
    }

    function testFlashLiquidate() external {
        address _tokenIn = liquidationPair.tokenIn();
        address _tokenOut = liquidationPair.tokenOut();

        bytes memory _swapPath = abi.encodePacked(
            _tokenOut,
            uint24(100), // 0.01% fee tier
            USDCE,
            uint24(10000), // 1% fee tier
            _tokenIn
        );

        bytes memory _swapPathInToOut = abi.encodePacked(
            _tokenIn,
            uint24(10000), // 1% fee tier
            USDCE,
            uint24(100), // 0.01% fee tier
            _tokenOut
        );

        (, /* uint256 _maxAmountOut */ uint256 _maxAmountIn) = flashLiquidation.previewMaxAmount(liquidationPair);

        // We estimate the `amountOut` of `tokenOut` we need to swap to be able
        // to contribute `maxAmountIn` of `tokenIn` to the PrizePool
        uint256 _amountOut = uniswapV3Quoter.quoteExactInput(_swapPathInToOut, _maxAmountIn);

        bytes[] memory _swapInput = new bytes[](1);
        _swapInput[0] = abi.encode(address(flashLiquidation), _amountOut, 0, _swapPath, false);

        uint256 _tokenInProfit = flashLiquidation.flashLiquidate(
            liquidationPair,
            alice,
            _amountOut,
            _maxAmountIn,
            0, // we don't expect to make a profit
            abi.encodePacked(V3_SWAP_EXACT_IN),
            _swapInput,
            block.timestamp + 1800 // current timestamp + 30 minutes
        );

        assertEq(IERC20(_tokenIn).balanceOf(alice), _tokenInProfit);
    }
}
