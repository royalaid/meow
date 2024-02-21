pragma solidity 0.8.20;

import '../interfaces/IBeefy.sol';
import '../interfaces/IERC20.sol';
import 'forge-std/console.sol';

contract BeefyVaultPSM {
  uint256 public constant MAX_INT =
    115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935;
  address public constant MAI_ADDRESS = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;

  uint256 public totalStableLiquidity;
  uint256 public depositFee;
  uint256 public withdrawalFee;
  uint256 public minimumDepositFee;
  uint256 public minimumWithdrawalFee;
  uint256 public decimalDifference;

  uint256 public maxDeposit;
  uint256 public maxWithdraw;
  uint256 public upgradeTime;

  address public underlying;
  address public owner;
  address public gem;

  // user deposits stable, schedules withdrawal of shares
  mapping(address => uint256) public withdrawalEpoch;
  mapping(address => uint256) public scheduledWithdrawalAmount;

  mapping(bytes4 => bool) public paused;
  bool public stopped;

  bool public initialized;

  error CallerIsNotOwner();
  error ContractIsPaused();
  error InvalidAmount();
  error InvalidAmountAfterFee();
  error InsufficientMAIBalance();
  error WithdrawalAlreadyScheduled();
  error NotWithinWithdrawalPeriod();
  error NoWithdrawalScheduled();
  error WithdrawalAlreadyExecutable();
  error AlreadyInitialized();
  error NewOwnerCannotBeZeroAddress();
  error WithdrawalNotAvailable();
  error NotEnoughLiquidity();

  // Events
  event Deposited(address indexed _user, uint256 _amount);
  event Withdrawn(address indexed _user, uint256 _amount);
  event OwnerUpdated(address _newOwner);
  event MAIRemoved(address indexed _user, uint256 _amount);
  event FeesWithdrawn(address indexed _owner, uint256 _feesEarned);
  event PauseEvent(address _account, bytes4 selector, bool _paused);
  event WithdrawalCancelled(address indexed _user, uint256 _amount);
  event ScheduledWithdrawal(address indexed _user, uint256 _amount);
  event WithdrawalScheduled(address indexed _user, uint256 _amount);
  event MaxDepositUpdated(uint256 _maxDeposit);
  event MaxWithdrawUpdated(uint256 _maxWithdraw);
  event MinimumFeesUpdated(uint256 _newMinimumDepositFee, uint256 _newMinimumWithdrawalFee);
  event FeesUpdated(uint256 _newDepositFee, uint256 _newWithdrawalFee);
  event MaxUpdated(uint256 _maxDeposit, uint256 _maxWithdraw);

  // target 0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf
  constructor() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    if (msg.sender != owner) revert CallerIsNotOwner();
    _;
  }

  modifier pausable() {
    if (paused[msg.sig] || stopped && block.timestamp > upgradeTime) revert ContractIsPaused();
    _;
  }

  function initialize(address _gem, uint256 _depositFee, uint256 _withdrawalFee) external onlyOwner {
    if (initialized) {
      revert AlreadyInitialized();
    }
    depositFee = _depositFee;
    withdrawalFee = _withdrawalFee;
    minimumDepositFee = 1_000_000;
    minimumWithdrawalFee = 1_000_000;

    IBeefy beef = IBeefy(_gem);

    maxDeposit = 1e24; // 1 million ether
    maxWithdraw = 1e24; // 1 million ether
    underlying = beef.want();
    decimalDifference = uint256(beef.decimals() - IERC20(underlying).decimals());
    gem = _gem;
    approveBeef();
  }

  function approveBeef() public {
    IERC20(underlying).approve(gem, MAX_INT);
  }

  // user deposits tokens (6 decimals), withdraws stable
  function deposit(uint256 _amount) external pausable {
    if (_amount <= minimumDepositFee || _amount > maxDeposit) revert InvalidAmount();
    IERC20(underlying).transferFrom(msg.sender, address(this), _amount);
    uint256 fee = calculateFee(_amount, true);
    _amount = _amount - fee;
    totalStableLiquidity += _amount;
    IBeefy(gem).depositAll();

    IERC20(MAI_ADDRESS).transfer(msg.sender, _amount * (10 ** (decimalDifference)));
    emit Deposited(msg.sender, _amount);
  }

  function scheduleWithdraw(uint256 _amount) external pausable {
    if (withdrawalEpoch[msg.sender] != 0) {
      revert WithdrawalAlreadyScheduled();
    }
    if (_amount < minimumWithdrawalFee || _amount > maxWithdraw) revert InvalidAmount();

    scheduledWithdrawalAmount[msg.sender] = _amount;
    withdrawalEpoch[msg.sender] = block.timestamp + 3 days;
    emit WithdrawalScheduled(msg.sender, _amount);
  }

  function calculateAmountToShares(uint256 _amount) internal view returns (uint256 _shares) {
    IBeefy beef = IBeefy(gem);
    return (_amount * beef.totalSupply()) / beef.balance();
  }

  function calculateSharesToAmount(uint256 _shares) internal view returns (uint256 _amount) {
    IBeefy beef = IBeefy(gem);
    return (_shares * beef.balance()) / beef.totalSupply();
  }

  function withdraw() external pausable {
    if (withdrawalEpoch[msg.sender] == 0 || block.timestamp < withdrawalEpoch[msg.sender]) {
      revert WithdrawalNotAvailable();
    }

    withdrawalEpoch[msg.sender] = 0;
    uint256 _amount = scheduledWithdrawalAmount[msg.sender];
    scheduledWithdrawalAmount[msg.sender] = 0;
    uint256 toWithdraw = _amount / (10 ** decimalDifference);
    uint256 fee = calculateFee(toWithdraw, false);
    uint256 toWithdrawwFee = (toWithdraw - fee);
    if (toWithdraw > totalStableLiquidity) {
      revert NotEnoughLiquidity();
    }
    IBeefy beef = IBeefy(gem);
    // get shares from an amount
    uint256 freshShares = calculateAmountToShares(_amount);
    uint256 freshSharesRounded = (freshShares / (10 ** decimalDifference)) + 1;
    uint256 shares = (_amount * (10 ** 6)) / beef.getPricePerFullShare();
    console.log('shares:                    ', shares);
    console.log('sharesInContract:          ', beef.balanceOf(address(this)));
    console.log('shareValueUsd:             ', (beef.getPricePerFullShare() * shares) / (10 ** 6));
    console.log('amount:                    ', _amount);
    console.log('freshShareValueUsd:        ', (beef.getPricePerFullShare() * freshSharesRounded) / (10 ** 6));
    console.log('freshShares:               ', freshSharesRounded);

    beef.withdraw(freshSharesRounded);

    totalStableLiquidity -= toWithdraw;

    IERC20(underlying).transfer(msg.sender, toWithdrawwFee);

    emit Withdrawn(msg.sender, _amount);
  }

  function calculateFee(uint256 _amount, bool _deposit) public view returns (uint256 _fee) {
    if (_deposit) {
      _fee = _amount * depositFee / 10_000;
      _fee = _fee < minimumDepositFee ? minimumDepositFee : _fee;
    } else {
      _fee = _amount * withdrawalFee / 10_000;
      _fee = _fee < minimumWithdrawalFee ? minimumWithdrawalFee : _fee;
    }
  }

  function claimFees() external onlyOwner {
    IBeefy beef = IBeefy(gem);
    // get total balance in underlying
    uint256 shares = beef.balanceOf(address(this));
    uint256 totalStoredInUsd = calculateSharesToAmount(shares) / (10 ** decimalDifference);
    uint256 totalStableShares = calculateAmountToShares(totalStableLiquidity) / (10 ** decimalDifference);
    console.log('totalStableLiquidity:      ', totalStableLiquidity);
    console.log('totalStoredInUsd:          ', totalStoredInUsd);
    console.log('totalStableShares:         ', totalStableShares);
    if (totalStoredInUsd > totalStableLiquidity) {
      uint256 fees = (totalStoredInUsd - totalStableLiquidity); // in USDC
      beef.withdraw(shares - totalStableShares);
      IERC20(underlying).transfer(msg.sender, fees / (10 ** decimalDifference));
    }
  }

  function setPaused(bytes4 selector, bool _paused) external onlyOwner {
    paused[selector] = _paused;
    emit PauseEvent(msg.sender, selector, _paused);
  }

  function transferOwnership(address newOwner) external onlyOwner {
    if (newOwner == address(0)) revert NewOwnerCannotBeZeroAddress();
    owner = newOwner;
    emit OwnerUpdated(newOwner);
  }

  function setUpgrade() external onlyOwner {
    if (!stopped) {
      stopped = true;
      upgradeTime = block.timestamp + 2 days;
    }
  }

  function transferToken(address _token, address _to, uint256 _amount) external onlyOwner {
    if (stopped && block.timestamp > upgradeTime) {
      IERC20(_token).transfer(_to, _amount);
    }
  }

  function withdrawMAI() external onlyOwner {
    IERC20 mai = IERC20(MAI_ADDRESS);
    mai.transfer(msg.sender, mai.balanceOf(address(this)));
  }

  function updateMinimumFees(uint256 _newMinimumDepositFee, uint256 _newMinimumWithdrawalFee) external onlyOwner {
    minimumDepositFee = _newMinimumDepositFee;
    minimumWithdrawalFee = _newMinimumWithdrawalFee;
    emit MinimumFeesUpdated(_newMinimumDepositFee, _newMinimumWithdrawalFee);
  }

  function updateFeesBP(uint256 _newDepositFee, uint256 _newWithdrawalFee) external onlyOwner {
    depositFee = _newDepositFee;
    withdrawalFee = _newWithdrawalFee;
    emit FeesUpdated(_newDepositFee, _newWithdrawalFee);
  }

  function updateMax(uint256 _maxDeposit, uint256 _maxWithdraw) external onlyOwner {
    maxDeposit = _maxDeposit;
    maxWithdraw = _maxWithdraw;
    emit MaxUpdated(_maxDeposit, _maxWithdraw);
  }
}
