//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/Address.sol";

import "../../src/moneymarkets/BaseMoneyMarket.sol";
import "../../src/moneymarkets/interfaces/IMoneyMarket.sol";
import "../../src/moneymarkets/interfaces/IUnderlyingPositionFactory.sol";
import "../../src/interfaces/IContango.sol";
import "../../src/interfaces/IVault.sol";
import "../../src/libraries/DataTypes.sol";
import "../../src/libraries/Errors.sol";

/// @dev Concrete implementation of BaseMoneyMarket with in-memory balance tracking
contract ConcreteMoneyMarket is BaseMoneyMarket {

    mapping(bytes32 => uint256) public collateralBalances;
    mapping(bytes32 => uint256) public debtBalances;

    constructor(MoneyMarketId _moneyMarketId, IContango _contango) BaseMoneyMarket(_moneyMarketId, _contango) { }

    function NEEDS_ACCOUNT() external pure returns (bool) {
        return true;
    }

    function _initialise(PositionId, IERC20, IERC20) internal override { }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address, uint256)
        internal
        override
        returns (uint256)
    {
        bytes32 key = keccak256(abi.encode(positionId, asset));
        collateralBalances[key] += amount;
        return amount;
    }

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address, uint256)
        internal
        override
        returns (uint256)
    {
        bytes32 key = keccak256(abi.encode(positionId, asset));
        uint256 bal = collateralBalances[key];
        uint256 withdrawn = amount > bal ? bal : amount;
        collateralBalances[key] -= withdrawn;
        return withdrawn;
    }

    function _borrow(PositionId positionId, IERC20 asset, uint256 amount, address, uint256)
        internal
        override
        returns (uint256)
    {
        bytes32 key = keccak256(abi.encode(positionId, asset));
        debtBalances[key] += amount;
        return amount;
    }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address, uint256)
        internal
        override
        returns (uint256)
    {
        bytes32 key = keccak256(abi.encode(positionId, asset));
        uint256 bal = debtBalances[key];
        uint256 repaid = amount > bal ? bal : amount;
        debtBalances[key] -= repaid;
        return repaid;
    }

    function _collateralBalance(PositionId positionId, IERC20 asset) internal override returns (uint256) {
        return collateralBalances[keccak256(abi.encode(positionId, asset))];
    }

    function _debtBalance(PositionId positionId, IERC20 asset) internal override returns (uint256) {
        return debtBalances[keccak256(abi.encode(positionId, asset))];
    }

    // Allow receiving ETH for retrieve tests
    receive() external payable { }

}

contract BaseMoneyMarketTest is Test, IMoneyMarketEvents {

    ConcreteMoneyMarket internal sut;
    address internal contangoAddr;
    address internal hacker;

    MoneyMarketId internal constant MM_ID = MoneyMarketId.wrap(5);
    MoneyMarketId internal constant WRONG_MM_ID = MoneyMarketId.wrap(7);

    IERC20 internal collateralAsset;
    IERC20 internal debtAsset;
    PositionId internal positionId;
    PositionId internal wrongMmPositionId;

    function setUp() public {
        contangoAddr = makeAddr("contango");
        hacker = makeAddr("hacker");

        // Deploy mock ERC20s
        collateralAsset = IERC20(address(new MockERC20("Collateral", "COL", 18)));
        debtAsset = IERC20(address(new MockERC20("Debt", "DBT", 18)));

        // Mock IContango at contangoAddr
        vm.etch(contangoAddr, hex"00");

        sut = new ConcreteMoneyMarket(MM_ID, IContango(contangoAddr));

        positionId = _makePositionId(MM_ID, 1);
        wrongMmPositionId = _makePositionId(WRONG_MM_ID, 1);
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

    // ==================== onlyContango Tests ====================

    function test_initialise_onlyContango_reverts() public {
        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.initialise(positionId, collateralAsset, debtAsset);
    }

    function test_lend_onlyContango_reverts() public {
        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.lend(positionId, collateralAsset, 100e18);
    }

    function test_withdraw_onlyContango_reverts() public {
        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.withdraw(positionId, collateralAsset, 100e18, hacker);
    }

    function test_borrow_onlyContango_reverts() public {
        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.borrow(positionId, debtAsset, 100e18, hacker);
    }

    function test_repay_onlyContango_reverts() public {
        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.repay(positionId, debtAsset, 100e18);
    }

    function test_claimRewards_onlyContango_reverts() public {
        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.claimRewards(positionId, collateralAsset, debtAsset, hacker);
    }

    // ==================== Initialise Tests ====================

    function test_initialise_matchingMM_succeeds() public {
        vm.prank(contangoAddr);
        sut.initialise(positionId, collateralAsset, debtAsset);
        // No revert means success
    }

    function test_initialise_wrongMM_reverts() public {
        vm.prank(contangoAddr);
        vm.expectRevert(abi.encodeWithSelector(IMoneyMarket.InvalidMoneyMarketId.selector));
        sut.initialise(wrongMmPositionId, collateralAsset, debtAsset);
    }

    // ==================== Lend Tests ====================

    function test_lend_normal() public {
        vm.prank(contangoAddr);
        vm.expectEmit(true, true, true, true);
        emit Lent(positionId, collateralAsset, 100e18, 0);

        uint256 lent = sut.lend(positionId, collateralAsset, 100e18);
        assertEq(lent, 100e18);

        // Verify balance tracking
        assertEq(sut.collateralBalances(keccak256(abi.encode(positionId, collateralAsset))), 100e18);
    }

    function test_lend_zeroAmount_returnsZero() public {
        vm.prank(contangoAddr);
        uint256 lent = sut.lend(positionId, collateralAsset, 0);
        assertEq(lent, 0);
    }

    function test_lend_emitsEvent() public {
        // Lend some first so balanceBefore is non-zero
        vm.prank(contangoAddr);
        sut.lend(positionId, collateralAsset, 50e18);

        vm.prank(contangoAddr);
        vm.expectEmit(true, true, true, true);
        emit Lent(positionId, collateralAsset, 75e18, 50e18);
        sut.lend(positionId, collateralAsset, 75e18);
    }

    // ==================== Withdraw Tests ====================

    function test_withdraw_normal() public {
        // First lend to have a balance
        vm.prank(contangoAddr);
        sut.lend(positionId, collateralAsset, 100e18);

        address receiver = makeAddr("receiver");

        vm.prank(contangoAddr);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(positionId, collateralAsset, 40e18, 100e18);

        uint256 withdrawn = sut.withdraw(positionId, collateralAsset, 40e18, receiver);
        assertEq(withdrawn, 40e18);
    }

    function test_withdraw_zeroAmount_returnsZero() public {
        // Lend first
        vm.prank(contangoAddr);
        sut.lend(positionId, collateralAsset, 100e18);

        vm.prank(contangoAddr);
        uint256 withdrawn = sut.withdraw(positionId, collateralAsset, 0, hacker);
        assertEq(withdrawn, 0);
    }

    function test_withdraw_zeroBalance_returnsZero() public {
        // No collateral deposited, balance is 0
        vm.prank(contangoAddr);
        uint256 withdrawn = sut.withdraw(positionId, collateralAsset, 100e18, hacker);
        assertEq(withdrawn, 0);
    }

    // ==================== Borrow Tests ====================

    function test_borrow_normal() public {
        address receiver = makeAddr("receiver");

        vm.prank(contangoAddr);
        vm.expectEmit(true, true, true, true);
        emit Borrowed(positionId, debtAsset, 50e18, 0);

        uint256 borrowed = sut.borrow(positionId, debtAsset, 50e18, receiver);
        assertEq(borrowed, 50e18);
    }

    function test_borrow_zeroAmount_returnsZero() public {
        vm.prank(contangoAddr);
        uint256 borrowed = sut.borrow(positionId, debtAsset, 0, hacker);
        assertEq(borrowed, 0);
    }

    // ==================== Repay Tests ====================

    function test_repay_normal() public {
        // Borrow first to create debt
        vm.prank(contangoAddr);
        sut.borrow(positionId, debtAsset, 100e18, hacker);

        vm.prank(contangoAddr);
        vm.expectEmit(true, true, true, true);
        emit Repaid(positionId, debtAsset, 60e18, 100e18);

        uint256 repaid = sut.repay(positionId, debtAsset, 60e18);
        assertEq(repaid, 60e18);
    }

    function test_repay_zeroAmount_returnsZero() public {
        vm.prank(contangoAddr);
        uint256 repaid = sut.repay(positionId, debtAsset, 0);
        assertEq(repaid, 0);
    }

    function test_repay_zeroBalance_returnsZero() public {
        // No debt, balance is 0
        vm.prank(contangoAddr);
        uint256 repaid = sut.repay(positionId, debtAsset, 100e18);
        assertEq(repaid, 0);
    }

    // ==================== ClaimRewards Tests ====================

    function test_claimRewards_emitsEvent() public {
        address receiver = makeAddr("receiver");

        vm.prank(contangoAddr);
        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(positionId, receiver);

        sut.claimRewards(positionId, collateralAsset, debtAsset, receiver);
    }

    // ==================== Retrieve Tests ====================

    function test_retrieve_invalidPositionId_reverts() public {
        // Mock the positionFactory to return a different money market address
        address mockFactory = makeAddr("factory");
        address wrongMM = makeAddr("wrongMM");

        vm.mockCall(
            contangoAddr,
            abi.encodeWithSelector(IContango.positionFactory.selector),
            abi.encode(mockFactory)
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(bytes4(keccak256("moneyMarket(bytes32)")), positionId),
            abi.encode(wrongMM)
        );

        vm.expectRevert(abi.encodeWithSelector(IMoneyMarket.InvalidPositionId.selector, positionId));
        sut.retrieve(positionId, collateralAsset);
    }

    function test_retrieve_unsupportedToken_reverts() public {
        address mockFactory = makeAddr("factory");
        address mockNFT = makeAddr("nft");
        address mockVault = makeAddr("vault");
        address owner = makeAddr("owner");

        // Mock positionFactory to return sut as the money market
        vm.mockCall(
            contangoAddr,
            abi.encodeWithSelector(IContango.positionFactory.selector),
            abi.encode(mockFactory)
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(bytes4(keccak256("moneyMarket(bytes32)")), positionId),
            abi.encode(address(sut))
        );
        vm.mockCall(
            contangoAddr,
            abi.encodeWithSelector(IContango.positionNFT.selector),
            abi.encode(mockNFT)
        );
        // Mock PositionNFT.exists -> true
        vm.mockCall(
            mockNFT,
            abi.encodeWithSelector(bytes4(keccak256("exists(bytes32)"))),
            abi.encode(true)
        );
        vm.mockCall(
            mockNFT,
            abi.encodeWithSelector(bytes4(keccak256("positionOwner(bytes32)"))),
            abi.encode(owner)
        );
        // Mock vault
        vm.mockCall(
            contangoAddr,
            abi.encodeWithSelector(IContango.vault.selector),
            abi.encode(mockVault)
        );
        // Token not supported
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IVault.isTokenSupported.selector, collateralAsset),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(IMoneyMarket.TokenCantBeRetrieved.selector, collateralAsset));
        sut.retrieve(positionId, collateralAsset);
    }

    function test_retrieve_nativeETH() public {
        address mockFactory = makeAddr("factory");
        address mockNFT = makeAddr("nft");
        address owner = makeAddr("owner");

        // Mock positionFactory to return sut as the money market
        vm.mockCall(
            contangoAddr,
            abi.encodeWithSelector(IContango.positionFactory.selector),
            abi.encode(mockFactory)
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(bytes4(keccak256("moneyMarket(bytes32)")), positionId),
            abi.encode(address(sut))
        );
        vm.mockCall(
            contangoAddr,
            abi.encodeWithSelector(IContango.positionNFT.selector),
            abi.encode(mockNFT)
        );
        vm.mockCall(
            mockNFT,
            abi.encodeWithSelector(bytes4(keccak256("exists(bytes32)"))),
            abi.encode(true)
        );
        vm.mockCall(
            mockNFT,
            abi.encodeWithSelector(bytes4(keccak256("positionOwner(bytes32)"))),
            abi.encode(owner)
        );

        // Send some ETH to the sut contract
        vm.deal(address(sut), 1 ether);

        // Retrieve with token = address(0) means native ETH
        vm.expectEmit(true, true, true, true);
        emit Retrieved(positionId, IERC20(address(0)), 1 ether);

        uint256 amount = sut.retrieve(positionId, IERC20(address(0)));
        assertEq(amount, 1 ether);
        assertEq(owner.balance, 1 ether);
    }

    function test_retrieve_validToken() public {
        address mockFactory = makeAddr("factory");
        address mockNFT = makeAddr("nft");
        address mockVault = makeAddr("vault");
        address owner = makeAddr("owner");

        // Mock positionFactory to return sut as the money market
        vm.mockCall(
            contangoAddr,
            abi.encodeWithSelector(IContango.positionFactory.selector),
            abi.encode(mockFactory)
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(bytes4(keccak256("moneyMarket(bytes32)")), positionId),
            abi.encode(address(sut))
        );
        vm.mockCall(
            contangoAddr,
            abi.encodeWithSelector(IContango.positionNFT.selector),
            abi.encode(mockNFT)
        );
        vm.mockCall(
            mockNFT,
            abi.encodeWithSelector(bytes4(keccak256("exists(bytes32)"))),
            abi.encode(true)
        );
        vm.mockCall(
            mockNFT,
            abi.encodeWithSelector(bytes4(keccak256("positionOwner(bytes32)"))),
            abi.encode(owner)
        );
        vm.mockCall(
            contangoAddr,
            abi.encodeWithSelector(IContango.vault.selector),
            abi.encode(mockVault)
        );
        vm.mockCall(
            mockVault,
            abi.encodeWithSelector(IVault.isTokenSupported.selector, collateralAsset),
            abi.encode(true)
        );

        // Transfer some tokens to sut
        MockERC20(address(collateralAsset)).mint(address(sut), 500e18);

        vm.expectEmit(true, true, true, true);
        emit Retrieved(positionId, collateralAsset, 500e18);

        uint256 amount = sut.retrieve(positionId, collateralAsset);
        assertEq(amount, 500e18);
        assertEq(IERC20(collateralAsset).balanceOf(owner), 500e18);
    }

    // ==================== SupportsInterface Tests ====================

    function test_supportsInterface_IMoneyMarket() public view {
        assertTrue(sut.supportsInterface(type(IMoneyMarket).interfaceId));
    }

    function test_supportsInterface_random_returnsFalse() public view {
        assertFalse(sut.supportsInterface(0xdeadbeef));
    }

    // ==================== CollateralBalance and DebtBalance Tests ====================

    function test_collateralBalance_delegatesToInternal() public {
        vm.prank(contangoAddr);
        sut.lend(positionId, collateralAsset, 200e18);

        uint256 bal = sut.collateralBalance(positionId, collateralAsset);
        assertEq(bal, 200e18);
    }

    function test_debtBalance_delegatesToInternal() public {
        vm.prank(contangoAddr);
        sut.borrow(positionId, debtAsset, 150e18, hacker);

        uint256 bal = sut.debtBalance(positionId, debtAsset);
        assertEq(bal, 150e18);
    }

}

/// @dev Minimal ERC20 mock for testing
contract MockERC20 {

    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

}
