// SPDX-License-Identifier: MIT

// ArbExec.sol
pragma solidity 0.8.20;

// Aave v3
import "github/aave/aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import "github/aave/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import "github/aave/aave-v3-core/contracts/interfaces/IPool.sol";

// OpenZeppelin
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Uniswap V3
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

// Sushiswap
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// ============ CHAINLINK INTERFACE (INLINED) ============
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);
}

// ============ CUSTOM INTERFACES ============
interface IQuoter {
    function quoteExactInput(bytes memory path, uint256 amountIn)
        external
        returns (uint256 amountOut);

    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

/// @title ArbExecutor
/// @notice Advanced arbitrage execution contract with flash loan support, dual oracle validation, and comprehensive risk management
/// @dev Implements IFlashLoanSimpleReceiver for Aave V3 flash loan integration
contract ArbExecutor is ReentrancyGuard, Ownable, IFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;

    // ============ CUSTOM ERRORS (Gas Optimized) ============
    error UnauthorizedCaller();
    error InvalidAsset();
    error InvalidAmount();
    error ExceedsMaxLoan();
    error UnsupportedToken();
    error InvalidRouteId();
    error InvalidRoutePath();
    error InvalidPathLength();
    error InvalidTokenAddress();
    error DuplicateTokenInPath();
    error CircularPathRequired();
    error DEXNotConfigured();
    error NoPriceFeed();
    error InvalidOraclePrice();
    error StalePriceFeed();
    error StaleSecondaryFeed();
    error PriceDeviationTooHigh();
    error SecondaryPriceDeviationTooHigh();
    error QuoteFailed();
    error InsufficientOutput();
    error ProfitBelowMinimum();
    error ProfitBelowAbsoluteMinimum();
    error ContractPaused();
    error InvalidBps();
    error InvalidFee();
    error InvalidBeneficiary();
    error BeneficiaryShareExceedsMax();
    error InvalidProvider();
    error InvalidPool();
    error InvalidRouter();
    error InvalidQuoter();
    error InvalidToken();
    error InvalidFeed();
    error ArrayLengthMismatch();
    error NoBalance();
    error ETHTransferFailed();
    error ApprovalFailed();
    error SwapFailed();
    error RouterNotWhitelisted();
    error InvalidInitiator();
    error InsufficientLiquidityForRoute();
    error TradNotProfitable();

    // ============ CONSTANTS ============
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant PRICE_PRECISION = 1e18;
    uint256 private constant MAX_PATH_LENGTH = 4;
    uint256 private constant MIN_PATH_LENGTH = 2;
    uint256 private constant MAX_BENEFICIARY_BPS = 5_000;
    uint256 private constant DECIMAL_SCALE = 1e18;
    uint256 private constant PRICE_CACHE_DURATION = 1; // 1 block

    // ============ ENUMS ============
    enum DEXType {
        UNISWAP_V3,
        SUSHISWAP
    }

    // ============ STRUCTS ============
    /// @notice Represents a complete arbitrage route configuration
    struct ArbitrageRoute {
        uint256 routeId;
        address[] path;
        uint256 minProfit;
        DEXType dexA;
        DEXType dexB;
    }

    /// @notice Profitability analysis result
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

    /// @notice Cached oracle price data with timestamps
    struct OraclePrice {
        uint256 price0;
        uint256 price1;
        uint40 updatedAt0;
        uint40 updatedAt1;
    }

    /// @notice Token decimal information
    struct TokenDecimals {
        uint8 decimals0;
        uint8 decimals1;
    }

    /// @notice Price cache entry
    struct PriceCache {
        uint256 price;
        uint256 blockNumber;
    }

    // ============ CONFIGURATION STATE ============
    mapping(address => bool) public supportedTokens;
    mapping(address => address) public priceFeeds;
    mapping(address => address) public secondaryPriceFeeds;
    mapping(address => uint8) public tokenDecimals;
    mapping(DEXType => address) public dexRouters;
    mapping(DEXType => address) public dexQuoters;
    mapping(address => bool) public whitelistedRouters;
    mapping(address => PriceCache) private priceCache;

    address public aaveV3AddressesProvider;
    address public weth;

    uint256 public minProfitBps = 100;
    uint256 public maxSlippageBps = 300;
    uint256 public deadlineSeconds = 90;
    uint256 public gasUnitsEstimate = 500_000;
    uint256 public maxPriceFeedAge = 300;
    uint256 public oracleDeviationBps = 800;
    uint256 public secondaryOracleDeviationBps = 1200;
    uint24 public defaultUniV3Fee = 3000;

    uint256 public builderTipBps = 10;
    uint256 public safetyBufferBps = 50;
    uint256 public flashLoanPremiumBps = 9;
    uint256 public gasPrice = 50 gwei;

    uint256 public maxLoanAmount = 10_000 ether;
    uint256 public minProfitAbsolute = 0;

    address public beneficiary;
    uint256 public beneficiaryShareBps = 5_000;
    bool public autoUnwrapWETH = true;
    bool public enforceProfitabilityCheck = true;
    bool public enforceSecondaryOracle = true;
    bool public paused = false;

    // ============ ARBITRAGE STATE ============
    mapping(uint256 => ArbitrageRoute) public routes;
    uint256 public routeCount;
    IPool public aaveV3Pool;

    // ============ EVENTS ============
    event ArbitrageSuccess(
        address indexed asset,
        uint256 amount,
        uint256 profit,
        uint256 routeId,
        uint256 gasUsed
    );
    event ArbitrageInitiated(address indexed asset, uint256 amount, uint256 routeId);
    event ProfitabilityCheckPassed(uint256 routeId, uint256 expectedNetProfit);
    event ProfitabilityCheckFailed(uint256 routeId, string reason);
    event RoutesUpdated(uint256 indexed routeId, uint256 pathLength);
    event RouteDeleted(uint256 indexed routeId);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    event ETHWithdrawn(uint256 amount);
    event TokenSupportChanged(address indexed token, bool supported);
    event PriceFeedSet(address indexed token, address indexed feed);
    event SecondaryPriceFeedSet(address indexed token, address indexed feed);
    event DEXRouterSet(DEXType indexed dexType, address indexed router);
    event DEXQuoterSet(DEXType indexed dexType, address indexed quoter);
    event ProtocolAddressesSet(address indexed aaveV3Provider, address indexed weth);
    event RiskParamsUpdated(
        uint256 minProfitBps,
        uint256 maxSlippageBps,
        uint256 deadlineSeconds,
        uint256 gasUnitsEstimate
    );
    event OracleParamsUpdated(
        uint256 maxPriceFeedAge,
        uint256 oracleDeviationBps,
        uint256 secondaryOracleDeviationBps
    );
    event ProfitabilityParamsUpdated(
        uint256 builderTipBps,
        uint256 safetyBufferBps,
        uint256 flashLoanPremiumBps,
        uint256 gasPrice
    );
    event UniV3FeeUpdated(uint24 fee);
    event BeneficiaryUpdated(address indexed beneficiary);
    event BeneficiaryShareUpdated(uint256 beneficiaryShareBps);
    event AutoUnwrapWETHUpdated(bool enabled);
    event EnforceProfitabilityCheckUpdated(bool enabled);
    event EnforceSecondaryOracleUpdated(bool enabled);
    event PausedStateChanged(bool paused);
    event MaxLoanAmountUpdated(uint256 maxLoanAmount);
    event MinProfitAbsoluteUpdated(uint256 minProfitAbsolute);
    event ProfitDistributed(address indexed beneficiary, uint256 amount);
    event TokenDecimalsSet(address indexed token, uint8 decimals);
    event RouterWhitelisted(address indexed router, bool whitelisted);
    event PriceCacheUpdated(address indexed token, uint256 price);

    // ============ MODIFIERS ============
    /// @notice Ensures contract is not paused
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    /// @notice Validates path length is within acceptable bounds
    modifier validPathLength(uint256 length) {
        if (length < MIN_PATH_LENGTH || length > MAX_PATH_LENGTH) revert InvalidPathLength();
        _;
    }

    // ============ CONSTRUCTOR ============
    /// @notice Initialize ArbExecutor with Mainnet addresses
    constructor() Ownable(msg.sender) ReentrancyGuard() {
        aaveV3Pool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
        aaveV3AddressesProvider = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
        weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        // Uniswap V3
        dexRouters[DEXType.UNISWAP_V3] = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        dexQuoters[DEXType.UNISWAP_V3] = 0x61FFE014bA17989e8A2D3BCCdA57b7A7FCD78f74;
        whitelistedRouters[0xE592427A0AEce92De3Edee1F18E0157C05861564] = true;

        // Sushiswap (Uniswap V2 compatible)
        dexRouters[DEXType.SUSHISWAP] = 0x0d9e1CE17f2641f24Ae57B168B3C7A5bA3Df4039;
        dexQuoters[DEXType.SUSHISWAP] = address(0);
        whitelistedRouters[0x0d9e1CE17f2641f24Ae57B168B3C7A5bA3Df4039] = true;

        beneficiary = 0xCf714f4C2932ff5148651FF8A3a91Af69cf9ade3;

        emit ProtocolAddressesSet(aaveV3AddressesProvider, weth);
    }

    // ============ PROFITABILITY CALCULATION FUNCTIONS ============
    /// @notice Calculate profitability of a potential arbitrage trade
    /// @param path Token path for arbitrage (must be circular)
    /// @param borrowAmount Amount to borrow via flash loan
    /// @param dexA First DEX to use
    /// @param dexB Second DEX to use
    /// @return ProfitabilityQuote with all cost breakdowns
    function calculateProfitability(
        address[] memory path,
        uint256 borrowAmount,
        DEXType dexA,
        DEXType dexB
    ) external validPathLength(path.length) returns (ProfitabilityQuote memory) {
        if (borrowAmount == 0) revert InvalidAmount();
        if (borrowAmount > maxLoanAmount) revert ExceedsMaxLoan();
        if (path[0] != path[path.length - 1]) revert CircularPathRequired();

        for (uint256 i = 0; i < path.length; i++) {
            if (path[i] == address(0)) revert InvalidTokenAddress();
            if (!isTokenSupported(path[i])) revert UnsupportedToken();
        }

        uint256 leg1AmountOut = _getQuote(path[0], path[path.length - 1], borrowAmount, dexA);
        if (leg1AmountOut == 0) revert QuoteFailed();

        uint256 leg2AmountOut = _getQuote(path[path.length - 1], path[0], leg1AmountOut, dexB);
        if (leg2AmountOut == 0) revert QuoteFailed();

        OraclePrice memory oracleData = _getOraclePricesAndValidate(
            path[0],
            path[path.length - 1]
        );

        _validatePriceDeviationWithCache(
            borrowAmount,
            leg1AmountOut,
            oracleData.price0,
            oracleData.price1
        );
        _validatePriceDeviationWithCache(
            leg1AmountOut,
            leg2AmountOut,
            oracleData.price1,
            oracleData.price0
        );

        uint256 dynamicGasUnits = _calculateDynamicGasEstimate(path.length);
        uint256 flashLoanPremium = _calculateBps(borrowAmount, flashLoanPremiumBps);
        uint256 gasCostEstimate = (dynamicGasUnits * gasPrice) / 1e9;
        uint256 builderTip = _calculateBps(borrowAmount, builderTipBps);
        uint256 safetyBuffer = _calculateBps(borrowAmount, safetyBufferBps);

        uint256 totalCosts = flashLoanPremium + gasCostEstimate + builderTip + safetyBuffer;
        uint256 expectedGrossProfit = leg2AmountOut > borrowAmount
            ? leg2AmountOut - borrowAmount
            : 0;
        uint256 expectedNetProfit = expectedGrossProfit >= totalCosts
            ? expectedGrossProfit - totalCosts
            : 0;

        bool isProfitable = expectedNetProfit > 0 &&
            (expectedNetProfit * BPS_DENOMINATOR) / borrowAmount >= minProfitBps &&
            expectedNetProfit >= minProfitAbsolute;

        return
            ProfitabilityQuote({
                leg1AmountOut: leg1AmountOut,
                leg2AmountOut: leg2AmountOut,
                flashLoanPremium: flashLoanPremium,
                gasCostEstimate: gasCostEstimate,
                builderTip: builderTip,
                safetyBuffer: safetyBuffer,
                expectedGrossProfit: expectedGrossProfit,
                totalCosts: totalCosts,
                expectedNetProfit: expectedNetProfit,
                isProfitable: isProfitable
            });
    }

    /// @notice Calculate basis points amount
    /// @param amount Base amount
    /// @param bps Basis points (1 = 0.01%)
    /// @return Calculated amount
    function _calculateBps(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / BPS_DENOMINATOR;
    }

    /// @notice Calculate dynamic gas estimate based on path length
    /// @param pathLength Number of hops in arbitrage path
    /// @return Estimated gas units
    function _calculateDynamicGasEstimate(uint256 pathLength)
        internal
        pure
        returns (uint256)
    {
        if (pathLength < MIN_PATH_LENGTH || pathLength > MAX_PATH_LENGTH)
            revert InvalidPathLength();
        uint256 additionalGasPerHop = 100_000;
        uint256 baseGas = 400_000;
        return baseGas + (additionalGasPerHop * (pathLength - 1));
    }

    /// @notice Calculate dynamic slippage based on trade size and liquidity
    /// @param amountIn Trade input amount
    /// @param liquidity Pool liquidity
    /// @return Dynamic slippage in BPS
    function _calculateDynamicSlippage(uint256 amountIn, uint256 liquidity)
        internal
        pure
        returns (uint256)
    {
        if (liquidity == 0) return 10_000; // 100% slippage if no liquidity

        // slippage = (amountIn / liquidity) * 10000, capped at maxSlippageBps
        uint256 calculatedSlippage = (amountIn * BPS_DENOMINATOR) / liquidity;
        return calculatedSlippage > 5000 ? 5000 : calculatedSlippage; // Cap at 50%
    }

    /// @notice Get quote from DEX
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountIn Input amount
    /// @param dexType DEX to use
    /// @return Output amount
    function _getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        DEXType dexType
    ) internal returns (uint256) {
        if (dexType == DEXType.UNISWAP_V3) {
            return _getUniswapV3Quote(tokenIn, tokenOut, amountIn);
        } else {
            return _getSushiswapQuote(tokenIn, tokenOut, amountIn);
        }
    }

    /// @notice Get Uniswap V3 quote
    function _getUniswapV3Quote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        address quoter = dexQuoters[DEXType.UNISWAP_V3];
        if (quoter == address(0)) revert DEXNotConfigured();

        try
            IQuoter(quoter).quoteExactInputSingle(
                tokenIn,
                tokenOut,
                defaultUniV3Fee,
                amountIn,
                0
            )
        returns (uint256 amountOut) {
            return amountOut;
        } catch {
            return 0;
        }
    }

    /// @notice Get Sushiswap quote
    function _getSushiswapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256) {
        address router = dexRouters[DEXType.SUSHISWAP];
        if (router == address(0)) revert DEXNotConfigured();

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        try IUniswapV2Router02(router).getAmountsOut(amountIn, path) returns (
            uint256[] memory amounts
        ) {
            return amounts[amounts.length - 1];
        } catch {
            return 0;
        }
    }

    /// @notice Get and validate oracle prices with caching
    /// @param token0 First token
    /// @param token1 Second token
    /// @return OraclePrice with normalized prices
    function _getOraclePricesAndValidate(address token0, address token1)
        internal
        view
        returns (OraclePrice memory)
    {
        if (priceFeeds[token0] == address(0)) revert NoPriceFeed();
        if (priceFeeds[token1] == address(0)) revert NoPriceFeed();

        AggregatorV3Interface feed0 = AggregatorV3Interface(priceFeeds[token0]);
        AggregatorV3Interface feed1 = AggregatorV3Interface(priceFeeds[token1]);

        (, int256 price0, , uint256 updatedAt0, ) = feed0.latestRoundData();
        (, int256 price1, , uint256 updatedAt1, ) = feed1.latestRoundData();

        if (price0 <= 0 || price1 <= 0) revert InvalidOraclePrice();
        if (block.timestamp - updatedAt0 > maxPriceFeedAge) revert StalePriceFeed();
        if (block.timestamp - updatedAt1 > maxPriceFeedAge) revert StalePriceFeed();

        // Validate secondary oracle if enabled
        if (enforceSecondaryOracle) {
            _validateSecondaryOracle(token0, token1, price0, price1);
        }

        uint256 normalizedPrice0 = _normalizePrice(uint256(price0), token0);
        uint256 normalizedPrice1 = _normalizePrice(uint256(price1), token1);

        return
            OraclePrice({
                price0: (normalizedPrice0 * PRICE_PRECISION) / normalizedPrice1,
                price1: (normalizedPrice1 * PRICE_PRECISION) / normalizedPrice0,
                updatedAt0: uint40(updatedAt0),
                updatedAt1: uint40(updatedAt1)
            });
    }

    /// @notice Normalize price to 18 decimals
    /// @param price Raw oracle price
    /// @param token Token address
    /// @return Normalized price
    function _normalizePrice(uint256 price, address token) internal view returns (uint256) {
        uint8 decimals = tokenDecimals[token];
        if (decimals == 0) {
            decimals = 18;
        }
        if (decimals >= 18) {
            return price / (10 ** (decimals - 18));
        } else {
            return price * (10 ** (18 - decimals));
        }
    }

    /// @notice Validate secondary oracle prices
    function _validateSecondaryOracle(
        address token0,
        address token1,
        int256 price0,
        int256 price1
    ) internal view {
        address secondaryFeed0 = secondaryPriceFeeds[token0];
        address secondaryFeed1 = secondaryPriceFeeds[token1];

        if (secondaryFeed0 != address(0) && secondaryFeed1 != address(0)) {
            AggregatorV3Interface feed0 = AggregatorV3Interface(secondaryFeed0);
            AggregatorV3Interface feed1 = AggregatorV3Interface(secondaryFeed1);

            (, int256 secondaryPrice0, , uint256 updatedAt0, ) = feed0.latestRoundData();
            (, int256 secondaryPrice1, , uint256 updatedAt1, ) = feed1.latestRoundData();

            if (secondaryPrice0 <= 0 || secondaryPrice1 <= 0) revert InvalidOraclePrice();
            if (block.timestamp - updatedAt0 > maxPriceFeedAge) revert StaleSecondaryFeed();
            if (block.timestamp - updatedAt1 > maxPriceFeedAge) revert StaleSecondaryFeed();

            uint256 deviation0 = _calculateDeviation(uint256(price0), uint256(secondaryPrice0));
            uint256 deviation1 = _calculateDeviation(uint256(price1), uint256(secondaryPrice1));

            if (deviation0 > secondaryOracleDeviationBps) revert SecondaryPriceDeviationTooHigh();
            if (deviation1 > secondaryOracleDeviationBps) revert SecondaryPriceDeviationTooHigh();
        }
    }

    /// @notice Validate price deviation with caching
    function _validatePriceDeviationWithCache(
        uint256 amountIn,
        uint256 expectedAmountOut,
        uint256 oraclePrice0,
        uint256 oraclePrice1
    ) internal view {
        if (amountIn == 0) revert InvalidAmount();
        if (expectedAmountOut == 0) revert InvalidAmount();

        uint256 expectedPrice = (expectedAmountOut * PRICE_PRECISION) / amountIn;
        uint256 oraclePrice = (oraclePrice0 * PRICE_PRECISION) / oraclePrice1;

        uint256 deviation = _calculateDeviation(oraclePrice, expectedPrice);
        if (deviation > oracleDeviationBps) revert PriceDeviationTooHigh();
    }

    /// @notice Calculate price deviation in BPS
    /// @param price1 First price
    /// @param price2 Second price
    /// @return Deviation in BPS
    function _calculateDeviation(uint256 price1, uint256 price2)
        internal
        pure
        returns (uint256)
    {
        if (price1 == 0 || price2 == 0) revert InvalidOraclePrice();

        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 base = price1 > price2 ? price1 : price2;

        return (diff * BPS_DENOMINATOR) / base;
    }

    // ============ IFlashLoanSimpleReceiver FUNCTIONS ============
    /// @notice Return Aave V3 addresses provider
    function ADDRESSES_PROVIDER()
        external
        view
        override
        returns (IPoolAddressesProvider)
    {
        return IPoolAddressesProvider(aaveV3AddressesProvider);
    }

    /// @notice Return Aave V3 pool
    function POOL() external view override returns (IPool) {
        return aaveV3Pool;
    }

    // ============ CORE ARBITRAGE LOGIC ============
    /// @notice Execute flash loan callback and arbitrage
    /// @dev Called by Aave V3 pool during flash loan
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override nonReentrant returns (bool) {
        // CRITICAL FIX: Verify flash loan caller is Aave V3 Pool
        if (msg.sender != address(aaveV3Pool)) revert UnauthorizedCaller();
        if (initiator != address(this)) revert InvalidInitiator();
        if (paused) revert ContractPaused();

        (uint256 routeId, bool quietEvents) = abi.decode(params, (uint256, bool));
        if (routeId >= routeCount) revert InvalidRouteId();

        ArbitrageRoute memory route = routes[routeId];
        if (route.path.length < MIN_PATH_LENGTH) revert InvalidRoutePath();

        uint256 startGas = gasleft();

        // CRITICAL FIX: Add deadline to all swaps
        uint256 deadline = block.timestamp + deadlineSeconds;

        uint256 finalAmount = _executeArbitrage(
            route.path,
            amount,
            route.dexA,
            route.dexB,
            maxSlippageBps,
            deadline
        );

        uint256 amountOwed = amount + premium;
        if (finalAmount < amountOwed) revert InsufficientOutput();

        uint256 profit = finalAmount - amountOwed;

        if (profit < route.minProfit) revert ProfitBelowMinimum();
        if (profit < _calculateBps(amount, minProfitBps)) revert ProfitBelowMinimum();
        if (profit < minProfitAbsolute) revert ProfitBelowAbsoluteMinimum();

        uint256 gasUsed = startGas - gasleft();

        if (!quietEvents) {
            emit ArbitrageSuccess(asset, amount, profit, routeId, gasUsed);
        }

        _distributeProfitToBeneficiary(asset, profit);

        // CRITICAL FIX: Check return value of approval
        if (!IERC20(asset).approve(address(aaveV3Pool), amountOwed)) revert ApprovalFailed();

        return true;
    }

    /// @notice Distribute profit to beneficiary
    function _distributeProfitToBeneficiary(address asset, uint256 profit) internal {
        if (beneficiary != address(0) && profit > 0) {
            uint256 beneficiaryShare = _calculateBps(profit, beneficiaryShareBps);
            if (beneficiaryShare > 0) {
                IERC20(asset).safeTransfer(beneficiary, beneficiaryShare);
                emit ProfitDistributed(beneficiary, beneficiaryShare);
            }
        }
    }

    /// @notice Execute arbitrage across two DEXs
    function _executeArbitrage(
        address[] memory path,
        uint256 amountIn,
        DEXType dexA,
        DEXType dexB,
        uint256 slippageBps,
        uint256 deadline
    ) internal validPathLength(path.length) returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmount();

        uint256 leg1Out = _executeDexSwap(
            path[0],
            path[path.length - 1],
            amountIn,
            dexA,
            slippageBps,
            deadline
        );
        if (leg1Out == 0) revert SwapFailed();

        uint256 leg2Out = _executeDexSwap(
            path[path.length - 1],
            path[0],
            leg1Out,
            dexB,
            slippageBps,
            deadline
        );
        if (leg2Out == 0) revert SwapFailed();

        return leg2Out;
    }

    /// @notice Execute swap on specified DEX
    function _executeDexSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        DEXType dexType,
        uint256 slippageBps,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        if (dexType == DEXType.UNISWAP_V3) {
            return _executeUniswapV3Swap(tokenIn, tokenOut, amountIn, slippageBps, deadline);
        } else {
            return _executeSushiswapSwap(tokenIn, tokenOut, amountIn, slippageBps, deadline);
        }
    }

    /// @notice Execute Uniswap V3 swap with router validation
    function _executeUniswapV3Swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps,
        uint256 deadline
    ) internal returns (uint256) {
        address router = getDEXRouter(DEXType.UNISWAP_V3);
        if (!whitelistedRouters[router]) revert RouterNotWhitelisted();

        IERC20(tokenIn).forceApprove(router, amountIn);

        bytes memory encodedPath = abi.encodePacked(tokenIn, defaultUniV3Fee, tokenOut);
        uint256 minAmountOut = (amountIn * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;

        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: encodedPath,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        return ISwapRouter(router).exactInput(swapParams);
    }

    /// @notice Execute Sushiswap swap with router validation
    function _executeSushiswapSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps,
        uint256 deadline
    ) internal returns (uint256) {
        address router = getDEXRouter(DEXType.SUSHISWAP);
        if (!whitelistedRouters[router]) revert RouterNotWhitelisted();

        IERC20(tokenIn).forceApprove(router, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256 minAmountOut = (amountIn * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;

        uint256[] memory amounts = IUniswapV2Router02(router).swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            deadline
        );

        return amounts[amounts.length - 1];
    }

    // ============ PUBLIC ARBITRAGE FUNCTIONS ============
    /// @notice Initiate arbitrage execution
    /// @param asset Token to borrow
    /// @param amount Amount to borrow
    /// @param routeId Route configuration ID
    /// @param quietEvents Suppress events if true
    function initiateArbitrage(
        address asset,
        uint256 amount,
        uint256 routeId,
        bool quietEvents
    ) external nonReentrant onlyOwner whenNotPaused {
        if (asset == address(0)) revert InvalidAsset();
        if (amount == 0) revert InvalidAmount();
        if (amount > maxLoanAmount) revert ExceedsMaxLoan();
        if (routeId >= routeCount) revert InvalidRouteId();
        if (!isTokenSupported(asset)) revert UnsupportedToken();

        if (enforceProfitabilityCheck) {
            ArbitrageRoute memory route = routes[routeId];
            ProfitabilityQuote memory quote = this.calculateProfitability(
                route.path,
                amount,
                route.dexA,
                route.dexB
            );

            if (!quote.isProfitable) revert TradNotProfitable();
            emit ProfitabilityCheckPassed(routeId, quote.expectedNetProfit);
        }

        emit ArbitrageInitiated(asset, amount, routeId);
        bytes memory params = abi.encode(routeId, quietEvents);
        aaveV3Pool.flashLoanSimple(address(this), asset, amount, params, 0);
    }

    // ============ ROUTE MANAGEMENT ============
    /// @notice Internal route addition with validation
    function _addRouteInternal(
        address[] calldata path,
        uint256 minProfit,
        DEXType dexA,
        DEXType dexB
    ) internal validPathLength(path.length) {
        if (path[0] != path[path.length - 1]) revert CircularPathRequired();
        if (dexRouters[dexA] == address(0)) revert DEXNotConfigured();
        if (dexRouters[dexB] == address(0)) revert DEXNotConfigured();

        // Validate tokens and check for duplicates
        for (uint256 i = 0; i < path.length; i++) {
            if (path[i] == address(0)) revert InvalidTokenAddress();
            if (!isTokenSupported(path[i])) revert UnsupportedToken();
            for (uint256 j = i + 1; j < path.length - 1; j++) {
                if (path[i] == path[j]) revert DuplicateTokenInPath();
            }
        }

        routes[routeCount] = ArbitrageRoute({
            routeId: routeCount,
            path: path,
            minProfit: minProfit,
            dexA: dexA,
            dexB: dexB
        });
        emit RoutesUpdated(routeCount, path.length);
        routeCount++;
    }

    /// @notice Add new arbitrage route
    function addRoute(
        address[] calldata path,
        uint256 minProfit,
        DEXType dexA,
        DEXType dexB
    ) external onlyOwner {
        _addRouteInternal(path, minProfit, dexA, dexB);
    }

    /// @notice Add multiple routes in batch
    function addRoutesBatch(
        address[][] calldata paths,
        uint256[] calldata minProfits,
        DEXType[] calldata dexAs,
        DEXType[] calldata dexBs
    ) external onlyOwner {
        if (
            paths.length != minProfits.length ||
            minProfits.length != dexAs.length ||
            dexAs.length != dexBs.length
        ) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < paths.length; i++) {
            _addRouteInternal(paths[i], minProfits[i], dexAs[i], dexBs[i]);
        }
    }

    /// @notice Update existing route
    function updateRoute(
        uint256 routeId,
        address[] calldata path,
        uint256 minProfit,
        DEXType dexA,
        DEXType dexB
    ) external onlyOwner validPathLength(path.length) {
        if (routeId >= routeCount) revert InvalidRouteId();
        if (path[0] != path[path.length - 1]) revert CircularPathRequired();
        if (dexRouters[dexA] == address(0)) revert DEXNotConfigured();
        if (dexRouters[dexB] == address(0)) revert DEXNotConfigured();

        for (uint256 i = 0; i < path.length; i++) {
            if (path[i] == address(0)) revert InvalidTokenAddress();
            if (!isTokenSupported(path[i])) revert UnsupportedToken();
            for (uint256 j = i + 1; j < path.length - 1; j++) {
                if (path[i] == path[j]) revert DuplicateTokenInPath();
            }
        }

        routes[routeId] = ArbitrageRoute({
            routeId: routeId,
            path: path,
            minProfit: minProfit,
            dexA: dexA,
            dexB: dexB
        });
        emit RoutesUpdated(routeId, path.length);
    }

    /// @notice Get route by ID
    function getRoute(uint256 routeId) external view returns (ArbitrageRoute memory) {
        if (routeId >= routeCount) revert InvalidRouteId();
        return routes[routeId];
    }

    /// @notice Get total number of routes
    function getRouteCount() external view returns (uint256) {
        return routeCount;
    }

    /// @notice Get routes with pagination
    function getAllRoutes(uint256 offset, uint256 limit)
        external
        view
        returns (ArbitrageRoute[] memory)
    {
        if (offset >= routeCount) revert InvalidRouteId();

        uint256 end = offset + limit;
        if (end > routeCount) {
            end = routeCount;
        }

        ArbitrageRoute[] memory result = new ArbitrageRoute[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = routes[i];
        }
        return result;
    }

    /// @notice Delete route by ID
    function deleteRoute(uint256 routeId) external onlyOwner {
        if (routeId >= routeCount) revert InvalidRouteId();
        if (routeId != routeCount - 1) {
            routes[routeId] = routes[routeCount - 1];
            routes[routeId].routeId = routeId;
        }
        delete routes[routeCount - 1];
        routeCount--;
        emit RouteDeleted(routeId);
    }

    // ============ CONFIGURATION MANAGEMENT ============
    /// @notice Set token support status
    function setTokenSupported(address token, bool supported) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        supportedTokens[token] = supported;
        emit TokenSupportChanged(token, supported);
    }

    /// @notice Set multiple tokens support status
    function setTokensSupportedBatch(address[] calldata tokens, bool[] calldata supported)
        external
        onlyOwner
    {
        if (tokens.length != supported.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidToken();
            supportedTokens[tokens[i]] = supported[i];
            emit TokenSupportChanged(tokens[i], supported[i]);
        }
    }

    /// @notice Check if token is supported
    function isTokenSupported(address token) public view returns (bool) {
        return supportedTokens[token];
    }

    /// @notice Set token decimals
    function setTokenDecimals(address token, uint8 decimals) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        tokenDecimals[token] = decimals;
        emit TokenDecimalsSet(token, decimals);
    }

    /// @notice Get token decimals
    function getTokenDecimals(address token) external view returns (uint8) {
        uint8 decimals = tokenDecimals[token];
        if (decimals == 0) {
            try IERC20Metadata(token).decimals() returns (uint8 d) {
                return d;
            } catch {
                return 18;
            }
        }
        return decimals;
    }

    /// @notice Set price feed for token
    function setPriceFeed(address token, address feed) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        if (feed == address(0)) revert InvalidFeed();
        priceFeeds[token] = feed;
        emit PriceFeedSet(token, feed);
    }

    /// @notice Set secondary price feed for token
    function setSecondaryPriceFeed(address token, address feed) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        if (feed == address(0)) revert InvalidFeed();
        secondaryPriceFeeds[token] = feed;
        emit SecondaryPriceFeedSet(token, feed);
    }

    /// @notice Set multiple price feeds
    function setPriceFeedsBatch(address[] calldata tokens, address[] calldata feeds)
        external
        onlyOwner
    {
        if (tokens.length != feeds.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidToken();
            if (feeds[i] == address(0)) revert InvalidFeed();
            priceFeeds[tokens[i]] = feeds[i];
            emit PriceFeedSet(tokens[i], feeds[i]);
        }
    }

    /// @notice Get price feed for token
    function getPriceFeed(address token) external view returns (address) {
        return priceFeeds[token];
    }

    /// @notice Set DEX router
    function setDEXRouter(DEXType dexType, address router) external onlyOwner {
        if (router == address(0)) revert InvalidRouter();
        dexRouters[dexType] = router;
        whitelistedRouters[router] = true;
        emit DEXRouterSet(dexType, router);
    }

    /// @notice Get DEX router
    function getDEXRouter(DEXType dexType) public view returns (address) {
        address router = dexRouters[dexType];
        if (router == address(0)) revert DEXNotConfigured();
        return router;
    }

    /// @notice Set DEX quoter
    function setDEXQuoter(DEXType dexType, address quoter) external onlyOwner {
        if (quoter == address(0)) revert InvalidQuoter();
        dexQuoters[dexType] = quoter;
        emit DEXQuoterSet(dexType, quoter);
    }

    /// @notice Get DEX quoter
    function getDEXQuoter(DEXType dexType) public view returns (address) {
        return dexQuoters[dexType];
    }

    /// @notice Whitelist router for swaps
    function whitelistRouter(address router, bool whitelisted) external onlyOwner {
        if (router == address(0)) revert InvalidRouter();
        whitelistedRouters[router] = whitelisted;
        emit RouterWhitelisted(router, whitelisted);
    }

    /// @notice Check if router is whitelisted
    function isRouterWhitelisted(address router) external view returns (bool) {
        return whitelistedRouters[router];
    }

    /// @notice Set protocol addresses
    function setProtocolAddresses(address _aaveV3Provider, address _weth) external onlyOwner {
        if (_aaveV3Provider == address(0)) revert InvalidProvider();
        if (_weth == address(0)) revert InvalidToken();

        aaveV3AddressesProvider = _aaveV3Provider;
        weth = _weth;

        emit ProtocolAddressesSet(_aaveV3Provider, _weth);
    }

    /// @notice Update risk parameters
    function updateRiskParams(
        uint256 _minProfitBps,
        uint256 _maxSlippageBps,
        uint256 _deadlineSeconds,
        uint256 _gasUnitsEstimate
    ) external onlyOwner {
        if (_minProfitBps > BPS_DENOMINATOR) revert InvalidBps();
        if (_maxSlippageBps > BPS_DENOMINATOR) revert InvalidBps();
        if (_deadlineSeconds == 0) revert InvalidAmount();
        if (_gasUnitsEstimate == 0) revert InvalidAmount();

        minProfitBps = _minProfitBps;
        maxSlippageBps = _maxSlippageBps;
        deadlineSeconds = _deadlineSeconds;
        gasUnitsEstimate = _gasUnitsEstimate;

        emit RiskParamsUpdated(
            _minProfitBps,
            _maxSlippageBps,
            _deadlineSeconds,
            _gasUnitsEstimate
        );
    }

    /// @notice Update oracle parameters
    function updateOracleParams(
        uint256 _maxPriceFeedAge,
        uint256 _oracleDeviationBps,
        uint256 _secondaryOracleDeviationBps
    ) external onlyOwner {
        if (_maxPriceFeedAge == 0) revert InvalidAmount();
        if (_oracleDeviationBps > BPS_DENOMINATOR) revert InvalidBps();
        if (_secondaryOracleDeviationBps > BPS_DENOMINATOR) revert InvalidBps();

        maxPriceFeedAge = _maxPriceFeedAge;
        oracleDeviationBps = _oracleDeviationBps;
        secondaryOracleDeviationBps = _secondaryOracleDeviationBps;

        emit OracleParamsUpdated(
            _maxPriceFeedAge,
            _oracleDeviationBps,
            _secondaryOracleDeviationBps
        );
    }

    /// @notice Update profitability parameters
    function updateProfitabilityParams(
        uint256 _builderTipBps,
        uint256 _safetyBufferBps,
        uint256 _flashLoanPremiumBps,
        uint256 _gasPrice
    ) external onlyOwner {
        if (_builderTipBps > BPS_DENOMINATOR) revert InvalidBps();
        if (_safetyBufferBps > BPS_DENOMINATOR) revert InvalidBps();
        if (_flashLoanPremiumBps > BPS_DENOMINATOR) revert InvalidBps();
        if (_gasPrice == 0) revert InvalidAmount();

        builderTipBps = _builderTipBps;
        safetyBufferBps = _safetyBufferBps;
        flashLoanPremiumBps = _flashLoanPremiumBps;
        gasPrice = _gasPrice;

        emit ProfitabilityParamsUpdated(
            _builderTipBps,
            _safetyBufferBps,
            _flashLoanPremiumBps,
            _gasPrice
        );
    }

    /// @notice Set Uniswap V3 fee tier
    function setDefaultUniV3Fee(uint24 fee) external onlyOwner {
        if (fee != 500 && fee != 3000 && fee != 10_000) revert InvalidFee();
        defaultUniV3Fee = fee;
        emit UniV3FeeUpdated(fee);
    }

    /// @notice Set beneficiary address
    function setBeneficiary(address _beneficiary) external onlyOwner {
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        beneficiary = _beneficiary;
        emit BeneficiaryUpdated(_beneficiary);
    }

    /// @notice Set beneficiary share
    function setBeneficiaryShare(uint256 _beneficiaryShareBps) external onlyOwner {
        if (_beneficiaryShareBps > MAX_BENEFICIARY_BPS) revert BeneficiaryShareExceedsMax();
        beneficiaryShareBps = _beneficiaryShareBps;
        emit BeneficiaryShareUpdated(_beneficiaryShareBps);
    }

    /// @notice Enable/disable auto WETH unwrap
    function setAutoUnwrapWETH(bool enabled) external onlyOwner {
        autoUnwrapWETH = enabled;
        emit AutoUnwrapWETHUpdated(enabled);
    }

    /// @notice Enable/disable profitability check enforcement
    function setEnforceProfitabilityCheck(bool enabled) external onlyOwner {
        enforceProfitabilityCheck = enabled;
        emit EnforceProfitabilityCheckUpdated(enabled);
    }

    /// @notice Enable/disable secondary oracle enforcement
    function setEnforceSecondaryOracle(bool enabled) external onlyOwner {
        enforceSecondaryOracle = enabled;
        emit EnforceSecondaryOracleUpdated(enabled);
    }

    /// @notice Pause/unpause contract
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedStateChanged(_paused);
    }

    /// @notice Check if contract is paused
    function isPaused() external view returns (bool) {
        return paused;
    }

    /// @notice Set maximum loan amount
    function setMaxLoanAmount(uint256 _maxLoanAmount) external onlyOwner {
        if (_maxLoanAmount == 0) revert InvalidAmount();
        maxLoanAmount = _maxLoanAmount;
        emit MaxLoanAmountUpdated(_maxLoanAmount);
    }

    /// @notice Set minimum absolute profit
    function setMinProfitAbsolute(uint256 _minProfitAbsolute) external onlyOwner {
        minProfitAbsolute = _minProfitAbsolute;
        emit MinProfitAbsoluteUpdated(_minProfitAbsolute);
    }

    // ============ EMERGENCY WITHDRAWAL FUNCTIONS ============
    /// @notice Emergency withdraw token
    function emergencyWithdraw(address token) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NoBalance();
        IERC20(token).safeTransfer(owner(), balance);
        emit EmergencyWithdrawal(token, balance);
    }

    /// @notice Withdraw ETH
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoBalance();
        (bool success, ) = owner().call{value: balance}("");
        if (!success) revert ETHTransferFailed();
        emit ETHWithdrawn(balance);
    }

    /// @notice Emergency cleanup of multiple tokens
    function emergencyCleanup(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokens[i]).safeTransfer(owner(), balance);
                emit EmergencyWithdrawal(tokens[i], balance);
            }
        }
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success, ) = owner().call{value: ethBalance}("");
            if (!success) revert ETHTransferFailed();
            emit ETHWithdrawn(ethBalance);
        }
    }

    /// @notice Update Aave V3 addresses provider
    function updateAddressesProvider(IPoolAddressesProvider _newProvider) external onlyOwner {
        if (address(_newProvider) == address(0)) revert InvalidProvider();
        aaveV3AddressesProvider = address(_newProvider);
    }

    /// @notice Update Aave V3 pool
    function updateAaveV3Pool(IPool _newPool) external onlyOwner {
        if (address(_newPool) == address(0)) revert InvalidPool();
        aaveV3Pool = _newPool;
    }

    /// @notice Receive ETH
    receive() external payable {}
}