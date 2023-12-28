// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';
import {BeefyVaultWithdrawal, IBeefy} from 'contracts/BeefyVaultWithdrawal.sol';
import 'forge-std/console.sol';
import {BeefyIntegrationBase} from '../integration/BeefyIntegrationBase.sol';

contract UnitBeefyVaultWithdrawalConstructor is BeefyIntegrationBase {
  function test_OwnerSet(address _owner) public {
    vm.prank(_owner);
    _beefyVaultWithdrawal = new BeefyVaultWithdrawal(address(_mooToken), address(_maiToken), 100, 100);

    assertEq(_beefyVaultWithdrawal.owner(), _owner);
  }

  function test_TokenSet(IERC20 _mooToken) public {
    _beefyVaultWithdrawal = new BeefyVaultWithdrawal(address(_mooToken), address(_maiToken), 100, 100);

    assertEq(address(_beefyVaultWithdrawal.gem()), address(_mooToken));
  }

  function test_BeefySet() public {
    _beefyVaultWithdrawal = new BeefyVaultWithdrawal(address(_mooToken), address(_maiToken), 100, 100);

    assertEq(address(_beefyVaultWithdrawal.underlying()), address(_maiToken));
  }
}

contract UnitBeefyVaultWithdrawalDeposit is UnitBeefyVaultWithdrawalConstructor {
  event Deposited(address indexed user, uint256 amount);

  function test_RevertIfPaused() public {
    vm.prank(_owner);
    _beefyVaultWithdrawal.togglePause(true);

    vm.expectRevert('Contract is paused');
    _beefyVaultWithdrawal.deposit(100_000_000);
  }

  function test_Deposit_ZeroAmountReverts() public {
    uint256 _amount = 0;
    vm.expectRevert('Invalid amount');
    _beefyVaultWithdrawal.deposit(_amount);
  }

  function test_Deposit(uint256 _amount) public {
    // Precondition: Skip the test if the deposit amount is 0
    if (_amount == 0) {
      return;
    }

    // Verify that the deposit amount is within the allowed range for deposits
    uint256 maxDeposit = _beefyVaultWithdrawal.maxDeposit();
    uint256 minDeposit = _beefyVaultWithdrawal.minimumDepositFee();
    if (_amount < minDeposit || _amount > maxDeposit) {
      vm.expectRevert('Invalid amount');
      _beefyVaultWithdrawal.deposit(_amount);
      return;
    }

    // Verify that the withdrawal amount is within the allowed range for withdrawals
    uint256 maxWithdraw = _beefyVaultWithdrawal.maxWithdraw();
    uint256 minWithdraw = _beefyVaultWithdrawal.minimumWithdrawalFee();
    if (_amount < minWithdraw || _amount > maxWithdraw) {
      vm.expectRevert('Invalid amount');
      _beefyVaultWithdrawal.scheduleWithdraw(_amount);
      return;
    }

    // Calculate the expected fee
    uint256 expectedFee = _beefyVaultWithdrawal.calculateDepositFee(_amount);

    // If the deposit amount is less than or equal to the minimumDepositFee or the fee, expect a revert
    if (_amount <= _beefyVaultWithdrawal.minimumDepositFee() || _amount <= expectedFee) {
      vm.expectRevert('Invalid amount');
      _beefyVaultWithdrawal.deposit(_amount);
      return;
    }

    uint256 initialMooBalance = _mooToken.balanceOf(address(_beefyVaultWithdrawal));
    uint256 initialMaiBalance = _maiToken.balanceOf(_user);

    if (initialMooBalance <= 0) {
      return;
    }

    // Expect the Deposited event to be emitted with the correct parameters
    vm.expectEmit(true, true, true, true, address(_beefyVaultWithdrawal));
    emit Deposited(_user, _amount);

    vm.prank(_user);
    _beefyVaultWithdrawal.deposit(_amount);

    uint256 finalMooBalance = _mooToken.balanceOf(address(_beefyVaultWithdrawal));
    uint256 finalMaiBalance = _maiToken.balanceOf(_user);

    // Check that the mooToken balance of the BeefyVaultWithdrawal contract has increased by _amount
    assertEq(finalMooBalance, initialMooBalance + _amount, 'mooToken balance did not increase correctly');

    // Check that the maiToken balance of the user has decreased by the correct amount after deposit
    uint256 expectedMaiBalance = initialMaiBalance - _amount; // Adjust this calculation based on the fee logic if necessary
    assertEq(finalMaiBalance, expectedMaiBalance, 'maiToken balance did not decrease correctly');
  }
}

contract UnitBeefyVaultWithdrawalWithdraw is UnitBeefyVaultWithdrawalConstructor {
  event Withdrawn(address indexed user, uint256 amount);

  function test_RevertIfPaused() public {
    _beefyVaultWithdrawal.togglePause(true);

    vm.expectRevert('Contract is paused');
    _beefyVaultWithdrawal.scheduleWithdraw(1000);
  }

  function test_Withdraw(uint256 _amount) public {
    // Schedule the withdrawal first
    _beefyVaultWithdrawal.scheduleWithdraw(_amount);

    // Move forward in time to the next epoch to simulate the passage of time for withdrawal execution
    vm.warp(block.timestamp + 1 days);

    // Mock the transferFrom call to simulate the withdrawal execution
    vm.mockCall(
      address(_maiToken),
      abi.encodeWithSelector(IERC20.transferFrom.selector, _user, address(_beefyVaultWithdrawal), _amount),
      abi.encode(true)
    );

    // Expect the Withdrawn event to be emitted with the correct parameters
    vm.expectEmit(true, true, true, true, address(_beefyVaultWithdrawal));
    emit Withdrawn(_user, _amount);

    // Execute the withdrawal
    _beefyVaultWithdrawal.executeWithdrawal();
  }
}
