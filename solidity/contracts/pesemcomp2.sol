
pragma solidity 0.8.20;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract AutoDepositCompound {
    uint256 public constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    address public constant C_TOKEN_ADDRESS = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
    address public constant MAI_ADDRESS = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;

    uint256 public totalUSDCDeposited;
    uint256 public depositFee;
    uint256 public withdrawalFee;
    uint256 public minimumDepositFee;
    uint256 public minimumWithdrawalFee;

    address public owner;
    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event FeesUpdated(uint256 newDepositFee, uint256 newWithdrawalFee);
    event MinimumFeesUpdated(uint256 newMinimumDepositFee, uint256 newMinimumWithdrawalFee);
    event OwnerUpdated(address newOwner);

    constructor(uint256 _depositFee, uint256 _withdrawalFee, uint256 _minimumDepositFee, uint256 _minimumWithdrawalFee) {
        depositFee = _depositFee;
        withdrawalFee = _withdrawalFee;
        minimumDepositFee = _minimumDepositFee;
        minimumWithdrawalFee = _minimumWithdrawalFee;
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, 'Caller is not the owner');
        _;
    }
    
    function deposit(uint256 amount) external {
        require(amount > minimumDepositFee, 'Amount must be greater than minimumDepositFee');

        uint256 fee = calculateDepositFee(amount);
        uint256 amountAfterFee = amount - fee;

        IERC20(C_TOKEN_ADDRESS).transferFrom(msg.sender, address(this), amount);
        totalUSDCDeposited += amountAfterFee;
        IERC20(MAI_ADDRESS).transferFrom(address(this), msg.sender, amountAfterFee);

        emit Deposited(msg.sender, amountAfterFee);
    }

    function withdraw(uint256 amount) external {
        require(amount > minimumWithdrawalFee && amount <= totalUSDCDeposited, 'Invalid amount');

        IERC20(MAI_ADDRESS).transfer(msg.sender, amount);
        uint256 fee = calculateWithdrawalFee(amount);
        uint256 amountAfterFee = amount - fee;
        totalUSDCDeposited -= amount;
        IERC20(C_TOKEN_ADDRESS).transfer(msg.sender, amountAfterFee);

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

    function withdrawFees() public {
        uint256 compBalance = IERC20(C_TOKEN_ADDRESS).balanceOf(address(this));
        uint256 FeesEarned = compBalance-totalUSDCDeposited;
        IERC20(C_TOKEN_ADDRESS).transfer(owner, FeesEarned);
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
    
}