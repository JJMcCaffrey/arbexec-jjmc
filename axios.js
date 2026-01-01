const axios = require('axios');
const { Tenderly } = require('@tenderly/sdk');

const TENDERLY_USER = 'your-username';
const TENDERLY_PROJECT = 'your-project';
const TENDERLY_ACCESS_KEY = 'your-access-key';

const tenderly = new Tenderly({
  accountName: TENDERLY_USER,
  projectName: TENDERLY_PROJECT,
  accessKey: TENDERLY_ACCESS_KEY,
});

// Simulate a single route
async function simulateRoute(routeId, flashLoanAmount) {
  try {
    const simulation = await tenderly.simulator.simulateTransaction({
      // Simulate the executeOptimalArbitrage call
      from: '0xYourAddress',
      to: '0xArbOptV2Address',
      input: encodeAbiForExecuteOptimalArbitrage(flashLoanAmount),
      gas: 5000000,
      gasPrice: '50000000000', // 50 gwei
      blockNumber: 'latest',
      save: false, // Don't save simulation
    });

    return {
      routeId,
      success: simulation.status === '0x1',
      gasUsed: simulation.gasUsed,
      profit: extractProfitFromLogs(simulation.logs),
      error: simulation.error,
    };
  } catch (error) {
    console.error(`Route ${routeId} simulation failed:`, error);
    return { routeId, success: false, profit: 0 };
  }
}

// Analyze all routes
async function findOptimalRouteOffChain(flashLoanAmount) {
  const routeCount = await getRouteCountFromContract();

  console.log(`Analyzing ${routeCount} routes off-chain...`);

  const results = [];
  for (let i = 0; i < routeCount; i++) {
    const result = await simulateRoute(i, flashLoanAmount);
    results.push(result);
    console.log(`Route ${i}: Profit = ${result.profit}, Success = ${result.success}`);
  }

  // Find best route
  const bestRoute = results.reduce((best, current) =>
    current.profit > best.profit ? current : best
  );

  console.log(`\nBest route: ${bestRoute.routeId} with profit ${bestRoute.profit}`);

  return bestRoute;
}

// Execute on-chain only if profitable
async function executeIfProfitable(flashLoanAmount, minProfit) {
  const bestRoute = await findOptimalRouteOffChain(flashLoanAmount);

  if (bestRoute.profit >= minProfit && bestRoute.success) {
    console.log(`✓ Executing route ${bestRoute.routeId} on-chain...`);

    // Only one on-chain transaction!
    const tx = await arbOptV2.executeOptimalArbitrage(flashLoanAmount);
    console.log(`Transaction: ${tx.hash}`);

    return tx;
  } else {
    console.log(`✗ No profitable route found. Best profit: ${bestRoute.profit}`);
    return null;
  }
}

// Usage
executeIfProfitable(
  ethers.parseEther('10'),  // 10 WETH
  ethers.parseEther('0.05') // 0.05 WETH minimum profit
);