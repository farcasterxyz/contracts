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

    function batchPurchaseTier(
        uint256 tier,
        uint256[] calldata fids,
        uint256[] calldata forDays,
        address payer
    ) external;

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    function setTier(
        uint256 tier,
        address paymentToken,
        uint256 minDays,
        uint256 maxDays,
        uint256 tokenPricePerDay,
        address vault
    ) external;

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
