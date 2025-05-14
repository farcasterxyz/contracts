// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IStorageRegistry} from "./IStorageRegistry.sol";
import {IIdRegistry} from "./IIdRegistry.sol";

interface IIdGateway {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller does not have the authority to perform the action.
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when the admin sets a new StorageRegistry address.
     *
     * @param oldStorageRegistry The previous StorageRegistry address.
     * @param newStorageRegistry The new StorageRegistry address.
     */
    event SetStorageRegistry(address oldStorageRegistry, address newStorageRegistry);

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice EIP-712 typehash for Register signatures.
     */
    function REGISTER_TYPEHASH() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The IdRegistry contract
     */
    function idRegistry() external view returns (IIdRegistry);

    /**
     * @notice The StorageRegistry contract
     */
    function storageRegistry() external view returns (IStorageRegistry);

    /*//////////////////////////////////////////////////////////////
                             PRICE VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the total price to register, equal to 1 storage unit.
     *
     * @return Total price in wei.
     */
    function price() external view returns (uint256);

    /**
     * @notice Calculate the total price to register, including additional storage.
     *
     * @param extraStorage Number of additional storage units to rent.
     *
     * @return Total price in wei.
     */
    function price(
        uint256 extraStorage
    ) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new Farcaster ID (fid) to the caller. The caller must not have an fid.
     *
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     *
     * @return fid registered FID.
     */
    function register(
        address recovery
    ) external payable returns (uint256 fid, uint256 overpayment);

    /**
     * @notice Register a new Farcaster ID (fid) to the caller and rent additional storage.
     *         The caller must not have an fid.
     *
     * @param recovery     Address which can recover the fid. Set to zero to disable recovery.
     * @param extraStorage Number of additional storage units to rent.
     *
     * @return fid registered FID.
     */
    function register(
        address recovery,
        uint256 extraStorage
    ) external payable returns (uint256 fid, uint256 overpayment);

    /**
     * @notice Register a new Farcaster ID (fid) to any address. A signed message from the address
     *         must be provided which approves both the to and the recovery. The address must not
     *         have an fid.
     *
     * @param to       Address which will own the fid.
     * @param recovery Address which can recover the fid. Set to zero to disable recovery.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Register signature signed by the to address.
     *
     * @return fid registered FID.
     */
    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig
    ) external payable returns (uint256 fid, uint256 overpayment);

    /**
     * @notice Register a new Farcaster ID (fid) to any address and rent additional storage.
     *         A signed message from the address must be provided which approves both the to
     *         and the recovery. The address must not have an fid.
     *
     * @param to           Address which will own the fid.
     * @param recovery     Address which can recover the fid. Set to zero to disable recovery.
     * @param deadline     Expiration timestamp of the signature.
     * @param sig          EIP-712 Register signature signed by the to address.
     * @param extraStorage Number of additional storage units to rent.
     *
     * @return fid registered FID.
     */
    function registerFor(
        address to,
        address recovery,
        uint256 deadline,
        bytes calldata sig,
        uint256 extraStorage
    ) external payable returns (uint256 fid, uint256 overpayment);

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the StorageRegistry address. Only callable by owner.
     *
     * @param _storageRegistry The new StorageREgistry address.
     */
    function setStorageRegistry(
        address _storageRegistry
    ) external;
}
