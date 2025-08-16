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
import {UniversalRouter} from "uniswap/universal-router/contracts/UniversalRouter.sol";
import {Commands} from "uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {IPermit2} from "uniswap/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

// Attach CurrencyLibrary functions to Currency type

contract uniswap_v4 {
    using CurrencyLibrary for Currency;

    MyToken public myToken;
    IPoolManager public poolManager = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
    IPositionManager public positionManager = IPositionManager(0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4);
    UniversalRouter public router = UniversalRouter(payable(0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b));
    IPermit2 public immutable permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // Store the pool key for later use
    PoolKey internal key = PoolKey({
        currency0: Currency.wrap(address(0)), // ETH
        currency1: Currency.wrap(address(myToken)), // MyToken
        fee: 500,
        tickSpacing: 10,
        hooks: IHooks(address(0))
    });

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
        params[2] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, recipient);
        uint256 deadline = block.timestamp + 60;

        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;

        positionManager.modifyLiquidities{value: valueToPass}(abi.encode(actions, params), deadline);
    }

    function increaseLiquidity(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        bytes calldata hookData,
        address currency0,
        address currency1,
        bool isEthPosition,
        uint256 deadline
    ) external payable {
        // Step 1: Encode the actions
        bytes memory actions = isEthPosition
            ? abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP))
            : abi.encodePacked(uint8(Actions.INCREASE_LIQUIDITY), uint8(Actions.SETTLE_PAIR));

        // Step 2: Encode parameters
        uint256 paramCount = isEthPosition ? 3 : 2;
        bytes[] memory params = new bytes[](paramCount);

        // Required: increase parameters
        params[0] = abi.encode(tokenId, liquidity, amount0Max, amount1Max, hookData);

        // settle pair parameters
        params[1] = abi.encode(Currency.wrap(currency0), Currency.wrap(currency1));

        // sweep parameters (only if ETH involved)
        if (isEthPosition) {
            params[2] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, msg.sender);
        }

        // Step 3: Define ETH value if needed
        uint256 valueToSend = isEthPosition ? amount0Max : 0;

        // Execute the transaction
        positionManager.modifyLiquidities{value: valueToSend}(abi.encode(actions, params), deadline);
    }

    /**
     * @notice Decrease liquidity from an existing position
     * @param tokenId The position NFT ID
     * @param liquidity Amount of liquidity to remove
     * @param amount0Min Minimum amount of token0 to receive
     * @param amount1Min Minimum amount of token1 to receive
     * @param hookData Optional hook data
     * @param currency0 Address of token0 (0x0 for ETH)
     * @param currency1 Address of token1
     * @param recipient Address to receive withdrawn tokens
     * @param isDustTolerant If true, use CLEAR_OR_TAKE instead of TAKE_PAIR
     */
    function decreaseLiquidity(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Min,
        uint128 amount1Min,
        bytes calldata hookData,
        address currency0,
        address currency1,
        address recipient,
        bool isDustTolerant
    ) external {
        bytes memory actions;
        bytes[] memory params;

        if (!isDustTolerant) {
            // Case 1: Take both tokens normally
            actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));

            params = new bytes[](2);
            params[0] = abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData);
            params[1] = abi.encode(Currency.wrap(currency0), Currency.wrap(currency1), recipient);
        } else {
            // Case 2: Dust-tolerant mode (CLEAR_OR_TAKE for each token)
            actions = abi.encodePacked(
                uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.CLEAR_OR_TAKE), uint8(Actions.CLEAR_OR_TAKE)
            );

            params = new bytes[](3);
            params[0] = abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData);
            params[1] = abi.encode(Currency.wrap(currency0), amount0Min);
            params[2] = abi.encode(Currency.wrap(currency1), amount1Min);
        }

        uint256 deadline = block.timestamp + 60;

        // For ETH pairs, valueToPass is almost always 0 when withdrawing
        positionManager.modifyLiquidities(abi.encode(actions, params), deadline);
    }

    // collect fees from a position
    function collectFees(uint256 tokenId, address recipient) external {
        // Encode the actions for collecting fees
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        /// @dev collecting fees is achieved with liquidity=0, the second parameter
        params[0] = abi.encode(tokenId, 0, 0, 0, "");
        params[1] = abi.encode(Currency.wrap(address(0)), Currency.wrap(address(myToken)), recipient);
        uint256 deadline = block.timestamp + 60;
        // Execute the transaction
        positionManager.modifyLiquidities(abi.encode(actions, params), deadline);
        console.log("Fees collected for tokenId: ", tokenId, " to recipient: ", recipient);
    }

    // Burn Position
    function burnPosition(uint256 tokenId, address recipient) external {
        // Encode the actions for burning a position
        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION), uint8(Actions.TAKE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, 0, 0, 0, "");
        params[1] = abi.encode(Currency.wrap(address(0)), Currency.wrap(address(myToken)), recipient);
        uint256 deadline = block.timestamp + 60;
        // Execute the transaction
        positionManager.modifyLiquidities(abi.encode(actions, params), deadline);
        console.log("Position burned for tokenId: ", tokenId);
    }

    function approveTokenWithPermit2(address token, uint160 amount, uint48 expiration) external {
        IERC20(token).approve(address(permit2), type(uint256).max);
        permit2.approve(token, address(router), amount, expiration);
    }

    function swapExactInputSingle(
        PoolKey calldata key, // PoolKey struct that identifies the v4 pool
        uint128 amountIn, // Exact amount of tokens to swap
        uint128 minAmountOut, // Minimum amount of output tokens expected
        uint256 deadline // Timestamp after which the transaction will revert
    ) external returns (uint256 amountOut) {
        // Implementation will follow
    }

    function swapExactInputSingle(uint128 amountIn, uint128 minAmountOut, uint256 deadline)
        external
        payable
        returns (uint256 amountOut)
    {
        address tokenIn = Currency.unwrap(key.currency0);
        address tokenOut = Currency.unwrap(key.currency1);

        if (tokenIn == address(0)) {
            // Case 1: Native ETH as input
            require(msg.value == amountIn, "Must send ETH equal to amountIn");
        } else {
            // Case 2: ERC20 input
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).approve(address(permit2), amountIn);
            permit2.approve(tokenIn, address(router), amountIn, uint48(block.timestamp + 3600));
        }

        // Step 2: Encode the swap
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        // Encode V4Router actions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);

        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true, // true if we're swapping token0 for token1
                amountIn: amountIn, // amount of tokens we're swapping
                amountOutMinimum: minAmountOut, // minimum amount we expect to receive
                hookData: bytes("") // no hook data needed
            })
        );

        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(key.currency0, amountIn);

        // Third parameter: specify output tokens from the swap
        params[2] = abi.encode(key.currency1, minAmountOut);

        bytes[] memory inputs = new bytes[](1);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        router.execute(commands, inputs, deadline);
        amountOut = key.currency1.balanceOf(address(this));
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }

    // Allow contract to receive ETH

    receive() external payable {}
}
