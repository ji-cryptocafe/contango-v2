//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "src/security/TradeLimits.sol";

contract TradeLimitsTest is Test {

    TradeLimits limits;
    address owner = makeAddr("owner");
    address rando = makeAddr("rando");
    address trader = makeAddr("trader");
    address contangoAddr = makeAddr("contango");

    function setUp() public {
        vm.startPrank(owner);
        limits = new TradeLimits();
        limits.setContango(contangoAddr);
        vm.stopPrank();
    }

    // =================== Ownership ===================

    function test_constructor_setsOwner() public view {
        assertEq(limits.owner(), owner);
    }

    function test_nonOwner_cannotSetMaxTradeSize() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        limits.setMaxTradeSize(100e18);
    }

    function test_nonOwner_cannotSetMaxDailyVolume() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        limits.setMaxDailyVolume(1000e18);
    }

    function test_nonOwner_cannotSetMaxOpenPositions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        limits.setMaxOpenPositions(5);
    }

    function test_nonOwner_cannotSetContango() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        limits.setContango(rando);
    }

    // =================== onlyContango access control ===================

    function test_recordVolume_reverts_nonContango() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        vm.expectRevert(TradeLimits.OnlyContango.selector);
        vm.prank(rando);
        limits.recordAndValidateVolume(trader, 50e18);
    }

    function test_incrementOpenPositions_reverts_nonContango() public {
        vm.expectRevert(TradeLimits.OnlyContango.selector);
        vm.prank(rando);
        limits.incrementOpenPositions(trader);
    }

    function test_decrementOpenPositions_reverts_nonContango() public {
        vm.expectRevert(TradeLimits.OnlyContango.selector);
        vm.prank(rando);
        limits.decrementOpenPositions(trader);
    }

    function test_owner_cannot_callStateMutations() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        vm.expectRevert(TradeLimits.OnlyContango.selector);
        vm.prank(owner);
        limits.recordAndValidateVolume(trader, 50e18);
    }

    // =================== Configuration ===================

    function test_setMaxTradeSize() public {
        vm.prank(owner);
        limits.setMaxTradeSize(50e18);
        assertEq(limits.maxTradeSize(), 50e18);
    }

    function test_setMaxDailyVolume() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(500e18);
        assertEq(limits.maxDailyVolume(), 500e18);
    }

    function test_setMaxOpenPositions() public {
        vm.prank(owner);
        limits.setMaxOpenPositions(3);
        assertEq(limits.maxOpenPositions(), 3);
    }

    function test_setContango() public {
        address newContango = makeAddr("newContango");
        vm.prank(owner);
        limits.setContango(newContango);
        assertEq(limits.contango(), newContango);
    }

    function test_defaults_areZero_meansUnlimited() public view {
        assertEq(limits.maxTradeSize(), 0);
        assertEq(limits.maxDailyVolume(), 0);
        assertEq(limits.maxOpenPositions(), 0);
    }

    // =================== validateTradeSize (view — no access control) ===================

    function test_validateTradeSize_withinLimit() public {
        vm.prank(owner);
        limits.setMaxTradeSize(10e18);

        limits.validateTradeSize(10e18);
    }

    function test_validateTradeSize_exceedsLimit() public {
        vm.prank(owner);
        limits.setMaxTradeSize(10e18);

        vm.expectRevert(abi.encodeWithSelector(TradeLimits.TradeSizeExceeded.selector, 10e18, 11e18));
        limits.validateTradeSize(11e18);
    }

    function test_validateTradeSize_zeroLimit_meansUnlimited() public view {
        limits.validateTradeSize(type(uint256).max);
    }

    function test_validateTradeSize_zeroSize_alwaysPasses() public {
        vm.prank(owner);
        limits.setMaxTradeSize(10e18);

        limits.validateTradeSize(0);
    }

    // =================== recordAndValidateVolume ===================

    function test_recordVolume_withinLimit() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader, 50e18);
        assertEq(limits.dailyVolume(trader), 50e18);
    }

    function test_recordVolume_accumulates() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader, 30e18);
        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader, 40e18);
        assertEq(limits.dailyVolume(trader), 70e18);
    }

    function test_recordVolume_exceedsLimit() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader, 60e18);

        vm.expectRevert(abi.encodeWithSelector(TradeLimits.DailyVolumeExceeded.selector, trader, 100e18, 110e18));
        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader, 50e18);
    }

    function test_recordVolume_zeroLimit_meansUnlimited() public {
        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader, type(uint128).max);
    }

    function test_recordVolume_epochResets() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader, 90e18);
        assertEq(limits.dailyVolume(trader), 90e18);

        vm.warp(block.timestamp + 1 days);

        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader, 90e18);
        assertEq(limits.dailyVolume(trader), 90e18);
    }

    function test_recordVolume_differentTraders_independent() public {
        address trader2 = makeAddr("trader2");

        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader, 80e18);
        vm.prank(contangoAddr);
        limits.recordAndValidateVolume(trader2, 80e18);

        assertEq(limits.dailyVolume(trader), 80e18);
        assertEq(limits.dailyVolume(trader2), 80e18);
    }

    // =================== Open position count ===================

    function test_validateOpenPositionCount_withinLimit() public {
        vm.prank(owner);
        limits.setMaxOpenPositions(3);

        vm.startPrank(contangoAddr);
        limits.incrementOpenPositions(trader);
        limits.incrementOpenPositions(trader);
        limits.incrementOpenPositions(trader);
        vm.stopPrank();
        assertEq(limits.openPositionCount(trader), 3);
    }

    function test_validateOpenPositionCount_exceedsLimit() public {
        vm.prank(owner);
        limits.setMaxOpenPositions(2);

        vm.startPrank(contangoAddr);
        limits.incrementOpenPositions(trader);
        limits.incrementOpenPositions(trader);

        vm.expectRevert(abi.encodeWithSelector(TradeLimits.MaxOpenPositionsExceeded.selector, trader, 2));
        limits.incrementOpenPositions(trader);
        vm.stopPrank();
    }

    function test_validateOpenPositionCount_zeroLimit_meansUnlimited() public {
        vm.startPrank(contangoAddr);
        for (uint256 i = 0; i < 100; i++) {
            limits.incrementOpenPositions(trader);
        }
        vm.stopPrank();
        assertEq(limits.openPositionCount(trader), 100);
    }

    function test_decrementOpenPositions() public {
        vm.prank(owner);
        limits.setMaxOpenPositions(2);

        vm.startPrank(contangoAddr);
        limits.incrementOpenPositions(trader);
        limits.incrementOpenPositions(trader);

        vm.expectRevert(abi.encodeWithSelector(TradeLimits.MaxOpenPositionsExceeded.selector, trader, 2));
        limits.incrementOpenPositions(trader);

        limits.decrementOpenPositions(trader);
        assertEq(limits.openPositionCount(trader), 1);

        limits.incrementOpenPositions(trader);
        assertEq(limits.openPositionCount(trader), 2);
        vm.stopPrank();
    }

    function test_decrementOpenPositions_zeroIsNoOp() public {
        vm.prank(contangoAddr);
        limits.decrementOpenPositions(trader);
        assertEq(limits.openPositionCount(trader), 0);
    }

    // =================== Fuzz ===================

    function test_fuzz_tradeSize(uint256 maxSize, uint256 tradeSize) public {
        vm.assume(maxSize > 0);
        vm.prank(owner);
        limits.setMaxTradeSize(maxSize);

        if (tradeSize <= maxSize) {
            limits.validateTradeSize(tradeSize);
        } else {
            vm.expectRevert(abi.encodeWithSelector(TradeLimits.TradeSizeExceeded.selector, maxSize, tradeSize));
            limits.validateTradeSize(tradeSize);
        }
    }

}
