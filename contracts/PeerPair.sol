pragma solidity ^0.7.0;

import './interfaces/IPeerPair.sol';
import './PeerERC20.sol';
import './interfaces/IERC20.sol';



interface IPrice {
    function getCurrencyPrice(address _which) external view returns (uint256); // 1 - BNB, 2 - ETH, 3 - BTC
}

contract PeerPair is  PeerERC20,IPeerPair {
    using SafeMath  for uint;
    IPrice internal priceFeed;
    
    address public override token0;
    address public override token1;
    
    mapping(address => address) pairMapping;
    mapping(address => uint256) tokenDecimals;
    
    constructor(address _token0,address _token1,address _price) {
        token0 = _token0;
        token1 = _token1;
        pairMapping[token1] = token0;
        pairMapping[token0] = token1;
        tokenDecimals[token0] = IERC20(token0).decimals();
        tokenDecimals[token1] = IERC20(token1).decimals();
        priceFeed = IPrice(_price);
    }
    
    
    function _getReservesUsd() public view returns (uint256 _reserve0, uint256 _reserve1) {
        _reserve0 = IERC20(token0).balanceOf(address(this))*priceFeed.getCurrencyPrice(token0)/10**tokenDecimals[token0];
        _reserve1 = IERC20(token1).balanceOf(address(this))*priceFeed.getCurrencyPrice(token1)/10**tokenDecimals[token1];
    }
    
    function getReservesUsd() external override view returns (uint256 _reserve0, uint256 _reserve1) {
        return _getReservesUsd();
    }
    
    function _getTokenAmount(address fromtoken,uint amountIn) internal view returns(uint256 toTokenAmount) {
        uint256 fromTokenPrice = priceFeed.getCurrencyPrice(fromtoken);
        address toToken = pairMapping[fromtoken];
        uint256 toTokenPrice = priceFeed.getCurrencyPrice(toToken);
        uint256 fromTokenUsd  = amountIn.mul(fromTokenPrice).div(10**tokenDecimals[fromtoken]);
        toTokenAmount = fromTokenUsd.mul(10**tokenDecimals[fromtoken]).div(toTokenPrice);
    }
    
    function getTokenAmount(address fromtoken,uint amountIn) external override view returns(uint256 toTokenAmount) {
        return _getTokenAmount(fromtoken,amountIn);
    }
    
    function swap(address fromtoken,uint amountIn, address to) external override  returns (uint256){
        address toToken = pairMapping[fromtoken];
        require(toToken != address(0),"err token pair not found");
        safeTransferFrom(fromtoken,msg.sender,address(this),amountIn);
        uint256 tokenAmount =  _getTokenAmount(fromtoken,amountIn);
        IERC20(toToken).transfer(to,tokenAmount);
        return tokenAmount;
    }
    

    function fund(address token,uint256 amountIn,address to) external override returns(uint256){
        address toToken = pairMapping[token];
        require(toToken != address(0),"err token pair not found");
        safeTransferFrom(token,msg.sender,address(this),amountIn);
        uint256 tokenPrice = priceFeed.getCurrencyPrice(token);
        uint256 tokenPriceUsd  = amountIn.mul(tokenPrice).div(10**tokenDecimals[token]);
        (uint256 _reserve0, uint256 _reserve1) = _getReservesUsd();
        uint256 totalReserve = _reserve1.add(_reserve0);

        if(totalReserve == 0){
            _mint(to,tokenPriceUsd*10**9);
            return tokenPriceUsd*10**9; 
        }else{
            uint256 ratio = totalReserve.mul(tokenPrice).mul(10**18).div(totalSupply);
            _mint(to,ratio);
            return ratio;
        }
    } 
    
    function liqudate(uint256 amountIn,address outToken,address to) external override returns(uint256){
        address toToken = pairMapping[outToken];
        require(toToken != address(0),"err token pair not found");
        uint256 tokenPrice = priceFeed.getCurrencyPrice(outToken);
        (uint256 _reserve0, uint256 _reserve1) = _getReservesUsd();
        uint256 totalReserve = _reserve1.add(_reserve0);
        uint256 outUsdAmount = totalReserve.mul(amountIn).div(totalSupply);
        _burn(msg.sender,amountIn);
        uint256 tokenAmount = outUsdAmount.mul(10**tokenDecimals[outToken]).div(tokenPrice);
        safeTransfer(outToken,to,tokenAmount);
        return tokenAmount;
    } 
    
    
    function safeTransfer(address token,address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }
  
    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }
    
    
    
    
}