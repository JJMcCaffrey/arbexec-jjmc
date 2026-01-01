// main.ts
import ArbitrageOrchestrator from "./orchestrator";
import { CONFIG } from "./config";

async function main() {
  const orchestrator = new ArbitrageOrchestrator(
    CONFIG.RPC_URL,
    CONFIG.ALCHEMY_API_KEY
  );

  // Mock historical trades (in production, fetch from your database)
  const historicalTrades = [
    { profit: 0.05, gasUsed: 450000, slippage: 250, executionTime: 45 },
    { profit: 0.08, gasUsed: 480000, slippage: 280, executionTime: 52 },
    { profit: 0.03, gasUsed: 420000, slippage: 200, executionTime: 38 },
    { profit: 0.12, gasUsed: 510000, slippage: 320, executionTime: 60 },
    { profit: 0.02, gasUsed: 400000, slippage: 150, executionTime: 30 },
  ];

  const executionPlans = await orchestrator.analyzeAndPlan(
    CONFIG.TOKEN_PAIRS,
    historicalTrades,
    CONFIG.MIN_PROFIT_BPS
  );

  orchestrator.exportReport(executionPlans, CONFIG.REPORT_OUTPUT_PATH);

  console.log("\n📋 Execution Plans:");
  executionPlans.forEach((plan, idx) => {
    console.log(`\nPlan ${idx + 1}:`);
    console.log(`  Tokens: ${plan.tokenPath.join(" → ")}`);
    console.log(`  Net Profit: ${plan.profitability.netProfit} Wei`);
    console.log(`  ROI: ${(plan.profitability.roi * 100).toFixed(2)}%`);
    console.log(`  Recommended minProfitBps: ${plan.recommendedParams.minProfitBps}`);
  });
}

main().catch(console.error);