// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {BeefyVaultPSM} from '../../contracts/BeefyVaultDDW.sol';
import 'forge-std/console.sol';
import {BeefyIntegrationBase} from '../integration/BeefyIntegrationBase.sol';

contract UnitBeefyVaultWithdrawalConstructor is BeefyIntegrationBase {
  function test_OwnerSet() public {
    psm = new BeefyVaultPSM();
    psm.initialize(address(_mooToken), 100, 100);

    assertEq(psm.owner(), address(_owner));
  }

  function test_TokenSet() public {
    psm = new BeefyVaultPSM();
    psm.initialize(address(_mooToken), 100, 100);

    assertEq(address(psm.gem()), address(_mooToken));
  }

  function test_BeefySet() public {
    psm = new BeefyVaultPSM();
    psm.initialize(address(_mooToken), 100, 100);
    assertEq(address(psm.underlying()), address(_usdbcToken));
  }
}

contract DepositSuite is UnitBeefyVaultWithdrawalConstructor {
  event Deposited(address indexed user, uint256 amount);

  function test_RevertIfPaused() public {
    psm.togglePause(true);
    vm.expectRevert(BeefyVaultPSM.ContractIsPaused.selector);
    psm.deposit(100_000_000);
  }

  function test_Deposit_ZeroAmountReverts() public {
    uint256 _amount = 0;
    vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
    psm.deposit(_amount);
  }

  function test_Deposit(uint256 _amount) public {
    vm.assume(_amount <= _usdbcToken.balanceOf(_user));
    // Verify that the deposit amount is within the allowed range for deposits
    uint256 maxDeposit = psm.maxDeposit();
    uint256 minDeposit = psm.minimumDepositFee();
    if (_amount < minDeposit || _amount > maxDeposit) {
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      psm.deposit(_amount);
      return;
    }

    // Verify that the withdrawal amount is within the allowed range for withdrawals
    uint256 maxWithdraw = psm.maxWithdraw();
    uint256 minWithdraw = psm.minimumWithdrawalFee();
    if (_amount < minWithdraw || _amount > maxWithdraw) {
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      psm.deposit(_amount);
      return;
    }

    // Calculate the expected fee
    uint256 expectedFee = psm.calculateFee(_amount, true);

    uint256 initialMooBalance = _mooToken.balanceOf(address(psm));
    uint256 initialMaiBalance = _maiToken.balanceOf(_user);

    vm.startPrank(_user);
    _usdbcToken.approve(address(psm), _amount);
    // If the deposit amount is less than or equal to the minimumDepositFee or the fee, expect a revert
    if (_amount <= psm.minimumDepositFee() || _amount <= expectedFee) {
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      psm.deposit(_amount);
      return;
    }
    // Expect the Deposited event to be emitted with the correct parameters
    vm.expectEmit(true, false, false, true);
    emit Deposited(_user, _amount - expectedFee);
    psm.deposit(_amount);

    uint256 finalMooBalance = _mooToken.balanceOf(address(psm));
    uint256 finalMaiBalance = _maiToken.balanceOf(_user);

    // Check that the mooToken balance of the BeefyVaultWithdrawal contract has increased by _amount
    // assertEq(finalMooBalance, initialMooBalance + _amount, 'mooToken balance did not increase correctly');

    // Check that the maiToken balance of the user has decreased by the correct amount after deposit
    // uint256 expectedMaiBalance = initialMaiBalance - _amount; // Adjust this calculation based on the fee logic if necessary
    // assertEq(finalMaiBalance, expectedMaiBalance, 'maiToken balance did not decrease correctly');
  }
}

contract WithdrawSuite is UnitBeefyVaultWithdrawalConstructor {
  event Withdrawn(address indexed user, uint256 amount);

  function test_RevertIfPaused() public {
    psm.togglePause(true);

    vm.expectRevert(BeefyVaultPSM.ContractIsPaused.selector);
    psm.scheduleWithdraw(1000);
  }

  function test_DepositAndWithdraw(uint256 _depositAmount, uint256 _withdrawAmount) public {
    _depositAmount = bound(_depositAmount, 1e6, _usdbcToken.balanceOf(_user));
    _withdrawAmount = bound(_withdrawAmount, 1e18, _depositAmount * 10 ** 12);
    // Deposit first to ensure there are tokens to withdraw
    _usdbcToken.approve(address(psm), _depositAmount);
    console.log('Deposit amount:', _depositAmount);
    console.log('maxDeposit:', psm.maxDeposit());
    console.log('minimumDepositFee:', psm.minimumDepositFee());
    console.log('mooToken balance bfore:', _mooToken.balanceOf(address(psm)));

    if (_depositAmount <= psm.minimumDepositFee() || _depositAmount > psm.maxDeposit()) {
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      psm.deposit(_depositAmount);
      return;
    } else {
      psm.deposit(_depositAmount);
    }
    console.log('mooToken balance after:', _mooToken.balanceOf(address(psm)));

    // Schedule the withdrawal
    if (_withdrawAmount < psm.minimumWithdrawalFee() || _withdrawAmount > psm.maxWithdraw()) {
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      psm.scheduleWithdraw(_withdrawAmount);
      return;
    } else {
      psm.scheduleWithdraw(_withdrawAmount);
    }

    // Move forward in time to the next epoch to simulate the passage of time for withdrawal execution
    vm.warp(block.timestamp + 4 days);

    // Mock the transferFrom call to simulate the withdrawal execution
    // vm.mockCall(
    //   address(_maiToken),
    //   abi.encodeWithSelector(IERC20.transferFrom.selector, _user, address(psm), _withdrawAmount),
    //   abi.encode(true)
    // );

    // Execute the withdrawal
    if (_withdrawAmount > _depositAmount * 10 ** 12) {
      psm.withdraw();
      vm.expectRevert();
    } else if (_withdrawAmount < psm.minimumWithdrawalFee() || _withdrawAmount > psm.maxWithdraw()) {
      psm.withdraw();
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
    } else {
      // vm.expectEmit(false, false, false, false);
      // emit Withdrawn(_user, _withdrawAmount);
      psm.withdraw();
    }
    // Expect the Withdrawn event to be emitted with the correct parameters
  }
}
