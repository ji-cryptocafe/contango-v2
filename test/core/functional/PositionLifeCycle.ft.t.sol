//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../stub/MorphoOracleMock.sol";
import { MarketParamsLib } from "src/moneymarkets/morpho/dependencies/MarketParamsLib.sol";

import "./AbstractPositionLifeCycle.ft.t.sol";

contract PositionLifeCycleAaveArbitrumFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_AAVE, WETH, USDC, 0);
    }

}

contract PositionLifeCycleSparkSkyMainnetFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, 18_233_968, MM_SPARK_SKY, WETH, DAI, 0);
    }

}

contract PositionLifeCycleMorphoBlueMainnetFunctionalLong is AbstractPositionLifeCycleFunctional {

    using MarketParamsLib for MarketParams;

    function setUp() public {
        super.setUp(Network.Mainnet, 18_919_243, MM_MORPHO_BLUE, WETH, USDC, 0);

        IMorpho morpho = env.morpho();

        MarketParams memory params = MarketParams({
            loanToken: env.token(USDC),
            collateralToken: env.token(WETH),
            oracle: new MorphoOracleMock(env.erc20(WETH), env.erc20(USDC)),
            irm: IIrm(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC),
            lltv: 0.86e18
        });
        morpho.createMarket(params);
        address lp = makeAddr("LP");
        env.dealAndApprove(env.token(USDC), lp, 100_000e6, address(morpho));
        vm.prank(lp);
        morpho.supply({ marketParams: params, assets: 100_000e6, shares: 0, onBehalf: lp, data: "" });

        vm.startPrank(Timelock.unwrap(TIMELOCK));
        MorphoBlueReverseLookup reverseLookup =
            MorphoBlueMoneyMarket(address(contango.positionFactory().moneyMarket(MM_MORPHO_BLUE))).reverseLookup();
        Payload payload = reverseLookup.setMarket(params.id());
        vm.stopPrank();

        env.encoder().setPayload(payload);

        deal(address(instrument.baseData.token), TRADER, 0);
        deal(address(instrument.quoteData.token), TRADER, 0);
    }

}
