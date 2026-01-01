// config.ts
export const CONFIG = {
  // RPC & API
  RPC_URL: "https://eth-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY",
  ALCHEMY_API_KEY: "YOUR_ALCHEMY_KEY",

  // Contract Addresses
  ARBEXEC_ADDRESS: "0x...", // Your ArbExec deployment
  WETH_ADDRESS: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  AAVE_V3_POOL: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",

  // Risk Parameters
  MIN_PROFIT_BPS: 100, // 1%
  MAX_SLIPPAGE_BPS: 300, // 3%
  DEADLINE_SECONDS: 90,
  GAS_UNITS_ESTIMATE: 500000,

  // Oracle Parameters
  MAX_PRICE_FEED_AGE: 300, // 5 minutes
  ORACLE_DEVIATION_BPS: 800, // 8%
  SECONDARY_ORACLE_DEVIATION_BPS: 1200, // 12%

  // Profitability Parameters
  BUILDER_TIP_BPS: 10,
  SAFETY_BUFFER_BPS: 50,
  FLASH_LOAN_PREMIUM_BPS: 9,
  GAS_PRICE: "50", // gwei

  // Token Pairs to Monitor
  TOKEN_PAIRS: [
    {
      token0: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
      token1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
    },
    {
      token0: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
      token1: "0x6B175474E89094C44Da98b954EedeAC495271d0F", // DAI
    },
  ],

  // Analysis
  BACKTEST_WINDOW: 7 * 24 * 60 * 60, // 7 days in seconds
  REPORT_OUTPUT_PATH: "./reports/arbitrage-analysis.json",
};