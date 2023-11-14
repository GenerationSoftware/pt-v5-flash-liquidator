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
 * @notice Thrown when the amount of tokenIn left after the liquidation is lower than the expected `profitMin`.
 * @param profit Amount of `tokenIn` left after performing the flash liquidation
 * @param profitMin Minimum profit expected
 */
error InsufficientProfit(uint256 profit, uint256 profitMin);

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
     * @param _amountInMax Maximum amount of tokenIn to send to the LiquidationPair target
     * @param _profitMin Minimum amount of excess tokenIn to receive for performing the liquidation
     * @param _swapCommand A 1-byte command indicating the Uniswap command to use for swapping (i.e. 0x00 V3_SWAP_EXACT_IN or 0x08 V2_SWAP_EXACT_IN)
     * @param _swapInput The Uniswap input to execute for the respective command
     * @param _deadline The timestamp by which the flash liquidation must be executed
     * @return The amount of tokenOut in excess sent to `_receiver`
     */
    function flashLiquidate(
        ILiquidationPair _liquidationPair,
        address _receiver,
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256 _profitMin,
        bytes calldata _swapCommand,
        bytes[] calldata _swapInput,
        uint256 _deadline
    ) external returns (uint256) {
        if (block.timestamp > _deadline) {
            revert FlashLiquidationExpired(block.timestamp, _deadline);
        }

        _liquidationPair.swapExactAmountOut(
            address(this),
            _amountOut,
            _amountInMax,
            abi.encode(_swapCommand, _swapInput, _deadline)
        );

        IERC20 _tokenIn = IERC20(_liquidationPair.tokenIn());
        uint256 _tokenInBalance = _tokenIn.balanceOf(address(this));

        if (_tokenInBalance < _profitMin) {
            revert InsufficientProfit(_tokenInBalance, _profitMin);
        }

        if (_tokenInBalance > 0) {
            _tokenIn.transfer(_receiver, _tokenInBalance);
        }

        return _tokenInBalance;
    }

    /// @inheritdoc IFlashSwapCallback
    function flashSwapCallback(
        address /** _sender */,
        uint256 _amountIn,
        uint256 _amountOut,
        bytes calldata _flashSwapData
    ) external {
        (bytes memory _swapCommand, bytes[] memory _swapInput, uint256 _deadline) = abi.decode(
            _flashSwapData,
            (bytes, bytes[], uint256)
        );

        ILiquidationPair _liquidationPair = ILiquidationPair(msg.sender);
        IERC20(_liquidationPair.tokenOut()).transfer(address(_universalRouter), _amountOut);

        _universalRouter.execute(_swapCommand, _swapInput, _deadline);

        IERC20 _tokenIn = IERC20(_liquidationPair.tokenIn());
        _tokenIn.transfer(_liquidationPair.target(), _amountIn);
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
