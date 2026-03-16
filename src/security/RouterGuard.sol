//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract RouterGuard is Ownable {

    event RouterSet(address indexed router, bool indexed allowed);
    event SpenderSet(address indexed spender, bool indexed allowed);
    event FlashLoanProviderSet(address indexed provider, bool indexed allowed);

    error RouterNotAllowed(address router);
    error SpenderNotAllowed(address spender);
    error FlashLoanProviderNotAllowed(address provider);

    mapping(address => bool) public allowedRouters;
    mapping(address => bool) public allowedSpenders;
    mapping(address => bool) public allowedFlashLoanProviders;

    constructor() Ownable() {
        _transferOwnership(msg.sender);
    }

    function setRouter(address router, bool allowed) external onlyOwner {
        allowedRouters[router] = allowed;
        emit RouterSet(router, allowed);
    }

    function setSpender(address spender, bool allowed) external onlyOwner {
        allowedSpenders[spender] = allowed;
        emit SpenderSet(spender, allowed);
    }

    function setFlashLoanProvider(address provider, bool allowed) external onlyOwner {
        allowedFlashLoanProviders[provider] = allowed;
        emit FlashLoanProviderSet(provider, allowed);
    }

    function validateRouter(address router) public view {
        if (!allowedRouters[router]) revert RouterNotAllowed(router);
    }

    function validateSpender(address spender) public view {
        if (!allowedSpenders[spender]) revert SpenderNotAllowed(spender);
    }

    function validateFlashLoanProvider(address provider) public view {
        if (provider != address(0) && !allowedFlashLoanProviders[provider]) {
            revert FlashLoanProviderNotAllowed(provider);
        }
    }

    function validateExecution(address router, address spender, address flashLoanProvider) external view {
        validateRouter(router);
        validateSpender(spender);
        validateFlashLoanProvider(flashLoanProvider);
    }

}
