pragma solidity 0.8.20;

interface IERC20 {
  function approve(address _spender, uint256 _amount) external returns (bool _success);
  function transfer(address _recipient, uint256 _amount) external returns (bool _success);
  function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool _success);
  function balanceOf(address _account) external view returns (uint256 _balance);
}

interface IBeefy {
  function getPricePerFullShare() external view returns (uint256 _pricePerFullShare);
}

contract BeefyVaultDelayWithdrawal4 {
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

  address public underlying;
  address public owner;
  address public gem;

  // user deposits stable, schedules withdrawal of shares
  mapping(address => uint256) public withdrawalEpoch;
  mapping(address => uint256) public scheduledWithdrawalAmount;

  bool public paused;

  error CallerIsNotOwner();
  error ContractIsPaused();
  error InvalidAmount();
  error InvalidAmountAfterFee();
  error InsufficientMAIBalance();
  error WithdrawalAlreadyScheduled();
  error NotWithinWithdrawalPeriod();
  error NoWithdrawalScheduled();
  error WithdrawalAlreadyExecutable();

  // Events
  event Deposited(address indexed _user, uint256 _amount);
  event Withdrawn(address indexed _user, uint256 _amount);
  event FeesUpdated(uint256 _newDepositFee, uint256 _newWithdrawalFee);
  event MinimumFeesUpdated(uint256 _newMinimumDepositFee, uint256 _newMinimumWithdrawalFee);
  event OwnerUpdated(address _newOwner);
  event MAIRemoved(address indexed _user, uint256 _amount);
  event FeesWithdrawn(address indexed _owner, uint256 _feesEarned);
  event PauseEvent(address _account, bool _paused);
  event WithdrawalCancelled(address indexed _user, uint256 _amount);
  event ScheduledWithdrawal(address indexed _user, uint256 _amount);
  event WithdrawalScheduled(address indexed _user, uint256 _amount);
  event MaxDepositUpdated(uint256 _maxDeposit);
  event MaxWithdrawUpdated(uint256 _maxWithdraw);

  // target 0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf
  constructor(address _gem, address _underlying, uint256 _depositFee, uint256 _withdrawalFee) {
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
    owner = msg.sender;
  }

  modifier onlyOwner() {
    if (msg.sender != owner) revert CallerIsNotOwner();
    _;
  }

  modifier pausable() {
    if (paused) revert ContractIsPaused();
    _;
  }

  // user deposits shares, withdraws stable
  function deposit(uint256 _amount) external pausable {
    if (_amount < minimumDepositFee || _amount > maxDeposit) revert InvalidAmount();

    uint256 _fee = calculateDepositFee(_amount);

    if (_amount <= _fee) revert InvalidAmount();

    uint256 _amountAfterFee = _amount - _fee;
    uint256 _amountOfUnderlying = IBeefy(gem).getPricePerFullShare() * _amountAfterFee / 1e18;

    if (IERC20(MAI_ADDRESS).balanceOf(address(this)) < _amountOfUnderlying) revert InsufficientMAIBalance();

    IERC20(gem).transferFrom(msg.sender, address(this), _amount);
    totalStableLiquidity += _amountOfUnderlying;
    accumulatedFees += _fee;

    IERC20(MAI_ADDRESS).transfer(msg.sender, _amountOfUnderlying);

    emit Deposited(msg.sender, _amountAfterFee);
  }

  function scheduleWithdraw(uint256 _amount) external pausable {
    if (_amount < minimumWithdrawalFee || _amount > maxWithdraw) revert InvalidAmount();
    if (scheduledWithdrawalAmount[msg.sender] != 0) revert WithdrawalAlreadyScheduled();

    IERC20(MAI_ADDRESS).transferFrom(msg.sender, address(this), _amount);
    scheduledWithdrawalAmount[msg.sender] = _amount;
    withdrawalEpoch[msg.sender] = getCurrentEpoch();

    emit ScheduledWithdrawal(msg.sender, _amount);
  }

  function executeWithdrawal() external pausable {
    if (!isWithinWithdrawalPeriod(withdrawalEpoch[msg.sender])) revert NotWithinWithdrawalPeriod();

    uint256 _amount = scheduledWithdrawalAmount[msg.sender];
    if (_amount > totalStableLiquidity) revert InvalidAmount();

    uint256 _amountOfShares = _amount * 1e18 / IBeefy(gem).getPricePerFullShare();
    uint256 _fee = calculateWithdrawalFee(_amountOfShares);
    if (_amountOfShares <= _fee) revert InvalidAmountAfterFee();

    uint256 _amountOfSharesAfterFee = _amountOfShares - _fee;
    totalStableLiquidity -= _amount;
    accumulatedFees += _fee;

    scheduledWithdrawalAmount[msg.sender] = 0;
    withdrawalEpoch[msg.sender] = 0;

    IERC20(gem).transfer(msg.sender, _amountOfSharesAfterFee);

    emit Withdrawn(msg.sender, _amountOfSharesAfterFee);
  }

  function cancelWithdrawal() external pausable {
    if (scheduledWithdrawalAmount[msg.sender] == 0) revert NoWithdrawalScheduled();
    if (getCurrentEpoch() - withdrawalEpoch[msg.sender] >= 3) revert WithdrawalAlreadyExecutable();

    uint256 _amount = scheduledWithdrawalAmount[msg.sender];
    scheduledWithdrawalAmount[msg.sender] = 0;
    withdrawalEpoch[msg.sender] = 0;

    IERC20(MAI_ADDRESS).transfer(msg.sender, _amount);
    emit WithdrawalCancelled(msg.sender, _amount);
  }

  function getCurrentEpoch() public view returns (uint256 _epoch) {
    _epoch = block.timestamp / 1 days;
  }

  function isWithinWithdrawalPeriod(uint256 _epoch) public view returns (bool _withinPeriod) {
    uint256 _epochStartTime = _epoch * 1 days;
    _withinPeriod = block.timestamp >= _epochStartTime && block.timestamp <= _epochStartTime + 12 hours;
  }

  function calculateDepositFee(uint256 _amount) public view returns (uint256 _fee) {
    _fee = _amount * depositFee / 10_000;
    _fee = _fee < minimumDepositFee ? minimumDepositFee : _fee;
  }

  function calculateWithdrawalFee(uint256 _amount) public view returns (uint256 _fee) {
    _fee = _amount * withdrawalFee / 10_000;
    _fee = _fee < minimumWithdrawalFee ? minimumWithdrawalFee : _fee;
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

  function updateOwner(address _newOwner) external onlyOwner {
    owner = _newOwner;
    emit OwnerUpdated(_newOwner);
  }

  function withdrawFees() external {
    totalFees += accumulatedFees * IBeefy(gem).getPricePerFullShare() / 1e18; // convert to underlying to set the token value.
    IERC20(gem).transfer(owner, accumulatedFees);
    emit FeesWithdrawn(owner, accumulatedFees);
    accumulatedFees = 0;
  }

  function removeMAI() external onlyOwner {
    IERC20 _mai = IERC20(MAI_ADDRESS);
    uint256 _bal = _mai.balanceOf(address(this));
    _mai.transfer(msg.sender, _bal);
    emit MAIRemoved(msg.sender, _bal);
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
