pragma solidity 0.8.20;

interface IERC20 {
  function approve(address _spender, uint256 _amount) external returns (bool _success);
  function transfer(address _recipient, uint256 _amount) external returns (bool _success);
  function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool _success);
  function balanceOf(address _account) external view returns (uint256 _balance);
  function decimals() external view returns (uint8 decimals);
}

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
  function initialize(address _strategy, string calldata _name, string calldata _symbol, uint256 _approvalDelay) external;
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

  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Initialized(uint8 version);
  event NewStratCandidate(address implementation);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event UpgradeStrat(address implementation);
}

contract BeefyVaultDelayWithdrawal {
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

  address public underlying;
  address public owner;
  address public gem;

  // user deposits stable, schedules withdrawal of shares
  mapping(address => uint256) public withdrawalEpoch;
  mapping(address => uint256) public scheduledWithdrawalAmount;

  bool public paused;
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
  constructor() {
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

  function initialize(address _gem, uint256 _depositFee, uint256 _withdrawalFee) external onlyOwner {
    if(initialized) {
        revert AlreadyInitialized();
    }
    depositFee = _depositFee;
    withdrawalFee = _withdrawalFee;
    minimumDepositFee = 1_000_000; 
    minimumWithdrawalFee = 1_000_000;

    IBeefy beef = IBeefy(_gem);

    maxDeposit = 1e24;  // 1 million ether
    maxWithdraw = 1e24; // 1 million ether
    underlying = beef.want();
    decimalDifference = uint256(beef.decimals() - IERC20(underlying).decimals());
    gem = _gem;
    IERC20.approve(_gem, MAX_INT);
  }

  // user deposits tokens, withdraws stable
  function deposit(uint256 _amount) external pausable {
    IERC20(underlying).transferFrom(msg.sender, _amount);
    totalStableLiquidity+=_amount;
    IBeefy(gem).depositAll();
    IERC20(MAI_ADDRESS).transfer(msg.sender, _amount * (10**(decimalDifference)));
    emit Deposited(msg.sender, _amount);
  }

  function scheduleWithdraw(uint256 _amount) external pausable {
    IERC20(MAI_ADDRESS).transferFrom(msg.sender, _amount);
    scheduledWithdrawalAmount[msg.sender] = _amount;
    withdrawalEpoch[msg.sender] = block.timestamp + 3 days;
    emit WithdrawalScheduled(msg.sender, _amount);
  }

  function withdraw() external pausable {

    if(withdrawalEpoch[msg.sender] == 0 || block.timestamp < withdrawalEpoch[msg.sender] || block.timestamp > withdrawalEpoch[msg.sender] + 12 hours) {
        revert WithdrawalNotAvailable();
    }
    withdrawalEpoch=0;
    uint256 _amount = scheduledWithdrawalAmount[msg.sender];
    scheduledWithdrawalAmount=0;
    
    IBeefy beef = IBeefy(gem);
    // get shares from an amount
    uint256 shares = _amount * 1e18 / beef.getPricePerFullShare();
    beef.withdraw(shares);

    uint256 towithdraw = _amount / (10**decimalDifference);
    totalStableLiquidity-=towithdraw;

    IERC20(underlying).transfer(_recipient, towithdraw);

    emit Withdrawn(msg.sender, _amount);
  }

  function claimFees() external onlyOwner() {
    IBeefy beef = IBeefy(gem);
    // get total balance in underlying
    uint256 shares = beef.balanceOf(address(this));
    uint256 want = beef.getPricePerFullShare() * shares / (10**decimalDifference);
    if(want>totalStableLiquidity){
        uint256 fees = (want - totalStableLiquidity);
        // convert back to shares i guess
        uint256 shares = want * 1e18 / beef.getPricePerFullShare();
        beef.withdraw(shares);
        IERC20(underlying).transfer(msg.sender, _amount / (10**decimalDifference));
    }
  }

  function togglePause(bool _paused) external onlyOwner {
    paused = _paused;
    emit PauseEvent(msg.sender, _paused);
  }
}