//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AccessGate is Ownable {

    event WalletWhitelisted(address indexed wallet);
    event WalletRemoved(address indexed wallet);

    error NotWhitelisted(address wallet);
    error MaxWalletsReached();

    mapping(address => bool) public whitelistedWallets;
    uint256 public maxWhitelistedWallets = 10;
    uint256 public whitelistedCount;

    constructor() Ownable() {
        _transferOwnership(msg.sender);
    }

    function addWallet(address wallet) external onlyOwner {
        if (whitelistedCount >= maxWhitelistedWallets && !whitelistedWallets[wallet]) revert MaxWalletsReached();
        if (!whitelistedWallets[wallet]) {
            whitelistedWallets[wallet] = true;
            whitelistedCount++;
            emit WalletWhitelisted(wallet);
        }
    }

    function removeWallet(address wallet) external onlyOwner {
        if (whitelistedWallets[wallet]) {
            whitelistedWallets[wallet] = false;
            whitelistedCount--;
            emit WalletRemoved(wallet);
        }
    }

    function setMaxWhitelistedWallets(uint256 max) external onlyOwner {
        maxWhitelistedWallets = max;
    }

    function isWhitelisted(address wallet) external view returns (bool) {
        return whitelistedWallets[wallet];
    }

    function requireWhitelisted(address wallet) external view {
        if (!whitelistedWallets[wallet]) revert NotWhitelisted(wallet);
    }

}
