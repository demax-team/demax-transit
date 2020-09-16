// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import './libraries/TransferHelper.sol';
import './BurgerERC20.sol';

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

contract BSCBurgerTransit {
    using SafeMath for uint;
    address public owner;
    address public handler;
    
    uint public totalFee;
    
    uint public developFee;
    
    struct Record {
        uint gasFee;
        uint amount;
    }
    mapping (address => mapping(address => Record)) public records;
    
    // key: bsc token, value: transit token
    mapping (address => address) public pairFor; 
    // key: transit token, value: bsc token
    mapping (address => address) public pairTo;
    
    event Payback(address indexed from, address indexed token, uint amount);
    event Withdraw(address indexed to, address indexed token, uint amount);
    event CollectFee(address indexed handler, uint amount);
    
    constructor() public {
        handler = msg.sender;
        owner = msg.sender;
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
    
    function addTransitRecord(address _transitToken, string memory _name, string memory _symbol, uint8 _decimals, address _to, uint _amount, uint _gasFee) public {
        require(msg.sender == handler, "ADD_RECORD_FORBIDDEN");
        
        if(pairTo[_transitToken] == address(0)) {
            _createToken(_transitToken, _name, _symbol, _decimals);
        }
        
        Record storage record = records[_to][pairTo[_transitToken]];
        record.amount = record.amount.add(_amount);
        record.gasFee = record.gasFee.add(_gasFee);
    }
    
    function paybackTransit(address _token, uint _amount) external {
        require(_amount > 0, "INVALID_AMOUNT");
        BurgerERC20(_token).burn(msg.sender, _amount);
        emit Payback(msg.sender, pairFor[_token], _amount);
    }
    
    function withdrawTransitToken(address _token) external payable {
        Record storage record = records[msg.sender][_token];
        require(record.amount > 0, "NOTHING_TO_WITHDRAW");
        require(msg.value == record.gasFee.add(developFee), "INSUFFICIENT_VALUE");
        
        BurgerERC20(_token).mint(msg.sender, record.amount);
        emit Withdraw(msg.sender, _token, record.amount);
        record.gasFee = 0;
        record.amount = 0;
    }
    
    function _createToken (address _transitToken, string memory _name, string memory _symbol, uint8 _decimals) internal returns(address bscBurgerToken){
        bytes memory bytecode = type(BurgerERC20).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_transitToken, _name, _symbol, _decimals));
            assembly {
                bscBurgerToken := create2(0, add(bytecode, 32), mload(bytecode), salt)
            }
        BurgerERC20(bscBurgerToken).initialize(_name, _symbol, _decimals);
        pairFor[bscBurgerToken] = _transitToken;
        pairTo[_transitToken] = bscBurgerToken;
    }
}