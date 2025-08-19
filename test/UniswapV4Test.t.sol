// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// adjust this import path to where your contract lives
import {uniswap_v4} from "../src/uniswap_v4.sol";
import {MyToken} from "../src/myToken.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {console} from "forge-std/console.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {UniversalRouter} from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

// import mockerc20

contract UniswapV4PoolCreationTest is Test {
    using CurrencyLibrary for Currency;

    MyToken public myToken;
    IPoolManager public poolManager = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
    IPositionManager public positionManager = IPositionManager(0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4);
    UniversalRouter public router = UniversalRouter(payable(0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b));
    IPermit2 public immutable permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    uniswap_v4 public uniswapV4;
    address public user = address(this);

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));

        myToken = new MyToken();
        uniswapV4 = new uniswap_v4(address(myToken));

        vm.label(address(myToken), "MyToken");
        vm.label(address(uniswapV4), "UniswapV4");
        vm.label(address(positionManager), "PositionManager");

        // Approve for position manager
        myToken.approve(address(positionManager), type(uint256).max);

        // Transfer tokens to test user
        myToken.transfer(user, 1_000_000 ether);
    }

    function test_CreatePool_SetsPoolKeyAndCallsInitialize() public {
        (int24 tickSpacing, PoolId poolId) = uniswapV4.createPool();
        console.log("Pool created with tick spacing: ", tickSpacing);
        console.logBytes32(PoolId.unwrap(poolId));
    }

    function test_AddLiquidity_ETH_MyToken() public {
        int24 tickLower = -60;
        int24 tickUpper = 60;
        uint128 liquidity = 1000;
        uint256 amount0Max = 1 ether; // ETH side
        uint256 amount1Max = 1000 ether; // MyToken side
        bytes memory hookData = "";
        // approve erc20 token to address(this)
        myToken.approve(address(uniswapV4), type(uint256).max);
        (int24 tickSpacing, PoolId poolId) = uniswapV4.createPool();

        // Act: add liquidity
        uniswapV4.addLiquidity{value: amount0Max}(
            tickLower, tickUpper, liquidity, amount0Max, amount1Max, user, hookData
        );

        // Assert 1: MyToken balance decreased
        uint256 remaining = myToken.balanceOf(user);
        console2.log("Remaining MyToken after adding liquidity:", remaining);
        assertLt(remaining, 1_000_000 ether, "MyToken not spent -> liquidity not added");

        // Assert 2: Query position from PositionManager
        // For V4 positions, the key is (poolId, owner, tickLower, tickUpper)
    }
}
