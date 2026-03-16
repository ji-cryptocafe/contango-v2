//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "src/security/TradeLimits.sol";

contract TradeLimitsTest is Test {

    TradeLimits limits;
    address owner = makeAddr("owner");
    address rando = makeAddr("rando");
    address trader = makeAddr("trader");

    function setUp() public {
        vm.prank(owner);
        limits = new TradeLimits();
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

    function test_defaults_areZero_meansUnlimited() public view {
        assertEq(limits.maxTradeSize(), 0);
        assertEq(limits.maxDailyVolume(), 0);
        assertEq(limits.maxOpenPositions(), 0);
    }

    // =================== validateTradeSize ===================

    function test_validateTradeSize_withinLimit() public {
        vm.prank(owner);
        limits.setMaxTradeSize(10e18);

        limits.validateTradeSize(10e18); // exact limit — should pass
    }

    function test_validateTradeSize_exceedsLimit() public {
        vm.prank(owner);
        limits.setMaxTradeSize(10e18);

        vm.expectRevert(abi.encodeWithSelector(TradeLimits.TradeSizeExceeded.selector, 10e18, 11e18));
        limits.validateTradeSize(11e18);
    }

    function test_validateTradeSize_zeroLimit_meansUnlimited() public view {
        // maxTradeSize = 0 → no limit
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

        limits.recordAndValidateVolume(trader, 50e18);
        assertEq(limits.dailyVolume(trader), 50e18);
    }

    function test_recordVolume_accumulates() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        limits.recordAndValidateVolume(trader, 30e18);
        limits.recordAndValidateVolume(trader, 40e18);
        assertEq(limits.dailyVolume(trader), 70e18);
    }

    function test_recordVolume_exceedsLimit() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        limits.recordAndValidateVolume(trader, 60e18);

        vm.expectRevert(abi.encodeWithSelector(TradeLimits.DailyVolumeExceeded.selector, trader, 100e18, 110e18));
        limits.recordAndValidateVolume(trader, 50e18);
    }

    function test_recordVolume_zeroLimit_meansUnlimited() public {
        limits.recordAndValidateVolume(trader, type(uint128).max);
    }

    function test_recordVolume_epochResets() public {
        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        limits.recordAndValidateVolume(trader, 90e18);
        assertEq(limits.dailyVolume(trader), 90e18);

        // Advance 1 day
        vm.warp(block.timestamp + 1 days);

        // Volume should reset — new epoch
        limits.recordAndValidateVolume(trader, 90e18); // should pass
        assertEq(limits.dailyVolume(trader), 90e18); // reset + new
    }

    function test_recordVolume_differentTraders_independent() public {
        address trader2 = makeAddr("trader2");

        vm.prank(owner);
        limits.setMaxDailyVolume(100e18);

        limits.recordAndValidateVolume(trader, 80e18);
        limits.recordAndValidateVolume(trader2, 80e18); // independent — should pass

        assertEq(limits.dailyVolume(trader), 80e18);
        assertEq(limits.dailyVolume(trader2), 80e18);
    }

    // =================== validateOpenPositionCount ===================

    function test_validateOpenPositionCount_withinLimit() public {
        vm.prank(owner);
        limits.setMaxOpenPositions(3);

        limits.incrementOpenPositions(trader);
        limits.incrementOpenPositions(trader);
        limits.incrementOpenPositions(trader);
        // 3 positions, limit is 3 — should have passed
        assertEq(limits.openPositionCount(trader), 3);
    }

    function test_validateOpenPositionCount_exceedsLimit() public {
        vm.prank(owner);
        limits.setMaxOpenPositions(2);

        limits.incrementOpenPositions(trader);
        limits.incrementOpenPositions(trader);

        vm.expectRevert(abi.encodeWithSelector(TradeLimits.MaxOpenPositionsExceeded.selector, trader, 2));
        limits.incrementOpenPositions(trader);
    }

    function test_validateOpenPositionCount_zeroLimit_meansUnlimited() public {
        // no limit set
        for (uint256 i = 0; i < 100; i++) {
            limits.incrementOpenPositions(trader);
        }
        assertEq(limits.openPositionCount(trader), 100);
    }

    function test_decrementOpenPositions() public {
        vm.prank(owner);
        limits.setMaxOpenPositions(2);

        limits.incrementOpenPositions(trader);
        limits.incrementOpenPositions(trader);

        // At max — can't open more
        vm.expectRevert(abi.encodeWithSelector(TradeLimits.MaxOpenPositionsExceeded.selector, trader, 2));
        limits.incrementOpenPositions(trader);

        // Close one
        limits.decrementOpenPositions(trader);
        assertEq(limits.openPositionCount(trader), 1);

        // Now can open again
        limits.incrementOpenPositions(trader);
        assertEq(limits.openPositionCount(trader), 2);
    }

    function test_decrementOpenPositions_zeroIsNoOp() public {
        // Should not underflow
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
