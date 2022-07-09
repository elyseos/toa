// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract Governance{
    address private _toa;
    address private _bonusPool;
    address private _bonusPoolExecution;
    address private _remedyExecution;
    uint256 private _quorumPerc;

    uint8 public constant bonusAllocation = 0;
    uint8 public constant remedy = 1;
    uint8 public constant other = 2;

    struct Referendum{
        string CID;
        uint8 voteType;
        uint256 allocation;
        uint256 startTime;
        uint256 duration;
        uint256 numVotes; 
    }

    mapping(uint256 => Referendum) private _referendums;
    uint256 private _numReferendums;
    mapping(uint256 => mapping(uint256 => bool)) private _voted;
    mapping(uint256 => mapping(uint256 => uint256)) private _vote;

    uint256 private _blocktime;  //for testing

    constructor(address TOA, address bonusPool, address bonusPoolExecution, address remedyExecution, uint256 quorumPerc){
        _toa = TOA;
        _bonusPool = bonusPool;
        _bonusPoolExecution = bonusPoolExecution;
        _remedyExecution = remedyExecution;
        _quorumPerc = quorumPerc;
    }

    function isTOAHolder() public view returns (bool){
        return (_TOA().balanceOf(msg.sender)>0);
    }

    function _TOA() private view returns (IERC721Enumerable){
        IERC721Enumerable toa = IERC721Enumerable(_toa);
        return toa;
    }

    function createReferrendum(uint8 voteType, string calldata CID, uint256 allocation, uint256 duration) public {
        require(isTOAHolder(),"Not authorized to create Referendum");
        if(voteType==bonusAllocation){
            //check with bonus execution => bonus escrow if allocation is feasable 
        } else if (voteType==remedy){
            //check with remedy execution contract if allocation is feasable
        }
        _referendums[_numReferendums] = Referendum({
            CID: CID,
            voteType: voteType,
            allocation: allocation,
            startTime: _blockTime(),
            duration: duration,
            numVotes: 0
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
        require(quorumReached(idx),"Quorum not reached");
        if(_referendums[idx].voteType==bonusAllocation){

        } else if (_referendums[idx].voteType==remedy){

        }
        else {

        }
    }

    function _blockTime() private view returns (uint256){
        return _blocktime;
        //return block.timestamp;
    }

    function test_increaseTime(uint256 days_) public {
        _blocktime += days_ * (1 days);
    }

}
