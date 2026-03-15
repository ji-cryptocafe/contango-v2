//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";

import "src/core/Maestro.sol";
import "src/interfaces/IContango.sol";
import "src/interfaces/IVault.sol";
import "src/interfaces/IMaestro.sol";
import "src/utils/SimpleSpotExecutor.sol";
import "src/libraries/DataTypes.sol";
import "src/libraries/Errors.sol";

// ============ Mock WETH ============

contract MockWETH is Test {

    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
    }

    function totalSupply() external view returns (uint256) {
        return address(this).balance;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
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

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }

}

// ============ Mock Vault ============

contract MockVault is Test {

    IWETH9 public nativeToken;

    mapping(IERC20 => mapping(address => uint256)) public balances;

    constructor(IWETH9 _nativeToken) {
        nativeToken = _nativeToken;
    }

    function balanceOf(IERC20 token, address owner) external view returns (uint256) {
        return balances[token][owner];
    }

    function deposit(IERC20 token, address account, uint256 amount) external returns (uint256) {
        balances[token][account] += amount;
        return amount;
    }

    function depositNative(address account) external payable returns (uint256) {
        balances[IERC20(address(nativeToken))][account] += msg.value;
        return msg.value;
    }

    function withdraw(IERC20 token, address account, uint256 amount, address to) external returns (uint256) {
        require(balances[token][account] >= amount, "MockVault: insufficient balance");
        balances[token][account] -= amount;
        // In a real vault this would transfer tokens; for testing we just track balances
        return amount;
    }

    function withdrawNative(address account, uint256 amount, address to) external returns (uint256) {
        IERC20 weth = IERC20(address(nativeToken));
        require(balances[weth][account] >= amount, "MockVault: insufficient balance");
        balances[weth][account] -= amount;
        return amount;
    }

    // Test helper to set balances directly
    function setBalance(IERC20 token, address owner, uint256 amount) external {
        balances[token][owner] = amount;
    }

}

// ============ Mock PositionNFT ============

contract MockPositionNFT {

    mapping(uint256 => address) public owners;
    mapping(uint256 => bool) public positions;
    mapping(address => mapping(address => bool)) public operatorApprovals;

    function exists(PositionId positionId) external view returns (bool) {
        return positions[uint256(PositionId.unwrap(positionId))];
    }

    function positionOwner(PositionId positionId) external view returns (address) {
        return owners[uint256(PositionId.unwrap(positionId))];
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return owner == operator || operatorApprovals[owner][operator];
    }

    // Test helpers
    function setPosition(PositionId positionId, address owner) external {
        uint256 id = uint256(PositionId.unwrap(positionId));
        positions[id] = true;
        owners[id] = owner;
    }

    function setApprovalForAll(address owner, address operator, bool approved) external {
        operatorApprovals[owner][operator] = approved;
    }

}

// ============ Mock Contango ============

contract MockContango {

    PositionNFT public positionNFT;

    // Storage for recording calls
    bool public tradeOnBehalfOfCalled;
    address public lastOnBehalfOf;
    TradeParams public lastTradeParams;

    // Return values for tradeOnBehalfOf
    PositionId public returnPositionId;
    Trade internal returnTrade;

    // Instrument storage
    mapping(bytes16 => Instrument) internal instruments;

    constructor(address _positionNFT) {
        positionNFT = PositionNFT(_positionNFT);
    }

    function tradeOnBehalfOf(TradeParams calldata tradeParams, ExecutionParams calldata, address onBehalfOf)
        external
        payable
        returns (PositionId, Trade memory)
    {
        tradeOnBehalfOfCalled = true;
        lastOnBehalfOf = onBehalfOf;
        // Store trade params
        lastTradeParams = tradeParams;
        return (returnPositionId, returnTrade);
    }

    function instrument(Symbol symbol) external view returns (Instrument memory) {
        return instruments[Symbol.unwrap(symbol)];
    }

    // Test helpers
    function setReturnPositionId(PositionId _positionId) external {
        returnPositionId = _positionId;
    }

    function setInstrument(Symbol symbol, IERC20 base, IERC20 quote) external {
        instruments[Symbol.unwrap(symbol)] = Instrument({
            base: base,
            baseUnit: 1e18,
            quote: quote,
            quoteUnit: 1e6,
            closingOnly: false
        });
    }

}

// ============ Maestro Unit Tests ============

contract MaestroUnitTest is Test {

    using SafeCast for *;
    using SignedMath for *;

    MockWETH internal weth;
    MockVault internal mockVault;
    MockPositionNFT internal mockPositionNFT;
    MockContango internal mockContango;
    SimpleSpotExecutor internal spotExecutor;
    Maestro internal maestro;

    address internal trader = makeAddr("trader");
    address internal recipient = makeAddr("recipient");

    IERC20 internal usdc;

    function setUp() public {
        weth = new MockWETH();
        mockPositionNFT = new MockPositionNFT();
        mockContango = new MockContango(address(mockPositionNFT));
        spotExecutor = new SimpleSpotExecutor();

        // Deploy mock vault
        mockVault = new MockVault(IWETH9(address(weth)));

        // Deploy a mock USDC token for testing
        MockToken mockUsdc = new MockToken("USD Coin", "USDC", 6);
        usdc = IERC20(address(mockUsdc));

        // Deploy maestro with mocks
        // We need the IContango and IVault interfaces so we cast our mocks
        maestro = new Maestro(IContango(address(mockContango)), IVault(address(mockVault)), spotExecutor);
    }

    // =================== deposit ===================

    function testDeposit_ForwardsToVault() public {
        uint256 amount = 10_000e6;

        vm.prank(trader);
        uint256 deposited = maestro.deposit(usdc, amount);

        assertEq(deposited, amount, "deposited amount");
        assertEq(mockVault.balances(usdc, trader), amount, "vault balance");
    }

    function testDeposit_MultipleCalls() public {
        vm.prank(trader);
        maestro.deposit(usdc, 1000e6);
        vm.prank(trader);
        maestro.deposit(usdc, 2000e6);

        assertEq(mockVault.balances(usdc, trader), 3000e6, "cumulative vault balance");
    }

    // =================== depositNative ===================

    function testDepositNative_WrapsAndForwards() public {
        vm.deal(trader, 10 ether);

        vm.prank(trader);
        uint256 deposited = maestro.depositNative{ value: 10 ether }();

        assertEq(deposited, 10 ether, "deposited amount");
        assertEq(mockVault.balances(IERC20(address(weth)), trader), 10 ether, "vault weth balance");
    }

    // =================== withdraw ===================

    function testWithdraw_ExactAmount() public {
        // Pre-fund vault balance
        mockVault.setBalance(usdc, trader, 10_000e6);

        vm.prank(trader);
        uint256 withdrawn = maestro.withdraw(usdc, 5000e6, recipient);

        assertEq(withdrawn, 5000e6, "withdrawn amount");
        assertEq(mockVault.balances(usdc, trader), 5000e6, "remaining vault balance");
    }

    function testWithdraw_All_ReadsBalance() public {
        // Pre-fund vault balance
        mockVault.setBalance(usdc, trader, 7777e6);

        vm.prank(trader);
        uint256 withdrawn = maestro.withdraw(usdc, 0, recipient); // ALL = 0

        assertEq(withdrawn, 7777e6, "withdrew full balance");
        assertEq(mockVault.balances(usdc, trader), 0, "vault balance zeroed");
    }

    function testWithdraw_ZeroBalance_ReturnsZero() public {
        // No balance in vault for trader
        vm.prank(trader);
        uint256 withdrawn = maestro.withdraw(usdc, 0, recipient);

        assertEq(withdrawn, 0, "zero returned for zero balance");
    }

    // =================== withdrawNative ===================

    function testWithdrawNative_ExactAmount() public {
        IERC20 wethToken = IERC20(address(weth));
        mockVault.setBalance(wethToken, trader, 10 ether);

        vm.prank(trader);
        uint256 withdrawn = maestro.withdrawNative(5 ether, recipient);

        assertEq(withdrawn, 5 ether, "withdrawn amount");
        assertEq(mockVault.balances(wethToken, trader), 5 ether, "remaining vault balance");
    }

    function testWithdrawNative_All() public {
        IERC20 wethToken = IERC20(address(weth));
        mockVault.setBalance(wethToken, trader, 3 ether);

        vm.prank(trader);
        uint256 withdrawn = maestro.withdrawNative(0, recipient); // ALL = 0

        assertEq(withdrawn, 3 ether, "withdrew full balance");
        assertEq(mockVault.balances(wethToken, trader), 0, "vault balance zeroed");
    }

    function testWithdrawNative_ZeroBalance_ReturnsZero() public {
        vm.prank(trader);
        uint256 withdrawn = maestro.withdrawNative(0, recipient);

        assertEq(withdrawn, 0, "zero returned for zero balance");
    }

    // =================== trade ===================

    function testTrade_NewPosition_CallsContango() public {
        // A position ID with number=0 means new position (doesn't exist yet)
        PositionId positionId = PositionId.wrap(bytes32(uint256(0x1234) << 48));

        TradeParams memory tradeParams = TradeParams({
            positionId: positionId,
            quantity: 1e18,
            limitPrice: 2000e6,
            cashflowCcy: Currency.Quote,
            cashflow: 1000e6
        });

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(0),
            router: address(0),
            swapAmount: 0,
            swapBytes: "",
            flashLoanProvider: IERC7399(address(0))
        });

        // New position: positionNFT.exists() returns false, so no permission check
        vm.prank(trader);
        maestro.trade(tradeParams, execParams);

        assertTrue(mockContango.tradeOnBehalfOfCalled(), "tradeOnBehalfOf called");
        assertEq(mockContango.lastOnBehalfOf(), trader, "onBehalfOf is trader");
    }

    function testTrade_ExistingPosition_ValidatesPermissions_Owner() public {
        // Create a position that exists and is owned by trader
        PositionId positionId = PositionId.wrap(bytes32(uint256(0xABCD)));
        mockPositionNFT.setPosition(positionId, trader);

        TradeParams memory tradeParams = TradeParams({
            positionId: positionId,
            quantity: -5e17,
            limitPrice: 2000e6,
            cashflowCcy: Currency.Quote,
            cashflow: 0
        });

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(0),
            router: address(0),
            swapAmount: 0,
            swapBytes: "",
            flashLoanProvider: IERC7399(address(0))
        });

        // Owner can modify their own position
        vm.prank(trader);
        maestro.trade(tradeParams, execParams);

        assertTrue(mockContango.tradeOnBehalfOfCalled(), "trade executed");
    }

    function testTrade_ExistingPosition_RevertsUnauthorized() public {
        PositionId positionId = PositionId.wrap(bytes32(uint256(0xABCD)));
        address positionOwner = makeAddr("positionOwner");
        mockPositionNFT.setPosition(positionId, positionOwner);

        TradeParams memory tradeParams = TradeParams({
            positionId: positionId,
            quantity: -5e17,
            limitPrice: 2000e6,
            cashflowCcy: Currency.Quote,
            cashflow: 0
        });

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(0),
            router: address(0),
            swapAmount: 0,
            swapBytes: "",
            flashLoanProvider: IERC7399(address(0))
        });

        // Random address without approval should be rejected
        address attacker = makeAddr("attacker");
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, attacker));
        vm.prank(attacker);
        maestro.trade(tradeParams, execParams);
    }

    function testTrade_ExistingPosition_ApprovedOperator() public {
        PositionId positionId = PositionId.wrap(bytes32(uint256(0xABCD)));
        address positionOwner = makeAddr("positionOwner");
        mockPositionNFT.setPosition(positionId, positionOwner);
        mockPositionNFT.setApprovalForAll(positionOwner, trader, true);

        TradeParams memory tradeParams = TradeParams({
            positionId: positionId,
            quantity: -5e17,
            limitPrice: 2000e6,
            cashflowCcy: Currency.Quote,
            cashflow: 0
        });

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(0),
            router: address(0),
            swapAmount: 0,
            swapBytes: "",
            flashLoanProvider: IERC7399(address(0))
        });

        vm.prank(trader);
        maestro.trade(tradeParams, execParams);

        assertTrue(mockContango.tradeOnBehalfOfCalled(), "approved operator can trade");
    }

    function testTrade_CashflowMax_UsesVaultBalance() public {
        // Set up instrument in mock contango
        PositionId positionId = PositionId.wrap(bytes32(uint256(0x1234) << 48));
        Symbol symbol = positionId.getSymbol();
        mockContango.setInstrument(symbol, IERC20(address(weth)), usdc);

        // Set trader's vault balance for the cashflow token (quote = usdc since cashflowCcy=Quote)
        mockVault.setBalance(usdc, trader, 5000e6);

        TradeParams memory tradeParams = TradeParams({
            positionId: positionId,
            quantity: 1e18,
            limitPrice: 2000e6,
            cashflowCcy: Currency.Quote,
            cashflow: type(int256).max // special: use full vault balance
        });

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(0),
            router: address(0),
            swapAmount: 0,
            swapBytes: "",
            flashLoanProvider: IERC7399(address(0))
        });

        vm.prank(trader);
        maestro.trade(tradeParams, execParams);

        // Verify the cashflow was set to the vault balance
        (,,,,int256 cashflow) = mockContango.lastTradeParams();
        assertEq(cashflow, int256(5000e6), "cashflow set to vault balance");
    }

    function testTrade_CashflowMax_BaseCurrency() public {
        PositionId positionId = PositionId.wrap(bytes32(uint256(0x1234) << 48));
        Symbol symbol = positionId.getSymbol();
        mockContango.setInstrument(symbol, IERC20(address(weth)), usdc);

        // Set trader's vault balance for base token (weth)
        mockVault.setBalance(IERC20(address(weth)), trader, 3 ether);

        TradeParams memory tradeParams = TradeParams({
            positionId: positionId,
            quantity: 1e18,
            limitPrice: 2000e6,
            cashflowCcy: Currency.Base,
            cashflow: type(int256).max
        });

        ExecutionParams memory execParams = ExecutionParams({
            spender: address(0),
            router: address(0),
            swapAmount: 0,
            swapBytes: "",
            flashLoanProvider: IERC7399(address(0))
        });

        vm.prank(trader);
        maestro.trade(tradeParams, execParams);

        (,,,,int256 cashflow) = mockContango.lastTradeParams();
        assertEq(cashflow, int256(3 ether), "cashflow set to weth vault balance");
    }

    // =================== receive ===================

    function testReceive_AcceptsFromNativeToken() public {
        // Fund WETH contract with some ether so it can send
        vm.deal(address(weth), 1 ether);

        // Sending ETH from nativeToken address should work
        vm.prank(address(weth));
        (bool success,) = address(maestro).call{ value: 0.5 ether }("");
        assertTrue(success, "receive accepted from nativeToken");
    }

    function testReceive_RevertsFromNonNativeToken() public {
        address randomSender = makeAddr("randomSender");
        vm.deal(randomSender, 1 ether);

        vm.prank(randomSender);
        (bool success, bytes memory returnData) = address(maestro).call{ value: 0.1 ether }("");
        assertFalse(success, "call should fail");
        assertEq(returnData, abi.encodeWithSelector(SenderIsNotNativeToken.selector, randomSender, address(weth)), "revert reason");
    }

    // =================== PayableMulticall ===================

    function testMulticall_BatchDepositAndWithdraw() public {
        // First, fund the vault with some balance for the trader
        mockVault.setBalance(usdc, trader, 0);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IMaestro.deposit.selector, usdc, 1000e6);
        data[1] = abi.encodeWithSelector(IMaestro.deposit.selector, usdc, 2000e6);

        vm.prank(trader);
        bytes[] memory results = maestro.multicall(data);

        // Both deposits should succeed
        uint256 first = abi.decode(results[0], (uint256));
        uint256 second = abi.decode(results[1], (uint256));
        assertEq(first, 1000e6, "first deposit");
        assertEq(second, 2000e6, "second deposit");
        assertEq(mockVault.balances(usdc, trader), 3000e6, "total deposited");
    }

    function testMulticall_DepositNativeWithValue() public {
        vm.deal(trader, 5 ether);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(IMaestro.depositNative.selector);

        vm.prank(trader);
        bytes[] memory results = maestro.multicall{ value: 5 ether }(data);

        uint256 deposited = abi.decode(results[0], (uint256));
        assertEq(deposited, 5 ether, "deposited via multicall");
        assertEq(mockVault.balances(IERC20(address(weth)), trader), 5 ether, "vault balance");
    }

    // =================== Immutable getters ===================

    function testImmutableGetters() public view {
        assertEq(address(maestro.contango()), address(mockContango), "contango");
        assertEq(address(maestro.vault()), address(mockVault), "vault");
        assertEq(address(maestro.spotExecutor()), address(spotExecutor), "spotExecutor");
        assertEq(address(maestro.positionNFT()), address(mockPositionNFT), "positionNFT");
        assertEq(address(maestro.nativeToken()), address(weth), "nativeToken");
    }

    function testAllConstant() public view {
        assertEq(maestro.ALL(), 0, "ALL constant is 0");
    }

}

// ============ Helper: MockToken (reused from SpotExecutor test) ============

contract MockToken is ERC20 {

    uint8 private _dec;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _dec = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}
