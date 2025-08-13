// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {MyToken} from "./myToken.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {console} from "forge-std/console.sol";

contract uniswap_v4 {
    MyToken public myToken;

    constructor(address _tokenAddress) {
        myToken = MyToken(_tokenAddress);
    }

    /// @notice Creates a pool with the specified parameters
    /// @dev This function initializes a pool with a specific currency pair, fee, tick spacing, and hooks.
    /// It also sets the initial price of the pool based on the provided amounts
    /// info this is only create the pool and insitlise the pool with the starting price and at this point we are not using the hooks
    function createPool() external {
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(myToken)),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        // 1 ETH = 1000 TKN
        uint256 amount0 = 1;
        uint256 amount1 = 1000;

        // If tokens decimals are not same
        // USDC = 6 decimals
        // Pool ETH - USDC
        // 1 ETH = 1000 USDC
        // amount0 = 1 ether; // 1+18 decimals
        // amount1 = 1000e6; // 1+6 decimals

        uint160 startingPrice = encodeSqrtRatioX96(amount1, amount0);

        int24 poolTick = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543).initialize(pool, startingPrice);

        console.log("Token deployed at: ", address(myToken));
        console.log("Pool tick is: ", poolTick);
    }

    function encodeSqrtRatioX96(uint256 amount1, uint256 amount0) internal pure returns (uint160 sqrtPriceX96) {
        require(amount0 > 0, "PriceMath: division by zero");
        // Multiply amount1 by 2^192 (left shift by 192) to preserve precision after the square root.
        uint256 ratioX192 = (amount1 << 192) / amount0;
        uint256 sqrtRatio = Math.sqrt(ratioX192);
        require(sqrtRatio <= type(uint160).max, "PriceMath: sqrt overflow");
        sqrtPriceX96 = uint160(sqrtRatio);
    }
}
