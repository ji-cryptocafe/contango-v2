//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "src/security/RouterGuard.sol";

contract RouterGuardTest is Test {

    event RouterSet(address indexed router, bool indexed allowed);
    event SpenderSet(address indexed spender, bool indexed allowed);
    event FlashLoanProviderSet(address indexed provider, bool indexed allowed);

    RouterGuard guard;
    address owner = makeAddr("owner");
    address rando = makeAddr("rando");

    address router1 = makeAddr("router1");
    address router2 = makeAddr("router2");
    address spender1 = makeAddr("spender1");
    address flp1 = makeAddr("flashLoanProvider1");

    function setUp() public {
        vm.prank(owner);
        guard = new RouterGuard();
    }

    // =================== Ownership ===================

    function test_constructor_setsOwner() public view {
        assertEq(guard.owner(), owner);
    }

    function test_nonOwner_cannotSetRouter() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        guard.setRouter(router1, true);
    }

    function test_nonOwner_cannotSetSpender() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        guard.setSpender(spender1, true);
    }

    function test_nonOwner_cannotSetFlashLoanProvider() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        guard.setFlashLoanProvider(flp1, true);
    }

    // =================== setRouter ===================

    function test_setRouter_enable() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit RouterSet(router1, true);
        guard.setRouter(router1, true);

        assertTrue(guard.allowedRouters(router1));
    }

    function test_setRouter_disable() public {
        vm.startPrank(owner);
        guard.setRouter(router1, true);
        assertTrue(guard.allowedRouters(router1));

        vm.expectEmit(true, true, false, true);
        emit RouterSet(router1, false);
        guard.setRouter(router1, false);
        vm.stopPrank();

        assertFalse(guard.allowedRouters(router1));
    }

    function test_setRouter_multipleRouters() public {
        vm.startPrank(owner);
        guard.setRouter(router1, true);
        guard.setRouter(router2, true);
        vm.stopPrank();

        assertTrue(guard.allowedRouters(router1));
        assertTrue(guard.allowedRouters(router2));
    }

    // =================== setSpender ===================

    function test_setSpender_enable() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit SpenderSet(spender1, true);
        guard.setSpender(spender1, true);

        assertTrue(guard.allowedSpenders(spender1));
    }

    function test_setSpender_disable() public {
        vm.startPrank(owner);
        guard.setSpender(spender1, true);
        guard.setSpender(spender1, false);
        vm.stopPrank();

        assertFalse(guard.allowedSpenders(spender1));
    }

    // =================== setFlashLoanProvider ===================

    function test_setFlashLoanProvider_enable() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit FlashLoanProviderSet(flp1, true);
        guard.setFlashLoanProvider(flp1, true);

        assertTrue(guard.allowedFlashLoanProviders(flp1));
    }

    function test_setFlashLoanProvider_disable() public {
        vm.startPrank(owner);
        guard.setFlashLoanProvider(flp1, true);
        guard.setFlashLoanProvider(flp1, false);
        vm.stopPrank();

        assertFalse(guard.allowedFlashLoanProviders(flp1));
    }

    // =================== validateRouter ===================

    function test_validateRouter_allowed() public {
        vm.prank(owner);
        guard.setRouter(router1, true);

        // Should not revert
        guard.validateRouter(router1);
    }

    function test_validateRouter_disallowed() public {
        vm.expectRevert(abi.encodeWithSelector(RouterGuard.RouterNotAllowed.selector, router1));
        guard.validateRouter(router1);
    }

    function test_validateRouter_disabledAfterEnable() public {
        vm.startPrank(owner);
        guard.setRouter(router1, true);
        guard.setRouter(router1, false);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(RouterGuard.RouterNotAllowed.selector, router1));
        guard.validateRouter(router1);
    }

    // =================== validateSpender ===================

    function test_validateSpender_allowed() public {
        vm.prank(owner);
        guard.setSpender(spender1, true);

        guard.validateSpender(spender1);
    }

    function test_validateSpender_disallowed() public {
        vm.expectRevert(abi.encodeWithSelector(RouterGuard.SpenderNotAllowed.selector, spender1));
        guard.validateSpender(spender1);
    }

    // =================== validateFlashLoanProvider ===================

    function test_validateFlashLoanProvider_allowed() public {
        vm.prank(owner);
        guard.setFlashLoanProvider(flp1, true);

        guard.validateFlashLoanProvider(flp1);
    }

    function test_validateFlashLoanProvider_disallowed() public {
        vm.expectRevert(abi.encodeWithSelector(RouterGuard.FlashLoanProviderNotAllowed.selector, flp1));
        guard.validateFlashLoanProvider(flp1);
    }

    function test_validateFlashLoanProvider_addressZero_alwaysAllowed() public view {
        // address(0) means "no flash loan provider" — should not revert
        guard.validateFlashLoanProvider(address(0));
    }

    // =================== validateExecution (combined) ===================

    function test_validateExecution_allAllowed() public {
        vm.startPrank(owner);
        guard.setRouter(router1, true);
        guard.setSpender(spender1, true);
        guard.setFlashLoanProvider(flp1, true);
        vm.stopPrank();

        guard.validateExecution(router1, spender1, flp1);
    }

    function test_validateExecution_routerNotAllowed() public {
        vm.startPrank(owner);
        guard.setSpender(spender1, true);
        guard.setFlashLoanProvider(flp1, true);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(RouterGuard.RouterNotAllowed.selector, router1));
        guard.validateExecution(router1, spender1, flp1);
    }

    function test_validateExecution_spenderNotAllowed() public {
        vm.startPrank(owner);
        guard.setRouter(router1, true);
        guard.setFlashLoanProvider(flp1, true);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(RouterGuard.SpenderNotAllowed.selector, spender1));
        guard.validateExecution(router1, spender1, flp1);
    }

    function test_validateExecution_flashLoanProviderNotAllowed() public {
        vm.startPrank(owner);
        guard.setRouter(router1, true);
        guard.setSpender(spender1, true);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(RouterGuard.FlashLoanProviderNotAllowed.selector, flp1));
        guard.validateExecution(router1, spender1, flp1);
    }

    function test_validateExecution_zeroFlashLoanProvider_skipsCheck() public {
        vm.startPrank(owner);
        guard.setRouter(router1, true);
        guard.setSpender(spender1, true);
        vm.stopPrank();

        // address(0) flash loan provider should pass without being whitelisted
        guard.validateExecution(router1, spender1, address(0));
    }

    function test_validateExecution_routerEqualsSpender() public {
        // Common case: router and spender are the same address (e.g., KyberSwap)
        vm.startPrank(owner);
        guard.setRouter(router1, true);
        guard.setSpender(router1, true);
        vm.stopPrank();

        guard.validateExecution(router1, router1, address(0));
    }

    // =================== Fuzz ===================

    function test_fuzz_unwhitelistedRouter_reverts(address randomRouter) public {
        vm.assume(randomRouter != address(0));
        vm.expectRevert(abi.encodeWithSelector(RouterGuard.RouterNotAllowed.selector, randomRouter));
        guard.validateRouter(randomRouter);
    }

    function test_fuzz_unwhitelistedSpender_reverts(address randomSpender) public {
        vm.assume(randomSpender != address(0));
        vm.expectRevert(abi.encodeWithSelector(RouterGuard.SpenderNotAllowed.selector, randomSpender));
        guard.validateSpender(randomSpender);
    }

}
