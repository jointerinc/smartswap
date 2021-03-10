pragma solidity ^0.7.0;

interface IPeerPair {
    
   
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReservesUsd() external view returns (uint256 _reserve0, uint256 _reserve1);
    function getTokenAmount(address fromtoken,uint amountIn) external view returns(uint256 toTokenAmount);
    
    function swap(address fromtoken,uint amountIn, address to) external  returns (uint256);
    function fund(address token,uint256 amountIn,address to) external returns(uint256);
    function liqudate(uint256 amountIn,address outToken,address to) external returns(uint256);
 }