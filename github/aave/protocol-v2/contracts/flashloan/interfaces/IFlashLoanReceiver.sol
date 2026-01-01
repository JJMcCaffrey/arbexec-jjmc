// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.20;

import {ILendingPoolAddressesProvider} from "github/aave/aave-protocol/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "github/aave/protocol-v2/contracts/interfaces/ILendingPool.sol";


/**
 * @title IFlashLoanReceiver
 * @notice Interface for contracts to receive flash loans from Aave's LendingPool.
 * @dev Must be implemented by a contract to execute flash loan logic.
 */
interface IFlashLoanReceiver {
    /**
     * @dev The address of the LendingPoolAddressesProvider.
     */
    function ADDRESSES_PROVIDER() external view returns (ILendingPoolAddressesProvider);

    /**
     * @dev The address of the LendingPool.
     */
    function LENDING_POOL() external view returns (ILendingPool);

    /**
     * @dev Executes the flash loan logic.
     * @param assets The addresses of the assets being flash-borrowed.
     * @param amounts The amounts of the assets being borrowed.
     * @param premiums The flash loan premiums (fees) to be paid.
     * @param initiator The address initiating the flash loan.
     * @param params Arbitrary data passed by the initiator (e.g., function selector + encoded args).
     * @return success True if the operation succeeded, false otherwise.
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool success);
}
