// statistical-analyzer.ts
import * as math from "mathjs";

interface ParameterRecommendation {
  minProfitBps: number;
  maxSlippageBps: number;
  deadlineSeconds: number;
  gasUnitsEstimate: number;
  confidence: number;
  reasoning: string;
}

interface StatisticalAnalysis {
  meanProfit: number;
  medianProfit: number;
  stdDeviation: number;
  minProfit: number;
  maxProfit: number;
  successRate: number;
  averageGasUsed: number;
  recommendations: ParameterRecommendation;
}

class StatisticalAnalyzer {
  /**
   * Analyze historical arbitrage trades
   */
  analyzeHistoricalTrades(
    trades: Array<{
      profit: number;
      gasUsed: number;
      slippage: number;
      executionTime: number;
    }>
  ): StatisticalAnalysis {
    if (trades.length === 0) {
      throw new Error("No trades to analyze");
    }

    const profits = trades.map((t) => t.profit);
    const gasUsages = trades.map((t) => t.gasUsed);
    const slippages = trades.map((t) => t.slippage);
    const executionTimes = trades.map((t) => t.executionTime);

    // Calculate statistics
    const meanProfit = math.mean(profits);
    const medianProfit = this.median(profits);
    const stdDeviation = math.std(profits);
    const minProfit = Math.min(...profits);
    const maxProfit = Math.max(...profits);
    const successRate = (trades.filter((t) => t.profit > 0).length / trades.length) * 100;
    const averageGasUsed = math.mean(gasUsages);

    // Generate recommendations
    const recommendations = this.generateRecommendations(
      meanProfit,
      stdDeviation,
      slippages,
      executionTimes,
      averageGasUsed
    );

    return {
      meanProfit,
      medianProfit,
      stdDeviation,
      minProfit,
      maxProfit,
      successRate,
      averageGasUsed,
      recommendations,
    };
  }

  /**
   * Calculate median
   */
  private median(arr: number[]): number {
    const sorted = [...arr].sort((a, b) => a - b);
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 !== 0 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /**
   * Generate parameter recommendations based on analysis
   */
  private generateRecommendations(
    meanProfit: number,
    stdDeviation: number,
    slippages: number[],
    executionTimes: number[],
    averageGasUsed: number
  ): ParameterRecommendation {
    // Conservative approach: use mean - 1 std dev as minimum profit
    const minProfitBps = Math.max(50, Math.floor((meanProfit - stdDeviation) * 100));

    // Max slippage: 95th percentile of observed slippages
    const sortedSlippages = [...slippages].sort((a, b) => a - b);
    const maxSlippageBps = Math.ceil(
      sortedSlippages[Math.floor(sortedSlippages.length * 0.95)]
    );

    // Deadline: 99th percentile of execution times + 30 second buffer
    const sortedTimes = [...executionTimes].sort((a, b) => a - b);
    const deadlineSeconds = Math.ceil(
      sortedTimes[Math.floor(sortedTimes.length * 0.99)] + 30
    );

    // Gas estimate: mean + 2 std dev
    const gasStdDev = math.std(executionTimes);
    const gasUnitsEstimate = Math.ceil(averageGasUsed * 1.5);

    const confidence = Math.min(100, Math.floor((meanProfit / stdDeviation) * 100));

    return {
      minProfitBps,
      maxSlippageBps,
      deadlineSeconds,
      gasUnitsEstimate,
      confidence,
      reasoning: `Based on ${executionTimes.length} historical trades. Mean profit: ${meanProfit.toFixed(
        4
      )} ETH, Success rate: ${((executionTimes.length / executionTimes.length) * 100).toFixed(
        2
      )}%`,
    };
  }

  /**
   * Analyze gas efficiency
   */
  analyzeGasEfficiency(
    trades: Array<{ gasUsed: number; profit: number; gasPrice: number }>
  ): {
    averageGasCost: number;
    profitPerGasUnit: number;
    recommendation: string;
  } {
    const gasCosts = trades.map((t) => t.gasUsed * t.gasPrice);
    const profitPerGas = trades.map((t) => t.profit / (t.gasUsed * t.gasPrice));

    const averageGasCost = math.mean(gasCosts);
    const avgProfitPerGas = math.mean(profitPerGas);

    return {
      averageGasCost,
      profitPerGasUnit: avgProfitPerGas,
      recommendation:
        avgProfitPerGas > 1
          ? "Gas costs are justified by profits"
          : "Consider optimizing gas usage or targeting higher-profit trades",
    };
  }

  /**
   * Backtest parameter combinations
   */
  backtestParameters(
    historicalTrades: Array<{
      profit: number;
      slippage: number;
      gasUsed: number;
    }>,
    parameterCombinations: Array<{
      minProfitBps: number;
      maxSlippageBps: number;
    }>
  ): Array<{
    params: { minProfitBps: number; maxSlippageBps: number };
    successCount: number;
    totalProfit: number;
    roi: number;
  }> {
    return parameterCombinations.map((params) => {
      const successfulTrades = historicalTrades.filter(
        (trade) =>
          trade.profit * 10000 >= params.minProfitBps &&
          trade.slippage <= params.maxSlippageBps
      );

      const totalProfit = successfulTrades.reduce((sum, t) => sum + t.profit, 0);
      const roi = (totalProfit / historicalTrades.length) * 100;

      return {
        params,
        successCount: successfulTrades.length,
        totalProfit,
        roi,
      };
    });
  }
}

export default StatisticalAnalyzer;