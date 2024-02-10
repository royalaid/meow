pragma solidity 0.8.20;

interface IBeefy {
  function getPricePerFullShare() external view returns (uint256 _pricePerFullShare);
  function allowance(address owner, address spender) external view returns (uint256);
  function approvalDelay() external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function available() external view returns (uint256);
  function balance() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function decimals() external view returns (uint8);
  function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
  function deposit(uint256 _amount) external;
  function depositAll() external;
  function inCaseTokensGetStuck(address _token) external;
  function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
  function initialize(
    address _strategy,
    string calldata _name,
    string calldata _symbol,
    uint256 _approvalDelay
  ) external;
  function name() external view returns (string memory);
  function owner() external view returns (address);
  function proposeStrat(address _implementation) external;
  function renounceOwnership() external;
  function stratCandidate() external view returns (address implementation, uint256 proposedTime);
  function strategy() external view returns (address);
  function symbol() external view returns (string memory);
  function totalSupply() external view returns (uint256);
  function want() external view returns (address);
  function withdraw(uint256 _shares) external;
  function withdrawAll() external;
}
