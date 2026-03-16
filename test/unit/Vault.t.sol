//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/core/Vault.sol";
import "src/libraries/DataTypes.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// ============ Mock Contracts ============

contract MockERC20 {

    string public name = "Mock Token";
    string public symbol = "MCK";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function totalSupply() external pure returns (uint256) {
        return type(uint256).max;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

}

contract MockWETH9 {

    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function totalSupply() external pure returns (uint256) {
        return type(uint256).max;
    }

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "insufficient balance");
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "insufficient allowance");
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

// ============ Helper to receive ETH in tests ============

contract ETHReceiver {

    receive() external payable { }

}

// ============ Test Contract ============

contract VaultUnitTest is Test {

    Vault public vault;
    MockERC20 public token;
    MockWETH9 public weth;
    IERC20 public ierc20Token;
    IWETH9 public iweth;

    address public admin = address(0xAD);
    address public operator = address(0x0B);
    address public contango = address(0xC0);
    address public alice = address(0xA1);
    address public bob = address(0xB0);
    address public unauthorized = address(0xBAD);

    bytes32 constant _CONTANGO_ROLE = keccak256("CONTANGO");
    bytes32 constant _OPERATOR_ROLE = keccak256("OPERATOR");
    bytes32 constant _DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        // Deploy mocks
        weth = new MockWETH9();
        token = new MockERC20();
        ierc20Token = IERC20(address(token));
        iweth = IWETH9(address(weth));

        // Deploy Vault directly (no proxy — upgradeability removed)
        vault = Vault(payable(address(new Vault(iweth, Timelock.wrap(admin)))));

        // Grant roles
        vm.startPrank(admin);
        vault.grantRole(_OPERATOR_ROLE, operator);
        vault.grantRole(_CONTANGO_ROLE, contango);
        vm.stopPrank();

        // Support mock token
        vm.prank(operator);
        vault.setTokenSupport(ierc20Token, true);

        // Fund users
        token.mint(alice, 1000e18);
        token.mint(bob, 1000e18);
        token.mint(contango, 1000e18);

        // Approve vault for users
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
        vm.prank(contango);
        token.approve(address(vault), type(uint256).max);

        // Fund ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(contango, 100 ether);
    }

    // =============================================
    // 1. Initialization
    // =============================================

    function test_initialization_nativeToken() public view {
        assertEq(address(vault.nativeToken()), address(weth));
    }

    function test_initialization_nativeTokenSupported() public view {
        assertTrue(vault.isTokenSupported(IERC20(address(weth))));
    }

    function test_initialization_adminRoleSet() public view {
        assertTrue(vault.hasRole(_DEFAULT_ADMIN_ROLE, admin));
    }

    function test_initialization_noOtherAdmin() public view {
        assertFalse(vault.hasRole(_DEFAULT_ADMIN_ROLE, address(this)));
    }

    // =============================================
    // 2. Token Support
    // =============================================

    function test_setTokenSupport_operatorCanSet() public {
        MockERC20 newToken = new MockERC20();
        IERC20 newIerc20 = IERC20(address(newToken));

        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit IVaultEvents.TokenSupportSet(newIerc20, true);
        vault.setTokenSupport(newIerc20, true);

        assertTrue(vault.isTokenSupported(newIerc20));
    }

    function test_setTokenSupport_operatorCanDisable() public {
        vm.prank(operator);
        vault.setTokenSupport(ierc20Token, false);

        assertFalse(vault.isTokenSupported(ierc20Token));
    }

    function test_setTokenSupport_revertsForNonOperator() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        vault.setTokenSupport(ierc20Token, true);
    }

    function test_setTokenSupport_revertsForAdmin() public {
        MockERC20 newToken = new MockERC20();
        vm.prank(admin);
        vm.expectRevert();
        vault.setTokenSupport(IERC20(address(newToken)), true);
    }

    // =============================================
    // 3. Deposit
    // =============================================

    function test_deposit_normalBySelf() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IVaultEvents.Deposited(ierc20Token, alice, 100e18);
        uint256 deposited = vault.deposit(ierc20Token, alice, 100e18);

        assertEq(deposited, 100e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 100e18);
        assertEq(vault.totalBalanceOf(ierc20Token), 100e18);
        assertEq(token.balanceOf(address(vault)), 100e18);
    }

    function test_deposit_byContangoRole() public {
        // contango deposits on behalf of alice — payer is alice, requires alice approval
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);

        vm.prank(contango);
        uint256 deposited = vault.deposit(ierc20Token, alice, 50e18);

        assertEq(deposited, 50e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 50e18);
        // payer is alice (the account), so alice's token balance decreases
        assertEq(token.balanceOf(alice), 950e18);
    }

    function test_depositTo_anyoneCanDeposit() public {
        vm.prank(unauthorized);
        token.mint(unauthorized, 200e18);
        vm.prank(unauthorized);
        token.approve(address(vault), type(uint256).max);

        vm.prank(unauthorized);
        uint256 deposited = vault.depositTo(ierc20Token, alice, 200e18);

        assertEq(deposited, 200e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 200e18);
        // payer is msg.sender (unauthorized), not alice
        assertEq(token.balanceOf(alice), 1000e18);
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vault.deposit(ierc20Token, alice, 0);
    }

    function test_deposit_revertsOnUnsupportedToken() public {
        MockERC20 unsupported = new MockERC20();
        unsupported.mint(alice, 100e18);

        vm.prank(alice);
        unsupported.approve(address(vault), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.UnsupportedToken.selector, IERC20(address(unsupported))));
        vault.deposit(IERC20(address(unsupported)), alice, 100e18);
    }

    function test_depositTo_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vault.depositTo(ierc20Token, alice, 0);
    }

    // =============================================
    // 4. Deposit with pre-funded tokens (available shortcut)
    // =============================================

    function test_deposit_preFundedFullAmount() public {
        // Send tokens directly to vault before calling deposit
        vm.prank(alice);
        token.transfer(address(vault), 100e18);

        // Now deposit — vault already has the tokens, so no transferFrom needed
        vm.prank(alice);
        uint256 deposited = vault.deposit(ierc20Token, alice, 100e18);

        assertEq(deposited, 100e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 100e18);
        assertEq(vault.totalBalanceOf(ierc20Token), 100e18);
        // Alice already sent 100e18, deposit shouldn't pull more
        assertEq(token.balanceOf(alice), 900e18);
    }

    function test_deposit_preFundedPartialAmount() public {
        // Pre-fund 40e18, deposit 100e18 — should pull remaining 60e18
        vm.prank(alice);
        token.transfer(address(vault), 40e18);

        vm.prank(alice);
        uint256 deposited = vault.deposit(ierc20Token, alice, 100e18);

        assertEq(deposited, 100e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 100e18);
        // alice started with 1000, sent 40 directly, then vault pulled 60 more
        assertEq(token.balanceOf(alice), 900e18);
        assertEq(token.balanceOf(address(vault)), 100e18);
    }

    function test_depositTo_preFunded() public {
        // Anyone pre-funds, then depositTo
        token.mint(unauthorized, 100e18);
        vm.prank(unauthorized);
        token.transfer(address(vault), 50e18);

        vm.prank(unauthorized);
        token.approve(address(vault), type(uint256).max);

        vm.prank(unauthorized);
        vault.depositTo(ierc20Token, bob, 50e18);

        assertEq(vault.balanceOf(ierc20Token, bob), 50e18);
        // No additional tokens pulled since 50 already there
        assertEq(token.balanceOf(unauthorized), 50e18);
    }

    // =============================================
    // 5. DepositNative
    // =============================================

    function test_depositNative_wrapsAndDeposits() public {
        vm.prank(alice);
        uint256 deposited = vault.depositNative{ value: 5 ether }(alice);

        assertEq(deposited, 5 ether);
        assertEq(vault.balanceOf(IERC20(address(weth)), alice), 5 ether);
        assertEq(vault.totalBalanceOf(IERC20(address(weth))), 5 ether);
        assertEq(weth.balanceOf(address(vault)), 5 ether);
    }

    function test_depositNative_revertsOnZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vault.depositNative{ value: 0 }(alice);
    }

    function test_depositNative_unauthorizedReverts() public {
        vm.prank(unauthorized);
        vm.deal(unauthorized, 1 ether);
        vm.expectRevert();
        vault.depositNative{ value: 1 ether }(alice);
    }

    function test_depositNative_contangoCanDepositForUser() public {
        // contango has CONTANGO_ROLE so can call depositNative on behalf of alice
        vm.prank(contango);
        uint256 deposited = vault.depositNative{ value: 2 ether }(alice);

        assertEq(deposited, 2 ether);
        assertEq(vault.balanceOf(IERC20(address(weth)), alice), 2 ether);
    }

    // =============================================
    // 6. Withdraw
    // =============================================

    function test_withdraw_normal() public {
        // Deposit first
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        ETHReceiver receiver = new ETHReceiver();

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IVaultEvents.Withdrawn(ierc20Token, alice, 60e18, address(receiver));
        uint256 withdrawn = vault.withdraw(ierc20Token, alice, 60e18, address(receiver));

        assertEq(withdrawn, 60e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 40e18);
        assertEq(vault.totalBalanceOf(ierc20Token), 40e18);
        assertEq(token.balanceOf(address(receiver)), 60e18);
    }

    function test_withdraw_partialBalance() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        vm.prank(alice);
        vault.withdraw(ierc20Token, alice, 30e18, alice);

        assertEq(vault.balanceOf(ierc20Token, alice), 70e18);
        assertEq(token.balanceOf(alice), 930e18);
    }

    function test_withdraw_revertsOnInsufficientBalance() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 50e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.NotEnoughBalance.selector, ierc20Token, 50e18, 100e18));
        vault.withdraw(ierc20Token, alice, 100e18, alice);
    }

    function test_withdraw_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vault.withdraw(ierc20Token, alice, 0, alice);
    }

    function test_withdraw_revertsOnZeroBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.NotEnoughBalance.selector, ierc20Token, 0, 10e18));
        vault.withdraw(ierc20Token, alice, 10e18, alice);
    }

    // =============================================
    // 7. WithdrawNative
    // =============================================

    function test_withdrawNative_unwrapsAndSendsETH() public {
        vm.prank(alice);
        vault.depositNative{ value: 10 ether }(alice);

        ETHReceiver receiver = new ETHReceiver();
        uint256 balBefore = address(receiver).balance;

        vm.prank(alice);
        uint256 withdrawn = vault.withdrawNative(alice, 4 ether, address(receiver));

        assertEq(withdrawn, 4 ether);
        assertEq(address(receiver).balance - balBefore, 4 ether);
        assertEq(vault.balanceOf(IERC20(address(weth)), alice), 6 ether);
    }

    function test_withdrawNative_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vault.withdrawNative(alice, 0, alice);
    }

    function test_withdrawNative_revertsOnInsufficientBalance() public {
        vm.prank(alice);
        vault.depositNative{ value: 1 ether }(alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.NotEnoughBalance.selector, IERC20(address(weth)), 1 ether, 2 ether)
        );
        vault.withdrawNative(alice, 2 ether, alice);
    }

    // =============================================
    // 8. Authorization
    // =============================================

    function test_deposit_revertsWhenUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        vault.deposit(ierc20Token, alice, 10e18);
    }

    function test_withdraw_revertsWhenUnauthorized() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        vm.prank(unauthorized);
        vm.expectRevert();
        vault.withdraw(ierc20Token, alice, 50e18, unauthorized);
    }

    function test_withdrawNative_revertsWhenUnauthorized() public {
        vm.prank(alice);
        vault.depositNative{ value: 5 ether }(alice);

        vm.prank(unauthorized);
        vm.expectRevert();
        vault.withdrawNative(alice, 1 ether, unauthorized);
    }

    function test_deposit_selfIsAuthorized() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 10e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 10e18);
    }

    function test_withdraw_contangoRoleIsAuthorized() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        vm.prank(contango);
        vault.withdraw(ierc20Token, alice, 50e18, alice);

        assertEq(vault.balanceOf(ierc20Token, alice), 50e18);
    }

    // =============================================
    // 9. Accounting
    // =============================================

    function test_accounting_totalBalanceTracksMultipleUsers() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        vm.prank(bob);
        vault.deposit(ierc20Token, bob, 200e18);

        assertEq(vault.totalBalanceOf(ierc20Token), 300e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 100e18);
        assertEq(vault.balanceOf(ierc20Token, bob), 200e18);
    }

    function test_accounting_depositWithdrawSequence() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        vm.prank(alice);
        vault.withdraw(ierc20Token, alice, 30e18, alice);

        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 50e18);

        assertEq(vault.balanceOf(ierc20Token, alice), 120e18);
        assertEq(vault.totalBalanceOf(ierc20Token), 120e18);
    }

    function test_accounting_multipleTokens() public {
        MockERC20 token2 = new MockERC20();
        IERC20 ierc20Token2 = IERC20(address(token2));

        vm.prank(operator);
        vault.setTokenSupport(ierc20Token2, true);

        token2.mint(alice, 500e18);
        vm.prank(alice);
        token2.approve(address(vault), type(uint256).max);

        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        vm.prank(alice);
        vault.deposit(ierc20Token2, alice, 200e18);

        assertEq(vault.balanceOf(ierc20Token, alice), 100e18);
        assertEq(vault.balanceOf(ierc20Token2, alice), 200e18);
        assertEq(vault.totalBalanceOf(ierc20Token), 100e18);
        assertEq(vault.totalBalanceOf(ierc20Token2), 200e18);
    }

    function test_accounting_withdrawReducesTotalAndAccountBalance() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        vm.prank(bob);
        vault.deposit(ierc20Token, bob, 50e18);

        vm.prank(alice);
        vault.withdraw(ierc20Token, alice, 40e18, alice);

        assertEq(vault.totalBalanceOf(ierc20Token), 110e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 60e18);
        assertEq(vault.balanceOf(ierc20Token, bob), 50e18);
    }

    // =============================================
    // 10. Receive
    // =============================================

    function test_receive_revertsWhenSenderIsNotNativeToken() public {
        vm.deal(unauthorized, 1 ether);
        vm.prank(unauthorized);
        (bool success, bytes memory retdata) = address(vault).call{ value: 1 ether }("");
        assertFalse(success);
        assertEq(
            retdata,
            abi.encodeWithSelector(SenderIsNotNativeToken.selector, unauthorized, address(weth))
        );
    }

    function test_receive_acceptsFromNativeToken() public {
        // Fund WETH with some ETH and have it send to vault
        // This happens naturally during withdrawNative when WETH sends ETH to vault
        // We simulate by calling from weth address
        vm.deal(address(weth), 1 ether);
        vm.prank(address(weth));
        (bool success,) = address(vault).call{ value: 1 ether }("");
        assertTrue(success);
    }

    // =============================================
    // 11. Edge cases
    // =============================================

    function test_edge_withdrawExactFullBalance() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 77e18);

        vm.prank(alice);
        vault.withdraw(ierc20Token, alice, 77e18, alice);

        assertEq(vault.balanceOf(ierc20Token, alice), 0);
        assertEq(vault.totalBalanceOf(ierc20Token), 0);
    }

    function test_edge_concurrentUsersIndependentBalances() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        vm.prank(bob);
        vault.deposit(ierc20Token, bob, 200e18);

        // Alice withdraws all
        vm.prank(alice);
        vault.withdraw(ierc20Token, alice, 100e18, alice);

        // Bob's balance should be untouched
        assertEq(vault.balanceOf(ierc20Token, bob), 200e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 0);
        assertEq(vault.totalBalanceOf(ierc20Token), 200e18);
    }

    function test_edge_depositAndWithdrawNativeFullCycle() public {
        vm.prank(alice);
        vault.depositNative{ value: 3 ether }(alice);

        ETHReceiver receiver = new ETHReceiver();

        vm.prank(alice);
        vault.withdrawNative(alice, 3 ether, address(receiver));

        assertEq(vault.balanceOf(IERC20(address(weth)), alice), 0);
        assertEq(vault.totalBalanceOf(IERC20(address(weth))), 0);
        assertEq(address(receiver).balance, 3 ether);
    }

    function test_edge_multipleDepositsAccumulate() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 10e18);

        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 20e18);

        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 30e18);

        assertEq(vault.balanceOf(ierc20Token, alice), 60e18);
        assertEq(vault.totalBalanceOf(ierc20Token), 60e18);
    }

    function test_edge_withdrawToThirdParty() public {
        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 100e18);

        ETHReceiver receiver = new ETHReceiver();

        vm.prank(alice);
        vault.withdraw(ierc20Token, alice, 50e18, address(receiver));

        assertEq(token.balanceOf(address(receiver)), 50e18);
        assertEq(vault.balanceOf(ierc20Token, alice), 50e18);
    }

    function test_edge_depositToMultipleAccounts() public {
        token.mint(address(this), 300e18);
        token.approve(address(vault), type(uint256).max);

        vault.depositTo(ierc20Token, alice, 100e18);
        vault.depositTo(ierc20Token, bob, 200e18);

        assertEq(vault.balanceOf(ierc20Token, alice), 100e18);
        assertEq(vault.balanceOf(ierc20Token, bob), 200e18);
        assertEq(vault.totalBalanceOf(ierc20Token), 300e18);
    }

    function test_edge_preFundedExcessDoesNotAffectAccounting() public {
        // Send more tokens than will be deposited
        vm.prank(alice);
        token.transfer(address(vault), 200e18);

        vm.prank(alice);
        vault.deposit(ierc20Token, alice, 50e18);

        // Only 50 should be tracked even though vault holds 200
        assertEq(vault.balanceOf(ierc20Token, alice), 50e18);
        assertEq(vault.totalBalanceOf(ierc20Token), 50e18);
        // Vault actually holds 200 tokens
        assertEq(token.balanceOf(address(vault)), 200e18);
    }

    function test_edge_withdrawNativeByContangoRole() public {
        vm.prank(alice);
        vault.depositNative{ value: 5 ether }(alice);

        ETHReceiver receiver = new ETHReceiver();

        vm.prank(contango);
        vault.withdrawNative(alice, 2 ether, address(receiver));

        assertEq(vault.balanceOf(IERC20(address(weth)), alice), 3 ether);
        assertEq(address(receiver).balance, 2 ether);
    }

}
