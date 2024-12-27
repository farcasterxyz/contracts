// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IIdRegistry {
    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Struct argument for bulk register function, representing an FID
     *      and its associated custody address and recovery address.
     *
     * @param fid      Fid to add.
     * @param custody  Custody address.
     * @param recovery Recovery address.
     */
    struct BulkRegisterData {
        uint24 fid;
        address custody;
        address recovery;
    }

    /**
     * @dev Struct argument for bulk register function, representing an FID
     *      and its associated custody address.
     *
     * @param fid      Fid associated with provided keys to add.
     * @param custody  Custody address.
     */
    struct BulkRegisterDefaultRecoveryData {
        uint24 fid;
        address custody;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert when the caller does not have the authority to perform the action.
    error Unauthorized();

    /// @dev Revert when the caller must have an fid but does not have one.
    error HasNoId();

    /// @dev Revert when the destination must be empty but has an fid.
    error HasId();

    /// @dev Revert when the gateway dependency is permanently frozen.
    error GatewayFrozen();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when a new Farcaster ID is registered.
     *
     *      Hubs listen for this and update their address-to-fid mapping by adding `to` as the
     *      current owner of `id`. Hubs assume the invariants:
     *
     *      1. Two Register events can never emit with the same `id`
     *
     *      2. Two Register(alice, ..., ...) cannot emit unless a Transfer(alice, bob, ...) emits
     *          in between, where bob != alice.
     *
     * @param to       The custody address that owns the fid
     * @param id       The fid that was registered.
     * @param recovery The address that can initiate a recovery request for the fid.
     */
    event Register(address indexed to, uint256 indexed id, address recovery);

    /**
     * @dev Emit an event when an fid is transferred to a new custody address.
     *
     *      Hubs listen to this event and atomically change the current owner of `id`
     *      from `from` to `to` in their address-to-fid mapping. Hubs assume the invariants:
     *
     *      1. A Transfer(..., alice, ...) cannot emit if the most recent event for alice is
     *         Register (alice, ..., ...)
     *
     *      2. A Transfer(alice, ..., id) cannot emit unless the most recent event with that id is
     *         Transfer(..., alice, id) or Register(alice, id, ...)
     *
     * @param from The custody address that previously owned the fid.
     * @param to   The custody address that now owns the fid.
     * @param id   The fid that was transferred.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    /**
     * @dev Emit an event when an fid is recovered.
     *
     * @param from The custody address that previously owned the fid.
     * @param to   The custody address that now owns the fid.
     * @param id   The fid that was recovered.
     */
    event Recover(address indexed from, address indexed to, uint256 indexed id);

    /**
     * @dev Emit an event when a Farcaster ID's recovery address changes. It is possible for this
     *      event to emit multiple times in a row with the same recovery address.
     *
     * @param id       The fid whose recovery address was changed.
     * @param recovery The new recovery address.
     */
    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);

    /**
     * @dev Emit an event when the contract owner sets a new IdGateway address.
     *
     * @param oldIdGateway The old IdGateway address.
     * @param newIdGateway The new IdGateway address.
     */
    event SetIdGateway(address oldIdGateway, address newIdGateway);

    /**
     * @dev Emit an event when the contract owner permanently freezes the IdGateway address.
     *
     * @param idGateway The permanent IdGateway address.
     */
    event FreezeIdGateway(address idGateway);

    /**
     * @dev Emit an event when the migration admin sets the idCounter.
     *
     * @param oldCounter The previous idCounter value.
     * @param newCounter The new idCounter value.
     */
    event SetIdCounter(uint256 oldCounter, uint256 newCounter);

    /**
     * @dev Emit an event when the migration admin resets an fid.
     *
     * @param fid The reset fid.
     */
    event AdminReset(uint256 indexed fid);

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Defined for compatibility with tools like Etherscan that detect fid
     *         transfers as token transfers. This is intentionally lowercased.
     */
    function name() external view returns (string memory);

    /**
     * @notice Contract version specified in the Farcaster protocol version scheme.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice EIP-712 typehash for Transfer signatures.
     */
    function TRANSFER_TYPEHASH() external view returns (bytes32);

    /**
     * @notice EIP-712 typehash for TransferAndChangeRecovery signatures.
     */
    function TRANSFER_AND_CHANGE_RECOVERY_TYPEHASH() external view returns (bytes32);

    /**
     * @notice EIP-712 typehash for ChangeRecoveryAddress signatures.
     */
    function CHANGE_RECOVERY_ADDRESS_TYPEHASH() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Address of the IdGateway, an address allowed to register fids.
     */
    function idGateway() external view returns (address);

    /**
     * @notice Whether the IdGateway address is permanently frozen.
     */
    function gatewayFrozen() external view returns (bool);

    /**
     * @notice The last Farcaster id that was issued.
     */
    function idCounter() external view returns (uint256);

    /**
     * @notice Maps each address to an fid, or zero if it does not own an fid.
     */
    function idOf(
        address owner
    ) external view returns (uint256 fid);

    /**
     * @notice Maps each fid to the address that currently owns it.
     */
    function custodyOf(
        uint256 fid
    ) external view returns (address owner);

    /**
     * @notice Maps each fid to an address that can initiate a recovery.
     */
    function recoveryOf(
        uint256 fid
    ) external view returns (address recovery);

    /*//////////////////////////////////////////////////////////////
                             TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer the fid owned by this address to another address that does not have an fid.
     *         A signed Transfer message from the destination address must be provided.
     *
     * @param to       The address to transfer the fid to.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Transfer signature signed by the to address.
     */
    function transfer(address to, uint256 deadline, bytes calldata sig) external;

    /**
     * @notice Transfer the fid owned by this address to another address that does not have an fid,
     *         and change the fid's recovery address to the provided recovery address. This function
     *         can be used to safely receive an fid from an untrusted address.
     *
     *         A signed TransferAndChangeRecovery message from the destination address including the
     *         new recovery must be provided.
     *
     * @param to       The address to transfer the fid to.
     * @param recovery The new recovery address.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Transfer signature signed by the to address.
     */
    function transferAndChangeRecovery(address to, address recovery, uint256 deadline, bytes calldata sig) external;

    /**
     * @notice Transfer the fid owned by the from address to another address that does not
     *         have an fid. Caller must provide two signed Transfer messages: one signed by
     *         the from address and one signed by the to address.
     *
     * @param from         The owner address of the fid to transfer.
     * @param to           The address to transfer the fid to.
     * @param fromDeadline Expiration timestamp of the from signature.
     * @param fromSig      EIP-712 Transfer signature signed by the from address.
     * @param toDeadline   Expiration timestamp of the to signature.
     * @param toSig        EIP-712 Transfer signature signed by the to address.
     */
    function transferFor(
        address from,
        address to,
        uint256 fromDeadline,
        bytes calldata fromSig,
        uint256 toDeadline,
        bytes calldata toSig
    ) external;

    /**
     * @notice Transfer the fid owned by the from address to another address that does not
     *         have an fid, and change the fid's recovery address to the provided recovery
     *         address. This can be used to safely receive an fid transfer from an untrusted
     *         address. Caller must provide two signed TransferAndChangeRecovery messages:
     *         one signed by the from address and one signed by the to address.
     *
     * @param from         The owner address of the fid to transfer.
     * @param to           The address to transfer the fid to.
     * @param recovery     The new recovery address.
     * @param fromDeadline Expiration timestamp of the from signature.
     * @param fromSig      EIP-712 Transfer signature signed by the from address.
     * @param toDeadline   Expiration timestamp of the to signature.
     * @param toSig        EIP-712 Transfer signature signed by the to address.
     */
    function transferAndChangeRecoveryFor(
        address from,
        address to,
        address recovery,
        uint256 fromDeadline,
        bytes calldata fromSig,
        uint256 toDeadline,
        bytes calldata toSig
    ) external;

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the recovery address of the fid owned by the caller.
     *
     * @param recovery The address which can recover the fid. Set to 0x0 to disable recovery.
     */
    function changeRecoveryAddress(
        address recovery
    ) external;

    /**
     * @notice Change the recovery address of fid owned by the owner. Caller must provide an
     *         EIP-712 ChangeRecoveryAddress message signed by the owner.
     *
     * @param owner    Custody address of the fid whose recovery address will be changed.
     * @param recovery The address which can recover the fid. Set to 0x0 to disable recovery.
     * @param deadline Expiration timestamp of the ChangeRecoveryAddress signature.
     * @param sig      EIP-712 ChangeRecoveryAddress message signed by the owner address.
     */
    function changeRecoveryAddressFor(address owner, address recovery, uint256 deadline, bytes calldata sig) external;

    /**
     * @notice Transfer the fid from the from address to the to address. Must be called by the
     *         recovery address. A signed message from the to address must be provided.
     *
     * @param from     The address that currently owns the fid.
     * @param to       The address to transfer the fid to.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Transfer signature signed by the to address.
     */
    function recover(address from, address to, uint256 deadline, bytes calldata sig) external;

    /**
     * @notice Transfer the fid owned by the from address to another address that does not
     *         have an fid. Caller must provide two signed Transfer messages: one signed by
     *         the recovery address and one signed by the to address.
     *
     * @param from             The owner address of the fid to transfer.
     * @param to               The address to transfer the fid to.
     * @param recoveryDeadline Expiration timestamp of the recovery signature.
     * @param recoverySig      EIP-712 Transfer signature signed by the recovery address.
     * @param toDeadline       Expiration timestamp of the to signature.
     * @param toSig            EIP-712 Transfer signature signed by the to address.
     */
    function recoverFor(
        address from,
        address to,
        uint256 recoveryDeadline,
        bytes calldata recoverySig,
        uint256 toDeadline,
        bytes calldata toSig
    ) external;

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verify that a signature was produced by the custody address that owns an fid.
     *
     * @param custodyAddress   The address to check the signature of.
     * @param fid              The fid to check the signature of.
     * @param digest           The digest that was signed.
     * @param sig              The signature to check.
     *
     * @return isValid Whether provided signature is valid.
     */
    function verifyFidSignature(
        address custodyAddress,
        uint256 fid,
        bytes32 digest,
        bytes calldata sig
    ) external view returns (bool isValid);

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONED ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers an fid to the given address and sets up recovery.
     *         May only be called by the configured IdGateway address.
     */
    function register(address to, address recovery) external returns (uint256 fid);

    /**
     * @notice Set the IdGateway address allowed to register fids. Only callable by owner.
     *
     * @param _idGateway The new IdGateway address.
     */
    function setIdGateway(
        address _idGateway
    ) external;

    /**
     * @notice Permanently freeze the IdGateway address. Only callable by owner.
     */
    function freezeIdGateway() external;
}
