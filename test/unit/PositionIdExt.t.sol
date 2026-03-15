// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {
    PositionId,
    Symbol,
    MoneyMarketId,
    Payload
} from "src/libraries/DataTypes.sol";
import {
    decode,
    getSymbol,
    getNumber,
    getMoneyMarket,
    getExpiry,
    isPerp,
    isExpired,
    withNumber,
    getFlags,
    getPayload,
    getPayloadNoFlags,
    asUint,
    fromUint,
    positionIdEquals,
    positionIdNotEquals,
    InvalidUInt48,
    InvalidPositionId
} from "src/libraries/extensions/PositionIdExt.sol";
import {
    encode
} from "test/Encoder.sol";

contract PositionIdExtTest is Test {

    // --- helpers ---

    uint32 constant PERP = type(uint32).max;

    function _encode(
        Symbol symbol,
        MoneyMarketId mm,
        uint32 expiry,
        uint48 number
    ) internal pure returns (PositionId) {
        return encode(symbol, mm, uint256(expiry), uint256(number), bytes1(0));
    }

    function _encodeWithFlags(
        Symbol symbol,
        MoneyMarketId mm,
        uint32 expiry,
        uint48 number,
        bytes1 flags
    ) internal pure returns (PositionId) {
        return encode(symbol, mm, uint256(expiry), uint256(number), flags);
    }

    function _encodeWithPayload(
        Symbol symbol,
        MoneyMarketId mm,
        uint32 expiry,
        uint48 number,
        Payload payload
    ) internal pure returns (PositionId) {
        return encode(symbol, mm, uint256(expiry), uint256(number), payload);
    }

    // --- decode ---

    function test_decode_roundTrip() public pure {
        Symbol sym = Symbol.wrap("ETHUSDC");
        MoneyMarketId mm = MoneyMarketId.wrap(3);
        uint32 expiry = 1700000000;
        uint48 number = 42;

        PositionId pid = _encode(sym, mm, expiry, number);
        (Symbol dSym, MoneyMarketId dMm, uint32 dExpiry, uint256 dNumber) = decode(pid);

        assertEq(Symbol.unwrap(dSym), Symbol.unwrap(sym));
        assertEq(MoneyMarketId.unwrap(dMm), MoneyMarketId.unwrap(mm));
        assertEq(dExpiry, expiry);
        assertEq(dNumber, number);
    }

    function test_decode_perp() public pure {
        Symbol sym = Symbol.wrap("BTCUSDC");
        MoneyMarketId mm = MoneyMarketId.wrap(1);

        PositionId pid = _encode(sym, mm, PERP, 1);
        (, , uint32 dExpiry, ) = decode(pid);
        assertEq(dExpiry, PERP);
    }

    function test_decode_zeroNumber() public pure {
        Symbol sym = Symbol.wrap("ETHUSDC");
        MoneyMarketId mm = MoneyMarketId.wrap(0);
        uint32 expiry = 1000;

        PositionId pid = _encode(sym, mm, expiry, 0);
        (, , , uint256 dNumber) = decode(pid);
        assertEq(dNumber, 0);
    }

    function test_decode_maxValues() public pure {
        // max symbol (all 0xff for 16 bytes)
        Symbol sym = Symbol.wrap(bytes16(type(uint128).max));
        MoneyMarketId mm = MoneyMarketId.wrap(type(uint8).max);
        uint32 expiry = type(uint32).max;
        uint48 number = type(uint48).max;

        PositionId pid = _encode(sym, mm, expiry, number);
        (Symbol dSym, MoneyMarketId dMm, uint32 dExpiry, uint256 dNumber) = decode(pid);

        assertEq(Symbol.unwrap(dSym), Symbol.unwrap(sym));
        assertEq(MoneyMarketId.unwrap(dMm), type(uint8).max);
        assertEq(dExpiry, type(uint32).max);
        assertEq(dNumber, type(uint48).max);
    }

    // --- getSymbol ---

    function test_getSymbol() public pure {
        Symbol sym = Symbol.wrap("ETHUSDC");
        PositionId pid = _encode(sym, MoneyMarketId.wrap(1), PERP, 1);
        assertEq(Symbol.unwrap(getSymbol(pid)), Symbol.unwrap(sym));
    }

    function test_getSymbol_empty() public pure {
        Symbol sym = Symbol.wrap(bytes16(0));
        PositionId pid = _encode(sym, MoneyMarketId.wrap(0), 1, 0);
        assertEq(Symbol.unwrap(getSymbol(pid)), bytes16(0));
    }

    // --- getNumber ---

    function test_getNumber() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 999);
        assertEq(getNumber(pid), 999);
    }

    function test_getNumber_zero() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 0);
        assertEq(getNumber(pid), 0);
    }

    function test_getNumber_max() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, type(uint48).max);
        assertEq(getNumber(pid), type(uint48).max);
    }

    // --- getMoneyMarket ---

    function test_getMoneyMarket() public pure {
        MoneyMarketId mm = MoneyMarketId.wrap(7);
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), mm, PERP, 1);
        assertEq(MoneyMarketId.unwrap(getMoneyMarket(pid)), 7);
    }

    function test_getMoneyMarket_zero() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(0), PERP, 1);
        assertEq(MoneyMarketId.unwrap(getMoneyMarket(pid)), 0);
    }

    function test_getMoneyMarket_max() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(type(uint8).max), PERP, 1);
        assertEq(MoneyMarketId.unwrap(getMoneyMarket(pid)), type(uint8).max);
    }

    // --- getExpiry ---

    function test_getExpiry() public pure {
        uint32 expiry = 1700000000;
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), expiry, 1);
        assertEq(getExpiry(pid), expiry);
    }

    function test_getExpiry_perp() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        assertEq(getExpiry(pid), type(uint32).max);
    }

    // --- isPerp ---

    function test_isPerp_true() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        assertTrue(isPerp(pid));
    }

    function test_isPerp_false() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), 1700000000, 1);
        assertFalse(isPerp(pid));
    }

    function test_isPerp_almostMax() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), type(uint32).max - 1, 1);
        assertFalse(isPerp(pid));
    }

    // --- isExpired ---

    function test_isExpired_true() public {
        uint32 expiry = 1000;
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), expiry, 1);
        vm.warp(1000);
        assertTrue(isExpired(pid));
    }

    function test_isExpired_true_pastExpiry() public {
        uint32 expiry = 1000;
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), expiry, 1);
        vm.warp(2000);
        assertTrue(isExpired(pid));
    }

    function test_isExpired_false() public {
        uint32 expiry = 2000;
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), expiry, 1);
        vm.warp(999);
        assertFalse(isExpired(pid));
    }

    function test_isExpired_perp_notExpired() public {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        vm.warp(1e9);
        assertFalse(isExpired(pid));
    }

    // --- withNumber ---

    function test_withNumber_setsNumber() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 0);
        PositionId result = withNumber(pid, 42);
        assertEq(getNumber(result), 42);
        // other fields unchanged
        assertEq(Symbol.unwrap(getSymbol(result)), Symbol.unwrap(Symbol.wrap("ETHUSDC")));
        assertEq(MoneyMarketId.unwrap(getMoneyMarket(result)), 1);
        assertEq(getExpiry(result), PERP);
    }

    function test_withNumber_maxUint48() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 0);
        PositionId result = withNumber(pid, type(uint48).max);
        assertEq(getNumber(result), type(uint48).max);
    }

    function test_withNumber_revertsIfNumberAlreadySet() public {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 5);
        PositionIdCaller caller = new PositionIdCaller();
        vm.expectRevert(InvalidPositionId.selector);
        caller.callWithNumber(pid, 10);
    }

    function test_withNumber_revertsIfNumberExceedsUint48() public {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 0);
        uint256 tooLarge = uint256(type(uint48).max) + 1;
        PositionIdCaller caller = new PositionIdCaller();
        vm.expectRevert(abi.encodeWithSelector(InvalidUInt48.selector, tooLarge));
        caller.callWithNumber(pid, tooLarge);
    }

    // --- getFlags ---

    function test_getFlags() public pure {
        bytes1 flags = bytes1(0x03); // bits 0 and 1 set
        PositionId pid = _encodeWithFlags(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1, flags);
        assertEq(getFlags(pid), flags);
    }

    function test_getFlags_zero() public pure {
        PositionId pid = _encodeWithFlags(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1, bytes1(0));
        assertEq(getFlags(pid), bytes1(0));
    }

    function test_getFlags_allSet() public pure {
        bytes1 flags = bytes1(0xFF);
        PositionId pid = _encodeWithFlags(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1, flags);
        assertEq(getFlags(pid), flags);
    }

    // --- getPayload ---

    function test_getPayload() public pure {
        bytes1 flags = bytes1(0xAB);
        bytes4 extra = bytes4(0x12345678);
        Payload payload = Payload.wrap(bytes5(flags) | bytes5(extra) >> 8);
        PositionId pid = _encodeWithPayload(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1, payload);
        assertEq(Payload.unwrap(getPayload(pid)), Payload.unwrap(payload));
    }

    function test_getPayload_zero() public pure {
        Payload payload = Payload.wrap(bytes5(0));
        PositionId pid = _encodeWithPayload(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1, payload);
        assertEq(Payload.unwrap(getPayload(pid)), bytes5(0));
    }

    // --- getPayloadNoFlags ---

    function test_getPayloadNoFlags() public pure {
        bytes1 flags = bytes1(0xAB);
        bytes4 extra = bytes4(0x12345678);
        Payload payload = Payload.wrap(bytes5(flags) | bytes5(extra) >> 8);
        PositionId pid = _encodeWithPayload(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1, payload);
        assertEq(getPayloadNoFlags(pid), extra);
    }

    function test_getPayloadNoFlags_zero() public pure {
        PositionId pid = _encodeWithPayload(
            Symbol.wrap("ETHUSDC"),
            MoneyMarketId.wrap(1),
            PERP,
            1,
            Payload.wrap(bytes5(bytes1(0xFF))) // flags only, no extra payload
        );
        assertEq(getPayloadNoFlags(pid), bytes4(0));
    }

    // --- asUint / fromUint ---

    function test_asUint_roundTrip() public pure {
        PositionId pid = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 42);
        uint256 raw = asUint(pid);
        PositionId reconstructed = fromUint(raw);
        assertTrue(positionIdEquals(pid, reconstructed));
    }

    function test_asUint_zero() public pure {
        PositionId pid = PositionId.wrap(bytes32(0));
        assertEq(asUint(pid), 0);
    }

    // --- positionIdEquals / positionIdNotEquals ---

    function test_positionIdEquals_true() public pure {
        PositionId a = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        PositionId b = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        assertTrue(positionIdEquals(a, b));
    }

    function test_positionIdEquals_false() public pure {
        PositionId a = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        PositionId b = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 2);
        assertFalse(positionIdEquals(a, b));
    }

    function test_positionIdNotEquals_true() public pure {
        PositionId a = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        PositionId b = _encode(Symbol.wrap("BTCUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        assertTrue(positionIdNotEquals(a, b));
    }

    function test_positionIdNotEquals_false() public pure {
        PositionId a = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        PositionId b = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        assertFalse(positionIdNotEquals(a, b));
    }

    // --- operator overloads via using-for global ---

    function test_operatorEq() public pure {
        PositionId a = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        PositionId b = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        assertTrue(a == b);
    }

    function test_operatorNeq() public pure {
        PositionId a = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 1);
        PositionId b = _encode(Symbol.wrap("ETHUSDC"), MoneyMarketId.wrap(1), PERP, 2);
        assertTrue(a != b);
    }

    // --- fuzz: encode/decode round-trip ---

    function test_fuzz_roundTrip(bytes16 rawSym, uint8 rawMm, uint32 expiry, uint48 number) public pure {
        vm.assume(expiry > 0);
        Symbol sym = Symbol.wrap(rawSym);
        MoneyMarketId mm = MoneyMarketId.wrap(rawMm);

        PositionId pid = _encode(sym, mm, expiry, number);
        (Symbol dSym, MoneyMarketId dMm, uint32 dExpiry, uint256 dNumber) = decode(pid);

        assertEq(Symbol.unwrap(dSym), Symbol.unwrap(sym));
        assertEq(MoneyMarketId.unwrap(dMm), rawMm);
        assertEq(dExpiry, expiry);
        assertEq(dNumber, number);
    }
}

/// @dev Helper contract to make free function calls external (so vm.expectRevert works)
contract PositionIdCaller {

    function callWithNumber(PositionId pid, uint256 number) external pure returns (PositionId) {
        return withNumber(pid, number);
    }

}
