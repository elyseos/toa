// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./bonusPoolEscrow.sol";

contract BonusPoolExecution{
    BonusPoolEscrow private _escrow;
    address private _governanceContract;

     modifier onlyGovernanceContract() {
        require(_governanceContract == msg.sender, "caller is not governance contract");
        _;
    }

    constructor(address usdc, address nft, address governanceContract, address[] memory wallets){
        _governanceContract = governanceContract;
        _escrow = new BonusPoolEscrow(usdc,nft,wallets);
    }

    function numRecipients() public view returns (uint256){
        return _escrow.numRecipients();
    }

    function escrowAddress() public view returns (address){
        return address(_escrow);
    }

    function payRecipient(uint256 idx, uint256 amount) public onlyGovernanceContract{
        _escrow.payRecipient(idx,amount);
    }

    function payFinal() public onlyGovernanceContract{
        _escrow.payFinal();
    }

    function payFinalAll() public onlyGovernanceContract{
        _escrow.payFinalAll();
    }

    function poolBalance() public view returns (uint256){
        return _escrow.poolBalance();
    }

}
