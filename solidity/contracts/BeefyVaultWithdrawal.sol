pragma solidity 0.8.20;

interface IERC20 {
  function approve(address spender, uint256 amount) external returns (bool);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
}

interface IBeefy {
  function getPricePerFullShare() external view returns (uint256);
}

contract BeefyVaultWithdrawal {
  uint256 public constant MAX_INT =
    115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935;
  address public constant MAI_ADDRESS = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;

  uint256 public totalStableLiquidity;
  uint256 public depositFee;
  uint256 public withdrawalFee;
  uint256 public minimumDepositFee;
  uint256 public minimumWithdrawalFee;

  uint256 public maxDeposit;
  uint256 public maxWithdraw;

  uint256 public totalFees;
  uint256 public accumulatedFees;

  address public target;
  address public underlying;
  address public owner;
  address public gem;

  // user deposits stable, schedules withdrawal of shares
  mapping(address => uint256) public withdrawalEpoch;
  mapping(address => uint256) public scheduledWithdrawalAmount;

  bool public paused;

  // Events
  event Deposited(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event FeesUpdated(uint256 newDepositFee, uint256 newWithdrawalFee);
  event MinimumFeesUpdated(uint256 newMinimumDepositFee, uint256 newMinimumWithdrawalFee);
  event OwnerUpdated(address newOwner);
  event MAIRemoved(address indexed user, uint256 amount);
  event FeesWithdrawn(address indexed owner, uint256 feesEarned);
  event PauseEvent(address account, bool paused);
  event WithdrawalCancelled(address indexed user, uint256 amount);
  event ScheduledWithdrawal(address indexed user, uint256 amount);
  event WithdrawalScheduled(address indexed user, uint256 amount);
  event MaxDepositUpdated(uint256 maxDeposit);
  event MaxWithdrawUpdated(uint256 maxWithdraw);

  // target 0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf
  constructor(address _gem, address _underlying, uint256 _depositFee, uint256 _withdrawalFee, address _target) {
    depositFee = _depositFee;
    withdrawalFee = _withdrawalFee;
    minimumDepositFee = 1_000_000; //
    minimumWithdrawalFee = 1_000_000;
    //
    maxDeposit = 1e24;
    // 1 million ether
    maxWithdraw = 1e24; // 1 million ether
    underlying = _underlying;
    gem = _gem;
    target = _target;
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, 'Caller is not the owner');
    _;
  }

  modifier pausable() {
    require(!paused, 'Contract is paused');
    _;
  }

  // user deposits shares, withdraws stable
  function deposit(uint256 amount) external pausable {
    require(amount >= minimumDepositFee && amount <= maxDeposit, 'Invalid amount');

    uint256 fee = calculateDepositFee(amount);

    require(amount > fee, 'Invalid amount');

    uint256 amountAfterFee = amount - fee;
    uint256 amountOfUnderlying = IBeefy(gem).getPricePerFullShare() * amountAfterFee / 1e18;

    IERC20(gem).transferFrom(msg.sender, address(this), amount);
    totalStableLiquidity += amountOfUnderlying;
    accumulatedFees += fee;

    IERC20(MAI_ADDRESS).transfer(msg.sender, amountOfUnderlying);

    emit Deposited(msg.sender, amountAfterFee);
  }

  function scheduleWithdraw(uint256 amount) external pausable {
    require(amount >= minimumWithdrawalFee && amount <= maxWithdraw, 'Invalid amount');
    require(scheduledWithdrawalAmount[msg.sender] == 0, 'Withdrawal already scheduled');

    IERC20(MAI_ADDRESS).transferFrom(msg.sender, address(this), amount);
    scheduledWithdrawalAmount[msg.sender] = amount;
    withdrawalEpoch[msg.sender] = getCurrentEpoch();

    emit ScheduledWithdrawal(msg.sender, amount);
  }

  function executeWithdrawal() external pausable {
    require(isWithinWithdrawalPeriod(withdrawalEpoch[msg.sender]), 'Not within withdrawal period');

    uint256 amount = scheduledWithdrawalAmount[msg.sender];
    require(amount <= totalStableLiquidity, 'Invalid amount');

    uint256 amountOfShares = amount * 1e18 / IBeefy(gem).getPricePerFullShare();
    uint256 fee = calculateWithdrawalFee(amountOfShares);
    require(amountOfShares > fee, 'Invalid amount after fee');

    uint256 amountOfSharesAfterFee = amountOfShares - fee;
    totalStableLiquidity -= amount;
    accumulatedFees += fee;

    scheduledWithdrawalAmount[msg.sender] = 0;
    withdrawalEpoch[msg.sender] = 0;

    IERC20(gem).transfer(msg.sender, amountOfSharesAfterFee);

    emit Withdrawn(msg.sender, amountOfSharesAfterFee);
  }

  function cancelWithdrawal() external pausable {
    require(scheduledWithdrawalAmount[msg.sender] > 0, 'No withdrawal scheduled');
    require(getCurrentEpoch() - withdrawalEpoch[msg.sender] < 3, 'Withdrawal already executable');

    uint256 amount = scheduledWithdrawalAmount[msg.sender];
    scheduledWithdrawalAmount[msg.sender] = 0;
    withdrawalEpoch[msg.sender] = 0;

    IERC20(MAI_ADDRESS).transfer(msg.sender, amount);
    emit WithdrawalCancelled(msg.sender, amount);
  }

  function getCurrentEpoch() public view returns (uint256) {
    return block.timestamp / 1 days;
  }

  function isWithinWithdrawalPeriod(uint256 epoch) public view returns (bool) {
    uint256 epochStartTime = epoch * 1 days;
    return block.timestamp >= epochStartTime && block.timestamp <= epochStartTime + 12 hours;
  }

  function calculateDepositFee(uint256 amount) public view returns (uint256 fee) {
    fee = amount * depositFee / 10_000;
    fee < minimumDepositFee ? minimumDepositFee : fee;
  }

  function calculateWithdrawalFee(uint256 amount) public view returns (uint256 fee) {
    fee = amount * withdrawalFee / 10_000;
    fee < minimumWithdrawalFee ? minimumWithdrawalFee : fee;
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

  function withdrawFees() external {
    totalFees += accumulatedFees * IBeefy(gem).getPricePerFullShare() / 1e18; // convert to underlying to set the token value.
    IERC20(gem).transfer(owner, accumulatedFees);
    emit FeesWithdrawn(owner, accumulatedFees);
    accumulatedFees = 0;
  }

  function removeMAI() external onlyOwner {
    IERC20 mai = IERC20(MAI_ADDRESS);
    uint256 bal = mai.balanceOf(address(this));
    mai.transfer(msg.sender, bal);
    emit MAIRemoved(msg.sender, bal);
  }

  function updateMaxDeposit(uint256 _maxDeposit) external onlyOwner {
    maxDeposit = _maxDeposit;
    emit MaxDepositUpdated(_maxDeposit);
  }

  function updateMaxWithdraw(uint256 _maxWithdraw) external onlyOwner {
    maxWithdraw = _maxWithdraw;
    emit MaxWithdrawUpdated(_maxWithdraw);
  }

  function togglePause(bool _paused) external onlyOwner {
    paused = _paused;
    emit PauseEvent(msg.sender, _paused);
  }
}
