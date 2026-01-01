// arbitrage-monitor.ts
import { ethers } from "ethers";
import axios from "axios";

interface ArbitrageOpportunity {
  tokenA: string;
  tokenB: string;
  dexA: string;
  dexB: string;
  priceA: number;
  priceB: number;
  priceDifference: number;
  estimatedProfit: number;
  profitabilityBps: number;
  timestamp: number;
  blockNumber: number;
}

interface PoolSnapshot {
  address: string;
  token0: string;
  token1: string;
  reserve0: bigint;
  reserve1: bigint;
  fee: number;
  timestamp: number;
}

class ArbitrageMonitor {
  private provider: ethers.JsonRpcProvider;
  private alchemyApiKey: string;
  private opportunities: ArbitrageOpportunity[] = [];

  constructor(rpcUrl: string, alchemyKey: string) {
    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.alchemyApiKey = alchemyKey;
  }

  /**
   * Fetch historical pool data from Alchemy
   * Uses Alchemy's getAssetTransfers to track liquidity changes
   */
  async fetchPoolSnapshots(
    poolAddress: string,
    fromBlock: number,
    toBlock: number
  ): Promise<PoolSnapshot[]> {
    const snapshots: PoolSnapshot[] = [];

    for (let block = fromBlock; block <= toBlock; block += 100) {
      const endBlock = Math.min(block + 100, toBlock);

      try {
        const response = await axios.post(
          `https://eth-mainnet.g.alchemy.com/v2/${this.alchemyApiKey}`,
          {
            jsonrpc: "2.0",
            method: "eth_getLogs",
            params: [
              {
                address: poolAddress,
                fromBlock: `0x${block.toString(16)}`,
                toBlock: `0x${endBlock.toString(16)}`,
                topics: [
                  "0x1f1ff1f5fb41346850b2f5c04e6c767e2f1c8a525c5c0c5e4d3c2b1a09080706", // Swap event
                ],
              },
            ],
            id: 1,
          }
        );

        if (response.data.result) {
          for (const log of response.data.result) {
            const snapshot = this.parseSwapLog(log, block);
            if (snapshot) snapshots.push(snapshot);
          }
        }
      } catch (error) {
        console.error(`Error fetching block ${block}:`, error);
      }
    }

    return snapshots;
  }

  /**
   * Parse Uniswap V3 Swap event logs
   */
  private parseSwapLog(log: any, blockNumber: number): PoolSnapshot | null {
    try {
      // Uniswap V3 Swap event: (sender, recipient, amount0, amount1, sqrtPriceX96, liquidity, tick)
      const iface = new ethers.Interface([
        "event Swap(address indexed sender, address indexed recipient, int256 amount0, int256 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick)",
      ]);

      // In production, decode the log properly
      return {
        address: log.address,
        token0: "0x0000000000000000000000000000000000000000",
        token1: "0x0000000000000000000000000000000000000000",
        reserve0: BigInt(0),
        reserve1: BigInt(0),
        fee: 3000,
        timestamp: Math.floor(Date.now() / 1000),
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * Identify arbitrage opportunities by comparing DEX prices
   */
  async identifyOpportunities(
    tokenPairs: Array<{ token0: string; token1: string }>,
    minProfitBps: number = 100
  ): Promise<ArbitrageOpportunity[]> {
    const opportunities: ArbitrageOpportunity[] = [];

    for (const pair of tokenPairs) {
      try {
        // Get prices from multiple DEXs
        const uniswapPrice = await this.getPriceFromDex(
          pair.token0,
          pair.token1,
          "uniswap-v3"
        );
        const sushiswapPrice = await this.getPriceFromDex(
          pair.token0,
          pair.token1,
          "sushiswap"
        );

        if (!uniswapPrice || !sushiswapPrice) continue;

        const priceDiff = Math.abs(uniswapPrice - sushiswapPrice);
        const profitBps = (priceDiff / Math.max(uniswapPrice, sushiswapPrice)) * 10000;

        if (profitBps >= minProfitBps) {
          opportunities.push({
            tokenA: pair.token0,
            tokenB: pair.token1,
            dexA: uniswapPrice > sushiswapPrice ? "sushiswap" : "uniswap-v3",
            dexB: uniswapPrice > sushiswapPrice ? "uniswap-v3" : "sushiswap",
            priceA: Math.min(uniswapPrice, sushiswapPrice),
            priceB: Math.max(uniswapPrice, sushiswapPrice),
            priceDifference: priceDiff,
            estimatedProfit: priceDiff * 1, // Simplified
            profitabilityBps: profitBps,
            timestamp: Math.floor(Date.now() / 1000),
            blockNumber: await this.provider.getBlockNumber(),
          });
        }
      } catch (error) {
        console.error(`Error analyzing pair ${pair.token0}-${pair.token1}:`, error);
      }
    }

    this.opportunities = opportunities;
    return opportunities;
  }

  /**
   * Get price from DEX via quote
   */
  private async getPriceFromDex(
    tokenIn: string,
    tokenOut: string,
    dex: string
  ): Promise<number | null> {
    try {
      // Placeholder - implement actual DEX quote logic
      // In production, use Uniswap V3 Quoter or SushiSwap router
      return Math.random() * 1000; // Mock price
    } catch (error) {
      return null;
    }
  }

  /**
   * Get opportunities sorted by profitability
   */
  getTopOpportunities(limit: number = 10): ArbitrageOpportunity[] {
    return this.opportunities
      .sort((a, b) => b.profitabilityBps - a.profitabilityBps)
      .slice(0, limit);
  }

  /**
   * Export opportunities for analysis
   */
  exportOpportunities(filePath: string): void {
    const fs = require("fs");
    fs.writeFileSync(filePath, JSON.stringify(this.opportunities, null, 2));
    console.log(`Exported ${this.opportunities.length} opportunities to ${filePath}`);
  }
}

export default ArbitrageMonitor;