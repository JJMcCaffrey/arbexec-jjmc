import hre from "hardhat";

async function main() {
  console.log("🚀 Deploying ArbitrageAnalyzer...");

  const ArbitrageAnalyzer = await hre.ethers.getContractFactory(
    "ArbitrageAnalyzer"
  );
  const analyzer = await ArbitrageAnalyzer.deploy();
  await analyzer.waitForDeployment();
  const analyzerAddress = await analyzer.getAddress();

  console.log("✅ ArbitrageAnalyzer deployed to:", analyzerAddress);

  console.log("\n🚀 Deploying AnalyzerUsageExample...");
  const AnalyzerUsageExample = await hre.ethers.getContractFactory(
    "AnalyzerUsageExample"
  );
  const example = await AnalyzerUsageExample.deploy(analyzerAddress);
  await example.waitForDeployment();
  const exampleAddress = await example.getAddress();

  console.log("✅ AnalyzerUsageExample deployed to:", exampleAddress);

  console.log("\n✅ Deployment complete!");
  console.log("\nDeployed Addresses:");
  console.log("  ArbitrageAnalyzer:", analyzerAddress);
  console.log("  AnalyzerUsageExample:", exampleAddress);

  return { analyzerAddress, exampleAddress };
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });