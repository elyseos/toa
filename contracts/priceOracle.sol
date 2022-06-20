
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

interface IFactory{
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IPair{
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IToken{
    function decimals() external view returns (uint8);
}

contract Price is Ownable{
    address _factory = 0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3;
    address _elys = 0xd89cc0d2A28a769eADeF50fFf74EBC07405DB9Fc;
    address _usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address _wFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;

    constructor(){}

    function changeFactory(address newFactory) public onlyOwner {
        _factory = newFactory;
    }

    function getElysPriceInFTM() public view returns (uint256){
        IFactory factory = IFactory(_factory);
        address pairAddress = factory.getPair(_elys,_wFTM);
        IPair pair = IPair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        uint256 elys = (token0==_elys)?reserve0:reserve1;
        uint256 ftm = (token0==_elys)?reserve1:reserve0;
        uint256 price = ftm*(10**IToken(_elys).decimals())/elys;
        return price;
    }

    function getFTMPriceInUSDC() public view returns (uint256){
        (uint256 usdc,uint256 ftm) = _getFTMUSDCPair();
        uint256 price = usdc*(10**IToken(_wFTM).decimals())/ftm;
        return price;
    }

    function getELYSPriceInUSDC(uint256 amount) public view returns (uint256){
        uint256 ftm =  getElysPriceInFTM();
        uint256 usdc = getFTMPriceInUSDC();
        return ftm*usdc*amount/10**(IToken(_wFTM).decimals())/10**(IToken(_elys).decimals());
    }

    function getNumFTMForUSDC(uint256 amount) public view returns (uint256){
        (uint256 usdc,uint256 ftm) = _getFTMUSDCPair();
        uint256 price = ftm*(10**IToken(_usdc).decimals())/usdc;
        return amount*price/10**IToken(_usdc).decimals();
    }

    
    function getNumELYSForUSDC(uint256 amount) public view returns (uint256){
        uint256 numFtm = getNumFTMForUSDC(amount);
        uint256 elys = getElysPriceInFTM();
        return numFtm*(10**IToken(_elys).decimals())/elys;
    }
    

    function _getFTMUSDCPair() private view returns (uint256,uint256){
        IFactory factory = IFactory(_factory);
        address pairAddress = factory.getPair(_usdc,_wFTM);
        IPair pair = IPair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        uint256 usdc = (token0==_usdc)?reserve0:reserve1;
        uint256 ftm = (token0==_usdc)?reserve1:reserve0;
        return (usdc,ftm);
    }
}

//0x86815820A579cCAff14909525a7178F489893A2D
