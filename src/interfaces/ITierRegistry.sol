// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

interface ITierRegistry {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                        STORAGE RENTAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function purchaseTier(uint256 fid, uint256 tier, uint256 forDays, address payer) external;

    function batchPurchaseTiers(
        uint256[] calldata fids,
        uint256[] calldata tiers,
        uint256[] calldata forDays,
        address payer
    ) external;

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    function creditTier(uint256 fid, uint256 tier, uint256 forDays) external;

    function batchCreditTiers(uint256[] calldata fids, uint256[] calldata tiers, uint256[] calldata forDays) external;

    /**
     * @notice Change the vault address that can receive funds from this contract.
     *         Only callable by owner.
     *
     * @param vaultAddr The new vault address.
     */
    function setVault(
        address vaultAddr
    ) external;

    function setToken(
        address tokenAddr
    ) external;

    function setTier(uint256 tier, uint256 price) external;

    function removeTier(
        uint256 tier
    ) external;

    /**
     * @notice Pause, disabling rentals and credits.
     *         Only callable by owner.
     */
    function pause() external;

    /**
     * @notice Unpause, enabling rentals and credits.
     *         Only callable by owner.
     */
    function unpause() external;
}
