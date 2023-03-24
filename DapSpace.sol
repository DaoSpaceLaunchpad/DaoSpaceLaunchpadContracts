// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/UniswapInterface.sol";

/*
 * Dao Sapce
 * Web: https://daospace.fund
 * Telegram: https://t.me/daospaceglobal
 * Twitter: https://twitter.com/daospacepad
 */

/// @author Arreta (Former WeCare) - https://arreta.org
/// @custom:security-contact security@arreta.org
contract DaoSpace is Context, IERC20, IERC20Metadata, Ownable {
    uint256 private constant FEE_DENOMINATOR = 1000;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    string private _name = "DaoSpace";
    string private _symbol = "DAOP";
    uint8 private _decimal = 18;

    uint256 private _totalSupply = 100_000_000 * 10 ** decimals();

    // is address excluded from Max Tx
    mapping(address => bool) public isExcludedFromMaxTx;
    // is address excluded from fee taken
    mapping(address => bool) public isExcludedFromFee;
    // Liquidity Pool Providers
    mapping(address => bool) public isDEX;
    // Max Tx Amount
    uint256 public maxTxAmount;

    uint256 public buyLiquidityFee;
    uint256 public buyMarketingFee = 50;

    uint256 public sellLiquidityFee = 50;
    uint256 public sellMarketingFee = 50;

    address public marketingWallet = 0xF90E8785FbB93Ed677C4f8d3dD35385290902c3D;
    address public liquidityWallet = 0x6998A9Ce1E4609fFb6533D6B65e84FE00843901E;

    uint256 public sellFeeCollected;
    uint256 public buyFeeCollected;

    uint256 public minimumTokensToSwap = 10_000 * 10 ** decimals();

    bool inSwap;

    IUniswapV2Router02 public uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    // Events
    event BuyFeesChanged(uint256 indexed newBuyLiquidityFee, uint256 indexed newBuyMarketingFee);
    event SellFeesChanged(uint256 indexed newSellLiquidityFee, uint256 indexed newSellMarketingFee);
    event WalletsChanged(address indexed newMarketingWallet, address indexed newLiquidityWallet);
    event MinimumTokensToSwapChanged(uint256 indexed newMinimumTokensToSwap);
    event MaxTxAmountChanged(uint256 indexed newMaxTxAmount);
    event ExcludedFromFeeChanged(address indexed account, bool indexed isExcluded);
    event ExcludedFromMaxTxChanged(address indexed account, bool indexed isExcluded);
    event DEXChanged(address indexed account, bool indexed isDEX);
    event RouterChanged(address indexed newRouter);

    constructor() {
        address uniswapPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        isDEX[uniswapPair] = true;

        isExcludedFromFee[owner()] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[marketingWallet] = true;
        isExcludedFromFee[liquidityWallet] = true;

        isExcludedFromMaxTx[owner()] = true;
        isExcludedFromMaxTx[address(this)] = true;
        isExcludedFromMaxTx[marketingWallet] = true;
        isExcludedFromMaxTx[liquidityWallet] = true;

        _balances[_msgSender()] = _totalSupply;
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    receive() external payable {}

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimal;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * Extended Functionalities
     */

    function setBuyTaxes(uint256 _lpFee, uint256 _teamFee) external onlyOwner {
        require(_lpFee + _teamFee <= 200, "Total fee cannot be more than %20");

        buyLiquidityFee = _lpFee;
        buyMarketingFee = _teamFee;

        emit BuyFeesChanged(_lpFee, _teamFee);
    }

    function setSellTaxes(uint256 _lpFee, uint256 _teamFee) external onlyOwner {
        require(_lpFee + _teamFee <= 200, "Total fee cannot be more than %20");

        sellLiquidityFee = _lpFee;
        sellMarketingFee = _teamFee;

        emit SellFeesChanged(_lpFee, _teamFee);
    }

    function setWallets(address _marketingWallet, address _liquidityWallet) external onlyOwner {
        marketingWallet = _marketingWallet;
        liquidityWallet = _liquidityWallet;

        emit WalletsChanged(_marketingWallet, _liquidityWallet);
    }

    function setMaxTxAmount(uint256 _maxTxAmount) external onlyOwner {
        maxTxAmount = _maxTxAmount;

        emit MaxTxAmountChanged(_maxTxAmount);
    }

    function setMinimumTokensToSwap(uint256 _minimumTokensToSwap) external onlyOwner {
        minimumTokensToSwap = _minimumTokensToSwap;

        emit MinimumTokensToSwapChanged(_minimumTokensToSwap);
    }

    function setDEX(address _dex, bool _isDEX) external onlyOwner {
        isDEX[_dex] = _isDEX;

        emit DEXChanged(_dex, _isDEX);
    }

    function setExcludedFromMaxTx(address _address, bool _isExcluded) external onlyOwner {
        isExcludedFromMaxTx[_address] = _isExcluded;

        emit ExcludedFromMaxTxChanged(_address, _isExcluded);
    }

    function setRouterAddress(address _routerAddress) external onlyOwner {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_routerAddress);
        uniswapV2Router = _uniswapV2Router;

        emit RouterChanged(_routerAddress);
    }

    function _transfer(address from, address to, uint256 amount) internal virtual returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if(inSwap) {
            return _standardTransfer(from, to, amount);
        }
        
        if (!isExcludedFromMaxTx[from] && !isExcludedFromMaxTx[to]) {
            require(amount <= maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }

        // Do swap here
        if (!inSwap && !isDEX[from]) {
            swapTokens();
        }

        if ((!isDEX[from] && !isDEX[to])) {
            return _standardTransfer(from, to, amount);
        }

        if (isExcludedFromFee[from] || isExcludedFromFee[to]) {
            return _standardTransfer(from, to, amount);
        }

        uint256 sendAmount = _collectFee(from, amount);
        return _standardTransfer(from, to, sendAmount);
    }

    function _standardTransfer(address from, address to, uint256 amount) internal virtual returns (bool) {
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
        return true;
    }

    function _collectFee(address from, uint256 amount) internal virtual returns (uint256) {
        uint256 feeAmount = 0;

        if (isDEX[from]) {
            feeAmount = (amount * (buyLiquidityFee + buyMarketingFee)) / FEE_DENOMINATOR;
            buyFeeCollected += feeAmount;
        } else {
            feeAmount = (amount * (sellLiquidityFee + sellMarketingFee)) / FEE_DENOMINATOR;
            sellFeeCollected += feeAmount;
        }

        if (feeAmount > 0) {
            _balances[address(this)] += feeAmount;
            emit Transfer(from, address(this), feeAmount);
        }

        // Calculate send amount
        return amount - feeAmount;
    }

    function swapTokens() internal virtual lockTheSwap {
        uint256 contractTokenBalance = balanceOf(address(this));
        if (sellFeeCollected >= minimumTokensToSwap && sellFeeCollected <= contractTokenBalance) {
            uint256 swapAmount = sellFeeCollected;
            sellFeeCollected = 0;
            
            // Swap tokens for ETH
            swapTokensForEth(swapAmount);

            // How much ETH did we just swap into?
            uint256 bnbBalance = address(this).balance;
            uint256 half = bnbBalance / 2;
            
            // Send to marketing wallet
            (bool successMarketing, ) = payable(marketingWallet).call{value: half}("");
            require(successMarketing, "Transfer failed.");

            // Send to liquidity wallet
            (bool successLiq, ) = payable(liquidityWallet).call{value: half}("");
            require(successLiq, "Transfer failed.");
        } else if (buyFeeCollected >= minimumTokensToSwap && buyFeeCollected <= contractTokenBalance) {
            uint256 swapAmount = buyFeeCollected;
            buyFeeCollected = 0;

            // Swap tokens for ETH
            swapTokensForEth(swapAmount);

            // Send to marketing wallet
            (bool success, ) = payable(marketingWallet).call{value: address(this).balance}("");
            require(success, "Transfer failed.");
        }
    }

    function swapTokensForEth(uint256 tokenAmount) internal virtual {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function withdrawContractTokens() external onlyOwner returns (bool) {
        uint256 contractBalance = balanceOf(address(this));

        if (contractBalance > 0) {
            _balances[marketingWallet] += contractBalance;

            emit Transfer(address(this), marketingWallet, contractBalance);
        }

        return true;
    }
}
