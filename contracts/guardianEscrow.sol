// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./toa.sol";

interface IPrice{
    function getELYSPriceInUSDC(uint256 amount) external view returns (uint256);
    function getNumELYSForUSDC(uint256 amount) external view returns (uint256);
}

interface IToken is IERC20{
    function decimals() external view returns (uint8);
}

contract GuardianEscrow is Ownable{
    address private _elys;
    address private _usdc;
    uint256 private _percElys;
    address private _priceOracle;
    address private _toa;
    address private _remedyContract;
    address private _guardian;
    uint256 private _start;
    uint256 private _stakeWithdrawn;

    uint256 private _stakedUSDC;
    uint256 private _stakedELYS;

    struct Pair{
        uint128 USDC;
        uint128 ELYS;
    }

    Pair private _remedies;
    mapping(uint256 => Pair) private _remedyWithdrawn;
    mapping(uint256 => Pair) private _stakeWithdrawal;

    uint256 private _blocktime; //for testing

    event Staked(uint256 USDCAmount, uint256 ELYsAmount, uint256 ts);

    constructor(address elys, address usdc, uint256 percElys, address priceOracle, address toa, address remedyContract){
        _elys = elys;
        _usdc = usdc;
        _percElys = percElys;
        _priceOracle = priceOracle;
        _toa = toa;
        _remedyContract = remedyContract;
    }

    function start() public onlyOwner {
        _start = _blockTime();
    }

    function stakeAmountsForUSDC(uint256 amount) public view returns (uint256,uint256){ //USDC, ELYS
        uint256 usdc = (100-_percElys)*amount/100;
        uint256 elys = IPrice(_priceOracle).getNumELYSForUSDC(_percElys*amount/100);
        return (usdc,elys);
    }

    function stake(uint256 amount) public {
        //split amounts
        (uint256 usdcAmount, uint256 elysAmount) = stakeAmountsForUSDC(amount);
        _guardian = msg.sender;
        //transfer amounts
        IToken(_usdc).transferFrom(_guardian,address(this),usdcAmount);
        IToken(_elys).transferFrom(_guardian,address(this),elysAmount);
        emit Staked(usdcAmount, elysAmount, _blockTime());
    }

    function executeRemedy(uint256 usdcAmount, uint256 elysAmount) public {
        require(msg.sender==_remedyContract,"Not authorised to execute remedy");
        (uint256 availableUSDC, uint256 availableELYS) = amountStaked();
        require(usdcAmount<=availableUSDC && elysAmount<=availableELYS,"Insufficient staked funds for amounts");
        _remedies.USDC += uint128(usdcAmount);
        _remedies.ELYS += uint128(elysAmount);
    }

    function amountStaked() public view returns (uint256, uint256){
        return (_stakedUSDC-_remedies.USDC,_stakedELYS-_remedies.ELYS);
    }

    function availableStakeToWithdraw() public view returns (uint256, uint256){
        uint256 yr = _getYear();
        if(yr<3) return (0,0);
        (uint256 usdc,uint256 elys) = amountStaked();
        usdc/=10;
        elys/=10;
        if(yr<10){
            return (usdc - _stakeWithdrawal[yr].USDC,elys - _stakeWithdrawal[yr].ELYS);
        }
        return (usdc*3 - _stakeWithdrawal[yr].USDC,elys*3- _stakeWithdrawal[yr].ELYS);
    }

    function withdrawStake(address to) public {
        require(msg.sender==_guardian,"Not authorised to withdraw");
        (uint256 usdcAmount, uint256 elysAmount) = availableStakeToWithdraw();
        require(usdcAmount>0 || elysAmount>0,"No funds to withdraw");
        uint256 yr = _getYear();
        _stakeWithdrawal[yr].USDC += uint128(usdcAmount);
        _stakeWithdrawal[yr].ELYS += uint128(elysAmount);
        IToken(_usdc).transfer(to,usdcAmount);
        IToken(_elys).transfer(to,elysAmount); 
    }

    function totalRemedies() public view returns (uint256, uint256){
        return (uint256(_remedies.USDC),uint256(_remedies.ELYS));
    }

    function remediesAvailable(uint256 tokenID) public view returns (uint256, uint256){
        TOA toas = TOA(_toa);
        uint256 total = toas.totalSupply();
        (uint256 usdc, uint256 elys) = totalRemedies();
        usdc/=total;
        elys/=total;
        usdc -= _remedyWithdrawn[tokenID].USDC;
        elys -= _remedyWithdrawn[tokenID].ELYS;
        return (usdc,elys);
    }


    function withdrawRemedy(uint256 tokenID, address to) public {
        TOA toas = TOA(_toa);
        require(toas.ownerOf(tokenID)==msg.sender,"Unauthorized to withdraw");
        (uint256 usdcAmount, uint256 elysAmount) = remediesAvailable(tokenID);
        require(usdcAmount>0||elysAmount>0,"Nothing to withdraw");
        _remedyWithdrawn[tokenID].USDC += uint128(usdcAmount);
        _remedyWithdrawn[tokenID].ELYS += uint128(elysAmount);
        IToken(_usdc).transfer(to,usdcAmount);
        IToken(_elys).transfer(to,elysAmount); 
    }
    

    function _getYear() private view returns (uint256){
        return (_blockTime()-_start)/(365 days);
    }

    function _blockTime() private view returns (uint256){
        return _blocktime;
        //return block.timestamp;
    }

    function test_increaseTime(uint256 days_) public {
        _blocktime += days_ * (1 days);
    }
}
