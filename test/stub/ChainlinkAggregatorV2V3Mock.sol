//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import { IAggregatorV2V3 } from "../dependencies/Chainlink.sol";

contract ChainlinkAggregatorV2V3Mock is IAggregatorV2V3 {

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    uint8 public override decimals;
    int256 public price;
    uint80 private _roundId;

    function setDecimals(uint8 _decimals) external returns (ChainlinkAggregatorV2V3Mock) {
        decimals = _decimals;
        return ChainlinkAggregatorV2V3Mock(address(this));
    }

    function set(int256 _price) external returns (ChainlinkAggregatorV2V3Mock) {
        price = _price;

        emit AnswerUpdated(price, ++_roundId, block.timestamp);

        return ChainlinkAggregatorV2V3Mock(address(this));
    }

    // V3

    function aggregator() external view returns (address) {
        return address(this);
    }

    function description() external pure returns (string memory) {
        return "ChainlinkAggregatorV2V3Mock";
    }

    function version() external pure returns (uint256) {
        return 3;
    }

    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80 roundId_, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (roundId, price, block.timestamp, block.timestamp, 0);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, price, block.timestamp, block.timestamp, _roundId);
    }

    // V2

    function latestAnswer() external view override returns (int256) {
        return price;
    }

    function latestTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function latestRound() external view returns (uint256) {
        return _roundId;
    }

    function getAnswer(uint256) external view returns (int256) {
        return price;
    }

    function getTimestamp(uint256) external view returns (uint256) {
        return block.timestamp;
    }

    // Aggregator

    function minAnswer() external pure returns (int192) {
        return type(int192).min;
    }

    function maxAnswer() external pure returns (int192) {
        return type(int192).max;
    }

}
