// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uniswap interface and library imports
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/SafeERC20.sol";
import "hardhat/console.sol";

contract CrossExchangeArbitrage {
    // Factory and Routing addresses for PancakeSwap
    address private constant UNISWAP_FACTORY =
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant UNISWAP_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address private constant SUSHI_FACTORY =
        0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant SUSHI_ROUTER =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    // Token addresses
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    // Deadline
    uint private deadline = block.timestamp + 1 days;

    uint private constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function checkResult(
        uint _amountToRepay,
        uint _acquiredCoin
    ) private pure returns (bool) {
        return _acquiredCoin > _amountToRepay;
    }

    function getBalanceOfToken(address _token) private view returns (uint) {
        return IERC20(_token).balanceOf(address(this));
    }

    function placeTrade(
        address _fromToken,
        address _toToken,
        uint _amountIn,
        address _factory,
        address _router
    ) private returns (uint) {
        address pair = IUniswapV2Factory(_factory).getPair(
            _fromToken,
            _toToken
        );

        require(pair != address(0), "This pool does not exist");

        // Calculate amount out
        address[] memory path = new address[](2); // length 2 array
        path[0] = _fromToken;
        path[1] = _toToken;

        uint amountRequired = IUniswapV2Router01(_router).getAmountsOut(
            _amountIn,
            path
        )[1];

        uint amountReceived = IUniswapV2Router01(_router)
            .swapExactTokensForTokens(
                _amountIn,
                amountRequired,
                path,
                address(this),
                deadline
            )[1];

        require(amountReceived > 0, "Transaction Abort: Error swapping tokens");

        return amountReceived;
    }

    function initiateArbitrage(address _tokenBorrow, uint _amount) external {
        IERC20(WETH).safeApprove(address(UNISWAP_ROUTER), MAX_INT);
        IERC20(USDC).safeApprove(address(UNISWAP_ROUTER), MAX_INT);
        IERC20(LINK).safeApprove(address(UNISWAP_ROUTER), MAX_INT);

        IERC20(WETH).safeApprove(address(SUSHI_ROUTER), MAX_INT);
        IERC20(USDC).safeApprove(address(SUSHI_ROUTER), MAX_INT);
        IERC20(LINK).safeApprove(address(SUSHI_ROUTER), MAX_INT);

        // liquidity pool address of USDC and WETH
        address pair = IUniswapV2Factory(UNISWAP_FACTORY).getPair(
            _tokenBorrow,
            WETH
        );

        require(pair != address(0), "This pool does not exist");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        uint amount0Out = _tokenBorrow == token0 ? _amount : 0; // WETH
        uint amount1Out = _tokenBorrow == token1 ? _amount : 0; // BUSD

        bytes memory data = abi.encode(_tokenBorrow, _amount, msg.sender);

        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    function UniswapV2Call(
        address _sender,
        uint _amount0,
        uint _amount1,
        bytes calldata _data
    ) external {
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();

        address pair = IUniswapV2Factory(UNISWAP_FACTORY).getPair(
            token0,
            token1
        );

        require(msg.sender == pair, "Pair does not match");
        require(_sender == address(this), "Sender does not match");

        (address busdBorrow, uint amount, address myAddress) = abi.decode(
            _data,
            (address, uint, address)
        );

        // Calculate the amount to repay at the end
        uint fee = ((amount * 3) / 997) + 1;
        uint amountToRepay = amount + fee;

        // Assign loan amount
        uint loanAmount = _amount0 > 0 ? _amount0 : _amount1;

        // Place trades
        uint tradeCoin1 = placeTrade(
            USDC,
            LINK,
            loanAmount,
            UNISWAP_FACTORY,
            UNISWAP_ROUTER
        );
        uint tradeCoin2 = placeTrade(
            LINK,
            USDC,
            tradeCoin1,
            SUSHI_FACTORY,
            SUSHI_ROUTER
        );

        // Check if profit is made
        bool profit = checkResult(amountToRepay, tradeCoin2);

        require(profit, "Arbitrage not profitable");

        // Pay myself
        IERC20(USDC).transfer(myAddress, tradeCoin2 - amountToRepay);

        // Pay loan back
        IERC20(busdBorrow).transfer(pair, amountToRepay);
    }
}
