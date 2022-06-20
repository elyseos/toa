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

    mapping(address => uint256) private _remedies;
    mapping (uint256 => uint256[2]) private _remediesClaimed; //maps year number to amount claimed

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

    function executeRemedy(uint256 amount) public {
        require(msg.sender==_remedyContract,"Not authorised to execute remedy");
        //loop through toas
    }

    function availableStakeToWithdraw() public view returns (uint256, uint256){
        uint256 yr = _getYear();
        if(yr<3) return (0,0);
        uint256 usdc = _stakedUSDC/10;
        uint256 elys = _stakedELYS/10;
        if(yr<10){
            usdc -= _remediesClaimed[yr][0];
            elys -= _remediesClaimed[yr][1];
            return (usdc,elys);
        }
        usdc *=3;
        elys *=3;
        for(uint256 i=8;i<=10;i++){
            usdc -= _remediesClaimed[i][0];
            elys -= _remediesClaimed[i][1];
        }
        return (usdc,elys);
    }

    function withdrawStake(address to) public {
        require(msg.sender==_guardian,"Not authorised to withdraw");
        (uint256 usdcAmount, uint256 elysAmount) = availableStakeToWithdraw();
        require(usdcAmount>0 || elysAmount>0,"No funds to withdraw");
        IToken(_usdc).transfer(to,usdcAmount);
        IToken(_elys).transfer(to,elysAmount); 
    }

    function withdrawRemedy(address to) public {

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


/*
test addresses:
    price oracle: 0x7d075DaF902E11824ec7A2f2Aa09C6a0d61eF15A
    address usdc: 0x9b76deD4C2386E214dB5B6B70Dd26c37abf39E13
    address elys: 0x52f1f3d2f38bdbe2377cda0b0dbeb993dc242b98

mainnet addresses: 
    price oracle: 0x86815820A579cCAff14909525a7178F489893A2D
    address elys: 0xd89cc0d2A28a769eADeF50fFf74EBC07405DB9Fc;
    address usdc: 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
*/
