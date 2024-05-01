// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ERC4626 } from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { IFlashSwapCallback } from "pt-v5-liquidator-interfaces/IFlashSwapCallback.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IUniswapV2Pair } from "./interfaces/uniswap-v2/IUniswapV2Pair.sol";

error PairNotFoundInFactory();

error NotWethPair();

contract UniswapV2WethPairFlashLiquidator is IFlashSwapCallback {
    
    IERC20 public immutable weth;

    constructor (
        IERC20 _weth
    ) {
        weth = _weth;
    }

    function isValidLiquidationPair(ILiquidationPair _pair) public view returns (bool) {
        ERC4626 prizeVault = ERC4626(ILiquidationPair(_pair).tokenOut());
        getLpAssets(IUniswapV2Pair(prizeVault.asset()));
        return true;
    }

    function getLpAssets(IUniswapV2Pair uniswapLp) public view returns (IERC20 token0, IERC20 token1) {
        token0 = IERC20(uniswapLp.token0());
        token1 = IERC20(uniswapLp.token1());
        if (address(token0) != address(weth) && address(token1) != address(weth)) {
            revert NotWethPair();
        }
    }

    function flashSwapExactAmountOut(
        ILiquidationPair _pair,
        address _receiver,
        uint256 _swapAmountOut,
        uint256 _minProfit
    ) external returns (uint256) {
        _pair.swapExactAmountOut(address(this), _swapAmountOut, type(uint256).max, abi.encode("flash!"));
        IERC20 tokenIn = IERC20(_pair.tokenIn());
        uint256 profit = tokenIn.balanceOf(address(this));
        require(profit >= _minProfit, "UniversalRouterFlashLiquidator: INSUFFICIENT_OUTPUT_AMOUNT");
        tokenIn.transfer(
            _receiver,
            profit
        );
        return profit;
    }

    function flashSwapCallback(
        address _sender,
        uint256 _amountIn,
        uint256 _amountOut,
        bytes calldata _flashSwapData
    ) external {
        ERC4626 prizeVault = ERC4626(ILiquidationPair(msg.sender).tokenOut());
        prizeVault.withdraw(_amountOut, address(this), address(this));
        IUniswapV2Pair lp = IUniswapV2Pair(prizeVault.asset());
        (IERC20 token0, IERC20 token1) = getLpAssets(lp);
        lp.transfer(address(lp), lp.balanceOf(address(this)));
        (uint amount0, uint amount1) = lp.burn(address(this));
        (uint112 reserve0, uint112 reserve1,) = lp.getReserves();
        if (address(token1) != address(weth)) {
            // if token1 is not weth, then dump it
            uint256 wethAmountOut = getAmountOut(amount1, reserve1, reserve0);
            token1.transfer(address(lp), amount1);
            lp.swap(wethAmountOut, 0, address(this), "");
        } else {
            uint256 wethAmountOut = getAmountOut(amount0, reserve0, reserve1);
            token0.transfer(address(lp), amount0);
            lp.swap(0, wethAmountOut, address(this), "");
        }
        IERC20(ILiquidationPair(msg.sender).tokenIn()).transfer(
            ILiquidationPair(msg.sender).target(),
            _amountIn
        );
    }

    // NOTE: Copied from https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

}
