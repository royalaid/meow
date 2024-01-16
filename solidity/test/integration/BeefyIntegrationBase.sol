// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {BeefyVaultDelayWithdrawal, IBeefy} from 'contracts/BeefyVaultDelayWithdrawal.sol';

contract BeefyIntegrationBase is Test {
  uint256 internal constant _FORK_BLOCK = 8_420_622;

  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  address internal _beefyWhale = 0x008a74d96d799b0fcfae8462BfFF8C37C7ccc611;
  IERC20 internal _mooToken = IERC20(0xD7803d3Bf95517D204CFc6211678cAb223aC4c48);
  IERC20 internal _maiToken = IERC20(0xbf1aeA8670D2528E08334083616dD9C5F3B087aE);

  IBeefy internal _beefyVault;
  BeefyVaultDelayWithdrawal internal _beefyVaultWithdrawal;

  function setUp() public {
    //vm.createSelectFork(vm.rpcUrl('base'), _FORK_BLOCK);
    vm.prank(_owner);
    _beefyVault = IBeefy(address(_mooToken));
    _beefyVaultWithdrawal = new BeefyVaultDelayWithdrawal(address(_mooToken), address(_beefyVault), 100, 100);
  }
}
