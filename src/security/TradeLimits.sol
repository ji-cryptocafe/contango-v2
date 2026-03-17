//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract TradeLimits is Ownable {

    error TradeSizeExceeded(uint256 maxAllowed, uint256 actual);
    error DailyVolumeExceeded(address trader, uint256 maxAllowed, uint256 actual);
    error MaxOpenPositionsExceeded(address trader, uint256 maxAllowed);
    error OnlyContango();

    event MaxTradeSizeSet(uint256 max);
    event MaxDailyVolumeSet(uint256 max);
    event MaxOpenPositionsSet(uint256 max);
    event ContangoSet(address contango);

    uint256 public maxTradeSize;      // 0 = unlimited
    uint256 public maxDailyVolume;    // 0 = unlimited
    uint256 public maxOpenPositions;  // 0 = unlimited

    address public contango;

    struct VolumeData {
        uint256 volume;
        uint256 epoch;
    }

    mapping(address => VolumeData) private _volumeData;
    mapping(address => uint256) public openPositionCount;

    constructor() Ownable() {
        _transferOwnership(msg.sender);
    }

    // =================== Configuration ===================

    function setContango(address _contango) external onlyOwner {
        contango = _contango;
        emit ContangoSet(_contango);
    }

    function setMaxTradeSize(uint256 max) external onlyOwner {
        maxTradeSize = max;
        emit MaxTradeSizeSet(max);
    }

    function setMaxDailyVolume(uint256 max) external onlyOwner {
        maxDailyVolume = max;
        emit MaxDailyVolumeSet(max);
    }

    function setMaxOpenPositions(uint256 max) external onlyOwner {
        maxOpenPositions = max;
        emit MaxOpenPositionsSet(max);
    }

    // =================== Validation (view — no access control needed) ===================

    function validateTradeSize(uint256 size) external view {
        if (maxTradeSize != 0 && size > maxTradeSize) {
            revert TradeSizeExceeded(maxTradeSize, size);
        }
    }

    // =================== State mutations (onlyContango) ===================

    function recordAndValidateVolume(address trader, uint256 volume) external onlyContango {
        if (maxDailyVolume == 0) return;

        VolumeData storage data = _volumeData[trader];
        uint256 currentEpoch = block.timestamp / 1 days;

        if (data.epoch != currentEpoch) {
            data.volume = 0;
            data.epoch = currentEpoch;
        }

        uint256 newVolume = data.volume + volume;
        if (newVolume > maxDailyVolume) {
            revert DailyVolumeExceeded(trader, maxDailyVolume, newVolume);
        }

        data.volume = newVolume;
    }

    function incrementOpenPositions(address trader) external onlyContango {
        if (maxOpenPositions != 0 && openPositionCount[trader] >= maxOpenPositions) {
            revert MaxOpenPositionsExceeded(trader, maxOpenPositions);
        }
        openPositionCount[trader]++;
    }

    function decrementOpenPositions(address trader) external onlyContango {
        if (openPositionCount[trader] > 0) {
            openPositionCount[trader]--;
        }
    }

    // =================== View ===================

    function dailyVolume(address trader) external view returns (uint256) {
        VolumeData storage data = _volumeData[trader];
        uint256 currentEpoch = block.timestamp / 1 days;
        if (data.epoch != currentEpoch) return 0;
        return data.volume;
    }

    // =================== Modifiers ===================

    modifier onlyContango() {
        if (msg.sender != contango) revert OnlyContango();
        _;
    }

}
