// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILendingPoolAddressesProvider
 * @notice Interface for fetching and updating addresses of Aave's core contracts.
 */
 
interface ILendingPoolAddressesProvider {

    // --- View Functions ---
    /**
     * @return The address of the LendingPool.
     */
    function getLendingPool() external view returns (address);

    /**
     * @return The address of the LendingPoolCore.
     */
    function getLendingPoolCore() external view returns (address payable);

    /**
     * @return The address of the LendingPoolConfigurator.
     */
    function getLendingPoolConfigurator() external view returns (address);

    /**
     * @return The address of the LendingPoolDataProvider.
     */
    function getLendingPoolDataProvider() external view returns (address);

    /**
     * @return The address of the LendingPoolParametersProvider.
     */
    function getLendingPoolParametersProvider() external view returns (address);

    /**
     * @return The address of the TokenDistributor.
     */
    function getTokenDistributor() external view returns (address);

    /**
     * @return The address of the FeeProvider.
     */
    function getFeeProvider() external view returns (address);

    /**
     * @return The address of the LendingPoolLiquidationManager.
     */
    function getLendingPoolLiquidationManager() external view returns (address);

    /**
     * @return The address of the LendingPoolManager.
     */
    function getLendingPoolManager() external view returns (address);

    /**
     * @return The address of the PriceOracle.
     */
    function getPriceOracle() external view returns (address);

    /**
     * @return The address of the LendingRateOracle.
     */
    function getLendingRateOracle() external view returns (address);

    // --- Admin Functions (Restricted Access) ---
    /**
     * @notice Updates the LendingPool implementation.
     * @param _pool The new LendingPool address.
     */
    function setLendingPoolImpl(address _pool) external;

    /**
     * @notice Updates the LendingPoolCore implementation.
     * @param _lendingPoolCore The new LendingPoolCore address.
     */
    function setLendingPoolCoreImpl(address _lendingPoolCore) external;

    /**
     * @notice Updates the LendingPoolConfigurator implementation.
     * @param _configurator The new LendingPoolConfigurator address.
     */
    function setLendingPoolConfiguratorImpl(address _configurator) external;

    /**
     * @notice Updates the LendingPoolDataProvider implementation.
     * @param _provider The new LendingPoolDataProvider address.
     */
    function setLendingPoolDataProviderImpl(address _provider) external;

    /**
     * @notice Updates the LendingPoolParametersProvider implementation.
     * @param _parametersProvider The new LendingPoolParametersProvider address.
     */
    function setLendingPoolParametersProviderImpl(address _parametersProvider) external;

    /**
     * @notice Updates the TokenDistributor address.
     * @param _tokenDistributor The new TokenDistributor address.
     */
    function setTokenDistributor(address _tokenDistributor) external;

    /**
     * @notice Updates the FeeProvider implementation.
     * @param _feeProvider The new FeeProvider address.
     */
    function setFeeProviderImpl(address _feeProvider) external;

    /**
     * @notice Updates the LendingPoolLiquidationManager address.
     * @param _manager The new LendingPoolLiquidationManager address.
     */
    function setLendingPoolLiquidationManager(address _manager) external;

    /**
     * @notice Updates the LendingPoolManager address.
     * @param _lendingPoolManager The new LendingPoolManager address.
     */
    function setLendingPoolManager(address _lendingPoolManager) external;

    /**
     * @notice Updates the PriceOracle address.
     * @param _priceOracle The new PriceOracle address.
     */
    function setPriceOracle(address _priceOracle) external;

    /**
     * @notice Updates the LendingRateOracle address.
     * @param _lendingRateOracle The new LendingRateOracle address.
     */
    function setLendingRateOracle(address _lendingRateOracle) external;
}