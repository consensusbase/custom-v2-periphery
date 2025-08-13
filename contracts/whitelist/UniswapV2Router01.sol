pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Router01.sol';
import '../libraries/UniswapV2Library.sol';
import '../libraries/SafeMath.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IWETH.sol';
import './interfaces/IWhiteListAuth.sol';

/**
 * The source code and license details for this contract can be found at the URL
 * specified in the sourceUrl variable. Please check the current value of sourceUrl
 * to access the complete source code and license information.
 */

contract UniswapV2Router01 is IUniswapV2Router01 {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WETH;
    address public routerOwner;
    address public authContract;
    bool public isActive;
    string public sourceUrl;

    event RouterStatusChanged(bool isActive);

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == routerOwner, 'UniswapV2Router: FORBIDDEN');
        _;
    }

    modifier onlyActive() {
        require(isActive, 'UniswapV2Router: ROUTER_INACTIVE');
        _;
    }

    constructor(address _factory, address _WETH, address _authContract) public {
        factory = _factory;
        WETH = _WETH;
        routerOwner = msg.sender;
        isActive = true;
        authContract = _authContract;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function isFactoryKycVerified(address tokenAddress) private view returns (bool) {
        if (authContract == address(0)) return false;

        IWhiteListAuth auth = IWhiteListAuth(authContract);
        IWhiteListAuth.KYCAttribute[] memory attributes = auth.getKYCAttributes(address(this));

        IWhiteListAuth.erc20Attribute memory tokenInfo = auth.getERC20Info(tokenAddress);
        uint8 tokenType = tokenInfo.tokenType;

        if (attributes.length == 0) return false;
        bool res = false;
        for (uint i = 0; i < attributes.length; i++) {
            if (!auth.getSupplierStatus(attributes[i].supplier)) continue;
            if (attributes[i].verifyType != tokenType) continue;
            if (attributes[i].deadlock) continue;
            if (!attributes[i].activity) continue;
            if (!attributes[i].isVerifiedToken && attributes[i].expireTime < block.timestamp) continue;
            res = true;
            break;
        }
        return res;
    }

    function isErc20TokenValid(address tokenAddress) private view returns (bool) {
        if (authContract == address(0)) return false;
        IWhiteListAuth auth = IWhiteListAuth(authContract);

        IWhiteListAuth.erc20Attribute memory tokenInfo = auth.getERC20Info(tokenAddress);
        bool activity = tokenInfo.activity;
        address minter = tokenInfo.minter;
        if (!activity) return false;
        if (!auth.getCTIStatus(minter)) return false;
        return true;
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        //ペアアドレス
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) onlyActive returns (uint amountA, uint amountB, uint liquidity) {
        require(isFactoryKycVerified(tokenA), 'UniswapV2: TOKEN_A_ROUTER_KYC_INVALID');
        require(isFactoryKycVerified(tokenB), 'UniswapV2: TOKEN_B_ROUTER_KYC_INVALID');
        require(isErc20TokenValid(tokenA), 'UniswapV2: TOKEN_A_ROUTER_NOT_VALID');
        require(isErc20TokenValid(tokenB), 'UniswapV2: TOKEN_B_ROUTER_NOT_VALID');

        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) onlyActive returns (uint[] memory amounts) {
        require(path.length < 3, 'UniswapV2Library: INVALID_PATH');
        require(isFactoryKycVerified(path[0]), 'UniswapV2: TOKEN_A_ROUTER_KYC_INVALID');
        require(isFactoryKycVerified(path[1]), 'UniswapV2: TOKEN_B_ROUTER_KYC_INVALID');
        require(isErc20TokenValid(path[0]), 'UniswapV2: TOKEN_A_ROUTER_NOT_VALID');
        require(isErc20TokenValid(path[1]), 'UniswapV2: TOKEN_B_ROUTER_NOT_VALID');

        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    // **** LIBRARY FUNCTIONS ****
    function setRouterStatus(bool _isActive) external override onlyOwner {
        isActive = _isActive;
        emit RouterStatusChanged(isActive);
    }

    function setSourceUrl(string calldata _sourceUrl) external override onlyOwner {
        sourceUrl = _sourceUrl;
    }

    function setRouterOwner(address _newOwner) external override onlyOwner {
        require(_newOwner != address(0), 'UniswapV2Router: ZERO_ADDRESS');
        routerOwner = _newOwner;
    }

    function setAuthContract(address _authContract) external override onlyOwner {
        authContract = _authContract;
    }

    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) public pure virtual override returns (uint amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) public pure virtual override returns (uint amountIn) {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(
        uint amountIn,
        address[] memory path
    ) public view virtual override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(
        uint amountOut,
        address[] memory path
    ) public view virtual override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
