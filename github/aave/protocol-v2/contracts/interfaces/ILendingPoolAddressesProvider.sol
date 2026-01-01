// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.20;

/**
 * @title ILendingPoolAddressesProvider
 * @notice Main registry of addresses for the Aave protocol, including proxy admin and governance-controlled roles.
 * @dev Acts as a factory for proxies and manages their implementations.
 */
interface ILendingPoolAddressesProvider {
    // --- Events ---
    /**
     * @dev Emitted when the market ID is updated.
     */
    event MarketIdSet(string newMarketId);

    /**
     * @dev Emitted when the LendingPool address is updated.
     */
    event LendingPoolUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the ConfigurationAdmin address is updated.
     */
    event ConfigurationAdminUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the EmergencyAdmin address is updated.
     */
    event EmergencyAdminUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the LendingPoolConfigurator address is updated.
     */
    event LendingPoolConfiguratorUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the LendingPoolCollateralManager address is updated.
     */
    event LendingPoolCollateralManagerUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the PriceOracle address is updated.
     */
    event PriceOracleUpdated(address indexed newAddress);

    /**
     * @dev Emitted when the LendingRateOracle address is updated.
     */
    event LendingRateOracleUpdated(address indexed newAddress);

    /**
     * @dev Emitted when a new proxy is created.
     */
    event ProxyCreated(bytes32 id, address indexed newAddress);

    /**
     * @dev Emitted when an address is set (with or without a proxy).
     */
    event AddressSet(bytes32 id, address indexed newAddress, bool hasProxy);

    // --- View Functions ---
    /**
     * @notice Returns the market ID (e.g., "Aave V3 Ethereum").
     * @return The market ID string.
     */
    function getMarketId() external view returns (string memory);

    /**
     * @notice Returns the address associated with the given ID.
     * @param id The bytes32 ID of the address (e.g., keccak256("LENDING_POOL")).
     * @return The address associated with the ID.
     */
    function getAddress(bytes32 id) external view returns (address);

    /**
     * @notice Returns the LendingPool address.
     * @return The LendingPool contract address.
     */
    function getLendingPool() external view returns (address);

    /**
     * @notice Returns the LendingPoolConfigurator address.
     * @return The LendingPoolConfigurator contract address.
     */
    function getLendingPoolConfigurator() external view returns (address);

    /**
     * @notice Returns the LendingPoolCollateralManager address.
     * @return The LendingPoolCollateralManager contract address.
     */
    function getLendingPoolCollateralManager() external view returns (address);

    /**
     * @notice Returns the PoolAdmin address (governance or admin role).
     * @return The PoolAdmin address.
     */
    function getPoolAdmin() external view returns (address);

    /**
     * @notice Returns the EmergencyAdmin address.
     * @return The EmergencyAdmin address.
     */
    function getEmergencyAdmin() external view returns (address);

    /**
     * @notice Returns the PriceOracle address.
     * @return The PriceOracle contract address.
     */
    function getPriceOracle() external view returns (address);

    /**
     * @notice Returns the LendingRateOracle address.
     * @return The LendingRateOracle contract address.
     */
    function getLendingRateOracle() external view returns (address);

    // --- Admin Functions ---
    /**
     * @notice Sets the market ID.
     * @dev Restricted to admin/governance.
     * @param marketId The new market ID (e.g., "Aave V3 Polygon").
     */
    function setMarketId(string calldata marketId) external;

    /**
     * @notice Sets an address for the given ID (without a proxy).
     * @dev Restricted to admin/governance.
     * @param id The bytes32 ID of the address.
     * @param newAddress The new address to associate with the ID.
     */
    function setAddress(bytes32 id, address newAddress) external;

    /**
     * @notice Sets an address for the given ID and creates a proxy for it.
     * @dev Restricted to admin/governance.
     * @param id The bytes32 ID of the address.
     * @param impl The implementation contract address for the proxy.
     */
    function setAddressAsProxy(bytes32 id, address impl) external;

    /**
     * @notice Sets the LendingPool implementation.
     * @dev Restricted to admin/governance.
     * @param pool The new LendingPool implementation address.
     */
    function setLendingPoolImpl(address pool) external;

    /**
     * @notice Sets the LendingPoolConfigurator implementation.
     * @dev Restricted to admin/governance.
     * @param configurator The new LendingPoolConfigurator implementation address.
     */
    function setLendingPoolConfiguratorImpl(address configurator) external;

    /**
     * @notice Sets the LendingPoolCollateralManager address.
     * @dev Restricted to admin/governance.
     * @param manager The new LendingPoolCollateralManager address.
     */
    function setLendingPoolCollateralManager(address manager) external;

    /**
     * @notice Sets the PoolAdmin address.
     * @dev Restricted to current admin/governance.
     * @param admin The new PoolAdmin address.
     */
    function setPoolAdmin(address admin) external;

    /**
     * @notice Sets the EmergencyAdmin address.
     * @dev Restricted to admin/governance.
     * @param admin The new EmergencyAdmin address.
     */
    function setEmergencyAdmin(address admin) external;

    /**
     * @notice Sets the PriceOracle address.
     * @dev Restricted to admin/governance.
     * @param priceOracle The new PriceOracle address.
     */
    function setPriceOracle(address priceOracle) external;

    /**
     * @notice Sets the LendingRateOracle address.
     * @dev Restricted to admin/governance.
     * @param lendingRateOracle The new LendingRateOracle address.
     */
    function setLendingRateOracle(address lendingRateOracle) external;
}