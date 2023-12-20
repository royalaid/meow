// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'openzeppelin-contracts/contracts/access/Ownable.sol';
import 'openzeppelin-contracts/contracts/utils/Pausable.sol';
import 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-contracts/contracts/interfaces/IERC721Receiver.sol';
import '../interfaces/IBeefyVault.sol';
import '../interfaces/ICrossChainStablecoin.sol';
import '../interfaces/IPerfToken.sol';

contract QiZappah is Ownable, Pausable, IERC721Receiver {
  struct AssetChain {
    IERC20 asset;
    IBeefyVault mooToken;
    IPerfToken perfToken;
    ICrossChainStablecoin mooTokenVault;
  }
  /*
        WETH ->
        Call deposit on yearn vault @ 0xA628c54C850ff1077b5C954491D19EccE7e321fF
        Call enter on PerfToken @ 0x5A6325c3E3c88Dbcd52a8d55a31b342d09fa7982
        Call depositCollateral @ 0xD13Ed4879DCF81C181DA82C46F4D0689b0734F23
        */

  mapping(bytes32 => AssetChain) private _chainWhiteList;

  event AssetZapped(address indexed asset, uint256 indexed amount, uint256 vaultId);
  event AssetUnZapped(address indexed asset, uint256 indexed amount, uint256 vaultId);

  constructor() Ownable(msg.sender) Pausable() {}

  function _beefyZapToVault(
    uint256 amount,
    uint256 vaultId,
    AssetChain memory chain
  ) internal whenNotPaused returns (uint256) {
    require(amount > 0, 'You need to deposit at least some tokens');

    uint256 allowance = chain.asset.allowance(msg.sender, address(this));
    require(allowance >= amount, 'Check the token allowance');
    require(chain.mooTokenVault.exists(vaultId), "VaultId provided doesn't exist");

    chain.asset.transferFrom(msg.sender, address(this), amount);

    chain.asset.approve(address(chain.mooToken), amount);
    uint256 originalMooTokenBal = chain.mooToken.balanceOf(address(this));
    chain.mooToken.deposit(amount);
    uint256 postDepositMooTokenBal = chain.mooToken.balanceOf(address(this));
    uint256 mooTokenBalToZap = postDepositMooTokenBal - originalMooTokenBal;

    uint256 originalPerfTokenBal = chain.perfToken.balanceOf(address(this));
    chain.mooToken.approve(address(chain.perfToken), mooTokenBalToZap);
    chain.perfToken.enter(mooTokenBalToZap);
    uint256 postEnterPerfTokenBal = chain.perfToken.balanceOf(address(this));
    uint256 perfTokenBalToZap = postEnterPerfTokenBal - originalPerfTokenBal;

    chain.perfToken.approve(address(chain.mooTokenVault), perfTokenBalToZap);
    chain.mooTokenVault.depositCollateral(vaultId, perfTokenBalToZap);
    emit AssetZapped(address(chain.asset), amount, vaultId);
    return chain.perfToken.balanceOf(msg.sender);
  }

  function _beefyZapFromVault(
    uint256 amount,
    uint256 vaultId,
    AssetChain memory chain
  ) internal whenNotPaused returns (uint256) {
    require(amount > 0, 'You need to withdraw at least some tokens');
    require(chain.mooTokenVault.getApproved(vaultId) == address(this), 'Need to have approval');
    require(chain.mooTokenVault.ownerOf(vaultId) == msg.sender, 'You can only zap out of vaults you own');

    //Transfer vault to this contract
    chain.perfToken.approve(address(chain.mooTokenVault), amount);
    chain.mooTokenVault.safeTransferFrom(msg.sender, address(this), vaultId);

    //Withdraw funds from vault
    uint256 perfTokenBalanceBeforeWithdraw = chain.perfToken.balanceOf(address(this));
    chain.mooTokenVault.withdrawCollateral(vaultId, amount);
    uint256 perfTokenBalanceToUnzap = chain.perfToken.balanceOf(address(this)) - perfTokenBalanceBeforeWithdraw;

    //Return vault to user
    chain.mooTokenVault.approve(msg.sender, vaultId);
    chain.mooTokenVault.safeTransferFrom(address(this), msg.sender, vaultId);

    //Exit from the perfToken to mooToken
    uint256 mooTokenBalanceBeforeWithdraw = chain.mooToken.balanceOf(address(this));
    chain.perfToken.leave(perfTokenBalanceToUnzap);
    uint256 mooTokenBalanceToUnzap = chain.mooToken.balanceOf(address(this)) - mooTokenBalanceBeforeWithdraw;

    //Withdraw underlying from respective yield bearing asset
    uint256 tokenBalanceBeforeWithdraw = chain.asset.balanceOf(address(this));
    chain.mooToken.withdraw(mooTokenBalanceToUnzap);
    uint256 tokenBalanceToTransfer = chain.asset.balanceOf(address(this)) - tokenBalanceBeforeWithdraw;

    //Transfer tokens to user
    chain.asset.approve(address(this), tokenBalanceToTransfer);
    chain.asset.transfer(msg.sender, tokenBalanceToTransfer);

    emit AssetUnZapped(address(chain.asset), amount, vaultId);
    return tokenBalanceToTransfer;
  }

  function _buildAssetChain(
    address _asset,
    address _mooAsset,
    address perfToken,
    address _mooAssetVault
  ) internal pure returns (AssetChain memory) {
    AssetChain memory chain;
    chain.asset = IERC20(_asset);
    chain.mooToken = IBeefyVault(_mooAsset);
    chain.perfToken = IPerfToken(perfToken);
    chain.mooTokenVault = ICrossChainStablecoin(_mooAssetVault);
    return chain;
  }

  function _hashAssetChain(AssetChain memory chain) internal pure returns (bytes32) {
    return keccak256(
      abi.encodePacked(
        address(chain.asset), address(chain.mooToken), address(chain.perfToken), address(chain.mooTokenVault)
      )
    );
  }

  function isWhiteListed(AssetChain memory chain) public view returns (bool) {
    return address(_chainWhiteList[_hashAssetChain(chain)].asset) != address(0x0);
  }

  function addChainToWhiteList(
    address _asset,
    address _mooAsset,
    address _perfToken,
    address _mooAssetVault
  ) public onlyOwner {
    AssetChain memory chain = _buildAssetChain(_asset, _mooAsset, _perfToken, _mooAssetVault);
    if (!isWhiteListed(chain)) {
      _chainWhiteList[_hashAssetChain(chain)] = chain;
    } else {
      revert('Chain already in White List');
    }
  }

  function removeChainFromWhiteList(
    address _asset,
    address _mooAsset,
    address _perfToken,
    address _mooAssetVault
  ) public onlyOwner {
    AssetChain memory chain = _buildAssetChain(_asset, _mooAsset, _perfToken, _mooAssetVault);
    if (isWhiteListed(chain)) {
      delete _chainWhiteList[_hashAssetChain(chain)];
    } else {
      revert('Chain not in white List');
    }
  }

  function pauseZapping() public onlyOwner {
    _pause();
  }

  function resumeZapping() public onlyOwner {
    _unpause();
  }

  function beefyZapToVault(
    uint256 amount,
    uint256 vaultId,
    address _asset,
    address _mooAsset,
    address _perfToken,
    address _mooAssetVault
  ) public whenNotPaused returns (uint256) {
    AssetChain memory chain = _buildAssetChain(_asset, _mooAsset, _perfToken, _mooAssetVault);
    require(isWhiteListed(chain), 'mooToken chain not in on allowable list');
    return _beefyZapToVault(amount, vaultId, chain);
  }

  function beefyZapFromVault(
    uint256 amount,
    uint256 vaultId,
    address _asset,
    address _mooAsset,
    address _perfToken,
    address _mooAssetVault
  ) public whenNotPaused returns (uint256) {
    AssetChain memory chain = _buildAssetChain(_asset, _mooAsset, _perfToken, _mooAssetVault);
    require(isWhiteListed(chain), 'mooToken chain not in on allowable list');
    return _beefyZapFromVault(amount, vaultId, chain);
  }

  function onERC721Received(address, address, uint256, bytes memory) public pure returns (bytes4) {
    return this.onERC721Received.selector;
  }
}
