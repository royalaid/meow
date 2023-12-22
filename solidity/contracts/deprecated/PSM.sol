pragma solidity 0.8.20;

/*
    reading material:
    https://github.com/BellwoodStudios/dss-psm/blob/master/src/psm.sol

*/

interface IERC20 {
  function approve(address spender, uint256 amount) external returns (bool);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
}

contract AutoDepositCompound {
  uint256 public constant MAX_INT =
    115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935;
  address public constant MAI_ADDRESS = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;

  mapping(address => bool) public approvedGems;

  struct PanicCallData {
    address target;
    bytes data;
    bool called;
    address underlying;
  }

  mapping(address => PanicCallData) public panicCalls;

  uint256 public totalStableDeposited;
  uint256 public depositFee;
  uint256 public withdrawalFee;
  uint256 public minimumDepositFee;
  uint256 public minimumWithdrawalFee;

  address public owner;

  // Events
  event GemApproved(address indexed gem);
  event Deposited(address indexed user, address indexed gem, uint256 amount);
  event Withdrawn(address indexed user, address indexed gem, uint256 amount);
  event FeesUpdated(uint256 newDepositFee, uint256 newWithdrawalFee);
  event MinimumFeesUpdated(uint256 newMinimumDepositFee, uint256 newMinimumWithdrawalFee);
  event OwnerUpdated(address newOwner);
  event MAIRemoved(address indexed user, uint256 amount);
  event FeesWithdrawn(address indexed owner, uint256 feesEarned);
  event GemPanicUpdated(address indexed gem, address target, bytes data, address underlying, bool called);

  constructor(uint256 _depositFee, uint256 _withdrawalFee, uint256 _minimumDepositFee, uint256 _minimumWithdrawalFee) {
    depositFee = _depositFee;
    withdrawalFee = _withdrawalFee;
    minimumDepositFee = _minimumDepositFee;
    minimumWithdrawalFee = _minimumWithdrawalFee;
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, 'Caller is not the owner');
    _;
  }

  function updateGem(address gem, bool _approved) external onlyOwner {
    approvedGems[gem] = _approved;
    emit GemApproved(gem);
  }

  function updateGemPanic(
    address gem,
    address _target,
    bytes memory _data,
    address _underlying,
    bool _called
  ) external onlyOwner {
    panicCalls[gem].called = _called;
    panicCalls[gem].target = _target;
    panicCalls[gem].underlying = _underlying;
    panicCalls[gem].data = _data;
    emit GemApproved(gem);
    emit GemPanicUpdated(gem, _target, _data, _underlying, _called);
  }

  function deposit(address gem, uint256 amount) external {
    require(approvedGems[gem], 'Gem is not approved');
    require(amount > minimumDepositFee, 'Amount must be greater than minimumDepositFee');

    uint256 fee = calculateDepositFee(amount);
    uint256 amountAfterFee = amount - fee;

    IERC20(gem).transferFrom(msg.sender, address(this), amount);
    totalStableDeposited += amountAfterFee;
    IERC20(MAI_ADDRESS).transferFrom(address(this), msg.sender, amountAfterFee);

    emit Deposited(msg.sender, gem, amountAfterFee);
  }

  function withdraw(address gem, uint256 amount) external {
    require(approvedGems[gem], 'Gem is not approved');
    require(amount > minimumWithdrawalFee && amount <= totalStableDeposited, 'Invalid amount');

    IERC20(MAI_ADDRESS).transfer(msg.sender, amount);
    uint256 fee = calculateWithdrawalFee(amount);
    uint256 amountAfterFee = amount - fee;
    totalStableDeposited -= amount;
    IERC20(gem).transfer(msg.sender, amountAfterFee);

    emit Withdrawn(msg.sender, gem, amountAfterFee);
  }

  function calculateDepositFee(uint256 amount) public view returns (uint256) {
    uint256 fee = amount * depositFee / 10_000;
    return fee < minimumDepositFee ? minimumDepositFee : fee;
  }

  function calculateWithdrawalFee(uint256 amount) public view returns (uint256) {
    uint256 fee = amount * withdrawalFee / 10_000;
    return fee < minimumWithdrawalFee ? minimumWithdrawalFee : fee;
  }

  function withdrawFees(address gem) public onlyOwner {
    require(approvedGems[gem], 'Gem is not approved');
    uint256 compBalance = IERC20(gem).balanceOf(address(this));
    uint256 FeesEarned = compBalance - totalStableDeposited;
    IERC20(gem).transfer(owner, FeesEarned);
    emit FeesWithdrawn(owner, FeesEarned);
  }

  function updateFees(uint256 _depositFee, uint256 _withdrawalFee) external onlyOwner {
    depositFee = _depositFee;
    withdrawalFee = _withdrawalFee;
    emit FeesUpdated(_depositFee, _withdrawalFee);
  }

  function updateMinimumFees(uint256 _minimumDepositFee, uint256 _minimumWithdrawalFee) external onlyOwner {
    minimumDepositFee = _minimumDepositFee;
    minimumWithdrawalFee = _minimumWithdrawalFee;
    emit MinimumFeesUpdated(_minimumDepositFee, _minimumWithdrawalFee);
  }

  function updateOwner(address newOwner) external onlyOwner {
    owner = newOwner;
    emit OwnerUpdated(newOwner);
  }

  function removeMAI() external onlyOwner {
    IERC20 mai = IERC20(MAI_ADDRESS);
    uint256 bal = mai.balanceOf(address(this));
    mai.transfer(msg.sender, bal);
    emit MAIRemoved(msg.sender, bal);
  }

  function callPanic(address token) external {
    require(!panicCalls[token].called, 'callPanic already executed here');
    (bool success, bytes memory returnData) = panicCalls[token].target.delegatecall(panicCalls[token].data);

    require(success, 'Delegatecall failed');
  }
}
