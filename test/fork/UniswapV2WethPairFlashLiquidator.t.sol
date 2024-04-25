// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { ERC4626 } from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {
    UniswapV2WethPairFlashLiquidator,
    ILiquidationPair,
    IERC20
} from "../../src/UniswapV2WethPairFlashLiquidator.sol";

contract UniswapV2WethPairFlashLiquidatorTest is Test {

    uint256 public optimismFork;
    
    address alice;

    ILiquidationPair public liquidationPairSteth = ILiquidationPair(0x685fb53798FEf73C79F485eF436C33F866E0c969);
    ERC4626 stethPrizeVault = ERC4626(0x9b4C0de59628c64b02D7ce86f21db9A579539d5A);
    ERC4626 stethBeefyVault = ERC4626(0xCC60ebB05b1E327Ccb4F6c297B9404fdD2Ff5fC2);
    address stethWhale = 0x9f82A8b19804141161C582CfEa1b84853340A246;
    IERC20 stethWeth = IERC20(0x6dA98Bde0068d10DDD11b468b197eA97D96F96Bc);

    ILiquidationPair public liquidationPairPool = ILiquidationPair(0x055bFA086ecEbC21e6D6De0BB2e2b6BcE0401d58);
    ERC4626 poolPrizeVault = ERC4626(0x9B53eF6F13077727D22Cb4ACAD1119c79a97BE17);
    ERC4626 poolBeefyVault = ERC4626(0x1dBD083e1422c8c7AcD7091F5437e8C2854F25f4);
    address poolWhale = 0xD70804463bb2760c3384Fc87bBe779e3D91BaB3A;
    IERC20 poolWeth = IERC20(0xDB1FE6DA83698885104DA02A6e0b3b65c0B0dE80);

    // WETH address on Optimism
    address constant WETH = 0x4200000000000000000000000000000000000006;

    UniswapV2WethPairFlashLiquidator public flasher;

    function setUp() public {
        optimismFork = vm.createFork(vm.rpcUrl("optimism"), 119206831);
        vm.selectFork(optimismFork);

        alice = makeAddr("alice");

        flasher = new UniswapV2WethPairFlashLiquidator(IERC20(WETH));
    }

    function testFlashLiquidateStethWeth() external {

        vm.prank(stethWhale);
        deal(address(stethWeth), alice, 10e18);

        vm.startPrank(alice);
        stethWeth.approve(address(stethPrizeVault), 10e18);
        stethPrizeVault.deposit(10e18, alice);
        vm.stopPrank();

        vm.prank(stethWhale);
        deal(address(stethWeth), address(stethBeefyVault), 10e18);
        deal(address(stethBeefyVault), address(stethPrizeVault), 10e18);

        assertGt(liquidationPairSteth.maxAmountOut(), 0, "max amount out");

        uint256 profit = flasher.flashSwapExactAmountOut(
            liquidationPairSteth,
            alice,
            liquidationPairSteth.maxAmountOut(),
            100
        );

        assertGt(profit, 0, "profit was non-zero");
    }



    function testFlashLiquidatePoolWeth() external {

        vm.prank(poolWhale);
        deal(address(poolWeth), alice, 10e18);

        vm.startPrank(alice);
        poolWeth.approve(address(poolPrizeVault), 10e18);
        poolPrizeVault.deposit(10e18, alice);
        vm.stopPrank();

        vm.prank(poolWhale);
        deal(address(poolWeth), address(poolBeefyVault), 10e18);
        deal(address(poolBeefyVault), address(poolPrizeVault), 10e18);

        assertGt(liquidationPairPool.maxAmountOut(), 0, "max amount out");

        uint256 profit = flasher.flashSwapExactAmountOut(
            liquidationPairPool,
            alice,
            liquidationPairPool.maxAmountOut(),
            100
        );

        assertGt(profit, 0, "profit was non-zero");
    }
}
