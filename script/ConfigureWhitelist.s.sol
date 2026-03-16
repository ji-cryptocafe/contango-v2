// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "src/security/AccessGate.sol";
import "src/security/RouterGuard.sol";

/// @title ConfigureWhitelist — Add/remove wallets and routers after deployment
/// @dev Usage:
///   # Add a wallet
///   forge script script/ConfigureWhitelist.s.sol:AddWallet \
///     --rpc-url $MAINNET_URL --broadcast \
///     --sig "run(address,address)" $ACCESS_GATE_ADDR $WALLET_ADDR
///
///   # Remove a wallet
///   forge script script/ConfigureWhitelist.s.sol:RemoveWallet \
///     --rpc-url $MAINNET_URL --broadcast \
///     --sig "run(address,address)" $ACCESS_GATE_ADDR $WALLET_ADDR
///
///   # Add a router
///   forge script script/ConfigureWhitelist.s.sol:AddRouter \
///     --rpc-url $MAINNET_URL --broadcast \
///     --sig "run(address,address)" $ROUTER_GUARD_ADDR $ROUTER_ADDR

contract AddWallet is Script {

    function run(address accessGateAddr, address wallet) external {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        AccessGate(accessGateAddr).addWallet(wallet);
        vm.stopBroadcast();
        console.log("Wallet added:", wallet);
    }

}

contract RemoveWallet is Script {

    function run(address accessGateAddr, address wallet) external {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        AccessGate(accessGateAddr).removeWallet(wallet);
        vm.stopBroadcast();
        console.log("Wallet removed:", wallet);
    }

}

contract AddRouter is Script {

    function run(address routerGuardAddr, address router) external {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        RouterGuard(routerGuardAddr).setRouter(router, true);
        RouterGuard(routerGuardAddr).setSpender(router, true);
        vm.stopBroadcast();
        console.log("Router + spender added:", router);
    }

}

contract RemoveRouter is Script {

    function run(address routerGuardAddr, address router) external {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        RouterGuard(routerGuardAddr).setRouter(router, false);
        RouterGuard(routerGuardAddr).setSpender(router, false);
        vm.stopBroadcast();
        console.log("Router + spender removed:", router);
    }

}

contract AddFlashLoanProvider is Script {

    function run(address routerGuardAddr, address provider) external {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        RouterGuard(routerGuardAddr).setFlashLoanProvider(provider, true);
        vm.stopBroadcast();
        console.log("Flash loan provider added:", provider);
    }

}
