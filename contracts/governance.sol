// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

interface IBonusPoolExecution{
    function poolBalance() external view returns (uint256);
    function payRecipient(uint256 idx, uint256 amount) external;
    function numRecipients() external view returns (uint256);
}

interface IRemedyExecution{
    function totalRemedies() external view returns (uint256, uint256);
    function execute(uint256 usdcAmount, uint256 elysAmount) external;
}

contract Governance{
    address private _toa;
    address private _bonusPool;
    IBonusPoolExecution private _bonusPoolExecution;
    IRemedyExecution private _remedyExecution;
    uint256 private _quorumPerc;

    uint8 public constant bonusAllocation = 0;
    uint8 public constant remedy = 1;
    uint8 public constant other = 2;

    struct Referendum{
        string CID;
        uint8 voteType;
        uint256[] allocation;
        uint256[] recipients;
        uint256 startTime;
        uint256 duration;
        uint256 numVotes; 
        bool actioned;
    }

    mapping(uint256 => Referendum) private _referendums;
    uint256 private _numReferendums;
    uint256 private _pendingBonusPoolAmount;
    uint256[2] private _pendingRemedyAmount;
    mapping(uint256 => mapping(uint256 => bool)) private _voted;
    mapping(uint256 => mapping(uint256 => uint256)) private _vote;

    uint256 private _blocktime;  //for testing

    constructor(address TOA, address bonusPool, address bonusPoolExecution, address remedyExecution, uint256 quorumPerc){
        _toa = TOA;
        _bonusPool = bonusPool;
        _bonusPoolExecution = IBonusPoolExecution(bonusPoolExecution);
        _remedyExecution = IRemedyExecution(remedyExecution);
        _quorumPerc = quorumPerc;
    }

    function isTOAHolder() public view returns (bool){
        return (_TOA().balanceOf(msg.sender)>0);
    }

    function _TOA() private view returns (IERC721Enumerable){
        IERC721Enumerable toa = IERC721Enumerable(_toa);
        return toa;
    }

    function createReferrendum(uint8 voteType, string calldata CID, uint256[] calldata allocation, uint256[] calldata recipients, uint256 duration) public {
        require(isTOAHolder(),"Not authorized to create Referendum");
        if(voteType==bonusAllocation){
            //check with bonus execution => bonus escrow if allocation is feasable 
            require(_bonusPoolExecution.numRecipients()>=recipients.length,"Invalid number of recipients");
            require(allocation.length==1,"Invalid allocation length");
            require(allocation[0]*recipients.length+_pendingBonusPoolAmount<=_bonusPoolExecution.poolBalance(),"Insufficient pool balance for allocation");
            _pendingBonusPoolAmount += allocation[0]*recipients.length;
        } else if (voteType==remedy){
            //check with remedy execution contract if allocation is feasable
            (uint256 usdcAmount, uint256 elysAmount) = _remedyExecution.totalRemedies();
            require(allocation.length==2,"Invalid allocation length");
            require(usdcAmount>=allocation[0]+_pendingRemedyAmount[0] && elysAmount>=allocation[1]+_pendingRemedyAmount[1],"Invalid allocation amounts");
            _pendingRemedyAmount[0] += _pendingRemedyAmount[0];
            _pendingRemedyAmount[1] += _pendingRemedyAmount[1];
        }
        _referendums[_numReferendums] = Referendum({
            CID: CID,
            voteType: voteType,
            allocation: allocation,
            recipients: recipients,
            startTime: _blockTime(),
            duration: duration,
            numVotes: 0,
            actioned: false
        });
        _numReferendums++;
        
    }

    function numReferendums() public view returns(uint256){
        return _numReferendums;
    }

    function referendum(uint256 idx) public view returns(Referendum memory){
        require(idx<_numReferendums,"idx out of bounds");
        return _referendums[idx];
    }

    function isComplete(uint256 idx) public view returns (bool){
        require(idx<_numReferendums,"idx out of bounds");
        return (_referendums[idx].startTime + _referendums[idx].duration < _blockTime());
    }

    
    function canVote(uint256 idx) public view returns(bool,uint256){
        IERC721Enumerable toa = _TOA();
        uint256 numTOAs = toa.balanceOf(msg.sender);
        bool _canVote;
        uint256 tokenID;
        for(uint256 i=0; i<numTOAs; i++){
            tokenID = toa.tokenOfOwnerByIndex(msg.sender,i);
            if(!_voted[idx][tokenID]){
                _canVote = true;
                break;
            }
        }
        return (_canVote, tokenID);
    }
    
    function vote(uint256 idx, uint256 selection) public {
        require(idx<_numReferendums,"idx out of bounds");
        require(!isComplete(idx),"Voting is closed for this referendum");
        require(msg.sender!=_bonusPool,"Bonus pool not allowed to vote");
        require(_TOA().balanceOf(msg.sender)>0,"Need TOA to be allowed to vote");
        (bool _canVote, uint256 tokenID) = canVote(idx);
        require(_canVote,"Already voted");
        _vote[idx][selection]++;
        _voted[idx][tokenID] = true;
        _referendums[idx].numVotes ++;
        //TODO: event
    }

    function votes(uint256 idx, uint256 selection) public view returns (uint256){
        require(idx<_numReferendums,"idx out of bounds");
        return _vote[idx][selection];
    }

    function quorumReached(uint256 idx) public view returns (bool){
        require(idx<_numReferendums,"idx out of bounds");
        IERC721Enumerable toa = _TOA();
        uint256 total = toa.totalSupply() - toa.balanceOf(_bonusPool);
        return (_referendums[idx].numVotes*100/total>_quorumPerc);
    }

    function actionReferendum(uint256 idx) public {
        require(!_referendums[idx].actioned,"Referendum already actioned");
        require(quorumReached(idx),"Quorum not reached");
        require(isComplete(idx),"Referendum still ongoing");
        _referendums[idx].actioned = true;
        if(_referendums[idx].voteType==bonusAllocation){
            for(uint256 i=0;i<_referendums[idx].recipients.length;i++){
                _bonusPoolExecution.payRecipient(_referendums[idx].recipients[i], _referendums[idx].allocation[0]);
                _pendingBonusPoolAmount -= _referendums[idx].allocation[0];
            }
        } else if (_referendums[idx].voteType==remedy){
            _remedyExecution.execute(_referendums[idx].allocation[0],_referendums[idx].allocation[1]);
            _pendingRemedyAmount[0]-=_referendums[idx].allocation[0];
            _pendingRemedyAmount[1]-=_referendums[idx].allocation[1];
        }
    }

    function _blockTime() private view returns (uint256){
        return _blocktime; //for testing only
        //return block.timestamp;
    }

    function test_increaseTime(uint256 days_) public {
        _blocktime += days_ * (1 days);
    }

}
