// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title ArbitrageAnalyzer
 * @notice Pure analysis contract for identifying optimal arbitrage parameters
 * @dev Performs statistical analysis on historical trade data and recommends parameters
 * Does NOT execute trades or interact with DEXs
 */
contract ArbitrageAnalyzer {
    // ============ CUSTOM ERRORS ============
    error InvalidInput();
    error InsufficientData();
    error ArrayLengthMismatch();
    error DivisionByZero();
    error InvalidTokenAddress();
    error InvalidPriceFeed();

    // ============ CONSTANTS ============
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MAX_TRADES = 1000;

    // ============ STRUCTS ============
    /// @notice Historical trade data point
    struct TradeData {
        uint256 profit; // In Wei
        uint256 gasUsed; // Gas units
        uint256 slippage; // In BPS
        uint256 executionTime; // In seconds
    }

    /// @notice Statistical analysis result
    struct StatisticalAnalysis {
        uint256 meanProfit;
        uint256 medianProfit;
        uint256 stdDeviation;
        uint256 minProfit;
        uint256 maxProfit;
        uint256 successRate; // In BPS (e.g., 9500 = 95%)
        uint256 averageGasUsed;
        uint256 totalTrades;
    }

    /// @notice Parameter recommendation
    struct ParameterRecommendation {
        uint256 minProfitBps;
        uint256 maxSlippageBps;
        uint256 deadlineSeconds;
        uint256 gasUnitsEstimate;
        uint256 confidence; // In BPS (e.g., 8500 = 85%)
        string reasoning;
    }

    /// @notice Profitability breakdown
    struct ProfitabilityBreakdown {
        uint256 borrowAmount;
        uint256 flashLoanFee;
        uint256 gasCost;
        uint256 builderTip;
        uint256 safetyBuffer;
        uint256 totalCosts;
        uint256 grossProfit;
        uint256 netProfit;
        uint256 roi; // In BPS
        bool isProfitable;
        CostPercentages costBreakdown;
    }

    /// @notice Cost percentages breakdown
    struct CostPercentages {
        uint256 flashLoanFeePercent; // In BPS
        uint256 gasCostPercent; // In BPS
        uint256 builderTipPercent; // In BPS
        uint256 safetyBufferPercent; // In BPS
    }

    /// @notice Sensitivity analysis result
    struct SensitivityResult {
        uint256 gasPrice;
        uint256 flashLoanPremiumBps;
        uint256 netProfit;
        uint256 roi; // In BPS
    }

    /// @notice Backtest result
    struct BacktestResult {
        uint256 minProfitBps;
        uint256 maxSlippageBps;
        uint256 successCount;
        uint256 totalProfit;
        uint256 roi; // In BPS
    }

    /// @notice Opportunity analysis
    struct OpportunityAnalysis {
        address tokenA;
        address tokenB;
        string dexA;
        string dexB;
        uint256 priceA; // In PRECISION
        uint256 priceB; // In PRECISION
        uint256 priceDifference; // In PRECISION
        uint256 profitabilityBps;
        uint256 timestamp;
        uint256 blockNumber;
    }

    /// @notice Optimal borrow amount result
    struct OptimalBorrowResult {
        uint256 optimalAmount;
        uint256 maxProfit;
        ProfitabilityBreakdown profitability;
    }

    // ============ EVENTS ============
    event AnalysisPerformed(
        uint256 indexed tradeCount,
        uint256 meanProfit,
        uint256 successRate
    );
    event ParametersRecommended(
        uint256 minProfitBps,
        uint256 maxSlippageBps,
        uint256 confidence
    );
    event ProfitabilityCalculated(
        uint256 borrowAmount,
        uint256 netProfit,
        bool isProfitable
    );
    event SensitivityAnalysisPerformed(uint256 scenarioCount);
    event BacktestCompleted(uint256 scenarioCount, uint256 bestRoi);

    // ============ ANALYSIS FUNCTIONS ============

    /**
     * @notice Analyze historical trade data and generate statistics
     * @param trades Array of historical trade data
     * @return StatisticalAnalysis with computed metrics
     */
    function analyzeHistoricalTrades(TradeData[] calldata trades)
        external
        returns (StatisticalAnalysis memory)
    {
        if (trades.length == 0) revert InsufficientData();
        if (trades.length > MAX_TRADES) revert InvalidInput();

        uint256 totalProfit = 0;
        uint256 totalGasUsed = 0;
        uint256 successCount = 0;
        uint256 minProfit = type(uint256).max;
        uint256 maxProfit = 0;

        // First pass: calculate sums and extremes
        for (uint256 i = 0; i < trades.length; i++) {
            totalProfit += trades[i].profit;
            totalGasUsed += trades[i].gasUsed;

            if (trades[i].profit > 0) {
                successCount++;
            }

            if (trades[i].profit < minProfit) {
                minProfit = trades[i].profit;
            }
            if (trades[i].profit > maxProfit) {
                maxProfit = trades[i].profit;
            }
        }

        uint256 meanProfit = totalProfit / trades.length;
        uint256 averageGasUsed = totalGasUsed / trades.length;
        uint256 successRate = (successCount * BPS_DENOMINATOR) / trades.length;

        // Calculate median
        uint256 medianProfit = _calculateMedian(_sortProfits(trades));

        // Calculate standard deviation
        uint256 stdDeviation = _calculateStdDeviation(trades, meanProfit);

        emit AnalysisPerformed(trades.length, meanProfit, successRate);

        return
            StatisticalAnalysis({
                meanProfit: meanProfit,
                medianProfit: medianProfit,
                stdDeviation: stdDeviation,
                minProfit: minProfit == type(uint256).max ? 0 : minProfit,
                maxProfit: maxProfit,
                successRate: successRate,
                averageGasUsed: averageGasUsed,
                totalTrades: trades.length
            });
    }

    /**
     * @notice Generate parameter recommendations based on analysis
     * @param analysis StatisticalAnalysis from analyzeHistoricalTrades
     * @param trades Original trade data for slippage and execution time analysis
     * @return ParameterRecommendation with suggested parameters
     */
    function generateParameterRecommendations(
        StatisticalAnalysis calldata analysis,
        TradeData[] calldata trades
    ) external returns (ParameterRecommendation memory) {
        if (trades.length == 0) revert InsufficientData();

        // Conservative minProfitBps: mean - 1 std dev
        uint256 minProfitBps = analysis.meanProfit > analysis.stdDeviation
            ? ((analysis.meanProfit - analysis.stdDeviation) * BPS_DENOMINATOR) / 1e18
            : 50;
        minProfitBps = minProfitBps < 50 ? 50 : minProfitBps;

        // Max slippage: 95th percentile of observed slippages
        uint256 maxSlippageBps = _calculatePercentile(
            _sortSlippages(trades),
            95
        );

        // Deadline: 99th percentile of execution times + 30 second buffer
        uint256 deadlineSeconds = _calculatePercentile(
            _sortExecutionTimes(trades),
            99
        ) + 30;

        // Gas estimate: average + 50%
        uint256 gasUnitsEstimate = (analysis.averageGasUsed * 150) / 100;

        // Confidence: based on consistency (inverse of coefficient of variation)
        uint256 confidence = analysis.meanProfit > 0
            ? _calculateConfidence(analysis.meanProfit, analysis.stdDeviation)
            : 0;

        string memory reasoning = _generateReasoning(
            analysis.totalTrades,
            analysis.successRate
        );

        emit ParametersRecommended(minProfitBps, maxSlippageBps, confidence);

        return
            ParameterRecommendation({
                minProfitBps: minProfitBps,
                maxSlippageBps: maxSlippageBps,
                deadlineSeconds: deadlineSeconds,
                gasUnitsEstimate: gasUnitsEstimate,
                confidence: confidence,
                reasoning: reasoning
            });
    }

    /**
     * @notice Calculate detailed profitability for a specific trade scenario
     * @param borrowAmount Amount to borrow in Wei
     * @param flashLoanPremiumBps Flash loan premium in BPS
     * @param gasPrice Gas price in Wei
     * @param gasUnitsEstimate Estimated gas units
     * @param leg1AmountOut Expected output from first leg in Wei
     * @param leg2AmountOut Expected output from second leg in Wei
     * @param builderTipBps Builder tip in BPS
     * @param safetyBufferBps Safety buffer in BPS
     * @return ProfitabilityBreakdown with detailed cost analysis
     */
    function calculateProfitability(
        uint256 borrowAmount,
        uint256 flashLoanPremiumBps,
        uint256 gasPrice,
        uint256 gasUnitsEstimate,
        uint256 leg1AmountOut,
        uint256 leg2AmountOut,
        uint256 builderTipBps,
        uint256 safetyBufferBps
    ) external returns (ProfitabilityBreakdown memory) {
        if (borrowAmount == 0) revert InvalidInput();
        if (leg1AmountOut == 0 || leg2AmountOut == 0) revert InvalidInput();

        // Calculate costs
        uint256 flashLoanFee = (borrowAmount * flashLoanPremiumBps) /
            BPS_DENOMINATOR;
        uint256 gasCost = gasPrice * gasUnitsEstimate;
        uint256 builderTip = (borrowAmount * builderTipBps) / BPS_DENOMINATOR;
        uint256 safetyBuffer = (borrowAmount * safetyBufferBps) /
            BPS_DENOMINATOR;

        uint256 totalCosts = flashLoanFee + gasCost + builderTip + safetyBuffer;

        // Calculate profit
        uint256 grossProfit = leg2AmountOut > borrowAmount
            ? leg2AmountOut - borrowAmount
            : 0;
        uint256 netProfit = grossProfit > totalCosts
            ? grossProfit - totalCosts
            : 0;

        // Calculate ROI in BPS
        uint256 roi = borrowAmount > 0
            ? (netProfit * BPS_DENOMINATOR) / borrowAmount
            : 0;

        // Calculate cost percentages
        CostPercentages memory costBreakdown;
        if (totalCosts > 0) {
            costBreakdown.flashLoanFeePercent = (flashLoanFee *
                BPS_DENOMINATOR) / totalCosts;
            costBreakdown.gasCostPercent = (gasCost * BPS_DENOMINATOR) /
                totalCosts;
            costBreakdown.builderTipPercent = (builderTip * BPS_DENOMINATOR) /
                totalCosts;
            costBreakdown.safetyBufferPercent = (safetyBuffer *
                BPS_DENOMINATOR) / totalCosts;
        }

        bool isProfitable = netProfit > 0;

        emit ProfitabilityCalculated(borrowAmount, netProfit, isProfitable);

        return
            ProfitabilityBreakdown({
                borrowAmount: borrowAmount,
                flashLoanFee: flashLoanFee,
                gasCost: gasCost,
                builderTip: builderTip,
                safetyBuffer: safetyBuffer,
                totalCosts: totalCosts,
                grossProfit: grossProfit,
                netProfit: netProfit,
                roi: roi,
                isProfitable: isProfitable,
                costBreakdown: costBreakdown
            });
    }

    /**
     * @notice Find optimal borrow amount for maximum profit
     * @param minBorrowAmount Minimum borrow amount in Wei
     * @param maxBorrowAmount Maximum borrow amount in Wei
     * @param step Step size for iteration in Wei
     * @param priceRatio Expected ratio of leg2Out / leg1Out (in PRECISION)
     * @param flashLoanPremiumBps Flash loan premium in BPS
     * @param gasPrice Gas price in Wei
     * @param gasUnitsEstimate Estimated gas units
     * @param builderTipBps Builder tip in BPS
     * @param safetyBufferBps Safety buffer in BPS
     * @return OptimalBorrowResult with optimal amount and profitability
     */
    function findOptimalBorrowAmount(
        uint256 minBorrowAmount,
        uint256 maxBorrowAmount,
        uint256 step,
        uint256 priceRatio,
        uint256 flashLoanPremiumBps,
        uint256 gasPrice,
        uint256 gasUnitsEstimate,
        uint256 builderTipBps,
        uint256 safetyBufferBps
    ) external returns (OptimalBorrowResult memory) {
        if (minBorrowAmount == 0 || maxBorrowAmount == 0) revert InvalidInput();
        if (minBorrowAmount > maxBorrowAmount) revert InvalidInput();
        if (step == 0) revert InvalidInput();
        if (priceRatio == 0) revert InvalidInput();

        uint256 maxProfit = 0;
        uint256 optimalAmount = minBorrowAmount;

        uint256 current = minBorrowAmount;
        while (current <= maxBorrowAmount) {
            uint256 currentLeg1Out = current;
            uint256 currentLeg2Out = (currentLeg1Out * priceRatio) / PRECISION;

            ProfitabilityBreakdown memory profitability = this
                .calculateProfitability(
                    current,
                    flashLoanPremiumBps,
                    gasPrice,
                    gasUnitsEstimate,
                    currentLeg1Out,
                    currentLeg2Out,
                    builderTipBps,
                    safetyBufferBps
                );

            if (profitability.netProfit > maxProfit) {
                maxProfit = profitability.netProfit;
                optimalAmount = current;
            }

            current += step;
        }

        // Calculate final profitability at optimal amount
        uint256 optimalLeg1Out = optimalAmount;
        uint256 optimalLeg2Out = (optimalLeg1Out * priceRatio) / PRECISION;

        ProfitabilityBreakdown memory finalProfitability = this
            .calculateProfitability(
                optimalAmount,
                flashLoanPremiumBps,
                gasPrice,
                gasUnitsEstimate,
                optimalLeg1Out,
                optimalLeg2Out,
                builderTipBps,
                safetyBufferBps
            );

        return
            OptimalBorrowResult({
                optimalAmount: optimalAmount,
                maxProfit: maxProfit,
                profitability: finalProfitability
            });
    }

    /**
     * @notice Perform sensitivity analysis on parameter variations
     * @param baseProfit Base profit amount in Wei
     * @param baseBorrowAmount Base borrow amount in Wei
     * @param gasPrices Array of gas prices to test in Wei
     * @param flashLoanPremiums Array of flash loan premiums to test in BPS
     * @param gasUnitsEstimate Estimated gas units
     * @param builderTipBps Builder tip in BPS
     * @param safetyBufferBps Safety buffer in BPS
     * @return Array of SensitivityResult for each combination
     */
    function sensitivityAnalysis(
        uint256 baseProfit,
        uint256 baseBorrowAmount,
        uint256[] calldata gasPrices,
        uint256[] calldata flashLoanPremiums,
        uint256 gasUnitsEstimate,
        uint256 builderTipBps,
        uint256 safetyBufferBps
    ) external returns (SensitivityResult[] memory) {
        if (gasPrices.length == 0 || flashLoanPremiums.length == 0)
            revert InvalidInput();

        uint256 resultCount = gasPrices.length * flashLoanPremiums.length;
        SensitivityResult[] memory results = new SensitivityResult[](
            resultCount
        );

        uint256 idx = 0;
        for (uint256 i = 0; i < gasPrices.length; i++) {
            for (uint256 j = 0; j < flashLoanPremiums.length; j++) {
                uint256 gasCost = gasPrices[i] * gasUnitsEstimate;
                uint256 flashLoanFee = (baseBorrowAmount *
                    flashLoanPremiums[j]) / BPS_DENOMINATOR;
                uint256 builderTip = (baseBorrowAmount * builderTipBps) /
                    BPS_DENOMINATOR;
                uint256 safetyBuffer = (baseBorrowAmount * safetyBufferBps) /
                    BPS_DENOMINATOR;

                uint256 totalCosts = gasCost +
                    flashLoanFee +
                    builderTip +
                    safetyBuffer;
                uint256 netProfit = baseProfit > totalCosts
                    ? baseProfit - totalCosts
                    : 0;
                uint256 roi = baseBorrowAmount > 0
                    ? (netProfit * BPS_DENOMINATOR) / baseBorrowAmount
                    : 0;

                results[idx] = SensitivityResult({
                    gasPrice: gasPrices[i],
                    flashLoanPremiumBps: flashLoanPremiums[j],
                    netProfit: netProfit,
                    roi: roi
                });

                idx++;
            }
        }

        emit SensitivityAnalysisPerformed(resultCount);
        return results;
    }

    /**
     * @notice Backtest parameter combinations against historical trades
     * @param trades Historical trade data
     * @param minProfitBpsArray Array of minProfitBps to test
     * @param maxSlippageBpsArray Array of maxSlippageBps to test
     * @return Array of BacktestResult for each combination
     */
    function backtestParameters(
        TradeData[] calldata trades,
        uint256[] calldata minProfitBpsArray,
        uint256[] calldata maxSlippageBpsArray
    ) external returns (BacktestResult[] memory) {
        if (trades.length == 0) revert InsufficientData();
        if (minProfitBpsArray.length == 0 || maxSlippageBpsArray.length == 0)
            revert InvalidInput();

        uint256 resultCount = minProfitBpsArray.length *
            maxSlippageBpsArray.length;
        BacktestResult[] memory results = new BacktestResult[](resultCount);

        uint256 idx = 0;
        uint256 bestRoi = 0;

        for (uint256 i = 0; i < minProfitBpsArray.length; i++) {
            for (uint256 j = 0; j < maxSlippageBpsArray.length; j++) {
                uint256 successCount = 0;
                uint256 totalProfit = 0;

                for (uint256 k = 0; k < trades.length; k++) {
                    // Check if trade meets criteria
                    uint256 profitBps = trades[k].profit > 0
                        ? (trades[k].profit * BPS_DENOMINATOR) / 1e18
                        : 0;

                    if (
                        profitBps >= minProfitBpsArray[i] &&
                        trades[k].slippage <= maxSlippageBpsArray[j]
                    ) {
                        successCount++;
                        totalProfit += trades[k].profit;
                    }
                }

                uint256 roi = successCount > 0
                    ? (totalProfit * BPS_DENOMINATOR) / trades.length
                    : 0;

                if (roi > bestRoi) {
                    bestRoi = roi;
                }

                results[idx] = BacktestResult({
                    minProfitBps: minProfitBpsArray[i],
                    maxSlippageBps: maxSlippageBpsArray[j],
                    successCount: successCount,
                    totalProfit: totalProfit,
                    roi: roi
                });

                idx++;
            }
        }

        emit BacktestCompleted(resultCount, bestRoi);
        return results;
    }

    /**
     * @notice Analyze gas efficiency of trades
     * @param trades Historical trade data with gas information
     * @param gasPrices Array of gas prices used in each trade
     * @return meanGasCost Average gas cost
     * @return profitPerGasUnit Average profit per gas unit
     * @return recommendation Text recommendation
     */
    function analyzeGasEfficiency(
        TradeData[] calldata trades,
        uint256[] calldata gasPrices
    )
        external
        pure
        returns (
            uint256 meanGasCost,
            uint256 profitPerGasUnit,
            string memory recommendation
        )
    {
        if (trades.length == 0) revert InsufficientData();
        if (trades.length != gasPrices.length) revert ArrayLengthMismatch();

        uint256 totalGasCost = 0;
        uint256 totalProfitPerGas = 0;

        for (uint256 i = 0; i < trades.length; i++) {
            uint256 gasCost = gasPrices[i] * trades[i].gasUsed;
            totalGasCost += gasCost;

            if (gasCost > 0) {
                totalProfitPerGas += (trades[i].profit * PRECISION) / gasCost;
            }
        }

        meanGasCost = totalGasCost / trades.length;
        profitPerGasUnit = totalProfitPerGas / trades.length;

        if (profitPerGasUnit > PRECISION) {
            recommendation = "Gas costs are justified by profits - CONTINUE";
        } else if (profitPerGasUnit > (PRECISION / 2)) {
            recommendation = "Gas costs are marginal - OPTIMIZE or INCREASE TRADE SIZE";
        } else {
            recommendation = "Gas costs exceed profits - RECONSIDER STRATEGY";
        }
    }

    // ============ HELPER FUNCTIONS ============

    /**
     * @notice Sort profits array for median calculation
     */
    function _sortProfits(TradeData[] calldata trades)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory profits = new uint256[](trades.length);
        for (uint256 i = 0; i < trades.length; i++) {
            profits[i] = trades[i].profit;
        }
        return _quickSort(profits, 0, int256(profits.length) - 1);
    }

    /**
     * @notice Sort slippages array
     */
    function _sortSlippages(TradeData[] calldata trades)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory slippages = new uint256[](trades.length);
        for (uint256 i = 0; i < trades.length; i++) {
            slippages[i] = trades[i].slippage;
        }
        return _quickSort(slippages, 0, int256(slippages.length) - 1);
    }

    /**
     * @notice Sort execution times array
     */
    function _sortExecutionTimes(TradeData[] calldata trades)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory times = new uint256[](trades.length);
        for (uint256 i = 0; i < trades.length; i++) {
            times[i] = trades[i].executionTime;
        }
        return _quickSort(times, 0, int256(times.length) - 1);
    }

    /**
     * @notice Quick sort implementation
     */
    function _quickSort(
        uint256[] memory arr,
        int256 left,
        int256 right
    ) private pure returns (uint256[] memory) {
        if (left < right) {
            int256 pi = _partition(arr, left, right);
            _quickSort(arr, left, pi - 1);
            _quickSort(arr, pi + 1, right);
        }
        return arr;
    }

    /**
     * @notice Partition helper for quick sort
     */
    function _partition(
        uint256[] memory arr,
        int256 left,
        int256 right
    ) private pure returns (int256) {
        uint256 pivot = arr[uint256(right)];
        int256 i = left - 1;

        for (int256 j = left; j < right; j++) {
            if (arr[uint256(j)] < pivot) {
                i++;
                (arr[uint256(i)], arr[uint256(j)]) = (
                    arr[uint256(j)],
                    arr[uint256(i)]
                );
            }
        }
        (arr[uint256(i + 1)], arr[uint256(right)]) = (
            arr[uint256(right)],
            arr[uint256(i + 1)]
        );
        return i + 1;
    }

    /**
     * @notice Calculate median from sorted array
     */
    function _calculateMedian(uint256[] memory sorted)
        private
        pure
        returns (uint256)
    {
        if (sorted.length == 0) return 0;
        if (sorted.length % 2 == 1) {
            return sorted[sorted.length / 2];
        } else {
            return
                (sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) /
                2;
        }
    }

    /**
     * @notice Calculate standard deviation
     */
    function _calculateStdDeviation(TradeData[] calldata trades, uint256 mean)
        private
        pure
        returns (uint256)
    {
        if (trades.length == 0) return 0;

        uint256 sumSquaredDiff = 0;
        for (uint256 i = 0; i < trades.length; i++) {
            uint256 diff = trades[i].profit > mean
                ? trades[i].profit - mean
                : mean - trades[i].profit;
            sumSquaredDiff += (diff * diff) / PRECISION;
        }

        uint256 variance = sumSquaredDiff / trades.length;
        return _sqrt(variance);
    }

    /**
     * @notice Calculate percentile from sorted array
     */
    function _calculatePercentile(uint256[] memory sorted, uint256 percentile)
        private
        pure
        returns (uint256)
    {
        if (sorted.length == 0) return 0;
        if (percentile >= 100) return sorted[sorted.length - 1];

        uint256 index = (sorted.length * percentile) / 100;
        return index >= sorted.length ? sorted[sorted.length - 1] : sorted[index];
    }

    /**
     * @notice Calculate confidence score
     */
    function _calculateConfidence(uint256 mean, uint256 stdDev)
        private
        pure
        returns (uint256)
    {
        if (stdDev == 0) return BPS_DENOMINATOR; // 100% confidence if no variance

        // Coefficient of variation: stdDev / mean
        uint256 cv = (stdDev * PRECISION) / mean;

        // Confidence = 1 / (1 + cv), expressed in BPS
        if (cv >= PRECISION) {
            return 0; // No confidence if cv >= 1
        }

        uint256 denominator = PRECISION + cv;
        return (PRECISION * BPS_DENOMINATOR) / denominator;
    }

    /**
     * @notice Generate reasoning string
     */
    function _generateReasoning(
        uint256 totalTrades,
        uint256 successRate
    ) private pure returns (string memory) {
        if (totalTrades < 10) {
            return "INSUFFICIENT DATA - Recommendations based on limited samples";
        }

        if (successRate >= 9000) {
            return "HIGH SUCCESS RATE - Parameters are conservative and well-tested";
        }

        if (successRate >= 7500) {
            return "GOOD SUCCESS RATE - Parameters are balanced for profitability";
        }

        if (successRate >= 5000) {
            return "MODERATE SUCCESS RATE - Parameters may need optimization";
        }

        return "LOW SUCCESS RATE - Consider more aggressive parameters or strategy review";
    }

    /**
     * @notice Integer square root using Newton's method
     */
    function _sqrt(uint256 x) private pure returns (uint256) {
        if (x == 0) return 0;
        if (x == 1) return 1;

        uint256 z = (x + 1) / 2;
        uint256 y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }
}