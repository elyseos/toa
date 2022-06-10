// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

interface INFT {
    function mint(address to) external;
    function owner() external view returns (address);
}

interface IToken {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from,address to,uint256 amount) external returns (bool);
}


contract Crowdsale is Ownable{
    address private _token;
    address private _NFT; 
    uint256 private _successThreshold;
    uint256 private _successWindow;
    uint256 private _priceTOA;
    uint256[] private _allocationTOA;
    uint256[] private _fundAllocation;
    uint256 private _duration;

    uint256 private _startTime;

    mapping (uint256 => address) private _beneficiary;
    uint256 private _numBeneficiaries;
    mapping (address => uint256) private _unmintedTOAs;

    uint256 private _fundsRaised;

    /**
    * [0] - guardian
    * [1] - rainmaker
    * [2] - bonus pool
    * [3] - concierge
    * [4] - wisdom holders
    **/
    address[] private _assignmentAddresses;
    mapping (address => uint256) private _assignmentIdx;
    //Keeps track of fund allocation withdrawals
    mapping (address => uint256) private _allocationWithdrawn;
    mapping (address => uint256) private _allocationTOAAssigned;

    uint256 private remainderTOAsToBonusPool;

    /**
    * token - address of token used for funds raised (USDC)
    * NFT - address of TOA NFT contract
    * successThreshold - min amount of funds to be raised withn successWindow
    * successWindow - time period in which successThreshold needs to be reached in terms of funds raised
    * priceTOA - price of a TOA
    * allocationTOA - number of TOAs made available:
    *       [0] - beneficiaries
    *       [1] - guardian
    *       [2] - rainmaker
    *       [3] - bonus pool
    *       [4] - concierge
    *       [5] - wisdom holders
    * fundAllocation - allocation percentage of funds raised
    *       [0] - producer
    *       [1] - platform commission
    *       [2] - reserve fund
    *       [3] - auditor
    *  duration - contract duration
    **/
    constructor(address token, address NFT, uint256 successThreshold, uint256 successWindow, uint256 priceTOA, uint256[] memory allocationTOA, uint256[] memory fundAllocation, uint256 duration){
        require(successThreshold/priceTOA<=allocationTOA[0],"Invalid allocation of TOAs or successThreshold");
        require(fundAllocation.length==4,"Invalid fundAllocation length");
        require(allocationTOA.length==6,"Invalid allocationTOA length");
        _token = token;
        _NFT = NFT;
        _successThreshold = successThreshold;
        _successWindow = successWindow;
        _priceTOA = priceTOA;
        _allocationTOA = allocationTOA;
        _fundAllocation = fundAllocation;
        _duration = duration;
        _assignmentAddresses = new address[](9);
    }

    /**
    * [0] - producer
    * [1] - platform commission
    * [2] - reserve fund
    * [3] - auditor
    * [4] - guardian
    * [5] - rainmaker
    * [6] - bonus pool
    * [7] - concierge
    * [8] - wisdom holders
    **/
    function setAllocationAddress(uint256 allocation, address recipient) public {
        require(allocation<_assignmentAddresses.length,"allocation out of bounds");
        require(_assignmentAddresses[allocation]==address(0) || _allocationWithdrawn[_assignmentAddresses[allocation]]==0,"Funds have already been allocated");
        require(msg.sender==owner() || msg.sender==_assignmentAddresses[allocation],"setting allocation not allowed from this sender");
        _assignmentAddresses[allocation] = recipient;
        _assignmentIdx[recipient] = allocation;
    }

    function start() public onlyOwner{
        require(_startTime==0,"Crowdsale already started");
        INFT nft = INFT(_NFT);
        require(nft.owner()==address(this),"Cannot start without ownership of TOA contract");
        _startTime = block.timestamp;
    }

    function timeUntilEnd() public view returns (uint256){
        require(_startTime>0,"Crowdsale has not started");
        uint256 timePassed = block.timestamp-_startTime;
        if(_duration<=timePassed) return 0;
        return _duration-timePassed;
    }

    function fundsRaised() public view returns (uint256){
        return _fundsRaised;
    }

    function isOpen() public view returns (bool){
        if(timeUntilEnd()>0) return false;
        if(block.timestamp-_startTime>_successWindow){
            return (fundsRaised()>=_successThreshold);
        }
        return true;
    }

    function isSuccess() public view returns (bool){
        require(block.timestamp-_startTime>_successWindow,"Not yet passed success window");
        return (fundsRaised()>=_successThreshold);
    }

    function numPurchased() public view returns (uint256){
        return _numBeneficiaries;
    }

    function available() public view returns (uint256){
        return _allocationTOA[0] - _numBeneficiaries;
    }

    function buy(uint256 numTOAs) public {
        require(numTOAs>0,"numTOAs cannot be zero");
        //check crowdsale still running
        require(isOpen(),"Crowdsale has ended");
        //check thath there are TOAs left to purchase
        require(available()>=numTOAs,"numTOAs exceeds number available");
        //check that buyers has allowance and balance
        uint256 paymentRequired = numTOAs*_priceTOA;
        IToken token = IToken(_token);
        require(token.balanceOf(msg.sender)>=paymentRequired,"Insufficient balance");
        require(token.allowance(msg.sender,address(this))>=paymentRequired,"Insufficient allowance");

        //transfer funds
        token.transferFrom(msg.sender,address(this),paymentRequired);
        for(uint256 i=0; i<numTOAs; i++){
            _beneficiary[_numBeneficiaries] = msg.sender;
            _numBeneficiaries++;
        }
        _unmintedTOAs[msg.sender] += numTOAs;
        _fundsRaised += paymentRequired;
    }

    function returnFunds(address to) public {
        require(!isSuccess(),"Crowdsale was succesful. No funds to be returned");
        require(_unmintedTOAs[msg.sender]>0,"Benificary has no funds to withdraw");
        uint256 bal = _unmintedTOAs[msg.sender];
        _unmintedTOAs[msg.sender] = 0;
        uint256 fundsToReturn = bal * _priceTOA;
        IToken token = IToken(_token);
        token.transfer(to,fundsToReturn);
    }

    function balanceOf(address account) public view returns (uint256){
        if(!isSuccess()){
            return _unmintedTOAs[account] * _priceTOA;
        }
        if(_assignmentAddresses[_assignmentIdx[msg.sender]]!=account) return 0;
        if(_assignmentIdx[account]<4) return 0;
        if(_allocationWithdrawn[account]!=0) return 0;
        return _fundAllocation[_assignmentIdx[account]]*_fundsRaised/100;
    }
    
    function withdrawFunds(address to) public {
        require(_assignmentAddresses[_assignmentIdx[msg.sender]]==msg.sender,"not authorised to withdraw funds");
        require(_assignmentIdx[msg.sender]<4,"not authorised to withdraw funds");
        //work out allocation
        uint256 allocation = _fundAllocation[_assignmentIdx[msg.sender]]*_fundsRaised/100;
        //_allocationWithdrawn
        require(_allocationWithdrawn[msg.sender]==0,"funds already withdrawn");
        _allocationWithdrawn[msg.sender] = allocation;
        IToken token = IToken(_token);
        token.transfer(to,allocation);
    } 

    function TOABalance(address account) public view returns (uint256){
        if(_assignmentAddresses[_assignmentIdx[account]]==account){
            uint256 idx = _assignmentIdx[msg.sender];
            if(idx>3) return 0;
            idx-=3;
            uint256 bal = _allocationTOA[idx];
            if(idx==3){
                if(remainderTOAsToBonusPool!=0) return 0;
                bal += _allocationTOA[0]-_numBeneficiaries;
            }
            return bal;
        }
        return _unmintedTOAs[msg.sender];
    }

    function assignTOAs(address to) public {
        uint256 bal;
        if(_assignmentAddresses[_assignmentIdx[msg.sender]]==msg.sender){
            uint256 idx = _assignmentIdx[msg.sender];
            require(idx>3,"Not authorised to assign TOAs");
            require(_allocationTOA[idx+1]>0,"No TOAs to assign");
            //scary bit here...
            idx -= 3;
            bal = _allocationTOA[idx];
            if(idx==3){
                uint256 remainderTOAs = _allocationTOA[0]-_numBeneficiaries;
                require(remainderTOAs==0 || remainderTOAsToBonusPool==0,"No TOAs to assign");
                bal += remainderTOAs;
                remainderTOAsToBonusPool = remainderTOAs;
            }
            _allocationTOA[idx+1] = 0;
        } else {
            require(_unmintedTOAs[msg.sender]>0,"No TOAs to assign");
            bal = _unmintedTOAs[msg.sender];
            _unmintedTOAs[msg.sender]=0;
        }
        INFT nft = INFT(_NFT);
        for(uint256 i=0;i<bal;i++){
            nft.mint(to);
        }
    }

}
