// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Price{
    function getELYSPriceInUSDC(uint256 amount) public pure returns (uint256){
        uint256 n = 27816245676398;
        return amount * n/10**15;
    }

    function getNumELYSForUSDC(uint256 amount) public pure returns (uint256){
        uint256 n = 366396866761293142;
        return amount * n/10**16;
    }
}
