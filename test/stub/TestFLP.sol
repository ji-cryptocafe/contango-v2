//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./TestFlashLoanProvider.sol";

contract TestFLP is TestFlashLoanProvider {
    constructor() TestFlashLoanProvider(0) { }
}
