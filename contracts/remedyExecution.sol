// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGuardianEscrow{
    function executeRemedy(uint256 usdcAmount, uint256 elysAmount) external;
}

contract RemedyExecution{
    IGuardianEscrow private _escrow;

    address private _governanceContract;

    modifier onlyGovernanceContract() {
        require(_governanceContract == msg.sender, "caller is not governance contract");
        _;
    }

    constructor(address governanceContract, address guardianEscrow){
        _governanceContract = governanceContract;
        _escrow = IGuardianEscrow(guardianEscrow);
    }

    function execute(uint256 usdcAmount, uint256 elysAmount) public onlyGovernanceContract {
        _escrow.executeRemedy(usdcAmount,elysAmount);
    }

}
