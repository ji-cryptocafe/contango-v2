//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "src/security/AccessGate.sol";

contract AccessGateTest is Test {

    event WalletWhitelisted(address indexed wallet);
    event WalletRemoved(address indexed wallet);

    AccessGate gate;
    address owner = makeAddr("owner");
    address rando = makeAddr("rando");
    address wallet1 = makeAddr("wallet1");
    address wallet2 = makeAddr("wallet2");
    address wallet3 = makeAddr("wallet3");

    function setUp() public {
        vm.prank(owner);
        gate = new AccessGate();
    }

    // =================== Ownership ===================

    function test_constructor_setsOwner() public view {
        assertEq(gate.owner(), owner);
    }

    function test_nonOwner_cannotAddWallet() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        gate.addWallet(wallet1);
    }

    function test_nonOwner_cannotRemoveWallet() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        gate.removeWallet(wallet1);
    }

    function test_nonOwner_cannotSetMaxWallets() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        gate.setMaxWhitelistedWallets(20);
    }

    // =================== addWallet ===================

    function test_addWallet_success() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit WalletWhitelisted(wallet1);
        gate.addWallet(wallet1);

        assertTrue(gate.whitelistedWallets(wallet1));
        assertEq(gate.whitelistedCount(), 1);
    }

    function test_addWallet_multiple() public {
        vm.startPrank(owner);
        gate.addWallet(wallet1);
        gate.addWallet(wallet2);
        gate.addWallet(wallet3);
        vm.stopPrank();

        assertTrue(gate.whitelistedWallets(wallet1));
        assertTrue(gate.whitelistedWallets(wallet2));
        assertTrue(gate.whitelistedWallets(wallet3));
        assertEq(gate.whitelistedCount(), 3);
    }

    function test_addWallet_duplicate_noOp() public {
        vm.startPrank(owner);
        gate.addWallet(wallet1);
        gate.addWallet(wallet1); // duplicate
        vm.stopPrank();

        assertTrue(gate.whitelistedWallets(wallet1));
        assertEq(gate.whitelistedCount(), 1); // not double-counted
    }

    function test_addWallet_rejectsWhenMaxReached() public {
        vm.startPrank(owner);
        gate.setMaxWhitelistedWallets(2);
        gate.addWallet(wallet1);
        gate.addWallet(wallet2);

        vm.expectRevert(AccessGate.MaxWalletsReached.selector);
        gate.addWallet(wallet3);
        vm.stopPrank();
    }

    function test_addWallet_duplicateDoesNotCountTowardsMax() public {
        vm.startPrank(owner);
        gate.setMaxWhitelistedWallets(2);
        gate.addWallet(wallet1);
        gate.addWallet(wallet1); // duplicate — should not increment count
        gate.addWallet(wallet2); // should succeed (count is still 2)
        vm.stopPrank();

        assertEq(gate.whitelistedCount(), 2);
    }

    // =================== removeWallet ===================

    function test_removeWallet_success() public {
        vm.startPrank(owner);
        gate.addWallet(wallet1);
        assertTrue(gate.whitelistedWallets(wallet1));

        vm.expectEmit(true, false, false, true);
        emit WalletRemoved(wallet1);
        gate.removeWallet(wallet1);
        vm.stopPrank();

        assertFalse(gate.whitelistedWallets(wallet1));
        assertEq(gate.whitelistedCount(), 0);
    }

    function test_removeWallet_notWhitelisted_noOp() public {
        vm.prank(owner);
        gate.removeWallet(wallet1); // not whitelisted, should not revert

        assertEq(gate.whitelistedCount(), 0);
    }

    function test_removeWallet_freesSlotForNew() public {
        vm.startPrank(owner);
        gate.setMaxWhitelistedWallets(2);
        gate.addWallet(wallet1);
        gate.addWallet(wallet2);

        // Max reached — can't add
        vm.expectRevert(AccessGate.MaxWalletsReached.selector);
        gate.addWallet(wallet3);

        // Remove one — now there's room
        gate.removeWallet(wallet1);
        gate.addWallet(wallet3); // should succeed
        vm.stopPrank();

        assertFalse(gate.whitelistedWallets(wallet1));
        assertTrue(gate.whitelistedWallets(wallet3));
        assertEq(gate.whitelistedCount(), 2);
    }

    // =================== setMaxWhitelistedWallets ===================

    function test_setMaxWhitelistedWallets() public {
        vm.prank(owner);
        gate.setMaxWhitelistedWallets(5);
        assertEq(gate.maxWhitelistedWallets(), 5);
    }

    function test_setMaxWhitelistedWallets_canReduceBelowCurrent() public {
        // Edge case: reducing max below current count doesn't remove wallets,
        // just prevents adding more
        vm.startPrank(owner);
        gate.addWallet(wallet1);
        gate.addWallet(wallet2);
        gate.setMaxWhitelistedWallets(1);
        vm.stopPrank();

        // Both still whitelisted
        assertTrue(gate.whitelistedWallets(wallet1));
        assertTrue(gate.whitelistedWallets(wallet2));
        assertEq(gate.whitelistedCount(), 2);

        // But can't add more
        vm.prank(owner);
        vm.expectRevert(AccessGate.MaxWalletsReached.selector);
        gate.addWallet(wallet3);
    }

    function test_defaultMaxWallets_is10() public view {
        assertEq(gate.maxWhitelistedWallets(), 10);
    }

    // =================== isWhitelisted ===================

    function test_isWhitelisted_true() public {
        vm.prank(owner);
        gate.addWallet(wallet1);
        assertTrue(gate.isWhitelisted(wallet1));
    }

    function test_isWhitelisted_false() public view {
        assertFalse(gate.isWhitelisted(rando));
    }

    function test_isWhitelisted_afterRemoval() public {
        vm.startPrank(owner);
        gate.addWallet(wallet1);
        gate.removeWallet(wallet1);
        vm.stopPrank();
        assertFalse(gate.isWhitelisted(wallet1));
    }

    // =================== requireWhitelisted ===================

    function test_requireWhitelisted_passes() public {
        vm.prank(owner);
        gate.addWallet(wallet1);

        gate.requireWhitelisted(wallet1); // should not revert
    }

    function test_requireWhitelisted_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(AccessGate.NotWhitelisted.selector, rando));
        gate.requireWhitelisted(rando);
    }

    // =================== Fuzz ===================

    function test_fuzz_unwhitelisted_reverts(address randomWallet) public {
        vm.expectRevert(abi.encodeWithSelector(AccessGate.NotWhitelisted.selector, randomWallet));
        gate.requireWhitelisted(randomWallet);
    }

    function test_fuzz_whitelisted_passes(address wallet) public {
        vm.prank(owner);
        gate.addWallet(wallet);
        gate.requireWhitelisted(wallet);
    }

}
