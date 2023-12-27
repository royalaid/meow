contract EpochScheduler {
  uint256 public epochTime;
  uint256 public minEpochWait;
  uint256 public withdrawalPeriod;

  mapping(address => uint256) public nextAvailableEpoch;

  event TransactionScheduled(address indexed user, uint256 indexed epoch);
  event TransactionExecuted(address indexed user, uint256 indexed epoch);

  constructor(uint256 _epochTime, uint256 _minEpochWait, uint256 _withdrawalPeriod) {
    require(_withdrawalPeriod <= _epochTime / 3, 'Withdrawal period must be within 1/3 of the epoch');
    epochTime = _epochTime;
    minEpochWait = _minEpochWait;
    withdrawalPeriod = _withdrawalPeriod;
  }

  modifier isEpochAvailable() {
    require(block.timestamp >= nextAvailableEpoch[msg.sender], 'Current epoch is not available yet');
    _;
  }

  function doLater() external {
    uint256 currentEpoch = getCurrentEpoch();
    require(nextAvailableEpoch[msg.sender] < currentEpoch, 'Transaction already scheduled for current epoch');
    nextAvailableEpoch[msg.sender] = currentEpoch + minEpochWait;
    emit TransactionScheduled(msg.sender, nextAvailableEpoch[msg.sender]);
  }

  function executeTransaction() external isEpochAvailable {
    uint256 currentEpoch = getCurrentEpoch();
    require(isWithinWithdrawalPeriod(currentEpoch), 'Not within withdrawal period');
    nextAvailableEpoch[msg.sender] = currentEpoch + 1; // Reset the epoch for the user
    emit TransactionExecuted(msg.sender, currentEpoch);
    // Execute the transaction logic here
  }

  function getCurrentEpoch() public view returns (uint256) {
    return block.timestamp / epochTime;
  }

  function isWithinWithdrawalPeriod(uint256 epoch) public view returns (bool) {
    uint256 epochStart = epoch * epochTime;
    return block.timestamp >= epochStart + epochTime - withdrawalPeriod && block.timestamp <= epochStart + epochTime;
  }
}
