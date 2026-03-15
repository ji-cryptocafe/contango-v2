// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { MathLib } from "src/libraries/MathLib.sol";
import { toArray, toStringArray } from "src/libraries/Arrays.sol";
import { isBitSet, InvalidUInt8 } from "src/libraries/BitFlags.sol";
import {
    PositionId,
    Symbol,
    MoneyMarketId,
    Payload,
    payloadEquals,
    mmEquals
} from "src/libraries/DataTypes.sol";
import {
    validateCreatePositionPermissions,
    validateModifyPositionPermissions
} from "src/libraries/Validations.sol";
import { Unauthorised } from "src/libraries/Errors.sol";
import "src/core/PositionNFT.sol";
import "src/libraries/Roles.sol";

// ============================================================
//  MathLib Tests
// ============================================================

contract MathLibTest is Test {
    using MathLib for int256;

    // --- absIfPositive ---

    function test_absIfPositive_positive() public pure {
        assertEq(int256(42).absIfPositive(), 42);
    }

    function test_absIfPositive_large() public pure {
        assertEq(int256(type(int256).max).absIfPositive(), uint256(type(int256).max));
    }

    function test_absIfPositive_negative() public pure {
        assertEq(int256(-5).absIfPositive(), 0);
    }

    function test_absIfPositive_zero() public pure {
        assertEq(int256(0).absIfPositive(), 0);
    }

    function test_absIfPositive_one() public pure {
        assertEq(int256(1).absIfPositive(), 1);
    }

    function test_absIfPositive_negOne() public pure {
        assertEq(int256(-1).absIfPositive(), 0);
    }

    // --- absIfNegative ---

    function test_absIfNegative_negative() public pure {
        assertEq(int256(-42).absIfNegative(), 42);
    }

    function test_absIfNegative_positive() public pure {
        assertEq(int256(5).absIfNegative(), 0);
    }

    function test_absIfNegative_zero() public pure {
        assertEq(int256(0).absIfNegative(), 0);
    }

    function test_absIfNegative_negOne() public pure {
        assertEq(int256(-1).absIfNegative(), 1);
    }

    function test_absIfNegative_minInt256() public pure {
        // type(int256).min == -(2^255), its absolute value is 2^255
        // In unchecked { uint256(-type(int256).min) } this works
        uint256 result = int256(type(int256).min).absIfNegative();
        assertEq(result, uint256(type(int256).max) + 1);
    }

    function test_absIfNegative_maxInt256() public pure {
        assertEq(int256(type(int256).max).absIfNegative(), 0);
    }

    // --- fuzz ---

    function test_fuzz_absIfPositive(int256 value) public pure {
        uint256 result = value.absIfPositive();
        if (value > 0) {
            assertEq(result, uint256(value));
        } else {
            assertEq(result, 0);
        }
    }

    function test_fuzz_absIfNegative(int256 value) public pure {
        uint256 result = value.absIfNegative();
        if (value < 0) {
            // unchecked negation matches library behavior
            unchecked {
                assertEq(result, uint256(-value));
            }
        } else {
            assertEq(result, 0);
        }
    }
}

// ============================================================
//  Arrays Tests
// ============================================================

contract ArraysTest is Test {

    function test_toArray_uint256() public pure {
        uint256[] memory arr = toArray(123);
        assertEq(arr.length, 1);
        assertEq(arr[0], 123);
    }

    function test_toArray_uint256_zero() public pure {
        uint256[] memory arr = toArray(uint256(0));
        assertEq(arr.length, 1);
        assertEq(arr[0], 0);
    }

    function test_toArray_singleAddress() public pure {
        address a = address(0xBEEF);
        address[] memory arr = toArray(a);
        assertEq(arr.length, 1);
        assertEq(arr[0], a);
    }

    function test_toArray_twoAddresses() public pure {
        address a = address(0xBEEF);
        address b = address(0xCAFE);
        address[] memory arr = toArray(a, b);
        assertEq(arr.length, 2);
        assertEq(arr[0], a);
        assertEq(arr[1], b);
    }

    function test_toArray_singleBytes() public pure {
        bytes memory data = hex"deadbeef";
        bytes[] memory arr = toArray(data);
        assertEq(arr.length, 1);
        assertEq(arr[0], data);
    }

    function test_toArray_twoBytes() public pure {
        bytes memory a = hex"aa";
        bytes memory b = hex"bb";
        bytes[] memory arr = toArray(a, b);
        assertEq(arr.length, 2);
        assertEq(arr[0], a);
        assertEq(arr[1], b);
    }

    function test_toStringArray_single() public pure {
        string[] memory arr = toStringArray("hello");
        assertEq(arr.length, 1);
        assertEq(arr[0], "hello");
    }

    function test_toStringArray_two() public pure {
        string[] memory arr = toStringArray("hello", "world");
        assertEq(arr.length, 2);
        assertEq(arr[0], "hello");
        assertEq(arr[1], "world");
    }

    function test_toArray_emptyBytes() public pure {
        bytes memory data = "";
        bytes[] memory arr = toArray(data);
        assertEq(arr.length, 1);
        assertEq(arr[0], data);
    }
}

// ============================================================
//  BitFlags Tests
// ============================================================

contract BitFlagsTest is Test {

    function test_isBitSet_bit0() public pure {
        bytes1 flags = bytes1(0x01); // bit 0 set
        assertTrue(isBitSet(flags, 0));
        assertFalse(isBitSet(flags, 1));
    }

    function test_isBitSet_bit7() public pure {
        bytes1 flags = bytes1(0x80); // bit 7 set
        assertTrue(isBitSet(flags, 7));
        assertFalse(isBitSet(flags, 0));
    }

    function test_isBitSet_allBits() public pure {
        bytes1 flags = bytes1(0xFF);
        for (uint256 i = 0; i < 8; i++) {
            assertTrue(isBitSet(flags, i));
        }
    }

    function test_isBitSet_noBits() public pure {
        bytes1 flags = bytes1(0x00);
        for (uint256 i = 0; i < 8; i++) {
            assertFalse(isBitSet(flags, i));
        }
    }

    function test_isBitSet_multipleBits() public pure {
        bytes1 flags = bytes1(0x05); // bits 0 and 2 set
        assertTrue(isBitSet(flags, 0));
        assertFalse(isBitSet(flags, 1));
        assertTrue(isBitSet(flags, 2));
        assertFalse(isBitSet(flags, 3));
    }

    function test_isBitSet_revertsIfBitTooLarge() public {
        BitFlagsCaller c = new BitFlagsCaller();
        vm.expectRevert(abi.encodeWithSelector(InvalidUInt8.selector, 8));
        c.callIsBitSet(bytes1(0xFF), 8);
    }

    function test_isBitSet_revertsIfBitWayTooLarge() public {
        BitFlagsCaller c = new BitFlagsCaller();
        vm.expectRevert(abi.encodeWithSelector(InvalidUInt8.selector, 256));
        c.callIsBitSet(bytes1(0xFF), 256);
    }
}

contract BitFlagsCaller {

    function callIsBitSet(bytes1 flags, uint256 bit) external pure returns (bool) {
        return isBitSet(flags, bit);
    }

}

// ============================================================
//  DataTypes Tests (payloadEquals, mmEquals)
// ============================================================

contract DataTypesTest is Test {

    // --- payloadEquals ---

    function test_payloadEquals_true() public pure {
        Payload a = Payload.wrap(bytes5(0x0102030405));
        Payload b = Payload.wrap(bytes5(0x0102030405));
        assertTrue(a == b);
    }

    function test_payloadEquals_false() public pure {
        Payload a = Payload.wrap(bytes5(0x0102030405));
        Payload b = Payload.wrap(bytes5(0x0102030406));
        assertFalse(a == b);
    }

    function test_payloadEquals_zero() public pure {
        Payload a = Payload.wrap(bytes5(0));
        Payload b = Payload.wrap(bytes5(0));
        assertTrue(a == b);
    }

    // --- mmEquals ---

    function test_mmEquals_true() public pure {
        MoneyMarketId a = MoneyMarketId.wrap(5);
        MoneyMarketId b = MoneyMarketId.wrap(5);
        assertTrue(a == b);
    }

    function test_mmEquals_false() public pure {
        MoneyMarketId a = MoneyMarketId.wrap(5);
        MoneyMarketId b = MoneyMarketId.wrap(6);
        assertFalse(a == b);
    }

    function test_mmEquals_zero() public pure {
        MoneyMarketId a = MoneyMarketId.wrap(0);
        MoneyMarketId b = MoneyMarketId.wrap(0);
        assertTrue(a == b);
    }

    function test_mmEquals_max() public pure {
        MoneyMarketId a = MoneyMarketId.wrap(type(uint8).max);
        MoneyMarketId b = MoneyMarketId.wrap(type(uint8).max);
        assertTrue(a == b);
    }
}

// ============================================================
//  Validations Tests
// ============================================================

/// @dev Wrapper contract so that validation free functions are called via an external call,
///      making msg.sender equal to the caller (controlled by vm.prank).
contract ValidationsCaller {
    function callValidateCreate(PositionNFT nft, address onBehalfOf) external view {
        validateCreatePositionPermissions(nft, onBehalfOf);
    }

    function callValidateModify(PositionNFT nft, PositionId pid) external view returns (address) {
        return validateModifyPositionPermissions(nft, pid);
    }
}

contract ValidationsTest is Test {

    PositionNFT positionNFT;
    ValidationsCaller caller;

    address owner = address(0xA11CE);
    address operator = address(0xB0B);
    address rando = address(0xBAD);
    address timelock = address(0x7777);

    PositionId positionId;

    function setUp() public {
        positionNFT = new PositionNFT(Timelock.wrap(timelock));
        caller = new ValidationsCaller();

        // Grant minter role to this contract so we can mint
        vm.startPrank(timelock);
        positionNFT.grantRole(MINTER_ROLE, address(this));
        vm.stopPrank();

        // Build a positionId without a number (number = 0)
        bytes32 raw = bytes32(Symbol.unwrap(Symbol.wrap("ETHUSDC")))
            | bytes32(uint256(1)) << 120
            | bytes32(uint256(type(uint32).max)) << 88;
        PositionId baseId = PositionId.wrap(raw);

        // Mint to owner (this sets the number)
        positionId = positionNFT.mint(baseId, owner);

        // Owner approves operator for all
        vm.prank(owner);
        positionNFT.setApprovalForAll(operator, true);
    }

    // --- validateCreatePositionPermissions ---

    function test_validateCreate_revertsWhenNotApproved() public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, rando));
        vm.prank(rando);
        caller.callValidateCreate(positionNFT, owner);
    }

    function test_validateCreate_succeedsWhenApproved() public {
        // operator is approved for all by owner — call from operator
        vm.prank(operator);
        caller.callValidateCreate(positionNFT, owner);
    }

    function test_validateCreate_ownerCallingOnBehalfOfSelfSucceeds() public {
        // PositionNFT.isApprovedForAll returns true when owner==operator, so this succeeds
        vm.prank(owner);
        caller.callValidateCreate(positionNFT, owner);
    }

    // --- validateModifyPositionPermissions ---

    function test_validateModify_succeedsForOwner() public {
        vm.prank(owner);
        address result = caller.callValidateModify(positionNFT, positionId);
        assertEq(result, owner);
    }

    function test_validateModify_succeedsForApprovedOperator() public {
        vm.prank(operator);
        address result = caller.callValidateModify(positionNFT, positionId);
        assertEq(result, owner);
    }

    function test_validateModify_revertsForUnapproved() public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, rando));
        vm.prank(rando);
        caller.callValidateModify(positionNFT, positionId);
    }
}
