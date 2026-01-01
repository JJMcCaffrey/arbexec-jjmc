// orchestrator.ts
import ArbitrageMonitor from "./arbitrage-monitor";
import StatisticalAnalyzer from "./statistical-analyzer";
import ProfitabilityCalculator from "./profitability-calculator";
import { ethers } from "ethers";

interface ExecutionPlan {
  tokenPath: string[];
  borrowAmount: string;
  dexA: string;
  dexB: string;
  profitability: any;
  recommendedParams: any;
}

class ArbitrageOrchestrator {
  private monitor: ArbitrageMonitor;
  private analyzer: StatisticalAnalyzer;
  private calculator: ProfitabilityCalculator;
  private provider: ethers.JsonRpcProvider;

  constructor(rpcUrl: string, alchemyKey: string) {
    this.monitor = new ArbitrageMonitor(rpcUrl, alchemyKey);
    this.analyzer = new StatisticalAnalyzer();
    this.calculator = new ProfitabilityCalculator();
    this.provider = new ethers.JsonRpcProvider(rpcUrl);
  }

  /**
   * Full analysis pipeline
   */
  async analyzeAndPlan(
    tokenPairs: Array<{ token0: string; token1: string }>,
    historicalTrades: Array<{
      profit: number;
      gasUsed: number;
      slippage: number;
      executionTime: number;
    }>,
    minProfitBps: number = 100
  ): Promise<ExecutionPlan[]> {
    console.log("🔍 Identifying arbitrage opportunities...");
    const opportunities = await this.monitor.identifyOpportunities(tokenPairs, minProfitBps);

    console.log(`✅ Found ${opportunities.length} opportunities`);

    console.log("📊 Analyzing historical data...");
    const analysis = this.analyzer.analyzeHistoricalTrades(historicalTrades);

    console.log(`Mean Profit: ${analysis.meanProfit.toFixed(6)} ETH`);
    console.log(`Success Rate: ${analysis.successRate.toFixed(2)}%`);
    console.log(`Recommended minProfitBps: ${analysis.recommendations.minProfitBps}`);
    console.log(`Recommended maxSlippageBps: ${analysis.recommendations.maxSlippageBps}`);

    console.log("💰 Calculating profitability for top opportunities...");
    const executionPlans: ExecutionPlan[] = [];

    for (const opp of this.monitor.getTopOpportunities(5)) {
      const profitability = this.calculator.calculateProfitability({
        borrowAmount: ethers.parseEther("10").toString(),
        flashLoanPremiumBps: 9,
        gasPrice: ethers.parseUnits("50", "gwei").toString(),
        gasUnitsEstimate: 500000,
        leg1AmountOut: ethers.parseEther("10.5").toString(),
        leg2AmountOut: ethers.parseEther("10.8").toString(),
        builderTipBps: 10,
        safetyBufferBps: 50,
      });

      if (profitability.isProfitable) {
        executionPlans.push({
          tokenPath: [opp.tokenA, opp.tokenB],
          borrowAmount: ethers.parseEther("10").toString(),
          dexA: opp.dexA,
          dexB: opp.dexB,
          profitability,
          recommendedParams: analysis.recommendations,
        });
      }
    }

    return executionPlans;
  }

  /**
   * Export analysis report
   */
  exportReport(
    plans: ExecutionPlan[],
    filePath: string
  ): void {
    const fs = require("fs");
    const report = {
      timestamp: new Date().toISOString(),
      executionPlans: plans,
      summary: {
        totalOpportunities: plans.length,
        totalPotentialProfit: plans.reduce(
          (sum, p) => sum + Number(p.profitability.netProfit),
          0
        ),
      },
    };

    fs.writeFileSync(filePath, JSON.stringify(report, null, 2));
    console.log(`📄 Report exported to ${filePath}`);
  }
}

export default ArbitrageOrchestrator;