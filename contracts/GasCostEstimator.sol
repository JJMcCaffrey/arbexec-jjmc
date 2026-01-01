// SPDX-License-Identifier: MIT

//* @GasCostEstimator.sol //* Off-chain gas cost estimation contract for arbitrage operations

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol"; import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IArbExecGasEstimation { enum DEXType { UNISWAP_V3, SUSHISWAP }