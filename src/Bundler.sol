// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";

import {IdRegistry} from "./IdRegistry.sol";
import {StorageRent} from "./StorageRent.sol";
import {KeyRegistry} from "./KeyRegistry.sol";
import {TransferHelper} from "./lib/TransferHelper.sol";

contract Bundler is Ownable2Step {
    using TransferHelper for address;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert if the caller does not have the authority to perform the action.
    error Unauthorized();

    /// @dev Revert when an invalid address is provided as input.
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when the trustedCaller is set
     *
     * @param oldCaller The previous trusted caller.
     * @param newCaller The new trusted caller.
     * @param owner The address of the owner making the change.
     */
    event SetTrustedCaller(address indexed oldCaller, address indexed newCaller, address owner);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Data needed to register a user with the fid and storage contracts.
    struct UserData {
        address to;
        uint256 units;
        address recovery;
    }

    struct RegistrationParams {
        address to;
        address recovery;
        uint256 deadline;
        bytes sig;
    }

    struct SignerParams {
        uint32 scheme;
        bytes key;
        bytes metadata;
        uint256 deadline;
        bytes sig;
    }

    /**
     * @dev Address that can call trustedRegister and trustedBatchRegister
     */
    address public trustedCaller;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Address of the IdRegistry contract
     */
    IdRegistry public immutable idRegistry;

    /**
     * @dev Address of the StorageRent contract
     */
    StorageRent public immutable storageRent;

    /**
     * @dev Address of the StorageRent contract
     */
    KeyRegistry public immutable keyRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure the addresses of the Registry contracts and the trusted caller which is
     *        allowed to register during the bootstrap phase.
     *
     * @param _idRegistry    Address of the IdRegistry contract
     * @param _storageRent   Address of the StorageRent contract
     * @param _trustedCaller Address that can call trustedRegister and trustedBatchRegister
     */
    constructor(
        address _idRegistry,
        address _storageRent,
        address _keyRegistry,
        address _trustedCaller,
        address _owner
    ) {
        _transferOwnership(_owner);

        idRegistry = IdRegistry(_idRegistry);
        storageRent = StorageRent(_storageRent);
        keyRegistry = KeyRegistry(_keyRegistry);
        trustedCaller = _trustedCaller;
        emit SetTrustedCaller(address(0), _trustedCaller, msg.sender);
    }

    /**
     * @notice Register an fid, single signer, and rent storage to an address in a single transaction.
     *
     */
    function register(
        RegistrationParams calldata registration,
        SignerParams calldata signer,
        uint256 storageUnits
    ) external payable {
        uint256 fid =
            idRegistry.registerFor(registration.to, registration.recovery, registration.deadline, registration.sig);
        keyRegistry.addFor(registration.to, signer.scheme, signer.key, signer.metadata, signer.deadline, signer.sig);
        uint256 overpayment = storageRent.rent{value: msg.value}(fid, storageUnits);

        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
        }
    }

    /**
     * @notice Register an fid, multiple signers, and rent storage to an address in a single transaction.
     *
     */
    function register(
        RegistrationParams calldata registration,
        SignerParams[] calldata signers,
        uint256 storageUnits
    ) external payable {
        uint256 fid =
            idRegistry.registerFor(registration.to, registration.recovery, registration.deadline, registration.sig);

        for (uint256 i; i < signers.length; i++) {
            SignerParams calldata signer = signers[i];
            keyRegistry.addFor(registration.to, signer.scheme, signer.key, signer.metadata, signer.deadline, signer.sig);
        }

        uint256 overpayment = storageRent.rent{value: msg.value}(fid, storageUnits);

        if (overpayment > 0) {
            msg.sender.sendNative(overpayment);
        }
    }

    /**
     * @notice Register an fid and credit storage to an address in a single transaction. Can only
     *         be called by the trustedCaller during the Seedable phase.
     *
     * @param to           Address of the fid to register
     * @param recovery     Address that is allowed to perform a recovery
     * @param storageUnits Number of storage units to rent
     */
    function trustedRegister(address to, address recovery, uint256 storageUnits) external {
        if (msg.sender != trustedCaller) revert Unauthorized();

        // Will revert unless IdRegistry is in the Seedable phase
        uint256 fid = idRegistry.trustedRegister(to, recovery);
        storageRent.credit(fid, storageUnits);
    }

    /**
     * @notice Register multiple fids and credit storage to an address in a single transaction. Can
     *         only be called by the trustedCaller during the Seedable phase. Will be used when
     *         migrating across Ethereum networks to bootstrap a new contract with existing data.
     *
     * @param users  Array of UserData structs to register
     */
    function trustedBatchRegister(UserData[] calldata users) external {
        // Do not allow anyone except the Farcaster Bootstrap Server (trustedCaller) to call this
        if (msg.sender != trustedCaller) revert Unauthorized();

        // Safety: calls inside a loop are safe since caller is trusted
        for (uint256 i = 0; i < users.length; i++) {
            uint256 fid = idRegistry.trustedRegister(users[i].to, users[i].recovery);
            storageRent.credit(fid, users[i].units);
        }
    }

    /**
     * @notice Change the trusted caller that can call trusted* functions
     */
    function setTrustedCaller(address _trustedCaller) external onlyOwner {
        if (_trustedCaller == address(0)) revert InvalidAddress();
        emit SetTrustedCaller(trustedCaller, _trustedCaller, msg.sender);
        trustedCaller = _trustedCaller;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
