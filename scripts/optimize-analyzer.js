const hre = require("hardhat");

async function main() {
  const exampleAddress = process.env.EXAMPLE_ADDRESS;

  if (!exampleAddress) {
    console.error("❌ Please set EXAMPLE_ADDRESS environment variable");
    process.exit(1);
  }

  console.log("🔍 Running optimization analysis...");

  const example = await hre.ethers.getContractAt(
    "AnalyzerUsageExample",
    exampleAddress
  );

  try {
    console.log("\n🔍 Finding optimal borrow amount...");
    const optimalResult = await example.findOptimalAmount();
    console.log(
      "  Optimal Amount:",
      hre.ethers.formatEther(optimalResult.optimalAmount),
      "ETH"
    );
    console.log(
      "  Max Profit:",
      hre.ethers.formatEther(optimalResult.maxProfit),
      "ETH"
    );
    console.log(
      "  Optimal ROI:",
      (Number(optimalResult.profitability.roi) / 100).toFixed(2),
      "%"
    );

    console.log("\n📊 Running sensitivity analysis...");
    const sensitivityResults = await example.runSensitivityAnalysis();
    console.log("  Tested", sensitivityResults.length, "scenarios");

    let bestRoi = 0n;
    let bestScenario = 0;
    for (let i = 0; i < sensitivityResults.length; i++) {
      if (sensitivityResults[i].roi > bestRoi) {
        bestRoi = sensitivityResults[i].roi;
        bestScenario = i;
      }
    }

    const best = sensitivityResults[bestScenario];
    console.log("  Best Scenario:");
    console.log(
      "    Gas Price:",
      hre.ethers.formatUnits(best.gasPrice, "gwei"),
      "gwei"
    );
    console.log(
      "    Flash Loan Premium:",
      best.flashLoanPremiumBps.toString(),
      "BPS"
    );
    console.log(
      "    Net Profit:",
      hre.ethers.formatEther(best.netProfit),
      "ETH"
    );
    console.log("    ROI:", (Number(best.roi) / 100).toFixed(2), "%");

    console.log("\n🧪 Running backtest...");
    const backtestResults = await example.runBacktest();
    console.log(
      "  Tested",
      backtestResults.length,
      "parameter combinations"
    );

    let bestBacktestRoi = 0n;
    let bestBacktestIdx = 0;
    for (let i = 0; i < backtestResults.length; i++) {
      if (backtestResults[i].roi > bestBacktestRoi) {
        bestBacktestRoi = backtestResults[i].roi;
        bestBacktestIdx = i;
      }
    }

    const bestBacktest = backtestResults[bestBacktestIdx];
    console.log("  Best Backtest Result:");
    console.log("    Min Profit BPS:", bestBacktest.minProfitBps.toString());
    console.log(
      "    Max Slippage BPS:",
      bestBacktest.maxSlippageBps.toString()
    );
    console.log("    Success Count:", bestBacktest.successCount.toString());
    console.log(
      "    Total Profit:",
      hre.ethers.formatEther(bestBacktest.totalProfit),
      "ETH"
    );
    console.log("    ROI:", (Number(bestBacktest.roi) / 100).toFixed(2), "%");

    console.log("\n⛽ Gas Efficiency Analysis:");
    const [meanGasCost, profitPerGasUnit, recommendation] =
      await example.analyzeGasUsage();
    console.log(
      "  Mean Gas Cost:",
      hre.ethers.formatEther(meanGasCost),
      "ETH"
    );
    console.log(
      "  Profit per Gas Unit:",
      hre.ethers.formatEther(profitPerGasUnit),
      "ETH"
    );
    console.log("  Recommendation:", recommendation);
  } catch (error) {
    console.error("❌ Error running optimization:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });