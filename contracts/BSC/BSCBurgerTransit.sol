// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

import './libraries/TransferHelper.sol';
import './libraries/SignatureUtils.sol';
import './BurgerERC20.sol';

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

contract BSCBurgerTransit {
    using SafeMath for uint;
    address public owner;
    address public signWallet;
    address public developWallet;
    
    uint public totalFee;
    
    uint public developFee;
    
    // key: bsc token, value: transit token
    mapping (address => address) public pairFor; 
    // key: transit token, value: bsc token
    mapping (address => address) public pairTo;
    
    // key: transit_id
    mapping (bytes32 => bool) public executedMap;
    
    event Payback(address indexed from, address indexed token, uint amount);
    event Withdraw(bytes32 transitId, address indexed to, address indexed token, uint amount);
    event CollectFee(address indexed handler, uint amount);
    
    constructor(address _signer, address _developer) public {
        signWallet = _signer;
        developWallet = _developer;
        owner = msg.sender;
    }
    
    function changeSigner(address _wallet) external {
        require(msg.sender == owner, "CHANGE_SIGNER_FORBIDDEN");
        signWallet = _wallet;
    }
    
    function changeDevelopWallet(address _wallet) external {
        require(msg.sender == owner, "CHANGE_DEVELOP_WALLET_FORBIDDEN");
        developWallet = _wallet;
    } 
    
    function changeDevelopFee(uint _amount) external {
        require(msg.sender == owner, "CHANGE_DEVELOP_FEE_FORBIDDEN");
        developFee = _amount;
    }
    
    function collectFee() external {
        require(msg.sender == owner, "FORBIDDEN");
        require(developWallet != address(0), "SETUP_DEVELOP_WALLET");
        require(totalFee > 0, "NO_FEE");
        TransferHelper.safeTransferETH(developWallet, totalFee);
        totalFee = 0;
    }
    
    function paybackTransit(address _token, uint _amount) external {
        require(pairFor[_token] != address(0), "UNSUPPORT_TOKEN");
        require(_amount > 0 && BurgerERC20(_token).balanceOf(msg.sender) >= _amount, "INVALID_AMOUNT");
        BurgerERC20(_token).burn(msg.sender, _amount);
        emit Payback(msg.sender, pairFor[_token], _amount);
    }
    
    function withdrawTransitToken(
    bytes calldata _signature,
    bytes32 _transitId,
    address _to,
    uint _amount,
    address _token,
    string calldata _name,
    string calldata _symbol,
    uint8 _decimals
    ) external payable {
        require(_to == msg.sender, "FORBIDDEN");
        require(executedMap[_transitId] == false, "ALREADY_EXECUTED");
        bytes32 message = keccak256(abi.encodePacked(_transitId, _to, _amount, _token, _name, _symbol, _decimals));
        require(_verify(message, _signature), "INVALID_SIGNATURE");

        require(_amount > 0, "NOTHING_TO_WITHDRAW");
        require(msg.value == developFee, "INSUFFICIENT_VALUE");
        
        if(pairTo[_token] == address(0)) {
            _createToken(_token, _name, _symbol, _decimals);
        }
        
        BurgerERC20(pairTo[_token]).mint(msg.sender, _amount);
        totalFee = totalFee.add(developFee);
        executedMap[_transitId] = true;
        
        emit Withdraw(_transitId, msg.sender, _token, _amount);
    }
    
    function _verify(bytes32 _message, bytes memory _signature) internal view returns (bool) {
        bytes32 hash = SignatureUtils.toEthBytes32SignedMessageHash(_message);
        address[] memory signList = SignatureUtils.recoverAddresses(hash, _signature);
        return signList[0] == signWallet;
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