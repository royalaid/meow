
pragma solidity 0.8.20;

interface ICompoundCtoken {
    function supply(uint256 amount) external;
    function withdraw(uint256 amount) external;
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract AutoDepositCompound {
    uint256 public constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    address public constant COMPOUND_ADDRESS = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address public constant C_TOKEN_ADDRESS = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
    address public constant USDC_ADDRESS = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address public constant MAI_ADDRESS = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;
    uint256 public totalUSDCDeposited;
    uint256 public depositFee;
    uint256 public withdrawalFee;
    uint256 public minimumDepositFee;
    uint256 public minimumWithdrawalFee;
    address public owner;
    address public comptroller;

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event FeesUpdated(uint256 newDepositFee, uint256 newWithdrawalFee);
    event MinimumFeesUpdated(uint256 newMinimumDepositFee, uint256 newMinimumWithdrawalFee);
    event OwnerUpdated(address newOwner);

    constructor(address _comptroller, uint256 _depositFee, uint256 _withdrawalFee, uint256 _minimumDepositFee, uint256 _minimumWithdrawalFee) {
        depositFee = _depositFee;
        withdrawalFee = _withdrawalFee;
        minimumDepositFee = _minimumDepositFee;
        minimumWithdrawalFee = _minimumWithdrawalFee;
        owner = msg.sender;
        comptroller=_comptroller;
    }

    modifier onlyOwner {
        require(msg.sender == owner, 'Caller is not the owner');
        _;
    }
    
    function deposit(uint256 amount) external {
        require(amount > 0, 'Amount must be greater than 0');
        uint256 fee = calculateDepositFee(amount);
        uint256 amountAfterFee = amount - fee;
        totalUSDCDeposited += amountAfterFee;

        // Approve and supply to Compound
        IERC20(USDC_ADDRESS).approve(COMPOUND_ADDRESS, amount);
        // Assuming supply function exists on the Compound cToken interface
        ICompoundCtoken(COMPOUND_ADDRESS).supply(amount);

        IERC20(MAI_ADDRESS).transferFrom(comptroller, msg.sender, amountAfterFee);

        emit Deposited(msg.sender, amountAfterFee);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0 && amount <= totalUSDCDeposited, 'Invalid amount');

        IERC20(MAI_ADDRESS).transferFrom(msg.sender, comptroller, amount);

        uint256 fee = calculateWithdrawalFee(amount);
        uint256 amountAfterFee = amount - fee;
        totalUSDCDeposited -= amount;

        ICompoundCtoken(COMPOUND_ADDRESS).withdraw(amountAfterFee);

        // Transfer USDC to user
        IERC20(USDC_ADDRESS).transfer(msg.sender, amountAfterFee);

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
        ICompoundCtoken(COMPOUND_ADDRESS).withdraw(FeesEarned);
        IERC20(USDC_ADDRESS).transfer(owner, FeesEarned);
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