// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol"; // <-- Added Chainlink interface

interface IArbExec {
    enum DEXType {
        UNISWAP_V3,
        SUSHISWAP
    }

struct ArbitrageRoute {
    uint256 routeId;
    address[] path;
    uint256 minProfit;
    DEXType dexA;
    DEXType dexB;
}

struct ProfitabilityQuote {
    uint256 leg1AmountOut;
    uint256 leg2AmountOut;
    uint256 flashLoanPremium;
    uint256 gasCostEstimate;
    uint256 builderTip;
    uint256 safetyBuffer;
    uint256 expectedGrossProfit;
    uint256 totalCosts;
    uint256 expectedNetProfit;
    bool isProfitable;
}

function initiateArbitrage(
    address asset,
    uint256 amount,
    uint256 routeId,
    bool quietEvents
) external;

function calculateProfitability(
    address[] memory path,
    uint256 borrowAmount,
    DEXType dexA,
    DEXType dexB
) external returns (ProfitabilityQuote memory);

function getRoute(uint256 routeId) external view returns (ArbitrageRoute memory);

function getRouteCount() external view returns (uint256);

function getAllRoutes(uint256 offset, uint256 limit)
    external
    view
    returns (ArbitrageRoute[] memory);

function emergencyWithdraw(address token) external;

function withdrawETH() external;
}

contract ArbOptimizer is Ownable, ReentrancyGuard, Pausable { 

// ============ Mainnet Addresses (Hardcoded) ============ 

// ArbExec Contract Address 
address private constant ARBEXEC_ADDRESS = 0xEfac88d8e212ca21d4FE670F715c4fE12CFbEF05;

// ============ USDC Addresses by Chain ============
// Ethereum Mainnet (ERC-20)
address private constant USDC_ETHEREUM = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
// Base (Native USDC)
address private constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
// Arbitrum (ERC-20)
address private constant USDC_ARBITRUM = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

// ============ Tokens - Extended List (Ethereum Mainnet) ============
address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Ethereum USDC
address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
address private constant FRAX = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
address private constant LUSD = 0x5f98805A4E8F28fB3FBE254CCf7e6f82e4467683;
address private constant USDP = 0x8E870D67f660D95d5Be2D7738B5b1294a692a0b9;
address private constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
address private constant GUSD = 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd;
address private constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
address private constant USDC_E = 0xa7d1D0dA000261f05d8d4532FD34439D3325AD8B;
address private constant EURS = 0xdB25f211AB05b1c97D595516F45794528a807ad8;

// ============ Chainlink Price Feeds (Ethereum Mainnet) ============
address private constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
address private constant USDC_USD_FEED = 0x8fFfFFd4afB6115b954Bd29BfD33EfF20d6E1E94;
address private constant USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
address private constant DAI_USD_FEED = 0xAEd0C38402A5d19DF6e4c03F4e2DCeD6E29c1235;
address private constant FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
address private constant LUSD_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

// ============ DEX Routers (Ethereum Mainnet) ============
address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
address private constant SUSHISWAP_ROUTER = 0x0d9e1CE17f2641f24Ae57B168B3C7A5bA3Df4039;

// ============ DEX Quoters (Ethereum Mainnet) ============
address private constant UNISWAP_V3_QUOTER = 0x61FFE014bA17989e8A2D3BCCdA57b7A7FCD78f74;

// ============ Aave V3 (Ethereum Mainnet) ============
address private constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
address private constant AAVE_V3_PROVIDER = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;

// ============ Beneficiary ============
address private constant BENEFICIARY = 0xCf714f4C2932ff5148651FF8A3a91Af69cf9ade3;

// ============ Chainlink Price Feed Interface ============
AggregatorV3Interface private constant ETH_USD_FEED_CONTRACT =
    AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

// ============ Chain Enum ============
enum Chain {
    ETHEREUM,
    BASE,
    ARBITRUM,
    BSC
}

// ============ New Function: Get WETH Value in USD ============
/**
 * @notice Fetches the current USD value of 100 WETH using Chainlink
 * @return usdValue The value in USD (scaled by 8 decimals, same as Chainlink)
 */
function getWethValueInUsd() external view returns (int256) {
    (, int256 ethUsdPrice, , , ) = ETH_USD_FEED_CONTRACT.latestRoundData();
    require(ethUsdPrice > 0, "Chainlink: Invalid ETH/USD price");
    // 100 WETH = 100 * ETH/USD price (scaled by 8 decimals)
    return ethUsdPrice * 100;
}

/**
 * @notice Get USDC address for a specific chain
 * @param chain Chain enum (ETHEREUM, BASE, ARBITRUM, BSC)
 * @return usdcAddress USDC contract address for the specified chain
 */
function getUSDCAddressByChain(Chain chain) external pure returns (address usdcAddress) {
    if (chain == Chain.ETHEREUM) {
        return USDC_ETHEREUM;
    } else if (chain == Chain.BASE) {
        return USDC_BASE;
    } else if (chain == Chain.ARBITRUM) {
        return USDC_ARBITRUM;
    }
    revert("Invalid chain");
}

/**
 * @notice Get all USDC addresses across chains
 * @return ethereumUsdc USDC address on Ethereum
 * @return baseUsdc USDC address on Base
 * @return arbitrumUsdc USDC address on Arbitrum
 */
function getAllUSDCAddresses()
    external
    pure
    returns (
        address ethereumUsdc,
        address baseUsdc,
        address arbitrumUsdc
    )
{
    return (USDC_ETHEREUM, USDC_BASE, USDC_ARBITRUM);
}

// ============ State Variables ============
IArbExec public arbExec;

// User Input Parameters
uint256 public userFlashLoanAmount = 1e18; // Default: 1 WETH
uint256 public userPremiumPercentage = 9; // Default: 0.09% (9 basis points)
uint256 public userMinProfitBps = 50; // Default: 50 basis points (0.5%)
uint256 public userMinProfitAmount = 0.01e18; // Default: 0.01 WETH
uint256 public minFlashLoanAmount = 1e18;
uint256 public maxFlashLoanAmount = 10000e18; // Up to 10,000 WETH
uint256 public minProfitBpsThreshold = 50;  // Updated name
uint256 public minProfitAmount = 0.01e18;
bool public autoExecute = false;
uint256 public lastExecutionTime;
uint256 public executionCooldown = 60 seconds;

// ============ Events ============
event RouteAnalyzed(
    uint256 indexed routeIndex,
    uint256 estimatedProfit,
    uint256 flashLoanAmount,
    bool isProfitable
);

event ArbitrageExecuted(
    uint256 indexed routeIndex,
    uint256 flashLoanAmount,
    uint256 estimatedProfit
);

event OptimalRouteSelected(
    uint256 indexed bestRouteIndex,
    uint256 highestProfit,
    uint256 flashLoanAmount
);

event ConfigurationUpdated(
    uint256 minFlashLoanAmount,
    uint256 maxFlashLoanAmount,
    uint256 minProfitBps,
    uint256 amount
);

event ProfitWithdrawn(address indexed token, uint256 amount, address indexed recipient);

event ETHWithdrawn(uint256 amount, address indexed recipient);

event UserParametersUpdated(
    uint256 flashLoanAmount,
    uint256 premiumPercentage,
    uint256 minProfitBpsThreshold,
    uint256 minProfitAmount
);

// ============ Constructor ============
constructor() Ownable(msg.sender) {
    arbExec = IArbExec(ARBEXEC_ADDRESS);
}

// ============ User Input Functions ============
/**
 * @notice Set flash loan amount (in wei)
 * @param _amount Amount in wei (e.g., 1e18 = 1 WETH, 10000e18 = 10,000 WETH)
 */
function setFlashLoanAmount(uint256 _amount) external onlyOwner {
    require(_amount >= minFlashLoanAmount, "Below minimum flash loan");
    require(_amount <= maxFlashLoanAmount, "Exceeds maximum flash loan");
    userFlashLoanAmount = _amount;
    emit UserParametersUpdated(
        userFlashLoanAmount,
        userPremiumPercentage,
        userMinProfitBps,
        userMinProfitAmount
    );
}

/**
 * @notice Set flash loan premium as percentage (e.g., 0.09 for 0.09%)
 * @param _premiumPercentage Premium percentage (9 = 0.09%, 100 = 1%)
 */
function setFlashLoanPremium(uint256 _premiumPercentage) external onlyOwner {
    require(_premiumPercentage > 0, "Premium must be positive");
    require(_premiumPercentage <= 1000, "Premium exceeds 10%");
    userPremiumPercentage = _premiumPercentage;
    emit UserParametersUpdated(
        userFlashLoanAmount,
        userPremiumPercentage,
        userMinProfitBps,
        userMinProfitAmount
    );
}

/**
 * @notice Set minimum profit threshold in basis points
 * @param _minProfitBps Minimum profit in BPS (50 = 0.5%, 100 = 1%)
 */
function setUserMinProfitBps(uint256 _minProfitBps) external onlyOwner {
    require(_minProfitBps <= 10000, "Invalid BPS");
    userMinProfitBps = _minProfitBps;
    emit UserParametersUpdated(
        userFlashLoanAmount,
        userPremiumPercentage,
        userMinProfitBps,
        userMinProfitAmount
    );
}

/**
 * @notice Set minimum profit threshold in absolute amount
 * @param _minProfitAmount Minimum profit in wei (e.g., 0.01e18 = 0.01 WETH)
 */
function setUserMinProfitAmount(uint256 _minProfitAmount) external onlyOwner {
    userMinProfitAmount = _minProfitAmount;
    emit UserParametersUpdated(
        userFlashLoanAmount,
        userPremiumPercentage,
        userMinProfitBps,
        userMinProfitAmount
    );
}

/**
 * @notice Get current user parameters
 * @return flashLoanAmount Current flash loan amount
 * @return premiumPercentage Current premium percentage
 * @return _minProfitBps Current minimum profit in basis points (BPS)  // <-- Added `_`
 * @return _minProfitAmount Current minimum profit amount in wei      // <-- Added `_`
 */
function getUserParameters()
    public
    view
    returns (
        uint256 flashLoanAmount,
        uint256 premiumPercentage,
        uint256 _minProfitBps,       // <-- Added underscore
        uint256 _minProfitAmount     // <-- Added underscore
    )
{
    return (
        userFlashLoanAmount,
        userPremiumPercentage,
        minProfitBpsThreshold,
        minProfitAmount
    );
}

/**
 * @notice Calculate actual premium amount from percentage
 * @return premiumAmount Premium amount in wei
 */
function calculatePremiumAmount() external view returns (uint256) {
    return (userFlashLoanAmount * userPremiumPercentage) / 10000;
}

// ============ Core Functions ============
/**
 * @notice Analyze a single route for profitability
 * @param routeIndex Index of the route to analyze
 * @param flashLoanAmount Amount to flash loan
 * @return estimatedProfit Expected profit in base token
 * @return isProfitable Whether route meets minimum profit threshold
 */
function analyzeRoute(uint256 routeIndex, uint256 flashLoanAmount)
    external
    returns (uint256 estimatedProfit, bool isProfitable)
{
    require(flashLoanAmount >= minFlashLoanAmount, "Below minimum flash loan");
    require(flashLoanAmount <= maxFlashLoanAmount, "Exceeds maximum flash loan");

    IArbExec.ArbitrageRoute memory route = arbExec.getRoute(routeIndex);
    require(route.path.length >= 2, "Invalid route");

    IArbExec.ProfitabilityQuote memory quote = arbExec.calculateProfitability(
        route.path,
        flashLoanAmount,
        route.dexA,
        route.dexB
    );

    estimatedProfit = quote.expectedNetProfit;
    isProfitable = quote.isProfitable &&
        estimatedProfit >= userMinProfitAmount &&
        (estimatedProfit * 10000) / flashLoanAmount >= userMinProfitBps;

    emit RouteAnalyzed(routeIndex, estimatedProfit, flashLoanAmount, isProfitable);
}

/**
 * @notice Find the most profitable route across all available routes
 * @param flashLoanAmount Amount to flash loan
 * @return bestRouteIndex Index of most profitable route
 * @return highestProfit Estimated profit of best route
 * @return isProfitable Whether best route meets minimum threshold
 */
function findOptimalRoute(uint256 flashLoanAmount)
    external
    returns (uint256 bestRouteIndex, uint256 highestProfit, bool isProfitable)
{
    uint256 routeCount = arbExec.getRouteCount();
    require(routeCount > 0, "No routes available");
    require(flashLoanAmount >= minFlashLoanAmount, "Below minimum flash loan");
    require(flashLoanAmount <= maxFlashLoanAmount, "Exceeds maximum flash loan");

    highestProfit = 0;
    bestRouteIndex = 0;
    isProfitable = false;

    for (uint256 i = 0; i < routeCount; i++) {
        try this.analyzeRoute(i, flashLoanAmount) returns (uint256 profit, bool profitable) {
            if (profit > highestProfit) {
                highestProfit = profit;
                bestRouteIndex = i;
                isProfitable = profitable;
            }
        } catch {
            continue;
        }
    }
}

/**
 * @notice Execute arbitrage on the optimal route using user parameters
 * @return success Whether execution was successful
 */
function executeOptimalArbitrageWithUserParams()
    external
    nonReentrant
    whenNotPaused
    onlyOwner
    returns (bool success)
{
    return executeOptimalArbitrage(userFlashLoanAmount);
}

/**
 * @notice Execute arbitrage on the optimal route
 * @param flashLoanAmount Amount to flash loan (in wei, e.g., 10e18 for 10 WETH)
 * @return success Whether execution was successful
 */
function executeOptimalArbitrage(uint256 flashLoanAmount)
    public
    nonReentrant
    whenNotPaused
    onlyOwner
    returns (bool success)
{
    require(flashLoanAmount >= minFlashLoanAmount, "Below minimum flash loan");
    require(flashLoanAmount <= maxFlashLoanAmount, "Exceeds maximum flash loan");

    if (autoExecute) {
        require(
            block.timestamp >= lastExecutionTime + executionCooldown,
            "Cooldown period active"
        );
    }

    (uint256 bestRouteIndex, uint256 estimatedProfit, bool isProfitable) = this
        .findOptimalRoute(flashLoanAmount);
    require(isProfitable, "No profitable route found");

    emit OptimalRouteSelected(bestRouteIndex, estimatedProfit, flashLoanAmount);

    try arbExec.initiateArbitrage(WETH, flashLoanAmount, bestRouteIndex, false) {
        lastExecutionTime = block.timestamp;
        emit ArbitrageExecuted(bestRouteIndex, flashLoanAmount, estimatedProfit);
        success = true;
    } catch {
        success = false;
    }
}

/**
 * @notice Analyze all routes and return profitability data
 * @param flashLoanAmount Amount to flash loan
 * @return routeProfits Array of profits for each route
 * @return routesProfitable Array of profitability flags
 */
function analyzeAllRoutes(uint256 flashLoanAmount)
    external
    returns (uint256[] memory routeProfits, bool[] memory routesProfitable)
{
    uint256 routeCount = arbExec.getRouteCount();
    routeProfits = new uint256[](routeCount);
    routesProfitable = new bool[](routeCount);

    for (uint256 i = 0; i < routeCount; i++) {
        try this.analyzeRoute(i, flashLoanAmount) returns (uint256 profit, bool profitable) {
            routeProfits[i] = profit;
            routesProfitable[i] = profitable;
        } catch {
            routeProfits[i] = 0;
            routesProfitable[i] = false;
        }
    }
}

// ============ Withdrawal Functions ============
/**
 * @notice Withdraw WETH profits
 */
function withdrawWETH() external nonReentrant onlyOwner {
    arbExec.emergencyWithdraw(WETH);
    uint256 balance = IERC20(WETH).balanceOf(address(this));
    if (balance > 0) {
        IERC20(WETH).transfer(msg.sender, balance);
        emit ProfitWithdrawn(WETH, balance, msg.sender);
    }
}

/**
 * @notice Withdraw USDC profits
 */
function withdrawUSDC() external nonReentrant onlyOwner {
    arbExec.emergencyWithdraw(USDC);
    uint256 balance = IERC20(USDC).balanceOf(address(this));
    if (balance > 0) {
        IERC20(USDC).transfer(msg.sender, balance);
        emit ProfitWithdrawn(USDC, balance, msg.sender);
    }
}

/**
 * @notice Withdraw USDT profits
 */
function withdrawUSDT() external nonReentrant onlyOwner {
    arbExec.emergencyWithdraw(USDT);
    uint256 balance = IERC20(USDT).balanceOf(address(this));
    if (balance > 0) {
        IERC20(USDT).transfer(msg.sender, balance);
        emit ProfitWithdrawn(USDT, balance, msg.sender);
    }
}

/**
 * @notice Withdraw DAI profits
 */
function withdrawDAI() external nonReentrant onlyOwner {
    arbExec.emergencyWithdraw(DAI);
    uint256 balance = IERC20(DAI).balanceOf(address(this));
    if (balance > 0) {
        IERC20(DAI).transfer(msg.sender, balance);
        emit ProfitWithdrawn(DAI, balance, msg.sender);
    }
}

/**
 * @notice Withdraw any token profits
 * @param token Token address to withdraw
 */
function withdrawToken(address token) external nonReentrant onlyOwner {
    require(token != address(0), "Invalid token");
    arbExec.emergencyWithdraw(token);
    uint256 balance = IERC20(token).balanceOf(address(this));
    if (balance > 0) {
        IERC20(token).transfer(msg.sender, balance);
        emit ProfitWithdrawn(token, balance, msg.sender);
    }
}

/**
 * @notice Withdraw ETH profits
 */
function withdrawETH() external nonReentrant onlyOwner {
    arbExec.withdrawETH();
    uint256 balance = address(this).balance;
    if (balance > 0) {
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "ETH transfer failed");
        emit ETHWithdrawn(balance, msg.sender);
    }
}

/**
 * @notice Withdraw all available profits
 */
function withdrawAll() external nonReentrant onlyOwner {
    // Withdraw all token types
    _safeWithdraw(WETH);
    _safeWithdraw(USDC);
    _safeWithdraw(USDT);
    _safeWithdraw(DAI);
    _safeWithdraw(FRAX);
    _safeWithdraw(LUSD);
    _safeWithdraw(USDP);
    _safeWithdraw(TUSD);
    _safeWithdraw(GUSD);
    _safeWithdraw(BUSD);
    _safeWithdraw(USDC_E);
    _safeWithdraw(EURS);

    // Withdraw ETH
    uint256 ethBalance = address(this).balance;
    if (ethBalance > 0) {
        (bool success, ) = msg.sender.call{value: ethBalance}("");
        require(success, "ETH transfer failed");
        emit ETHWithdrawn(ethBalance, msg.sender);
    }
}

/**
 * @notice Internal helper to safely withdraw token
 */
function _safeWithdraw(address token) internal {
    try arbExec.emergencyWithdraw(token) {} catch {}
    uint256 balance = IERC20(token).balanceOf(address(this));
    if (balance > 0) {
        IERC20(token).transfer(msg.sender, balance);
        emit ProfitWithdrawn(token, balance, msg.sender);
    }
}

// ============ Configuration Functions ============
/**
 * @notice Update flash loan amount limits
 */
function setFlashLoanLimits(uint256 _min, uint256 _max) external onlyOwner {
    require(_min > 0 && _max > _min, "Invalid limits");
    minFlashLoanAmount = _min;
    maxFlashLoanAmount = _max;
    emit ConfigurationUpdated(_min, _max, minProfitBpsThreshold, minProfitAmount);
}

/**
 * @notice Update minimum profit thresholds
 */
function setMinProfitThresholds(uint256 _bps, uint256 _amount) external onlyOwner {
    require(_bps <= 10000, "Invalid BPS");
    minProfitBpsThreshold = _bps;  // Now clearly refers to the state variable
    minProfitAmount = _amount;
    emit ConfigurationUpdated(minFlashLoanAmount, maxFlashLoanAmount, _bps, _amount);
}

/**
 * @notice Toggle auto-execution mode
 */
function setAutoExecute(bool _enabled) external onlyOwner {
    autoExecute = _enabled;
}

/**
 * @notice Set execution cooldown period
 */
function setExecutionCooldown(uint256 _cooldown) external onlyOwner {
    require(_cooldown <= 1 days, "Cooldown too long");
    executionCooldown = _cooldown;
}

/**
 * @notice Pause contract operations
 */
function pause() external onlyOwner {
    _pause();
}

/**
 * @notice Unpause contract operations
 */
function unpause() external onlyOwner {
    _unpause();
}

// ============ View Functions ============
/**
 * @notice Get ArbExec contract address
 */
function getArbExecAddress() external pure returns (address) {
    return ARBEXEC_ADDRESS;
}

/**
 * @notice Get WETH address
 */
function getWETHAddress() external pure returns (address) {
    return WETH;
}

/**
 * @notice Get all supported token addresses
 */
function getSupportedTokens() external pure returns (address[] memory) {
    address[] memory tokens = new address[](12);
    tokens[0] = WETH;
    tokens[1] = USDC;
    tokens[2] = USDT;
    tokens[3] = DAI;
    tokens[4] = FRAX;
    tokens[5] = LUSD;
    tokens[6] = USDP;
    tokens[7] = TUSD;
    tokens[8] = GUSD;
    tokens[9] = BUSD;
    tokens[10] = USDC_E;
    tokens[11] = EURS;
    return tokens;
}

/**
 * @notice Get token balance in this contract
 */
function getTokenBalance(address token) external view returns (uint256) {
    return IERC20(token).balanceOf(address(this));
}

/**
 * @notice Get ETH balance in this contract
 */
function getETHBalance() external view returns (uint256) {
    return address(this).balance;
}

/**
 * @notice Get all balances
 */
function getAllBalances()
    external
    view
    returns (
        uint256 wethBalance,
        uint256 usdcBalance,
        uint256 usdtBalance,
        uint256 daiBalance,
        uint256 fraxBalance,
        uint256 lusdBalance,
        uint256 usdpBalance,
        uint256 tusdBalance,
        uint256 gusdBalance,
        uint256 busdBalance,
        uint256 usdcEBalance,
        uint256 eursBalance,
        uint256 ethBalance
    )
{
    wethBalance = IERC20(WETH).balanceOf(address(this));
    usdcBalance = IERC20(USDC).balanceOf(address(this));
    usdtBalance = IERC20(USDT).balanceOf(address(this));
    daiBalance = IERC20(DAI).balanceOf(address(this));
    fraxBalance = IERC20(FRAX).balanceOf(address(this));
    lusdBalance = IERC20(LUSD).balanceOf(address(this));
    usdpBalance = IERC20(USDP).balanceOf(address(this));
    tusdBalance = IERC20(TUSD).balanceOf(address(this));
    gusdBalance = IERC20(GUSD).balanceOf(address(this));
    busdBalance = IERC20(BUSD).balanceOf(address(this));
    usdcEBalance = IERC20(USDC_E).balanceOf(address(this));
    eursBalance = IERC20(EURS).balanceOf(address(this));
    ethBalance = address(this).balance;
}

// ============ Fallback ============
/**
 * @notice Receive ETH
 */
receive() external payable {}
}