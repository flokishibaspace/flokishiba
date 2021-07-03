// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }
    
    function _msgData() internal view virtual returns (bytes memory) {
        this;
        return msg.data;
    }
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
    
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }
    
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
    
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }
    
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
}

contract ReentrancyGuard {
    bool private _notEntered;
    constructor () internal {
        _notEntered = true;
    }
    modifier nonReentrant() {
        require(_notEntered, "ReentrancyGuard: reentrant call");
        _notEntered = false;
        _;
        _notEntered = true;
    }
}

contract Farming is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    
    IBEP20 public depositToken;
    IBEP20 public rewardToken;
    address private admin;
    
    mapping (address => UserInfo) private user;    
    struct UserInfo {
        uint256 balance;
        uint256 lastRewardBlock;
    }
    
    PoolInfo public poolInfo;
    struct PoolInfo {
        uint256 balance;
        uint256 rewardPerBlock;
    }

    event Deposit(address indexed user, uint256 amount);
    event Donate(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);    
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event SetRewardPerBlock(uint256 amount);
    
    constructor (IBEP20 _depositToken, IBEP20 _rewardToken, uint256 _rewardPerBlock) public {
        depositToken = _depositToken;
        rewardToken = _rewardToken;
        admin = msg.sender;
        poolInfo.balance = 0;
        poolInfo.rewardPerBlock = _rewardPerBlock;
    }

    receive() external payable {
        assert(msg.sender == address(depositToken));
    }
    
    function deposit(uint256 _amount) public nonReentrant {
        require(_amount > 0, "Farming: amount must be greater than zero");
        depositToken.transferFrom(msg.sender, address(this), _amount);
        _claim(msg.sender);
        user[msg.sender].balance = user[msg.sender].balance.add(_amount);
        user[msg.sender].lastRewardBlock = block.number.add(1);
        poolInfo.balance = poolInfo.balance.add(_amount);
        emit Deposit(msg.sender, _amount);
    }

    function donate(uint256 _amount) public {
        require(_amount > 0, "Farming: amount must be greater than zero");
        rewardToken.transferFrom(msg.sender, address(this), _amount);
        emit Donate(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public nonReentrant {
        require(_amount > 0, "Farming: amount must be greater than zero");
        require(user[msg.sender].balance >= _amount, "Farming: amount exceeds balance");
        depositToken.transfer(msg.sender, _amount);
        _claim(msg.sender);
        user[msg.sender].balance = user[msg.sender].balance.sub(_amount);
        user[msg.sender].lastRewardBlock = block.number.add(1);
        poolInfo.balance = poolInfo.balance.sub(_amount);
        emit Withdraw(msg.sender, _amount); 
    }
    
    function emergencyWithdraw() public nonReentrant {
        require(user[msg.sender].balance > 0, 'Farming: not balance for emergency withdraw');
        uint256 _amount = user[msg.sender].balance;
        depositToken.transfer(msg.sender, _amount);
        user[msg.sender].balance = 0;
        user[msg.sender].lastRewardBlock = block.number.add(1);
        poolInfo.balance = poolInfo.balance.sub(_amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }
    
    function pendingReward(address _user) public view returns (uint256) {
        require(_user != address(0), 'Farming: pending reward from the zero address');
        if(user[_user].balance > 0 && user[_user].lastRewardBlock < block.number && user[_user].lastRewardBlock > 0){
            uint256 multiplier = block.number.sub(user[_user].lastRewardBlock);
            uint256 tokenPerShare = poolInfo.rewardPerBlock.mul(1e18).div(poolInfo.balance);
            return user[_user].balance.mul(tokenPerShare).div(1e18).mul(multiplier);
        }else{
            return 0;
        }
    }
    
    function claim(address _user) public nonReentrant returns (bool) {
        require(_user != address(0), 'Farming: claim to the zero address');
        _claim(_user);
        return true;
    }
    
    function _claim(address _user) private {
        uint256 pending = pendingReward(_user);
        require(pending < rewardToken.balanceOf(address(this)), 'Farming: not enough token in pool');
        if(pending > 0){
            rewardToken.transfer(_user, pending);
            user[_user].lastRewardBlock = block.number.add(1);
            emit Claim(_user, pending);
        }
    }
    
    function getBalance(address _user) public view returns (uint256) {
        require(_user != address(0), 'Farming: get balance from the zero address');
        return user[_user].balance;
    }
    
    function setRewardPerBlock(uint256 _amount) public onlyOwner {
        require(_amount > 0, "Farming: reward per block must be greater than zero");
        poolInfo.rewardPerBlock = _amount;
        emit SetRewardPerBlock(_amount);
    }
    
    function withdrawToken() public onlyOwner {
        uint256 balance = rewardToken.balanceOf(address(this));
        if(balance > 0){
            rewardToken.transfer(admin, balance);
        }
    }
}