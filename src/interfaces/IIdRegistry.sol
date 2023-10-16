// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IIdRegistry {
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
     * @notice EIP-712 typehash for ChangeRecoveryAddress signatures.
     */
    function CHANGE_RECOVERY_ADDRESS_TYPEHASH() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The last Farcaster id that was issued.
     */
    function idCounter() external view returns (uint256);

    /**
     * @notice Maps each address to an fid, or zero if it does not own an fid.
     */
    function idOf(address owner) external view returns (uint256 fid);

    /**
     * @notice Maps each fid to an address that can initiate a recovery.
     */
    function recoveryOf(uint256 fid) external view returns (address recovery);

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

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the recovery address of the fid owned by the caller.
     *
     * @param recovery The address which can recover the fid. Set to 0x0 to disable recovery.
     */
    function changeRecoveryAddress(address recovery) external;

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

    function register(address to, address recovery) external returns (uint256 fid);

    /**
     * @notice Pause registration, transfer, and recovery.
     *         Must be called by the owner.
     */
    function pause() external;

    /**
     * @notice Unpause registration, transfer, and recovery.
     *         Must be called by the owner.
     */
    function unpause() external;
}
