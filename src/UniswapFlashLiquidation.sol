// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { IFlashSwapCallback } from "pt-v5-liquidator-interfaces/IFlashSwapCallback.sol";

import { IERC20 } from "./interfaces/IERC20.sol";
import { IUniversalRouter } from "./interfaces/IUniversalRouter.sol";

/// @notice Trown if the UniversalRouter address passed to the constructor is zero.
error UniversalRouterAddressZero();

/**
 * @notice Thrown when the `flashLiquidate` `deadline has passed.
 * @param timestamp Timestamp at which the flash liquidation has been executed
 * @param deadline The timestamp by which the flash liquidation should have been executed
 */
error FlashLiquidationExpired(uint256 timestamp, uint256 deadline);

/**
 * @notice Thrown when `amountOut` of tokenOut is lower than the expected `amountOutMin`.
 * @param amountOut Amount of `tokenOut` left after performing the flash liquidation
 * @param amountOutMin Minimum amount of `tokenOut` expected
 */
error InsufficientTokenOutAmount(uint256 amountOut, uint256 amountOutMin);

/**
 * @notice Thrown when a staticcall failed.
 * @param returnData Data returned from the staticcall
 */
error StaticcallFailed(bytes returnData);

contract UniswapFlashLiquidation is IFlashSwapCallback {
    /// @notice Uniswap Universal Router address
    IUniversalRouter internal _universalRouter;

    /**
     * @notice UniswapFlashLiquidation constructor.
     * @param universalRouter_ Address of the Uniswap Universal Router to use to perform the flash liquidation
     */
    constructor(IUniversalRouter universalRouter_) {
        if (address(universalRouter_) == address(0)) {
            revert UniversalRouterAddressZero();
        }

        _universalRouter = universalRouter_;
    }

    /**
     * @notice Liquidate yield via the LiquidationPair and swap `_amountOut` of tokenOut in exchange of `_amountInMax` of tokenIn.
     *         Any excess in tokenOut is sent as profit to `_receiver`.
     * @dev Will revert if `block.timestamp` exceeds the `_deadline`.
     * @dev Will revert if the amount of tokenOut after performing the flash liquidation is lower than the expected `_amountOutMin`.
     * @param _liquidationPair Address of the LiquidationPair to flash liquidate against
     * @param _receiver Address that will receive the liquidation profit (i.e. the amount of tokenOut in excess)
     * @param _amountOut Amount of tokenOut to swap for tokenIn
     * @param _amountOutMin Minimum amount of excess tokenOut to receive for performing the liquidation
     * @param _amountInMax Maximum amount of tokens to be received
     * @param _swapCommand A 1-byte command indicating the Uniswap version to use for swapping (i.e. 0x01 V3_SWAP_EXACT_OUT or 0x09 V2_SWAP_EXACT_OUT)
     * @param _swapPath The Uniswap encoded path to trade along
     * @param _deadline The timestamp by which the flash liquidation must be executed
     * @return The amount of tokenOut in excess sent to `_receiver`
     */
    function flashLiquidate(
        ILiquidationPair _liquidationPair,
        address _receiver,
        uint256 _amountOut,
        uint256 _amountOutMin,
        uint256 _amountInMax,
        bytes calldata _swapCommand,
        bytes calldata _swapPath,
        uint256 _deadline
    ) external returns (uint256) {
        if (block.timestamp > _deadline) {
            revert FlashLiquidationExpired(block.timestamp, _deadline);
        }

        _liquidationPair.swapExactAmountOut(
            address(this),
            _amountOut,
            _amountInMax,
            abi.encode(_swapCommand, _swapPath, _deadline)
        );

        IERC20 _tokenOut = IERC20(ILiquidationPair(msg.sender).tokenOut());
        uint256 _tokenOutBalance = _tokenOut.balanceOf(address(this));

        if (_tokenOutBalance < _amountOutMin) {
            revert InsufficientTokenOutAmount(_tokenOutBalance, _amountOutMin);
        }

        _tokenOut.transfer(_receiver, _tokenOutBalance);

        return _tokenOutBalance;
    }

    /// @inheritdoc IFlashSwapCallback
    function flashSwapCallback(
        address /** _sender */,
        uint256 _amountIn,
        uint256 _amountOut,
        bytes calldata _flashSwapData
    ) external {
        ILiquidationPair _liquidationPair = ILiquidationPair(msg.sender);
        IERC20(_liquidationPair.tokenOut()).transfer(address(_universalRouter), _amountOut);

        (bytes memory _swapCommand, bytes[] memory _swapPath, uint256 _deadline) = abi.decode(
            _flashSwapData,
            (bytes, bytes[], uint256)
        );

        bytes[] memory _swapInput = new bytes[](1);
        _swapInput[0] = abi.encode(_liquidationPair.target(), _amountIn, _amountOut, _swapPath, false);

        // Swap maximum `_amountOut` of `tokenOut` in exchange of minimum `_amountIn` of `tokenIn`
        // and transfer to `target`
        _universalRouter.execute(_swapCommand, _swapInput, _deadline);
    }

    /**
     * @notice Get `maxAmountOut` of tokenOut that can be liquidated in exchange of `maxAmountIn` of tokenIn.
     * @param _liquidationPair Address of the LiquidationPair to flash liquidate against
     * @return maxAmountOut Maximum amount of tokenOut that can be liquidated
     * @return maxAmountIn Maximum amount of tokenIn that would be received in exchange of `maxAmountOut`` of tokenOut
     */
    function previewMaxAmount(
        ILiquidationPair _liquidationPair
    ) external returns (uint256 maxAmountOut, uint256 maxAmountIn) {
        maxAmountOut = _liquidationPair.maxAmountOut();
        maxAmountIn = _liquidationPair.computeExactAmountIn(maxAmountOut);
    }

    /**
     * @notice Get Uniswap Universal Router address set at deployment.
     * @return Uniswap Universal Router address
     */
    function universalRouter() external view returns (IUniversalRouter) {
        return _universalRouter;
    }
}
