// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import { Script } from "forge-std/Script.sol";

import {
    UniswapFlashLiquidation,
    ILiquidationPair,
    IUniswapV3StaticQuoter,
    IV3SwapRouter,
    IERC20
} from "../src/UniswapFlashLiquidation.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is Script {
    function run() public {
        vm.startBroadcast();

        if (block.chainid == 10) {
            new UniswapFlashLiquidation(
                IUniswapV3StaticQuoter(0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE),
                IV3SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45)
            );
        } else if (block.chainid == 8453) {
            new UniswapFlashLiquidation(
                IUniswapV3StaticQuoter(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a),
                IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481)
            );
        } else {
            revert("unsupported network");
        }

        vm.stopBroadcast();
    }
}
