// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../src/ArbitrageAnalyzer.sol";

/**
 * @title AnalyzerUsageExample
 * @notice Example contract demonstrating how to use ArbitrageAnalyzer
 * @dev This is a reference implementation showing all major functions
 */
contract AnalyzerUsageExample {
    ArbitrageAnalyzer public analyzer;

    event AnalysisComplete(
        uint256 meanProfit,
        uint256 successRate,
        uint256 recommendedMinProfitBps
    );

    constructor(address _analyzer) {
        analyzer = ArbitrageAnalyzer(_analyzer);
    }

    /**
     * @notice Complete analysis pipeline
     * @dev Demonstrates the typical workflow for analyzing arbitrage opportunities
     */
    function runCompleteAnalysis()
        external
        returns (
            ArbitrageAnalyzer.StatisticalAnalysis memory,
            ArbitrageAnalyzer.ParameterRecommendation memory,
            ArbitrageAnalyzer.ProfitabilityBreakdown memory
        )
    {
        // Step 1: Create sample historical trades
        ArbitrageAnalyzer.TradeData[] memory trades = _createSampleTrades();

        // Step 2: Analyze historical data
        ArbitrageAnalyzer.StatisticalAnalysis memory analysis = analyzer
            .analyzeHistoricalTrades(trades);

        // Step 3: Generate parameter recommendations
        ArbitrageAnalyzer.ParameterRecommendation memory recommendations = analyzer
            .generateParameterRecommendations(analysis, trades);

        // Step 4: Calculate profitability for recommended parameters
        ArbitrageAnalyzer.ProfitabilityBreakdown memory profitability = analyzer
            .calculateProfitability(
                10 ether,
                recommendations.minProfitBps,
                50 gwei,
                recommendations.gasUnitsEstimate,
                10.5 ether,
                10.8 ether,
                10,
                50
            );

        emit AnalysisComplete(
            analysis.meanProfit,
            analysis.successRate,
            recommendations.minProfitBps
        );

        return (analysis, recommendations, profitability);
    }

    /**
     * @notice Find optimal borrow amount
     * @dev Demonstrates finding the best amount to borrow for maximum profit
     */
    function findOptimalAmount()
        external
        returns (ArbitrageAnalyzer.OptimalBorrowResult memory)
    {
        return analyzer.findOptimalBorrowAmount(
            1 ether,
            50 ether,
            1 ether,
            1.05e18,
            9,
            50 gwei,
            500000,
            10,
            50
        );
    }

    /**
     * @notice Run sensitivity analysis
     * @dev Shows how profit changes with different gas prices and loan premiums
     */
    function runSensitivityAnalysis()
        external
        returns (ArbitrageAnalyzer.SensitivityResult[] memory)
    {
        uint256[] memory gasPrices = new uint256[](5);
        gasPrices[0] = 20 gwei;
        gasPrices[1] = 40 gwei;
        gasPrices[2] = 60 gwei;
        gasPrices[3] = 80 gwei;
        gasPrices[4] = 100 gwei;

        uint256[] memory flashLoanPremiums = new uint256[](3);
        flashLoanPremiums[0] = 5;
        flashLoanPremiums[1] = 9;
        flashLoanPremiums[2] = 15;

        return analyzer.sensitivityAnalysis(
            0.1 ether,
            10 ether,
            gasPrices,
            flashLoanPremiums,
            500000,
            10,
            50
        );
    }

    /**
     * @notice Backtest parameter combinations
     * @dev Tests which parameter combinations would have been most successful historically
     */
    function runBacktest()
        external
        returns (ArbitrageAnalyzer.BacktestResult[] memory)
    {
        ArbitrageAnalyzer.TradeData[] memory trades = _createSampleTrades();

        uint256[] memory minProfitBps = new uint256[](4);
        minProfitBps[0] = 50;
        minProfitBps[1] = 100;
        minProfitBps[2] = 150;
        minProfitBps[3] = 200;

        uint256[] memory maxSlippageBps = new uint256[](3);
        maxSlippageBps[0] = 200;
        maxSlippageBps[1] = 300;
        maxSlippageBps[2] = 400;

        return analyzer.backtestParameters(trades, minProfitBps, maxSlippageBps);
    }

    /**
     * @notice Analyze gas efficiency
     * @dev Evaluates how efficiently gas is being used relative to profits
     */
    function analyzeGasUsage()
        external
        view
        returns (
            uint256 meanGasCost,
            uint256 profitPerGasUnit,
            string memory recommendation
        )
    {
        ArbitrageAnalyzer.TradeData[] memory trades = _createSampleTrades();

        uint256[] memory gasPrices = new uint256[](trades.length);
        for (uint256 i = 0; i < trades.length; i++) {
            gasPrices[i] = 50 gwei;
        }

        return analyzer.analyzeGasEfficiency(trades, gasPrices);
    }

    /**
     * @notice Create sample historical trade data
     * @dev In production, this would be fetched from a database or oracle
     */
    function _createSampleTrades()
        internal
        pure
        returns (ArbitrageAnalyzer.TradeData[] memory)
    {
        ArbitrageAnalyzer.TradeData[] memory trades = new ArbitrageAnalyzer.TradeData[](10);

        trades[0] = ArbitrageAnalyzer.TradeData({
            profit: 0.05 ether,
            gasUsed: 450000,
            slippage: 250,
            executionTime: 45
        });

        trades[1] = ArbitrageAnalyzer.TradeData({
            profit: 0.08 ether,
            gasUsed: 480000,
            slippage: 280,
            executionTime: 52
        });

        trades[2] = ArbitrageAnalyzer.TradeData({
            profit: 0.03 ether,
            gasUsed: 420000,
            slippage: 200,
            executionTime: 38
        });

        trades[3] = ArbitrageAnalyzer.TradeData({
            profit: 0.12 ether,
            gasUsed: 510000,
            slippage: 320,
            executionTime: 60
        });

        trades[4] = ArbitrageAnalyzer.TradeData({
            profit: 0.02 ether,
            gasUsed: 400000,
            slippage: 150,
            executionTime: 30
        });

        trades[5] = ArbitrageAnalyzer.TradeData({
            profit: 0.07 ether,
            gasUsed: 470000,
            slippage: 270,
            executionTime: 48
        });

        trades[6] = ArbitrageAnalyzer.TradeData({
            profit: 0.04 ether,
            gasUsed: 440000,
            slippage: 240,
            executionTime: 42
        });

        trades[7] = ArbitrageAnalyzer.TradeData({
            profit: 0.09 ether,
            gasUsed: 490000,
            slippage: 290,
            executionTime: 55
        });

        trades[8] = ArbitrageAnalyzer.TradeData({
            profit: 0.06 ether,
            gasUsed: 460000,
            slippage: 260,
            executionTime: 50
        });

        trades[9] = ArbitrageAnalyzer.TradeData({
            profit: 0.11 ether,
            gasUsed: 500000,
            slippage: 310,
            executionTime: 58
        });

        return trades;
    }

    /**
     * @notice Get detailed breakdown for a specific scenario
     */
    function getDetailedProfitabilityBreakdown(
        uint256 borrowAmount,
        uint256 expectedLeg1Out,
        uint256 expectedLeg2Out
    ) external returns (ArbitrageAnalyzer.ProfitabilityBreakdown memory) {
        return analyzer.calculateProfitability(
            borrowAmount,
            9,
            50 gwei,
            500000,
            expectedLeg1Out,
            expectedLeg2Out,
            10,
            50
        );
    }
}