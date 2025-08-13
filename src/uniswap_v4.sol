// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {MyToken} from "./myToken.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {console} from "forge-std/console.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
// Attach CurrencyLibrary functions to Currency type

contract uniswap_v4 {
    using CurrencyLibrary for Currency;

    MyToken public myToken;
    IPoolManager public poolManager = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
    IPositionManager public positionManager = IPositionManager(0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4);

    // Store the pool key for later use
    PoolKey public poolKey;

    constructor(address _tokenAddress) {
        myToken = MyToken(_tokenAddress);
    }

    /// @notice Creates a pool with the specified parameters
    /// @dev This function initializes a pool with a specific currency pair, fee, tick spacing, and hooks.
    /// It also sets the initial price of the pool based on the provided amounts
    /// info this is only create the pool and insitlise the pool with the starting price and at this point we are not using the hooks
    function createPool() external {
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(address(myToken)), // Your token
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // 1 ETH = 1000 TKN
        uint256 amount0 = 1;
        uint256 amount1 = 1000;
        uint160 startingPrice = encodeSqrtRatioX96(amount1, amount0);

        int24 poolTick = poolManager.initialize(poolKey, startingPrice);

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

    // function for adding liquidity to the pool
    function addLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes calldata hookData
    ) external {
        // For ETH liquidity positions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP));

        bytes[] memory params = new bytes[](3);

        Currency currency0 = Currency.wrap(address(0)); // tokenAddress1 = 0 for native ETH
        Currency currency1 = Currency.wrap(address(myToken));
        PoolKey memory localPoolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(0)));
        params[0] =
            abi.encode(localPoolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(currency0, currency1);
        params[2] = abi.encode(Currency.wrap(address(0)), recipient);
        uint256 deadline = block.timestamp + 60;

        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;

        positionManager.modifyLiquidities{value: valueToPass}(abi.encode(actions, params), deadline);
    }

    // Create parameters for each action

    // Allow contract to receive ETH
    receive() external payable {}
}
