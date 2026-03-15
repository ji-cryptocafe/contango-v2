// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/core/PositionNFT.sol";
import "src/libraries/DataTypes.sol";
import "src/libraries/Roles.sol";

contract PositionNFTTest is Test {

    event ContangoContractSet(address indexed contractAddr, bool indexed enabled);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    PositionNFT private nft;

    address private timelockAddr = makeAddr("timelock");
    Timelock private timelock = Timelock.wrap(timelockAddr);

    address private minter = makeAddr("minter");
    address private trader1 = makeAddr("trader1");
    address private trader2 = makeAddr("trader2");
    address private unauthorised = makeAddr("unauthorised");

    Symbol private symbolETH = Symbol.wrap("ETH/USD");
    Symbol private symbolBTC = Symbol.wrap("BTC/USD");
    MoneyMarketId private mm1 = MoneyMarketId.wrap(1);
    MoneyMarketId private mm2 = MoneyMarketId.wrap(2);
    uint32 private constant PERP = type(uint32).max;

    function setUp() public {
        nft = new PositionNFT(timelock);

        vm.startPrank(timelockAddr);
        nft.grantRole(MINTER_ROLE, minter);
        vm.stopPrank();
    }

    // ========== Helpers ==========

    function _encodePositionId(Symbol symbol, MoneyMarketId mm, uint32 expiry) internal pure returns (PositionId) {
        return PositionId.wrap(bytes32(
            uint256(uint128(Symbol.unwrap(symbol))) << 128 |
            uint256(MoneyMarketId.unwrap(mm)) << 120 |
            uint256(expiry) << 88
        ));
    }

    function _mintPosition(Symbol symbol, MoneyMarketId mm, uint32 expiry, address to) internal returns (PositionId) {
        vm.prank(minter);
        return nft.mint(_encodePositionId(symbol, mm, expiry), to);
    }

    function _accessControlRevertMsg(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(account), 20),
            " is missing role ",
            Strings.toHexString(uint256(role), 32)
        );
    }

    // ========== 1. Constructor ==========

    function test_constructor_adminRoleGranted() public view {
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), timelockAddr));
    }

    function test_constructor_nameAndSymbol() public view {
        assertEq(nft.name(), "Contango Position");
        assertEq(nft.symbol(), "CTGP");
    }

    function test_constructor_counterStartsAtOne() public view {
        assertEq(nft.counter(), 1);
    }

    // ========== 2. Mint ==========

    function test_mint_returnsPositionIdWithNumber() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        assertEq(pid.getNumber(), 1);
        assertEq(Symbol.unwrap(pid.getSymbol()), Symbol.unwrap(symbolETH));
        assertEq(MoneyMarketId.unwrap(pid.getMoneyMarket()), MoneyMarketId.unwrap(mm1));
        assertEq(pid.getExpiry(), PERP);
    }

    function test_mint_counterIncrements() public {
        assertEq(nft.counter(), 1);
        _mintPosition(symbolETH, mm1, PERP, trader1);
        assertEq(nft.counter(), 2);
        _mintPosition(symbolBTC, mm2, PERP, trader2);
        assertEq(nft.counter(), 3);
    }

    function test_mint_nftOwnedByRecipient() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        assertEq(nft.ownerOf(uint256(PositionId.unwrap(pid))), trader1);
    }

    function test_mint_emitsTransferEvent() public {
        PositionId templateId = _encodePositionId(symbolETH, mm1, PERP);
        PositionId expectedPid = templateId.withNumber(1);

        vm.prank(minter);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), trader1, uint256(PositionId.unwrap(expectedPid)));
        nft.mint(templateId, trader1);
    }

    function test_mint_revertsWithoutMinterRole() public {
        vm.expectRevert(_accessControlRevertMsg(unauthorised, MINTER_ROLE));
        vm.prank(unauthorised);
        nft.mint(_encodePositionId(symbolETH, mm1, PERP), trader1);
    }

    function test_mint_balanceUpdatesCorrectly() public {
        _mintPosition(symbolETH, mm1, PERP, trader1);
        _mintPosition(symbolBTC, mm2, PERP, trader1);
        _mintPosition(symbolETH, mm2, PERP, trader2);

        assertEq(nft.balanceOf(trader1), 2);
        assertEq(nft.balanceOf(trader2), 1);
    }

    // ========== 3. Burn ==========

    function test_burn_existingPosition() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);

        assertEq(nft.balanceOf(trader1), 1);

        vm.prank(minter);
        nft.burn(pid);

        assertEq(nft.balanceOf(trader1), 0);
    }

    function test_burn_revertsWithoutMinterRole() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);

        vm.expectRevert(_accessControlRevertMsg(unauthorised, MINTER_ROLE));
        vm.prank(unauthorised);
        nft.burn(pid);
    }

    function test_burn_revertsOnNonExistent() public {
        PositionId fakePid = _encodePositionId(symbolETH, mm1, PERP).withNumber(999);

        vm.prank(minter);
        vm.expectRevert("ERC721: invalid token ID");
        nft.burn(fakePid);
    }

    function test_burn_emitsTransferEvent() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);

        vm.prank(minter);
        vm.expectEmit(true, true, true, true);
        emit Transfer(trader1, address(0), uint256(PositionId.unwrap(pid)));
        nft.burn(pid);
    }

    function test_burn_counterNotAffected() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        _mintPosition(symbolBTC, mm2, PERP, trader2);

        assertEq(nft.counter(), 3);

        vm.prank(minter);
        nft.burn(pid);

        assertEq(nft.counter(), 3);
    }

    // ========== 4. positionOwner ==========

    function test_positionOwner_returnsCorrectOwner() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        assertEq(nft.positionOwner(pid), trader1);
    }

    function test_positionOwner_returnsCorrectAfterTransfer() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);

        vm.prank(trader1);
        nft.transferFrom(trader1, trader2, uint256(PositionId.unwrap(pid)));

        assertEq(nft.positionOwner(pid), trader2);
    }

    function test_positionOwner_revertsForNonExistent() public {
        PositionId fakePid = _encodePositionId(symbolETH, mm1, PERP).withNumber(42);

        vm.expectRevert("ERC721: invalid token ID");
        nft.positionOwner(fakePid);
    }

    // ========== 5. exists ==========

    function test_exists_trueForMinted() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        assertTrue(nft.exists(pid));
    }

    function test_exists_falseForBurned() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);

        vm.prank(minter);
        nft.burn(pid);

        assertFalse(nft.exists(pid));
    }

    function test_exists_falseForNonExistent() public view {
        PositionId fakePid = _encodePositionId(symbolETH, mm1, PERP).withNumber(99);
        assertFalse(nft.exists(fakePid));
    }

    // ========== 6. setContangoContract ==========

    function test_setContangoContract_enable() public {
        address contractAddr = makeAddr("contangoContract");

        vm.prank(timelockAddr);
        nft.setContangoContract(contractAddr, true);

        assertTrue(nft.contangoContracts(contractAddr));
    }

    function test_setContangoContract_disable() public {
        address contractAddr = makeAddr("contangoContract");

        vm.startPrank(timelockAddr);
        nft.setContangoContract(contractAddr, true);
        assertTrue(nft.contangoContracts(contractAddr));

        nft.setContangoContract(contractAddr, false);
        assertFalse(nft.contangoContracts(contractAddr));
        vm.stopPrank();
    }

    function test_setContangoContract_revertsWithoutAdminRole() public {
        vm.expectRevert(_accessControlRevertMsg(unauthorised, nft.DEFAULT_ADMIN_ROLE()));
        vm.prank(unauthorised);
        nft.setContangoContract(makeAddr("any"), true);
    }

    function test_setContangoContract_emitsEvent() public {
        address contractAddr = makeAddr("contangoContract");

        vm.prank(timelockAddr);
        vm.expectEmit(true, true, false, true);
        emit ContangoContractSet(contractAddr, true);
        nft.setContangoContract(contractAddr, true);
    }

    function test_setContangoContract_emitsEventOnDisable() public {
        address contractAddr = makeAddr("contangoContract");

        vm.startPrank(timelockAddr);
        nft.setContangoContract(contractAddr, true);

        vm.expectEmit(true, true, false, true);
        emit ContangoContractSet(contractAddr, false);
        nft.setContangoContract(contractAddr, false);
        vm.stopPrank();
    }

    // ========== 7. isApprovedForAll ==========

    function test_isApprovedForAll_ownerEqualsOperator() public view {
        assertTrue(nft.isApprovedForAll(trader1, trader1));
    }

    function test_isApprovedForAll_contangoContractReturnsTrue() public {
        address contangoContract = makeAddr("contangoContract");

        vm.prank(timelockAddr);
        nft.setContangoContract(contangoContract, true);

        assertTrue(nft.isApprovedForAll(trader1, contangoContract));
        assertTrue(nft.isApprovedForAll(trader2, contangoContract));
    }

    function test_isApprovedForAll_disabledContangoContractReturnsFalse() public {
        address contangoContract = makeAddr("contangoContract");

        vm.startPrank(timelockAddr);
        nft.setContangoContract(contangoContract, true);
        nft.setContangoContract(contangoContract, false);
        vm.stopPrank();

        assertFalse(nft.isApprovedForAll(trader1, contangoContract));
    }

    function test_isApprovedForAll_standardApprovalWorks() public {
        address delegate = makeAddr("delegate");

        vm.prank(trader1);
        nft.setApprovalForAll(delegate, true);

        assertTrue(nft.isApprovedForAll(trader1, delegate));
        // Does not apply to other owners
        assertFalse(nft.isApprovedForAll(trader2, delegate));
    }

    function test_isApprovedForAll_nonApprovedReturnsFalse() public view {
        assertFalse(nft.isApprovedForAll(trader1, trader2));
        assertFalse(nft.isApprovedForAll(trader1, unauthorised));
    }

    // ========== 8. supportsInterface ==========

    function test_supportsInterface_ERC721() public view {
        // ERC721 interfaceId = 0x80ac58cd
        assertTrue(nft.supportsInterface(0x80ac58cd));
    }

    function test_supportsInterface_AccessControl() public view {
        // IAccessControl interfaceId = 0x7965db0b
        assertTrue(nft.supportsInterface(0x7965db0b));
    }

    function test_supportsInterface_ERC165() public view {
        // ERC165 interfaceId = 0x01ffc9a7
        assertTrue(nft.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_ERC721Metadata() public view {
        // ERC721Metadata interfaceId = 0x5b5e139f
        assertTrue(nft.supportsInterface(0x5b5e139f));
    }

    function test_supportsInterface_invalidReturnsFalse() public view {
        assertFalse(nft.supportsInterface(0xdeadbeef));
    }

    // ========== 9. Sequential Mints ==========

    function test_sequentialMints_counterIncrementsCorrectly() public {
        assertEq(nft.counter(), 1);

        PositionId pid1 = _mintPosition(symbolETH, mm1, PERP, trader1);
        assertEq(pid1.getNumber(), 1);
        assertEq(nft.counter(), 2);

        PositionId pid2 = _mintPosition(symbolETH, mm1, PERP, trader2);
        assertEq(pid2.getNumber(), 2);
        assertEq(nft.counter(), 3);

        PositionId pid3 = _mintPosition(symbolBTC, mm2, PERP, trader1);
        assertEq(pid3.getNumber(), 3);
        assertEq(nft.counter(), 4);

        PositionId pid4 = _mintPosition(symbolETH, mm1, 1704067200, trader2);
        assertEq(pid4.getNumber(), 4);
        assertEq(nft.counter(), 5);

        // Each tokenId is unique
        assertTrue(pid1 != pid2);
        assertTrue(pid2 != pid3);
        assertTrue(pid3 != pid4);
    }

    function test_sequentialMints_differentSymbolsSameNumber() public {
        PositionId pid1 = _mintPosition(symbolETH, mm1, PERP, trader1);
        PositionId pid2 = _mintPosition(symbolBTC, mm1, PERP, trader1);

        // Same number sequence
        assertEq(pid1.getNumber(), 1);
        assertEq(pid2.getNumber(), 2);

        // Different symbols
        assertEq(Symbol.unwrap(pid1.getSymbol()), Symbol.unwrap(symbolETH));
        assertEq(Symbol.unwrap(pid2.getSymbol()), Symbol.unwrap(symbolBTC));
    }

    function test_sequentialMints_burnDoesNotResetCounter() public {
        PositionId pid1 = _mintPosition(symbolETH, mm1, PERP, trader1);
        _mintPosition(symbolBTC, mm2, PERP, trader2);

        vm.prank(minter);
        nft.burn(pid1);

        PositionId pid3 = _mintPosition(symbolETH, mm1, PERP, trader1);
        assertEq(pid3.getNumber(), 3);
        assertEq(nft.counter(), 4);
    }

    // ========== 10. ERC721 Transfers ==========

    function test_transfer_standardTransferFrom() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        uint256 tokenId = uint256(PositionId.unwrap(pid));

        vm.prank(trader1);
        nft.transferFrom(trader1, trader2, tokenId);

        assertEq(nft.ownerOf(tokenId), trader2);
        assertEq(nft.balanceOf(trader1), 0);
        assertEq(nft.balanceOf(trader2), 1);
    }

    function test_transfer_safeTransferFrom() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        uint256 tokenId = uint256(PositionId.unwrap(pid));

        vm.prank(trader1);
        nft.safeTransferFrom(trader1, trader2, tokenId);

        assertEq(nft.ownerOf(tokenId), trader2);
    }

    function test_transfer_approvedOperatorCanTransfer() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        uint256 tokenId = uint256(PositionId.unwrap(pid));

        vm.prank(trader1);
        nft.approve(trader2, tokenId);

        vm.prank(trader2);
        nft.transferFrom(trader1, trader2, tokenId);

        assertEq(nft.ownerOf(tokenId), trader2);
    }

    function test_transfer_approvedForAllCanTransfer() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        uint256 tokenId = uint256(PositionId.unwrap(pid));

        vm.prank(trader1);
        nft.setApprovalForAll(trader2, true);

        vm.prank(trader2);
        nft.transferFrom(trader1, trader2, tokenId);

        assertEq(nft.ownerOf(tokenId), trader2);
    }

    function test_transfer_contangoContractCanTransfer() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        uint256 tokenId = uint256(PositionId.unwrap(pid));

        address contangoContract = makeAddr("contangoContract");
        vm.prank(timelockAddr);
        nft.setContangoContract(contangoContract, true);

        vm.prank(contangoContract);
        nft.transferFrom(trader1, trader2, tokenId);

        assertEq(nft.ownerOf(tokenId), trader2);
    }

    function test_transfer_revertsIfNotApproved() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        uint256 tokenId = uint256(PositionId.unwrap(pid));

        vm.prank(unauthorised);
        vm.expectRevert("ERC721: caller is not token owner or approved");
        nft.transferFrom(trader1, trader2, tokenId);
    }

    function test_transfer_approve_emitsEvent() public {
        PositionId pid = _mintPosition(symbolETH, mm1, PERP, trader1);
        uint256 tokenId = uint256(PositionId.unwrap(pid));

        vm.prank(trader1);
        vm.expectEmit(true, true, true, true);
        emit Approval(trader1, trader2, tokenId);
        nft.approve(trader2, tokenId);
    }

}
