// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract BonusPoolEscrow{

    address private _nft;
    address private _executionContract;
    address private _usdc;
    address[] private _wallets;

    uint256 private _finalPaymentCounter;
    uint256 private _finalPaymentAmount;

    modifier onlyExecutionContract() {
        require(_executionContract == msg.sender, "caller is not execution contract");
        _;
    }
    
    constructor(address usdc, address nft, address[] memory wallets){
        _usdc = usdc;
        _nft = nft;
        _executionContract = msg.sender;
        require(wallets.length==2,"Invalid length for wallets");
        _wallets = wallets;
    }

    function numTOAs() public view returns (uint256){
        IERC721 nft = IERC721(_nft);
        return nft.balanceOf(address(this));
    }

    function poolBalance() public view returns (uint256){
        IERC20 usdc = IERC20(_usdc);
        return usdc.balanceOf(address(this));
    }

    function payRecipient(uint256 walletIdx, uint256 amount) public onlyExecutionContract {
        require(walletIdx<_wallets.length,"WalletIdx out of bounds");
        require(poolBalance()>=amount,"Amount cannot be larger than pool balance");
        IERC20 usdc = IERC20(_usdc);
        usdc.transfer(_wallets[walletIdx],amount);
    }

    function payFinal() public onlyExecutionContract{
        require(_finalPaymentCounter<_wallets.length,"Payment complete");
        require(poolBalance()>0,"Insufficient funds");
        if(_finalPaymentCounter==0){
            _finalPaymentAmount = poolBalance()/_wallets.length;
            require(_finalPaymentAmount>0,"Insufficient funds to share equally");
        }
        if(_finalPaymentCounter==_wallets.length-1){
            _finalPaymentAmount = poolBalance(); //empty out rounding errors
        }
        uint256 idx = _finalPaymentCounter;
        _finalPaymentCounter++;
        IERC20 usdc = IERC20(_usdc);
        usdc.transfer(_wallets[idx],_finalPaymentAmount);
    }

    function payFinalAll() public onlyExecutionContract{
        while(_finalPaymentCounter<_wallets.length){
            payFinal();
        }
    }

}
