// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {StdCheats} from 'forge-std/StdCheats.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {USDCVaultDDW} from 'contracts/USDCVaultDDW.sol';
import {MetisIntegrationBase} from '../integration/MetisIntegrationBase.sol';

contract USDCVaultWithdrawalConstructor is MetisIntegrationBase {
  function test_OwnerSet() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100);

    assertEq(_psm.owner(), address(_owner));
  }
}

contract USDCVaultAdminSuite is USDCVaultWithdrawalConstructor {
  event FeesWithdrawn(address indexed owner, uint256 feesEarned);

  function test_TransferOwnership() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100);

    vm.expectRevert(USDCVaultDDW.NewOwnerCannotBeZeroAddress.selector);
    _psm.transferOwnership(address(0x0));

    _psm.transferOwnership(address(_user));
    assertEq(_psm.owner(), address(_user));

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.transferOwnership(address(0));
  }

  function test_UpdateMaxDepositWithdraw() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 200);

    _psm.updateMax(200, 3000);
    assertEq(_psm.maxDeposit(), 200);
    assertEq(_psm.maxWithdraw(), 3000);
  }

  function test_UpdateFeesBP() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100);

    assertEq(_psm.depositFee(), 100);
    assertEq(_psm.withdrawalFee(), 100);
    _psm.updateFeesBP(200, 200);
    assertEq(_psm.depositFee(), 200);
    assertEq(_psm.withdrawalFee(), 200);
  }

  function test_UpdateMinimumFees() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100);
    _psm.updateMinimumFees(200, 200);
    assertEq(_psm.minimumDepositFee(), 200);
    assertEq(_psm.minimumWithdrawalFee(), 200);
  }

  function test_ClaimFees() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(0, 0);

    vm.startPrank(_owner);
    deal(address(_usdcToken), _owner, 10_000_000_000 ether);
    deal(address(_maiToken), address(_psm), 10_000_000_000 ether);
    _usdcToken.approve(address(_psm), 1000 ether);
    console.log('WDAI balance:', _usdcToken.balanceOf(_owner));
    _psm.deposit(1000 ether);

    _usdcToken.approve(address(_psm), 1000 ether);
    _psm.deposit(1000 ether);

    uint256 feesBefore = _usdcToken.balanceOf(_owner);

    vm.expectEmit(true, false, false, false);
    emit FeesWithdrawn(_owner, 0);
    _psm.claimFees();
    uint256 feesAfter = _usdcToken.balanceOf(_owner);
    uint256 feesClaimed = feesAfter - feesBefore;
    console.log('Fees claimed:', feesClaimed);
  }

  function test_TransferTokenWithoutUpgradeSet() public {
    deal(address(_usdcToken), address(_psm), 1000 ether);
    uint256 _usdcTokenBalance = _usdcToken.balanceOf(address(_psm));
    console.log('transferToken usdcToken balance:', _usdcTokenBalance);
    vm.expectRevert(USDCVaultDDW.UpgradeNotScheduled.selector);
    _psm.transferToken(address(_usdcToken), address(_user), _usdcTokenBalance);
    _psm.setUpgrade();
    vm.warp(block.timestamp + 4 days);
    _psm.transferToken(address(_usdcToken), address(_user), _usdcTokenBalance);
    assertEq(_usdcToken.balanceOf(address(_psm)), 0);
  }
}

contract PsmDepositSuite is USDCVaultWithdrawalConstructor {
  event Deposited(address indexed user, uint256 amount);

  function test_Initialized() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100);

    assertEq(_psm.initialized(), true);
    vm.expectRevert();
    _psm.initialize(100, 100);
  }

  function test_RevertIfPaused() public {
    _psm.setPaused(USDCVaultDDW.deposit.selector, true);
    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.deposit(100_000_000);
  }

  function test_Deposit_ZeroAmountReverts() public {
    uint256 _amount = 0;
    vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
    _psm.deposit(_amount);
  }

  function test_Deposit_ZeroMaibalanceReverts() public {
    uint256 _amount = 1000 ether;
    _usdcToken.approve(address(_psm), _amount);
    _psm.withdrawMAI();
    vm.expectRevert(USDCVaultDDW.InsufficientMAIBalance.selector);
    _psm.deposit(_amount);
  }

  function test_Deposit(
    uint256 _amount
  ) public {
    bound(_amount, 0, _usdcToken.balanceOf(msg.sender));
    // Verify that the deposit amount is within the allowed range for deposits
    uint256 maxDeposit = _psm.maxDeposit();
    uint256 minDeposit = _psm.minimumDepositFee();
    if (_amount < minDeposit || _amount > maxDeposit) {
      console.log('Deposit amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.deposit(_amount);
      return;
    }

    // Verify that the withdrawal amount is within the allowed range for withdrawals
    uint256 maxWithdraw = _psm.maxWithdraw();
    uint256 minWithdraw = _psm.minimumWithdrawalFee();
    if (_amount < minWithdraw || _amount > maxWithdraw) {
      console.log('Withdraw amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.deposit(_amount);
      return;
    }

    // Calculate the expected fee

    vm.startPrank(_user);
    bound(_amount, 0, _usdcToken.balanceOf(_user) - 1);
    uint256 expectedFee = _psm.calculateFee(_amount, true);
    _usdcToken.approve(address(_psm), _amount);
    // If the deposit amount is less than or equal to the minimumDepositFee or the fee, expect a revert
    console.log('Deposit amount:      ', _amount);
    console.log('token balance:       ', _usdcToken.balanceOf(_user));
    console.log('maxDeposit:          ', _psm.maxDeposit());
    console.log('minimumDepositFee:   ', _psm.minimumDepositFee());
    if (_amount > _usdcToken.balanceOf(_user)) {
      console.log('Deposit amount too large');
      vm.expectRevert();
      _psm.deposit(_amount);
      return;
    }
    if (_amount <= _psm.minimumDepositFee() || _amount <= expectedFee) {
      console.log('Deposit amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.deposit(_amount);
      return;
    } else {
      // Expect the Deposited event to be emitted with the correct parameters
      // vm.expectEmit(true, false, false, true);
      // emit Deposited(_user, _amount - expectedFee);
      uint256 amtBefore = _usdcToken.balanceOf(_user);
      uint256 maiBalanceBefore = _maiToken.balanceOf(_user);
      _psm.deposit(_amount);
      uint256 amtAfter = _usdcToken.balanceOf(_user);
      uint256 maiBalanceAfter = _maiToken.balanceOf(_user);

      assertEq(amtBefore - _amount, amtAfter, 'Users token balance should decrease by the deposit amount');
      assertEq(
        (maiBalanceAfter - maiBalanceBefore),
        _amount - expectedFee,
        'Users MAI balance should increase by the deposit amount minus the fee'
      );
    }
  }

  function test_DepositWithZeroFee() public {
    USDCVaultDDW __psm = new USDCVaultDDW();
    _psm.initialize(0, 0);
    _psm.updateMinimumFees(0, 0);
    deal(address(_maiToken), address(_psm), 100_000_000 ether);
    _usdcToken.approve(address(_psm), 1000 ether);
    _psm.deposit(1000 ether);
    // assertEq(_l2dsr.balanceOf(address(_psm)), _l2dsr.convertToShares(1000 ether));
    assertEq(_maiToken.balanceOf(address(_owner)), 1000 ether);
    assertEq(__psm.depositFee(), 0);
    assertEq(__psm.withdrawalFee(), 0);
  }
}

contract USDCVaultWithdrawSuite is USDCVaultWithdrawalConstructor {
  event Withdrawn(address indexed user, uint256 amount);

  function test_RevertIfPaused() public {
    _psm.setPaused(USDCVaultDDW.scheduleWithdraw.selector, true);

    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.scheduleWithdraw(1000);
  }

  function test_DoubleWithdrawReverts() public {
    _usdcToken.approve(address(_psm), 1000 ether);
    _psm.deposit(1000 ether);
    console.log('maiToken balance before:', _maiToken.balanceOf(_owner));

    _maiToken.approve(address(_psm), _maiToken.balanceOf(_owner));
    _psm.scheduleWithdraw(_maiToken.balanceOf(_owner));
    uint256 _maiBalanceAfter = _maiToken.balanceOf(_owner);
    // MOOSE
    vm.expectRevert(USDCVaultDDW.WithdrawalAlreadyScheduled.selector);
    _psm.scheduleWithdraw(_maiBalanceAfter);
  }

  function test_Withdraw_BeforeEpochReverts() public {
    _usdcToken.approve(address(_psm), 1000 ether);
    _psm.deposit(1000 ether);
    _maiToken.approve(address(_psm), _maiToken.balanceOf(_owner));
    _psm.scheduleWithdraw(100 ether);
    vm.expectRevert(USDCVaultDDW.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  function test_Withdraw_NoScheduledWithdrawalReverts() public {
    vm.expectRevert(USDCVaultDDW.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  function test_DepositAndWithdraw(uint256 _depositAmount, uint256 _withdrawAmount) public {
    _depositAmount = bound(_depositAmount, 1e18, _usdcToken.balanceOf(_user));
    _withdrawAmount = bound(_withdrawAmount, 1e18, _depositAmount);
    // Deposit first to ensure there are tokens to withdraw
    _usdcToken.approve(address(_psm), _depositAmount);
    console.log('Deposit amount:', _depositAmount);
    console.log('maxDeposit:', _psm.maxDeposit());
    console.log('minimumDepositFee:', _psm.minimumDepositFee());
    console.log('WDAIToken balance bfore:', _usdcToken.balanceOf(address(_psm)));

    if (_depositAmount <= _psm.minimumDepositFee() || _depositAmount > _psm.maxDeposit()) {
      console.log('Deposit amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.deposit(_depositAmount);
      return;
    } else {
      uint256 _expectedFee = _psm.calculateFee(_depositAmount, true);
      uint256 _amtBefore = _usdcToken.balanceOf(_owner);
      uint256 _maiBalanceBefore = _maiToken.balanceOf(_owner);
      _psm.deposit(_depositAmount);
      uint256 _amtAfter = _usdcToken.balanceOf(_owner);
      uint256 _maiBalanceAfter = _maiToken.balanceOf(_owner);
      assertApproxEqAbs(
        _amtBefore, _amtAfter + _depositAmount, 10, 'Users token BALANCE should decrease by the deposit amount'
      );
      assertApproxEqAbs(
        (_maiBalanceAfter - _maiBalanceBefore),
        _depositAmount - _expectedFee,
        10,
        'Users MAI balance should increase by the deposit amount minus the fee'
      );
    }
    console.log('WDAIToken balance after:', _usdcToken.balanceOf(address(_psm)));
    uint256 _maiBalanceBefore = _maiToken.balanceOf(_owner);

    _maiToken.approve(address(_psm), _withdrawAmount);

    // Schedule the withdrawal
    if ((_psm.totalStableLiquidity() - _psm.totalQueuedLiquidity()) < _withdrawAmount) {
      console.log('Not enough liquidity');
      vm.expectRevert();
      _psm.scheduleWithdraw(_withdrawAmount);
      return;
    } else if (_withdrawAmount > _maiToken.balanceOf(address(_psm))) {
      console.log('Withdraw amount too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.scheduleWithdraw(_withdrawAmount);
      return;
    } else if (_withdrawAmount < _psm.minimumWithdrawalFee() || _withdrawAmount > _psm.maxWithdraw()) {
      console.log('Withdraw Amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.scheduleWithdraw(_withdrawAmount);
      return;
    } else {
      _psm.scheduleWithdraw(_withdrawAmount);
      uint256 _maiBalanceAfterSchedule = _maiToken.balanceOf(_owner);
      assertApproxEqAbs(
        _maiBalanceAfterSchedule,
        _maiBalanceBefore - _withdrawAmount,
        10,
        'Users MAI balance should decrease by the withdrawal amount'
      );
    }

    // Move forward in time to the next epoch to simulate the passage of time for withdrawal execution
    vm.warp(block.timestamp + 4 days);
    // Execute the withdrawal
    console.log('totalStableLiquidity:      ', _psm.totalStableLiquidity());
    console.log('withdrawAmount:            ', _withdrawAmount);
    if (_psm.totalStableLiquidity() < _withdrawAmount) {
      console.log('Not enough liquidity');
      vm.expectRevert(USDCVaultDDW.NotEnoughLiquidity.selector);
      _psm.withdraw();
    } else if (_withdrawAmount > _depositAmount) {
      console.log('Withdraw amount too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.withdraw();
    } else if (_withdrawAmount < _psm.minimumWithdrawalFee() || _withdrawAmount > _psm.maxWithdraw()) {
      console.log('Invalid amount');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.withdraw();
    } else {
      vm.expectEmit(false, false, false, false);
      emit Withdrawn(_user, _withdrawAmount);
      console.log('owner:                     ', _owner);
      console.log('user:                      ', _user);
      uint256 _amtBefore = _usdcToken.balanceOf(_owner);
      _psm.withdraw();
      uint256 _withdrawFee = _psm.calculateFee(_withdrawAmount, false);
      uint256 _maiBalanceAfter = _maiToken.balanceOf(_owner);
      uint256 _amtAfter = _usdcToken.balanceOf(_owner);

      console.log('_usdcTokenAddress:         ', address(_usdcToken));
      console.log('maiBalanceBefore:          ', _maiBalanceBefore);
      console.log('maiBalanceAfter:           ', _maiBalanceAfter);
      console.log('amtBefore:                 ', _amtBefore);
      console.log('amtAfter:                  ', _amtAfter);
      console.log('amtDiff:                   ', _amtAfter - _amtBefore);
      console.log('withdrawFee:               ', _withdrawFee);
      console.log('withdrawAmount:            ', _withdrawAmount);
      console.log('withdrawDiff:              ', _withdrawAmount - _withdrawFee);
      assertApproxEqAbs(
        _amtAfter - _amtBefore,
        _withdrawAmount - _withdrawFee,
        100,
        'Users token balance should increase by the withdrawal amount'
      );
      assertApproxEqAbs(
        _maiBalanceBefore,
        _maiToken.balanceOf(_owner) + _withdrawAmount,
        10_000,
        'Users MAI balance should decrease by the withdrawal amount'
      );
      assertGe(_usdcToken.balanceOf(_user), _withdrawAmount);
      assertGe(_usdcToken.balanceOf(address(_psm)), 0);
      _psm.claimFees();
      //                                    depositAmount   withdrawFee
      _psm.setUpgrade();
      vm.warp(block.timestamp + 4 days);
      _psm.transferToken(address(_usdcToken), address(_owner), _usdcToken.balanceOf(address(_psm)));
      assertEq(_usdcToken.balanceOf(address(_psm)), 0, 'usdcToken balance should be 0');

      _psm.transferToken(address(_usdcToken), address(_owner), _usdcToken.balanceOf(address(_psm)));
      assertEq(_usdcToken.balanceOf(address(_psm)), 0, 'WDAI balance should be 0');

      _psm.withdrawMAI();
      assertEq(_maiToken.balanceOf(address(_psm)), 0, 'MAI balance should be 0');
    }
  }
}
