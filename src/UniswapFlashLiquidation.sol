// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { IFlashSwapCallback } from "pt-v5-liquidator-interfaces/IFlashSwapCallback.sol";

import { IERC20 } from "./interfaces/IERC20.sol";
import { IUniswapV3StaticQuoter } from "./interfaces/IUniswapV3StaticQuoter.sol";
import { IV3SwapRouter } from "./interfaces/IV3SwapRouter.sol";
import { Constants } from "./libraries/UniswapConstants.sol";

/// @notice Thrown if the `IUniswapV3StaticQuoter` address passed to the constructor is the zero address.
error QuoterZeroAddress();

/// @notice Thrown if the `IV3SwapRouter` address passed to the constructor is the zero address.
error RouterZeroAddress();

/**
 * @notice Thrown when the `flashLiquidate` `deadline has passed.
 * @param timestamp Timestamp at which the flash liquidation has been executed
 * @param deadline The timestamp by which the flash liquidation should have been executed
 */
error FlashLiquidationExpired(uint256 timestamp, uint256 deadline);

/**
 * @notice Thrown when the amount of tokenIn left after the liquidation is lower than the expected `minProfit`.
 * @param profit Amount of `tokenIn` left after performing the flash liquidation
 * @param minProfit Minimum profit expected
 */
error InsufficientProfit(uint256 profit, uint256 minProfit);

/**
 * @notice This contract uses a flashswap on a PoolTogether V5 LiquidationPair to swap yield for
 * prize tokens on Uniswap V3 and then contributes the prize tokens to the prize pool while
 * sending any excess to the receiver as profit.
 * @author G9 Software Inc.
 */
contract UniswapFlashLiquidation is IFlashSwapCallback {
    /// @notice Uniswap V3 Static Quoter
    IUniswapV3StaticQuoter public immutable quoter;

    /// @notice Uniswap V3 Router
    IV3SwapRouter public immutable router;

    /**
     * @notice Emitted when a flashswap liquidation has been made.
     * @param receiver The address that received the profit
     * @param liquidationPair The pair that was liquidated
     * @param path The path used for the swap
     * @param profit The profit sent to the receiver
     */
    event FlashSwapLiquidation(
        address indexed receiver,
        ILiquidationPair indexed liquidationPair,
        bytes path,
        uint256 profit
    );

    /**
     * @notice UniswapFlashLiquidation constructor.
     * @param quoter_ The Uniswap V3 Static Quoter to use to quote swap prices
     * @param router_ The Uniswap V3 Swap Router to use for swaps
     */
    constructor(IUniswapV3StaticQuoter quoter_, IV3SwapRouter router_) {
        if (address(0) == address(quoter_)) {
            revert QuoterZeroAddress();
        }
        if (address(0) == address(router_)) {
            revert RouterZeroAddress();
        }

        quoter = quoter_;
        router = router_;
    }

    /**
     * @notice Liquidate yield via the LiquidationPair and swap `_amountOut` of tokenOut in exchange of
     * `_amountInMax` of tokenIn. Any excess in tokenOut is sent as profit to `_receiver`.
     * @dev Will revert if `block.timestamp` exceeds the `_deadline`.
     * @dev Will revert if the tokenIn profit is less than `_profitMin`.
     * @param _liquidationPair Address of the LiquidationPair to flash liquidate against
     * @param _receiver Address that will receive the liquidation profit
     * (i.e. the amount of tokenIn in excess)
     * @param _amountOut Amount of tokenOut to swap for tokenIn
     * @param _amountInMax Maximum amount of tokenIn to send to the LiquidationPair target
     * @param _profitMin Minimum amount of excess tokenIn to receive for performing the liquidation
     * @param _deadline The timestamp in seconds by which the flash liquidation must be executed
     * @param _path The Uniswap V3 path to take for the swap
     * @return The amount of tokenIn in excess sent to `_receiver`
     */
    function flashLiquidate(
        ILiquidationPair _liquidationPair,
        address _receiver,
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256 _profitMin,
        uint256 _deadline,
        bytes calldata _path
    ) public returns (uint256) {
        if (block.timestamp > _deadline) {
            revert FlashLiquidationExpired(block.timestamp, _deadline);
        }

        _liquidationPair.swapExactAmountOut(address(this), _amountOut, _amountInMax, _path);

        IERC20 _tokenIn = IERC20(_liquidationPair.tokenIn());
        uint256 _profit = _tokenIn.balanceOf(address(this));

        if (_profit < _profitMin) {
            revert InsufficientProfit(_profit, _profitMin);
        }

        if (_profit > 0) {
            _tokenIn.transfer(_receiver, _profit);
        }

        emit FlashSwapLiquidation(_receiver, _liquidationPair, _path, _profit);

        return _profit;
    }

    /// @inheritdoc IFlashSwapCallback
    function flashSwapCallback(
        address /* _sender */,
        uint256 _amountIn,
        uint256 _amountOut,
        bytes calldata _path
    ) external {
        ILiquidationPair _liquidationPair = ILiquidationPair(msg.sender);
        IERC20(_liquidationPair.tokenOut()).transfer(address(router), _amountOut);

        router.exactInput(
            IV3SwapRouter.ExactInputParams({
                path: _path,
                recipient: Constants.MSG_SENDER, // Saves gas compared to using `address(this)`
                amountIn: Constants.CONTRACT_BALANCE, // Saves gas compared to sending `_amountOut`
                amountOutMinimum: _amountIn // The amount we must send to the LP target
            })
        );

        IERC20(_liquidationPair.tokenIn()).transfer(_liquidationPair.target(), _amountIn);
    }

    /// @notice Finds the biggest profit that can be made with the given liquidation pair and swap path.
    /// @dev SHOULD be called statically, not intended for onchain interactions!
    /// @param _liquidationPair The pair to liquidate
    /// @param _path The Uniswap V3 swap path to use
    /// @return The profit info for the best swap
    function findBestQuoteStatic(
        ILiquidationPair _liquidationPair,
        bytes calldata _path
    ) external returns (ProfitInfo memory) {
        ProfitInfo[] memory p = new ProfitInfo[](4);
        ProfitInfo memory pMax;
        uint256 _minOut = 0;
        uint256 _maxOut = _liquidationPair.maxAmountOut();
        uint256 _diffOut = _maxOut - _minOut;
        p[0] = getProfitInfoStatic(0, _liquidationPair, _path);
        p[1] = getProfitInfoStatic(_diffOut / 3, _liquidationPair, _path);
        p[2] = getProfitInfoStatic((_diffOut * 2) / 3, _liquidationPair, _path);
        p[3] = getProfitInfoStatic(_diffOut, _liquidationPair, _path);
        while (_diffOut > 6) {
            if (p[0].profit > p[1].profit) {
                // max between 0 and 1
                pMax = p[0];
                _minOut = p[0].amountOut;
                _maxOut = p[1].amountOut;
                _diffOut = _maxOut - _minOut;
                p[3] = p[1]; // new upper limit
                p[1] = getProfitInfoStatic(_minOut + _diffOut / 3, _liquidationPair, _path);
                p[2] = getProfitInfoStatic(_minOut + (_diffOut * 2) / 3, _liquidationPair, _path);
            } else if (p[1].profit > p[2].profit) {
                // max between 0 and 2
                pMax = p[1];
                _minOut = p[0].amountOut;
                _maxOut = p[2].amountOut;
                _diffOut = _maxOut - _minOut;
                p[3] = p[2]; // new upper limit
                p[1] = getProfitInfoStatic(_minOut + _diffOut / 3, _liquidationPair, _path);
                p[2] = getProfitInfoStatic(_minOut + (_diffOut * 2) / 3, _liquidationPair, _path);
            } else if (p[2].profit > p[3].profit) {
                // max between 1 and 3
                pMax = p[2];
                _minOut = p[1].amountOut;
                _maxOut = p[3].amountOut;
                _diffOut = _maxOut - _minOut;
                p[0] = p[1]; // new lower limit
                p[1] = getProfitInfoStatic(_minOut + _diffOut / 3, _liquidationPair, _path);
                p[2] = getProfitInfoStatic(_minOut + (_diffOut * 2) / 3, _liquidationPair, _path);
            } else {
                // max between 2 and 3
                pMax = p[3];
                _minOut = p[2].amountOut;
                _maxOut = p[3].amountOut;
                _diffOut = _maxOut - _minOut;
                p[0] = p[2]; // new lower limit
                p[1] = getProfitInfoStatic(_minOut + _diffOut / 3, _liquidationPair, _path);
                p[2] = getProfitInfoStatic(_minOut + (_diffOut * 2) / 3, _liquidationPair, _path);
            }
        }
        return pMax;
    }

    /// @notice Calculates the profit point at the given amount out.
    /// @dev SHOULD be called statically, not intended for onchain interactions!
    /// @param _amountOut The amount out at which to calculate the profit point
    /// @param _liquidationPair The pair to liquidate
    /// @param _path The Uniswap V3 swap path to use
    /// @return The profit point for the given amount out
    function getProfitInfoStatic(
        uint256 _amountOut,
        ILiquidationPair _liquidationPair,
        bytes calldata _path
    ) public returns (ProfitInfo memory) {
        ProfitInfo memory p;
        if (_amountOut == 0) return p;
        p.amountOut = _amountOut;
        p.amountIn = _liquidationPair.computeExactAmountIn(_amountOut);
        uint256 _tokenInFromSwap = quoter.quoteExactInput(_path, p.amountOut);
        if (_tokenInFromSwap >= p.amountIn) {
            p.profit = _tokenInFromSwap - p.amountIn;
            p.success = true;
        }
        return p;
    }

    /// @notice Struct to store current profit info with the associated liquidation parameters.
    /// @param amountIn The amount of tokenIn that will be sent to the LP
    /// @param amountOut The amount of tokenOut that will be swapped for tokenIn
    /// @param profit The amount of tokenIn profit that can be made
    /// @param success True if the liquidation will be successful, False otherwise
    struct ProfitInfo {
        uint256 amountIn;
        uint256 amountOut;
        uint256 profit;
        bool success;
    }
}
