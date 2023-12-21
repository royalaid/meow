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

contract PSMVaultGeneric {
    uint256 public constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    address public constant MAI_ADDRESS = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;

    uint256 public totalStableDeposited;
    uint256 public depositFee;
    uint256 public withdrawalFee;
    uint256 public minimumDepositFee;
    uint256 public minimumWithdrawalFee;
    uint256 public underlyingDecimals;
    uint256 public constant maiDecimals = 1e18;

    address public target;
    address public underlying;
    address public owner;
    address public gem;

    bytes public data;
    bool public panic;
    bool public panicked;

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event FeesUpdated(uint256 newDepositFee, uint256 newWithdrawalFee);
    event MinimumFeesUpdated(uint256 newMinimumDepositFee, uint256 newMinimumWithdrawalFee);
    event OwnerUpdated(address newOwner);
    event MAIRemovedBy(address indexed user, uint256 amount);
    event FeesWithdrawn(address indexed owner, uint256 feesEarned);
    event PanicCallUpdated(address target, bytes data, bool called);

    // data 0xf3fef3a3000000000000000000000000d9aaec86b65d86f6a7b5b1b0c42ffa531710b6caffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    // target 0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf
    constructor(address _gem, address _underlying, uint256 _underlyingDecimals, uint256 _depositFee, uint256 _withdrawalFee, bytes memory _data, address _target) {
        depositFee = _depositFee;
        withdrawalFee = _withdrawalFee;
        minimumDepositFee = 1000000; // 1 dollar
        minimumWithdrawalFee = 1000000; // 1 dollar
        underlying = _underlying;
        underlyingDecimals = _underlyingDecimals;
        data = _data;
        gem = _gem;
        target = _target;
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, 'Caller is not the owner');
        _;
    }
    
    // always assume 6 decimals

    function deposit(uint256 amount) external {
        require(amount > minimumDepositFee, 'Amount must be greater than fee');

        uint256 fee = calculateDepositFee(amount);
        uint256 amountAfterFee = amount - fee;

        IERC20(gem).transferFrom(msg.sender, address(this), amount);
        totalStableDeposited += amountAfterFee;
        IERC20(MAI_ADDRESS).transferFrom(address(this), msg.sender, amountAfterFee * (maiDecimals - underlyingDecimals));

        emit Deposited(msg.sender, amountAfterFee);
    }

    function withdraw(uint256 amount) external {
        require(amount > minimumWithdrawalFee && amount <= totalStableDeposited, 'Invalid amount');

        IERC20(MAI_ADDRESS).transfer(msg.sender, amount* (maiDecimals - underlyingDecimals));
        uint256 fee = calculateWithdrawalFee(amount);
        uint256 amountAfterFee = amount - fee;
        totalStableDeposited -= amount;
        IERC20(gem).transfer(msg.sender, amountAfterFee);

        emit Withdrawn(msg.sender, amountAfterFee);
    }

    function calculateDepositFee(uint256 amount) public view returns (uint256) {
        uint256 fee = amount * depositFee / 10000;
        return fee < minimumDepositFee ? minimumDepositFee : fee;
    }

    function calculateWithdrawalFee(uint256 amount) public view returns (uint256) {
        uint256 fee = amount * withdrawalFee / 10000;
        return fee < minimumWithdrawalFee ? minimumWithdrawalFee : fee;
    }

    function withdrawFees() public onlyOwner {
        uint256 compBalance = IERC20(MAI_ADDRESS).balanceOf(address(this));
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
        emit MAIRemovedBy(msg.sender, bal);
    }

    function callPanic() external {
        require(!panicked, 'Already panicking');
        (bool success,) = target.delegatecall(data);
        require(success, 'Panic failed');   
    }
}