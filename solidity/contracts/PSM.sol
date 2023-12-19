pragma solidity 0.8.20;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract AutoDepositCompound {
    uint256 public constant MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    address public constant MAI_ADDRESS = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;

    mapping(address => bool) public approvedCTokens;

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
    event CTokenApproved(address indexed cToken);
    event Deposited(address indexed user, address indexed cToken, uint256 amount);
    event Withdrawn(address indexed user, address indexed cToken, uint256 amount);
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

    function approveCToken(address cToken) external onlyOwner {
        approvedCTokens[cToken] = true;
        emit CTokenApproved(cToken);
    }
    
    function deposit(address cToken, uint256 amount) external {
        require(approvedCTokens[cToken], 'CToken is not approved');
        require(amount > minimumDepositFee, 'Amount must be greater than minimumDepositFee');

        uint256 fee = calculateDepositFee(amount);
        uint256 amountAfterFee = amount - fee;

        IERC20(cToken).transferFrom(msg.sender, address(this), amount);
        totalStableDeposited += amountAfterFee;
        IERC20(MAI_ADDRESS).transferFrom(address(this), msg.sender, amountAfterFee);

        emit Deposited(msg.sender, cToken, amountAfterFee);
    }

    function withdraw(address cToken, uint256 amount) external {
        require(approvedCTokens[cToken], 'CToken is not approved');
        require(amount > minimumWithdrawalFee && amount <= totalStableDeposited, 'Invalid amount');

        IERC20(MAI_ADDRESS).transfer(msg.sender, amount);
        uint256 fee = calculateWithdrawalFee(amount);
        uint256 amountAfterFee = amount - fee;
        totalStableDeposited -= amount;
        IERC20(cToken).transfer(msg.sender, amountAfterFee);

        emit Withdrawn(msg.sender, cToken, amountAfterFee);
    }

    function calculateDepositFee(uint256 amount) public view returns (uint256) {
        uint256 fee = amount * depositFee / 10000;
        return fee < minimumDepositFee ? minimumDepositFee : fee;
    }

    function calculateWithdrawalFee(uint256 amount) public view returns (uint256) {
        uint256 fee = amount * withdrawalFee / 10000;
        return fee < minimumWithdrawalFee ? minimumWithdrawalFee : fee;
    }

    function withdrawFees(address cToken) public onlyOwner {
        require(approvedCTokens[cToken], 'CToken is not approved');
        uint256 compBalance = IERC20(cToken).balanceOf(address(this));
        uint256 FeesEarned = compBalance - totalStableDeposited;
        IERC20(cToken).transfer(owner, FeesEarned);
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

    /*
        Big Question-mark

        Do we prefer calling this as panic which will have predetermined ways to panic itself?
        Or do we prefer draining by minting MAI, swapping, and draining that liquidity that way?
        Then we have more fine-grained control of how we deposit it back, instead of just having underlying...
        It could be part of a bigger issue such as depegs or bridge hacks
    */

    function callPanic(address token) external {
        require(!panicCalls[token].called, "callPanic already executed here");
        (bool success, bytes memory returnData) = panicCalls[token].target.delegatecall(panicCalls[token].data);
        require(success, "Delegatecall failed");
    }
}