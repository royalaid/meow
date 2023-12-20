// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import 'openzeppelin-contracts/contracts/access/Ownable.sol';
import 'openzeppelin-contracts/contracts/utils/Pausable.sol';
import 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-contracts/contracts/interfaces/IERC721Receiver.sol';

abstract contract AbstractZappah is Ownable, Pausable, IERC721Receiver {
  mapping(bytes32 => address[]) private _chainWhiteList;

  error ChainAlreadyInWhitelist(address[] chain);
  error ChainNotInWhitelist(address[] chain);

  function _hashAssetChain(address[] memory chain) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(chain));
  }

  function isWhiteListed(address[] memory chain) public view returns (bool) {
    return _chainWhiteList[_hashAssetChain(chain)].length > 0;
  }

  function addChainToWhiteList(address[] memory chain) external onlyOwner {
    if (!isWhiteListed(chain)) {
      _chainWhiteList[_hashAssetChain(chain)] = chain;
    } else {
      revert ChainAlreadyInWhitelist(chain);
    }
  }

  function removeChainFromWhiteList(address[] memory chain) external onlyOwner {
    if (isWhiteListed(chain)) {
      delete _chainWhiteList[_hashAssetChain(chain)];
    } else {
      revert ChainNotInWhitelist(chain);
    }
  }

  function pauseZapping() external onlyOwner {
    _pause();
  }

  function resumeZapping() external onlyOwner {
    _unpause();
  }

  function onERC721Received(address, address, uint256, bytes memory) public pure returns (bytes4) {
    return this.onERC721Received.selector;
  }
}
