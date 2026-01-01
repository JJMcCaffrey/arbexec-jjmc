// profitability-calculator.ts
import { ethers } from "ethers";

interface ProfitabilityInput {
  borrowAmount: string; // Wei
  flashLoanPremiumBps: number;
  gasPrice: string; // Wei
  gasUnitsEstimate: number;
  leg1AmountOut: string; // Wei
  leg2AmountOut: string; // Wei
  builderTipBps: number;
  safetyBufferBps: number;
}

interface DetailedProfitability {
  borrowAmount: string;
  flashLoanFee: string;
  gasCost: string;
  builderTip: string;
  safetyBuffer: string;
  totalCosts: string;
  grossProfit: string;
  netProfit: string;
  roi: number;
  isProfitable: boolean;
  breakdownPercentages: {
    flashLoanFee: number;
    gasCost: number;
    builderTip: number;
    safetyBuffer: number;
  };
}

class ProfitabilityCalculator {
  /**
   * Calculate detailed profitability
   */
  calculateProfitability(input: ProfitabilityInput): DetailedProfitability {
    const borrowAmount = BigInt(input.borrowAmount);
    const leg1Out = BigInt(input.leg1AmountOut);
    const leg2Out = BigInt(input.leg2AmountOut);
    const gasPrice = BigInt(input.gasPrice);

    // Calculate costs
    const flashLoanFee = (borrowAmount * BigInt(input.flashLoanPremiumBps)) / BigInt(10000);
    const gasCost = gasPrice * BigInt(input.gasUnitsEstimate);
    const builderTip = (borrowAmount * BigInt(input.builderTipBps)) / BigInt(10000);
    const safetyBuffer = (borrowAmount * BigInt(input.safetyBufferBps)) / BigInt(10000);

    const totalCosts = flashLoanFee + gasCost + builderTip + safetyBuffer;

    // Calculate profit
    const grossProfit = leg2Out > borrowAmount ? leg2Out - borrowAmount : BigInt(0);
    const netProfit = grossProfit > totalCosts ? grossProfit - totalCosts : BigInt(0);

    // Calculate ROI
    const roi = borrowAmount > BigInt(0) ? Number(netProfit) / Number(borrowAmount) : 0;

    // Calculate percentages
    const totalCostsNum = Number(totalCosts);
    const breakdownPercentages = {
      flashLoanFee: (Number(flashLoanFee) / totalCostsNum) * 100,
      gasCost: (Number(gasCost) / totalCostsNum) * 100,
      builderTip: (Number(builderTip) / totalCostsNum) * 100,
      safetyBuffer: (Number(safetyBuffer) / totalCostsNum) * 100,
    };

    return {
      borrowAmount: borrowAmount.toString(),
      flashLoanFee: flashLoanFee.toString(),
      gasCost: gasCost.toString(),
      builderTip: builderTip.toString(),
      safetyBuffer: safetyBuffer.toString(),
      totalCosts: totalCosts.toString(),
      grossProfit: grossProfit.toString(),
      netProfit: netProfit.toString(),
      roi,
      isProfitable: netProfit > BigInt(0),
      breakdownPercentages,
    };
  }

  /**
   * Find optimal borrow amount for maximum profit
   */
  findOptimalBorrowAmount(
    minBorrowAmount: string,
    maxBorrowAmount: string,
    step: string,
    priceRatio: number, // leg2Out / leg1Out expected ratio
    input: Omit<ProfitabilityInput, "borrowAmount" | "leg1AmountOut" | "leg2AmountOut">
  ): {
    optimalAmount: string;
    maxProfit: string;
    profitability: DetailedProfitability;
  } {
    let maxProfit = BigInt(0);
    let optimalAmount = BigInt(minBorrowAmount);

    let current = BigInt(minBorrowAmount);
    const max = BigInt(maxBorrowAmount);
    const stepSize = BigInt(step);

    while (current <= max) {
      const leg1Out = current; // Assume 1:1 for simplicity
      const leg2Out = BigInt(Math.floor(Number(leg1Out) * priceRatio));

      const profitability = this.calculateProfitability({
        ...input,
        borrowAmount: current.toString(),
        leg1AmountOut: leg1Out.toString(),
        leg2AmountOut: leg2Out.toString(),
      });

      const netProfit = BigInt(profitability.netProfit);
      if (netProfit > maxProfit) {
        maxProfit = netProfit;
        optimalAmount = current;
      }

      current += stepSize;
    }

    const finalProfitability = this.calculateProfitability({
      ...input,
      borrowAmount: optimalAmount.toString(),
      leg1AmountOut: optimalAmount.toString(),
      leg2AmountOut: BigInt(Math.floor(Number(optimalAmount) * priceRatio)).toString(),
    });

    return {
      optimalAmount: optimalAmount.toString(),
      maxProfit: maxProfit.toString(),
      profitability: finalProfitability,
    };
  }

  /**
   * Sensitivity analysis: how profit changes with parameter variations
   */
  sensitivityAnalysis(
    baseInput: ProfitabilityInput,
    variations: {
      gasPrice: number[]; // Multipliers (e.g., [0.8, 1.0, 1.2])
      flashLoanPremium: number[];
    }
  ): Array<{
    gasPrice: string;
    flashLoanPremium: number;
    netProfit: string;
    roi: number;
  }> {
    const results = [];

    for (const gasPriceMultiplier of variations.gasPrice) {
      for (const flashLoanPremium of variations.flashLoanPremium) {
        const adjustedInput: ProfitabilityInput = {
          ...baseInput,
          gasPrice: (BigInt(baseInput.gasPrice) * BigInt(Math.floor(gasPriceMultiplier * 100)) / BigInt(100)).toString(),
          flashLoanPremiumBps: flashLoanPremium,
        };

        const profitability = this.calculateProfitability(adjustedInput);

        results.push({
          gasPrice: adjustedInput.gasPrice,
          flashLoanPremium,
          netProfit: profitability.netProfit,
          roi: profitability.roi,
        });
      }
    }

    return results;
  }
}

export default ProfitabilityCalculator;