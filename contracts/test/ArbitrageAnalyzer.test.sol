// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../src/ArbitrageAnalyzer.sol";

contract ArbitrageAnalyzerTest {
    ArbitrageAnalyzer analyzer;

    function setUp() public {
        analyzer = new ArbitrageAnalyzer();
    }

    // Helper assertion functions (since we can't use forge-std)
    function assertGt(uint256 a, uint256 b) internal pure {
        require(a > b, "AssertionError: a > b");
    }

    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "AssertionError: a == b");
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "AssertionError: condition is false");
    }

    function assertFalse(bool condition) internal pure {
        require(!condition, "AssertionError: condition is true");
    }

    // ============ TEST ANALYSIS FUNCTIONS ============

    function test_analyzeHistoricalTrades() public {
        ArbitrageAnalyzer.TradeData[] memory trades = new ArbitrageAnalyzer.TradeData[](5);

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

        ArbitrageAnalyzer.StatisticalAnalysis memory analysis = analyzer
            .analyzeHistoricalTrades(trades);

        assertGt(analysis.meanProfit, 0);
        assertGt(analysis.successRate, 0);
        assertEq(analysis.totalTrades, 5);
        assertGt(analysis.maxProfit, analysis.minProfit);
    }

    function test_generateParameterRecommendations() public {
        ArbitrageAnalyzer.TradeData[] memory trades = new ArbitrageAnalyzer.TradeData[](10);

        for (uint256 i = 0; i < 10; i++) {
            trades[i] = ArbitrageAnalyzer.TradeData({
                profit: (0.05 ether + i * 0.01 ether),
                gasUsed: 450000 + i * 10000,
                slippage: 250 + i * 10,
                executionTime: 45 + i * 5
            });
        }

        ArbitrageAnalyzer.StatisticalAnalysis memory analysis = analyzer
            .analyzeHistoricalTrades(trades);

        ArbitrageAnalyzer.ParameterRecommendation memory rec = analyzer
            .generateParameterRecommendations(analysis, trades);

        assertGt(rec.minProfitBps, 0);
        assertGt(rec.maxSlippageBps, 0);
        assertGt(rec.deadlineSeconds, 0);
        assertGt(rec.gasUnitsEstimate, 0);
        assertGt(rec.confidence, 0);
    }

    function test_calculateProfitability() public {
        ArbitrageAnalyzer.ProfitabilityBreakdown memory breakdown = analyzer
            .calculateProfitability(
                10 ether,
                9,
                50 gwei,
                500000,
                10.5 ether,
                10.8 ether,
                10,
                50
            );

        assertGt(breakdown.flashLoanFee, 0);
        assertGt(breakdown.gasCost, 0);
        assertGt(breakdown.totalCosts, 0);
        assertTrue(breakdown.isProfitable);
        assertGt(breakdown.netProfit, 0);
        assertGt(breakdown.roi, 0);
    }

    function test_calculateProfitability_Unprofitable() public {
        ArbitrageAnalyzer.ProfitabilityBreakdown memory breakdown = analyzer
            .calculateProfitability(
                10 ether,
                9,
                100 gwei,
                1000000,
                10.1 ether,
                10.05 ether,
                10,
                50
            );

        assertFalse(breakdown.isProfitable);
        assertEq(breakdown.netProfit, 0);
    }

    function test_findOptimalBorrowAmount() public {
        ArbitrageAnalyzer.OptimalBorrowResult memory result = analyzer
            .findOptimalBorrowAmount(
                1 ether,
                10 ether,
                1 ether,
                1.05e18,
                9,
                50 gwei,
                500000,
                10,
                50
            );

        assertGt(result.optimalAmount, 0);
        assertGt(result.maxProfit, 0);
        assertTrue(result.profitability.isProfitable);
    }

    function test_sensitivityAnalysis() public {
        uint256[] memory gasPrices = new uint256[](3);
        gasPrices[0] = 30 gwei;
        gasPrices[1] = 50 gwei;
        gasPrices[2] = 100 gwei;

        uint256[] memory flashLoanPremiums = new uint256[](3);
        flashLoanPremiums[0] = 5;
        flashLoanPremiums[1] = 9;
        flashLoanPremiums[2] = 15;

        ArbitrageAnalyzer.SensitivityResult[] memory results = analyzer
            .sensitivityAnalysis(
                0.1 ether,
                10 ether,
                gasPrices,
                flashLoanPremiums,
                500000,
                10,
                50
            );

        assertEq(results.length, 9);
        for (uint256 i = 0; i < results.length; i++) {
            assertGt(results[i].gasPrice, 0);
            assertGt(results[i].flashLoanPremiumBps, 0);
        }
    }

    function test_backtestParameters() public {
        ArbitrageAnalyzer.TradeData[] memory trades = new ArbitrageAnalyzer.TradeData[](5);

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

        uint256[] memory minProfitBps = new uint256[](3);
        minProfitBps[0] = 100;
        minProfitBps[1] = 200;
        minProfitBps[2] = 300;

        uint256[] memory maxSlippageBps = new uint256[](2);
        maxSlippageBps[0] = 250;
        maxSlippageBps[1] = 300;

        ArbitrageAnalyzer.BacktestResult[] memory results = analyzer
            .backtestParameters(trades, minProfitBps, maxSlippageBps);

        assertEq(results.length, 6);
    }

    function test_analyzeGasEfficiency() public view {
        ArbitrageAnalyzer.TradeData[] memory trades = new ArbitrageAnalyzer.TradeData[](3);

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

        uint256[] memory gasPrices = new uint256[](3);
        gasPrices[0] = 50 gwei;
        gasPrices[1] = 50 gwei;
        gasPrices[2] = 50 gwei;

        (
            uint256 meanGasCost,
            uint256 profitPerGasUnit,
            string memory recommendation
        ) = analyzer.analyzeGasEfficiency(trades, gasPrices);

        assertGt(meanGasCost, 0);
        assertGt(profitPerGasUnit, 0);
        assertTrue(bytes(recommendation).length > 0);
    }

    // ============ ERROR TESTS ============

    function test_analyzeHistoricalTrades_EmptyArray() public {
        ArbitrageAnalyzer.TradeData[] memory trades = new ArbitrageAnalyzer.TradeData[](0);

        try analyzer.analyzeHistoricalTrades(trades) {
            revert("Expected revert");
        } catch {}
    }

    function test_calculateProfitability_ZeroBorrowAmount() public {
        try analyzer.calculateProfitability(
            0,
            9,
            50 gwei,
            500000,
            10 ether,
            10.5 ether,
            10,
            50
        ) {
            revert("Expected revert");
        } catch {}
    }

    function test_findOptimalBorrowAmount_InvalidRange() public {
        try analyzer.findOptimalBorrowAmount(
            10 ether,
            1 ether,
            1 ether,
            1.05e18,
            9,
            50 gwei,
            500000,
            10,
            50
        ) {
            revert("Expected revert");
        } catch {}
    }

    function test_sensitivityAnalysis_ArrayLengthMismatch() public {
        uint256[] memory gasPrices = new uint256[](3);
        uint256[] memory flashLoanPremiums = new uint256[](0);

        try analyzer.sensitivityAnalysis(
            0.1 ether,
            10 ether,
            gasPrices,
            flashLoanPremiums,
            500000,
            10,
            50
        ) {
            revert("Expected revert");
        } catch {}
    }
}