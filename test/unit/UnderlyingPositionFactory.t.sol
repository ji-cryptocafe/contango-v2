//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../../src/moneymarkets/UnderlyingPositionFactory.sol";
import "../../src/moneymarkets/interfaces/IMoneyMarket.sol";
import "../../src/libraries/DataTypes.sol";
import "../../src/libraries/Roles.sol";

contract MockMoneyMarket is IMoneyMarket {

    MoneyMarketId public immutable _moneyMarketId;
    bool public immutable _needsAccount;

    constructor(MoneyMarketId mmId, bool needsAccount_) {
        _moneyMarketId = mmId;
        _needsAccount = needsAccount_;
    }

    function moneyMarketId() external view override returns (MoneyMarketId) {
        return _moneyMarketId;
    }

    function NEEDS_ACCOUNT() external view override returns (bool) {
        return _needsAccount;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IMoneyMarket).interfaceId;
    }

    function initialise(PositionId, IERC20, IERC20) external override { }
    function lend(PositionId, IERC20, uint256) external override returns (uint256) { return 0; }
    function withdraw(PositionId, IERC20, uint256, address) external override returns (uint256) { return 0; }
    function borrow(PositionId, IERC20, uint256, address) external override returns (uint256) { return 0; }
    function repay(PositionId, IERC20, uint256) external override returns (uint256) { return 0; }
    function claimRewards(PositionId, IERC20, IERC20, address) external override { }
    function collateralBalance(PositionId, IERC20) external override returns (uint256) { return 0; }
    function debtBalance(PositionId, IERC20) external override returns (uint256) { return 0; }
    function retrieve(PositionId, IERC20) external override returns (uint256) { return 0; }

}

contract UnderlyingPositionFactoryTest is Test, IUnderlyingPositionFactoryEvents {

    UnderlyingPositionFactory internal factory;
    address internal admin;
    address internal contangoAddr;

    MoneyMarketId internal constant MM_1 = MoneyMarketId.wrap(1);
    MoneyMarketId internal constant MM_2 = MoneyMarketId.wrap(2);
    MoneyMarketId internal constant MM_3 = MoneyMarketId.wrap(3);

    function setUp() public {
        admin = makeAddr("admin");
        contangoAddr = makeAddr("contango");

        factory = new UnderlyingPositionFactory(Timelock.wrap(admin));

        // Grant CONTANGO_ROLE to contangoAddr
        vm.prank(admin);
        factory.grantRole(CONTANGO_ROLE, contangoAddr);
    }

    function _makePositionId(MoneyMarketId mm, uint48 number) internal pure returns (PositionId) {
        Symbol symbol = Symbol.wrap(bytes16("TEST"));
        return PositionId.wrap(
            bytes32(
                uint256(uint128(Symbol.unwrap(symbol))) << 128 | uint256(MoneyMarketId.unwrap(mm)) << 120
                    | uint256(type(uint32).max) << 88 | uint256(number)
            )
        );
    }

    // ==================== Registration Tests ====================

    function test_registerMoneyMarket_success() public {
        MockMoneyMarket mm = new MockMoneyMarket(MM_1, true);

        vm.expectEmit(true, true, true, true);
        emit MoneyMarketRegistered(MM_1, IMoneyMarket(address(mm)));

        vm.prank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        assertEq(address(factory.moneyMarket(MM_1)), address(mm));
    }

    function test_registerMoneyMarket_doubleRegister_reverts() public {
        MockMoneyMarket mm = new MockMoneyMarket(MM_1, true);

        vm.startPrank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        vm.expectRevert(
            abi.encodeWithSelector(
                UnderlyingPositionFactory.MoneyMarketAlreadyRegistered.selector, MM_1, IMoneyMarket(address(mm))
            )
        );
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));
        vm.stopPrank();
    }

    function test_registerMoneyMarket_accessControl_reverts(address rando) public {
        vm.assume(rando != admin);

        MockMoneyMarket mm = new MockMoneyMarket(MM_1, true);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(rando), 20),
                " is missing role ",
                Strings.toHexString(uint256(factory.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        vm.prank(rando);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));
    }

    // ==================== CreateUnderlyingPosition Tests ====================

    function test_createUnderlyingPosition_needsAccount_clones() public {
        MockMoneyMarket mm = new MockMoneyMarket(MM_1, true);

        vm.prank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        PositionId positionId = _makePositionId(MM_1, 1);
        address expectedClone =
            Clones.predictDeterministicAddress(address(mm), PositionId.unwrap(positionId), address(factory));

        vm.expectEmit(true, true, true, true);
        emit UnderlyingPositionCreated(expectedClone, positionId);

        vm.prank(contangoAddr);
        IMoneyMarket result = factory.createUnderlyingPosition(positionId);

        assertEq(address(result), expectedClone);
        assertTrue(address(result) != address(mm), "should be a clone, not the original");
    }

    function test_createUnderlyingPosition_noAccount_returnsDirect() public {
        MockMoneyMarket mm = new MockMoneyMarket(MM_1, false);

        vm.prank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        PositionId positionId = _makePositionId(MM_1, 1);

        vm.prank(contangoAddr);
        IMoneyMarket result = factory.createUnderlyingPosition(positionId);

        assertEq(address(result), address(mm), "should return the original money market directly");
    }

    function test_createUnderlyingPosition_accessControl_reverts(address rando) public {
        vm.assume(rando != contangoAddr);

        MockMoneyMarket mm = new MockMoneyMarket(MM_1, true);
        vm.prank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        PositionId positionId = _makePositionId(MM_1, 1);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(rando), 20),
                " is missing role ",
                Strings.toHexString(uint256(CONTANGO_ROLE), 32)
            )
        );
        vm.prank(rando);
        factory.createUnderlyingPosition(positionId);
    }

    function test_createUnderlyingPosition_unregisteredMM_reverts() public {
        PositionId positionId = _makePositionId(MM_1, 1);

        vm.prank(contangoAddr);
        vm.expectRevert(abi.encodeWithSelector(UnderlyingPositionFactory.InvalidMoneyMarket.selector, MM_1));
        factory.createUnderlyingPosition(positionId);
    }

    // ==================== MoneyMarket View Tests ====================

    function test_moneyMarketByPositionId_needsAccount_returnsPredictedClone() public {
        MockMoneyMarket mm = new MockMoneyMarket(MM_1, true);

        vm.prank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        PositionId positionId = _makePositionId(MM_1, 42);
        address expected =
            Clones.predictDeterministicAddress(address(mm), PositionId.unwrap(positionId), address(factory));

        assertEq(address(factory.moneyMarket(positionId)), expected);
    }

    function test_moneyMarketByPositionId_noAccount_returnsDirect() public {
        MockMoneyMarket mm = new MockMoneyMarket(MM_1, false);

        vm.prank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        PositionId positionId = _makePositionId(MM_1, 42);

        assertEq(address(factory.moneyMarket(positionId)), address(mm));
    }

    function test_moneyMarketByPositionId_matchesCreateResult() public {
        MockMoneyMarket mm = new MockMoneyMarket(MM_1, true);

        vm.prank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        PositionId positionId = _makePositionId(MM_1, 7);

        // View should predict the same address as the actual clone
        address predicted = address(factory.moneyMarket(positionId));

        vm.prank(contangoAddr);
        IMoneyMarket created = factory.createUnderlyingPosition(positionId);

        assertEq(address(created), predicted, "predicted address should match created clone");
    }

    function test_moneyMarketById_returnsRegistered() public {
        MockMoneyMarket mm = new MockMoneyMarket(MM_1, true);

        vm.prank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        assertEq(address(factory.moneyMarket(MM_1)), address(mm));
    }

    // ==================== Invalid MoneyMarket Tests ====================

    function test_moneyMarketById_unregistered_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(UnderlyingPositionFactory.InvalidMoneyMarket.selector, MM_1));
        factory.moneyMarket(MM_1);
    }

    function test_moneyMarketByPositionId_unregistered_reverts() public {
        PositionId positionId = _makePositionId(MM_1, 1);

        vm.expectRevert(abi.encodeWithSelector(UnderlyingPositionFactory.InvalidMoneyMarket.selector, MM_1));
        factory.moneyMarket(positionId);
    }

    // ==================== Multiple Money Markets Tests ====================

    function test_multipleMoneyMarkets_registerAndCreate() public {
        MockMoneyMarket mm1 = new MockMoneyMarket(MM_1, true);
        MockMoneyMarket mm2 = new MockMoneyMarket(MM_2, false);
        MockMoneyMarket mm3 = new MockMoneyMarket(MM_3, true);

        vm.startPrank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm1)));
        factory.registerMoneyMarket(IMoneyMarket(address(mm2)));
        factory.registerMoneyMarket(IMoneyMarket(address(mm3)));
        vm.stopPrank();

        // Verify registrations
        assertEq(address(factory.moneyMarket(MM_1)), address(mm1));
        assertEq(address(factory.moneyMarket(MM_2)), address(mm2));
        assertEq(address(factory.moneyMarket(MM_3)), address(mm3));

        // Create positions on each
        PositionId pid1 = _makePositionId(MM_1, 1);
        PositionId pid2 = _makePositionId(MM_2, 2);
        PositionId pid3 = _makePositionId(MM_3, 3);

        vm.startPrank(contangoAddr);

        // MM_1 needs account -> clone
        IMoneyMarket result1 = factory.createUnderlyingPosition(pid1);
        assertTrue(address(result1) != address(mm1), "MM_1 should clone");

        // MM_2 does not need account -> direct
        IMoneyMarket result2 = factory.createUnderlyingPosition(pid2);
        assertEq(address(result2), address(mm2), "MM_2 should return direct");

        // MM_3 needs account -> clone
        IMoneyMarket result3 = factory.createUnderlyingPosition(pid3);
        assertTrue(address(result3) != address(mm3), "MM_3 should clone");

        vm.stopPrank();

        // Verify views match
        assertEq(address(factory.moneyMarket(pid1)), address(result1));
        assertEq(address(factory.moneyMarket(pid2)), address(result2));
        assertEq(address(factory.moneyMarket(pid3)), address(result3));
    }

    function test_multiplePositions_sameMM() public {
        MockMoneyMarket mm = new MockMoneyMarket(MM_1, true);

        vm.prank(admin);
        factory.registerMoneyMarket(IMoneyMarket(address(mm)));

        vm.startPrank(contangoAddr);

        PositionId pid1 = _makePositionId(MM_1, 1);
        PositionId pid2 = _makePositionId(MM_1, 2);
        PositionId pid3 = _makePositionId(MM_1, 3);

        IMoneyMarket r1 = factory.createUnderlyingPosition(pid1);
        IMoneyMarket r2 = factory.createUnderlyingPosition(pid2);
        IMoneyMarket r3 = factory.createUnderlyingPosition(pid3);

        vm.stopPrank();

        // All clones should be different addresses
        assertTrue(address(r1) != address(r2));
        assertTrue(address(r2) != address(r3));
        assertTrue(address(r1) != address(r3));

        // All different from the original
        assertTrue(address(r1) != address(mm));
        assertTrue(address(r2) != address(mm));
        assertTrue(address(r3) != address(mm));
    }

    // ==================== Constructor Tests ====================

    function test_constructor_grantsAdminRole() public {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_constructor_deployer_hasNoRole() public {
        assertFalse(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), address(this)));
    }

}
