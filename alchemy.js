const { Alchemy, Network } = require('alchemy-sdk');

const settings = {
  apiKey: 'your-alchemy-api-key',
  network: Network.ETH_MAINNET,
};

const alchemy = new Alchemy(settings);

// Simulate transaction
async function simulateRouteWithAlchemy(routeId, flashLoanAmount) {
  try {
    const response = await alchemy.transact.simulateExecution({
      from: '0xYourAddress',
      to: '0xArbOptV2Address',
      data: encodeAbiForExecuteOptimalArbitrage(flashLoanAmount),
      gas: '0x4C4B40', // 5M gas
      gasPrice: '0xBA43B7400', // 50 gwei
      value: '0x0',
    });

    return {
      routeId,
      success: response.status === '0x1',
      gasUsed: parseInt(response.gasUsed),
      logs: response.logs,
      profit: extractProfitFromLogs(response.logs),
    };
  } catch (error) {
    console.error(`Route ${routeId} simulation failed:`, error);
    return { routeId, success: false, profit: 0 };
  }
}

// Batch simulate all routes
async function batchSimulateAllRoutes(flashLoanAmount) {
  const routeCount = await getRouteCountFromContract();

  console.log(`Batch simulating ${routeCount} routes with Alchemy...`);

  const simulations = await Promise.all(
    Array.from({ length: routeCount }, (_, i) =>
      simulateRouteWithAlchemy(i, flashLoanAmount)
    )
  );

  return simulations;
}

// Find best and execute
async function findAndExecuteOptimalRoute(flashLoanAmount) {
  const simulations = await batchSimulateAllRoutes(flashLoanAmount);

  const bestRoute = simulations.reduce((best, current) =>
    current.profit > best.profit ? current : best
  );

  console.log(`Best route: ${bestRoute.routeId} | Profit: ${bestRoute.profit}`);

  if (bestRoute.success && bestRoute.profit > 0) {
    const tx = await arbOptV2.executeOptimalArbitrage(flashLoanAmount);
    return tx;
  }

  return null;
}