const hre = require("hardhat");

async function main() {
  const analyzerAddress = process.env.ANALYZER_ADDRESS;
  const exampleAddress = process.env.EXAMPLE_ADDRESS;

  if (!analyzerAddress || !exampleAddress) {
    console.error(
      "❌ Please set ANALYZER_ADDRESS and EXAMPLE_ADDRESS environment variables"
    );
    process.exit(1);
  }

  console.log("📊 Interacting with ArbitrageAnalyzer...");
  console.log("  Analyzer:", analyzerAddress);
  console.log("  Example:", exampleAddress);

  const example = await hre.ethers.getContractAt(
    "AnalyzerUsageExample",
    exampleAddress
  );

  try {
    console.log("\n📈 Running complete analysis...");
    const [analysis, recommendations, profitability] =
      await example.runCompleteAnalysis();

    console.log("\n📊 Analysis Results:");
    console.log(
      "  Mean Profit:",
      hre.ethers.formatEther(analysis.meanProfit),
      "ETH"
    );
    console.log(
      "  Median Profit:",
      hre.ethers.formatEther(analysis.medianProfit),
      "ETH"
    );
    console.log(
      "  Success Rate:",
      (Number(analysis.successRate) / 100).toFixed(2),
      "%"
    );
    console.log(
      "  Std Deviation:",
      hre.ethers.formatEther(analysis.stdDeviation),
      "ETH"
    );
    console.log("  Total Trades:", analysis.totalTrades.toString());

    console.log("\n🎯 Parameter Recommendations:");
    console.log("  Min Profit BPS:", recommendations.minProfitBps.toString());
    console.log(
      "  Max Slippage BPS:",
      recommendations.maxSlippageBps.toString()
    );
    console.log(
      "  Deadline Seconds:",
      recommendations.deadlineSeconds.toString()
    );
    console.log(
      "  Gas Units Estimate:",
      recommendations.gasUnitsEstimate.toString()
    );
    console.log(
      "  Confidence:",
      (Number(recommendations.confidence) / 100).toFixed(2),
      "%"
    );
    console.log("  Reasoning:", recommendations.reasoning);

    console.log("\n💰 Profitability Breakdown:");
    console.log(
      "  Flash Loan Fee:",
      hre.ethers.formatEther(profitability.flashLoanFee),
      "ETH"
    );
    console.log(
      "  Gas Cost:",
      hre.ethers.formatEther(profitability.gasCost),
      "ETH"
    );
    console.log(
      "  Builder Tip:",
      hre.ethers.formatEther(profitability.builderTip),
      "ETH"
    );
    console.log(
      "  Safety Buffer:",
      hre.ethers.formatEther(profitability.safetyBuffer),
      "ETH"
    );
    console.log(
      "  Total Costs:",
      hre.ethers.formatEther(profitability.totalCosts),
      "ETH"
    );
    console.log(
      "  Gross Profit:",
      hre.ethers.formatEther(profitability.grossProfit),
      "ETH"
    );
    console.log(
      "  Net Profit:",
      hre.ethers.formatEther(profitability.netProfit),
      "ETH"
    );
    console.log("  ROI:", (Number(profitability.roi) / 100).toFixed(2), "%");
    console.log("  Profitable:", profitability.isProfitable);
  } catch (error) {
    console.error("❌ Error running analysis:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });