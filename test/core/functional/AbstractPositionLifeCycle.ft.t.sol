// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

// AbstractPositionLifeCycleFunctional removed - depends on deleted ContangoLens and Balances types
abstract contract AbstractPositionLifeCycleFunctional is BaseTest {
    Env internal env;
    Contango internal contango;
    TestInstrument internal instrument;

    function setUp(Network network, MoneyMarketId mm, bytes32 base, bytes32 quote, uint256 multiplier) internal virtual {
        env = provider(network);
        env.init();
        contango = env.contango();
        instrument = env.createInstrument(env.erc20(base), env.erc20(quote));
    }

    function setUp(Network network, uint256 blockNo, MoneyMarketId mm, bytes32 base, bytes32 quote, uint256 multiplier) internal virtual {
        env = provider(network);
        env.init(blockNo);
        contango = env.contango();
        instrument = env.createInstrument(env.erc20(base), env.erc20(quote));
    }
}
