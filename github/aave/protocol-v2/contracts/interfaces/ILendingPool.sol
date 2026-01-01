// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.20;

import {IPoolAddressesProvider} from "github/aave/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "github/aave/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";


/**
 * @title ILendingPool
 * @notice Core Aave lending pool interface for deposits, borrows, liquidations, and flash loans.
 */
interface ILendingPool {
    // --- Events ---
    /**
     * @dev Emitted when a user deposits assets into the pool.
     */
    event Deposit(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint16 indexed referral
    );

    /**
     * @dev Emitted when a user withdraws assets from the pool.
     */
    event Withdraw(
        address indexed reserve,
        address indexed user,
        address indexed to,
        uint256 amount
    );

    /**
     * @dev Emitted when a user borrows assets or initiates a flash loan with debt.
     */
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRateMode,
        uint256 borrowRate,
        uint16 indexed referral
    );

    /**
     * @dev Emitted when a user repays borrowed assets.
     */
    event Repay(
        address indexed reserve,
        address indexed user,
        address indexed repayer,
        uint256 amount
    );

    /**
     * @dev Emitted when a user switches borrow rate mode (stable ↔ variable).
     */
    event Swap(address indexed reserve, address indexed user, uint256 rateMode);

    /**
     * @dev Emitted when a user enables a reserve as collateral.
     */
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted when a user disables a reserve as collateral.
     */
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    /**
     * @dev Emitted when a user’s stable borrow rate is rebalanced.
     */
    event RebalanceStableBorrowRate(address indexed reserve, address indexed user);

    /**
     * @dev Emitted when a flash loan is executed.
     */
    event FlashLoan(
        address indexed target,
        address indexed initiator,
        address indexed asset,
        uint256 amount,
        uint256 premium,
        uint16 referralCode
    );

    /**
     * @dev Emitted when the pool is paused.
     */
    event Paused();

    /**
     * @dev Emitted when the pool is unpaused.
     */
    event Unpaused();

    /**
     * @dev Emitted when a borrower is liquidated.
     */
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken
    );

    /**
     * @dev Emitted when reserve data (rates, indices) is updated.
     */
    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    // --- User Actions ---
    /**
     * @notice Deposits an asset into the pool, minting aTokens.
     * @param asset The address of the asset to deposit.
     * @param amount The amount to deposit.
     * @param onBehalfOf The recipient of the aTokens.
     * @param referralCode Referral code for integrator rewards (0 for direct user actions).
     */
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @notice Withdraws an asset from the pool, burning aTokens.
     * @param asset The address of the asset to withdraw.
     * @param amount The amount to withdraw (use `type(uint256).max` for max balance).
     * @param to The recipient of the withdrawn assets.
     * @return The actual amount withdrawn.
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /**
     * @notice Borrows an asset from the pool.
     * @param asset The address of the asset to borrow.
     * @param amount The amount to borrow.
     * @param interestRateMode The borrow rate mode (1: stable, 2: variable).
     * @param referralCode Referral code for integrator rewards.
     * @param onBehalfOf The recipient of the debt (borrower or credit delegator).
     */
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    /**
     * @notice Repays a borrowed asset.
     * @param asset The address of the borrowed asset.
     * @param amount The amount to repay (use `type(uint256).max` for full repayment).
     * @param rateMode The rate mode of the debt (1: stable, 2: variable).
     * @param onBehalfOf The borrower whose debt is repaid.
     * @return The actual amount repaid.
     */
    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external returns (uint256);

    /**
     * @notice Swaps a user’s borrow rate mode (stable ↔ variable).
     * @param asset The address of the borrowed asset.
     * @param rateMode The new rate mode (1: stable, 2: variable).
     */
    function swapBorrowRateMode(address asset, uint256 rateMode) external;

    /**
     * @notice Rebalances a user’s stable borrow rate to the current market rate.
     * @param asset The address of the borrowed asset.
     * @param user The address of the user to rebalance.
     */
    function rebalanceStableBorrowRate(address asset, address user) external;

    /**
     * @notice Enables/disables a deposited asset as collateral.
     * @param asset The address of the deposited asset.
     * @param useAsCollateral `true` to enable, `false` to disable.
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    /**
     * @notice Liquidates a non-healthy position.
     * @param collateralAsset The address of the collateral asset.
     * @param debtAsset The address of the borrowed asset to repay.
     * @param user The address of the borrower being liquidated.
     * @param debtToCover The amount of debt to cover.
     * @param receiveAToken `true` to receive collateral as aTokens, `false` for underlying asset.
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    /**
     * @notice Executes a flash loan.
     * @dev The receiver must implement `IFlashLoanReceiver` and repay the loan + premium.
     * @param receiverAddress The contract receiving the funds (must implement `IFlashLoanReceiver`).
     * @param assets The addresses of the assets to flash borrow.
     * @param amounts The amounts to borrow for each asset.
     * @param modes The debt modes (0: no debt, 1: stable, 2: variable).
     * @param onBehalfOf The address receiving the debt (if applicable).
     * @param params Arbitrary data passed to the receiver.
     * @param referralCode Referral code for integrator rewards.
     */
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    // --- View Functions ---
    /**
     * @notice Returns a user’s account data (collateral, debt, health factor, etc.).
     * @param user The address of the user.
     * @return totalCollateralETH Total collateral in ETH.
     * @return totalDebtETH Total debt in ETH.
     * @return availableBorrowsETH Borrowing power left in ETH.
     * @return currentLiquidationThreshold Liquidation threshold.
     * @return ltv Loan-to-value ratio.
     * @return healthFactor Current health factor.
     */
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /**
     * @notice Returns the configuration of a reserve.
     * @param asset The address of the reserve.
     * @return The reserve’s configuration.
     */
    function getConfiguration(address asset)
        external
        view
        returns (DataTypes.ReserveConfigurationMap memory);

    /**
     * @notice Returns a user’s configuration (collateral/enable flags) across all reserves.
     * @param user The address of the user.
     * @return The user’s configuration.
     */
    function getUserConfiguration(address user)
        external
        view
        returns (DataTypes.UserConfigurationMap memory);

    /**
     * @notice Returns the normalized income of a reserve.
     * @param asset The address of the reserve.
     * @return The normalized income.
     */
    function getReserveNormalizedIncome(address asset) external view returns (uint256);

    /**
     * @notice Returns the normalized variable debt of a reserve.
     * @param asset The address of the reserve.
     * @return The normalized variable debt.
     */
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256);

    /**
     * @notice Returns the state and configuration of a reserve.
     * @param asset The address of the reserve.
     * @return The reserve’s data.
     */
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);

    /**
     * @notice Returns the list of all reserves.
     * @return The array of reserve addresses.
     */
    function getReservesList() external view returns (address[] memory);

    /**
     * @notice Returns the `AddressesProvider` linked to the pool.
     * @return The address of the `ILendingPoolAddressesProvider`.
     */
    function getAddressesProvider() external view returns (IPoolAddressesProvider);

    // --- Admin Functions ---
    /**
     * @notice Initializes a reserve.
     * @param reserve The address of the reserve.
     * @param aTokenAddress The address of the aToken.
     * @param stableDebtAddress The address of the stable debt token.
     * @param variableDebtAddress The address of the variable debt token.
     * @param interestRateStrategyAddress The address of the interest rate strategy.
     */
    function initReserve(
        address reserve,
        address aTokenAddress,
        address stableDebtAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external;

    /**
     * @notice Sets the interest rate strategy for a reserve.
     * @param reserve The address of the reserve.
     * @param rateStrategyAddress The address of the new interest rate strategy.
     */
    function setReserveInterestRateStrategyAddress(
        address reserve,
        address rateStrategyAddress
    ) external;

    /**
     * @notice Sets the configuration of a reserve.
     * @param reserve The address of the reserve.
     * @param configuration The new configuration (bitmask).
     */
    function setConfiguration(address reserve, uint256 configuration) external;

    /**
     * @notice Finalizes a transfer (e.g., for aTokens).
     * @dev Used for accounting updates after transfers.
     * @param asset The address of the asset.
     * @param from The sender.
     * @param to The recipient.
     * @param amount The amount transferred.
     * @param balanceFromAfter The sender’s balance after transfer.
     * @param balanceToBefore The recipient’s balance before transfer.
     */
    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromAfter,
        uint256 balanceToBefore
    ) external;

    /**
     * @notice Pauses/unpauses the pool.
     * @param val `true` to pause, `false` to unpause.
     */
    function setPause(bool val) external;

    /**
     * @notice Returns the pause state of the pool.
     * @return `true` if paused, `false` otherwise.
     */
    function paused() external view returns (bool);
}
