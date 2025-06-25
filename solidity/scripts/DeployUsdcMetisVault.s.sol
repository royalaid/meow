// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import {USDCVaultDDW} from '../contracts/USDCVaultDDW.sol';

contract MyScript is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
    vm.startBroadcast(deployerPrivateKey);

    USDCVaultDDW usdcVaultDDW = new USDCVaultDDW();
    usdcVaultDDW.initialize(0, 30);

    vm.stopBroadcast();
  }
}
