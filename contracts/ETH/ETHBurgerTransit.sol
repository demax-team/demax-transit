// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import './libraries/SafeMath.sol';
import './libraries/TransferHelper.sol';

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

contract ETHBurgerTransit {
    using SafeMath for uint;
    
    address public owner;
    address public handler;
    address public WETH;
    
    uint public totalFee;
    
    uint public developFee;
    
    struct Record {
        uint gasFee;
        uint amount;
    }
    
    mapping (address => mapping(address => Record)) public records;
    
    event Transit(address indexed from, address indexed token, uint amount);
    event Withdraw(address indexed to, address indexed token, uint amount);
    event CollectFee(address indexed handler, uint amount);
    
    constructor(address _WETH) public {
        handler = msg.sender;
        owner = msg.sender;
        WETH = _WETH;
    }
    
    receive() external payable {
        assert(msg.sender == WETH);
    }
    
    function changeHandler(address _handler) external {
        require(msg.sender == owner, "CHANGE_HANDLER_FORBIDDEN");
        handler = _handler;
    }
    
    function changeDevelopFee(uint _amount) external {
        require(msg.sender == owner, "CHANGE_DEVELOP_FEE_FORBIDDEN");
        developFee = _amount;
    }
    
    function collectFee() external {
        require(msg.sender == handler || msg.sender == owner, "FORBIDDEN");
        require(totalFee > 0, "NO_FEE");
        TransferHelper.safeTransferETH(handler, totalFee);
    }
    
    function transitForBSC(address _token, uint _amount) external {
        require(_amount > 0, "INVALID_AMOUNT");
        TransferHelper.safeTransferFrom(_token, msg.sender, address(this), _amount);
        emit Transit(msg.sender, _token, _amount);
    }
    
    function transitETHForBSC() external payable {
        require(msg.value > 0, "INVALID_AMOUNT");
        IWETH(WETH).deposit{value: msg.value}();
        emit Transit(msg.sender, WETH, msg.value);
    }
    
    function addWithdrawRecord(address _token, address _to, uint _amount, uint _gasFee) external {
        require(msg.sender == handler, "ADD_RECORD_FORBIDDEN");
        records[_to][_token].amount = records[_to][_token].amount.add(_amount);
        records[_to][_token].gasFee = records[_to][_token].gasFee.add(_gasFee);
    }
    
    function withdrawFromBSC(address _token) external payable {
        Record storage record = records[msg.sender][_token];
        require(record.amount > 0, "NOTHING_TO_WITHDRAW");
        require(msg.value == record.gasFee.add(developFee), "INSUFFICIENT_VALUE");
        
        TransferHelper.safeTransfer(_token, msg.sender, record.amount);
        emit Withdraw(msg.sender, _token, record.amount);
        record.gasFee = 0;
        record.amount = 0;
    }
    
    function withdrawETHFromBSC() external payable {
        Record storage record = records[msg.sender][WETH];
        require(record.amount > 0, "NOTHING_TO_WITHDRAW");
        require(msg.value == record.gasFee.add(developFee), "INSUFFICIENT_VALUE");
        
        IWETH(WETH).withdraw(record.amount);
        TransferHelper.safeTransferETH(msg.sender, record.amount);
        totalFee = totalFee.add(record.gasFee);
        
        emit Withdraw(msg.sender, WETH, record.amount);
        record.gasFee = 0;
        record.amount = 0;
    }
}