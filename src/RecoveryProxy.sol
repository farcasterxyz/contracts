// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IIdRegistry} from "./interfaces/IIdRegistry.sol";
import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title Farcaster RecoveryProxy
 *
 * @notice  RecoveryProxy allows the recovery execution logic to be changed
 *          without changing the recovery address.
 *
 *          The proxy is set to the recovery address and it delegates
 *          permissions to execute the recovery to its owner. The owner
 *          can be changed at any time, for example from an EOA to a 2/3
 *          multisig. This allows a recovery service operator to change the
 *          recovery mechanisms in the future without requiring each user to
 *          come online and execute a transaction.
 *
 * @custom:security-contact security@merklemanufactory.com
 */
contract RecoveryProxy is Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emit an event when owner changes the IdRegistry
     *
     * @param oldIdRegistry The previous IIdRegistry
     * @param newIdRegistry The new IIdRegistry
     */
    event SetIdRegistry(IIdRegistry oldIdRegistry, IIdRegistry newIdRegistry);

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Address of the IdRegistry contract
     */
    IIdRegistry public idRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure the address of the IdRegistry contract and
     *         set the initial owner.
     *
     * @param _idRegistry      Address of the IdRegistry contract
     * @param _initialOwner    Initial owner address
     */
    constructor(address _idRegistry, address _initialOwner) {
        idRegistry = IIdRegistry(_idRegistry);
        _transferOwnership(_initialOwner);
    }

    /**
     * @notice Recover an fid for a user who has set the RecoveryProxy as their recovery address.
     *         Only owner.
     *
     * @param from     The address that currently owns the fid.
     * @param to       The address to transfer the fid to.
     * @param deadline Expiration timestamp of the signature.
     * @param sig      EIP-712 Transfer signature signed by the to address.
     */
    function recover(address from, address to, uint256 deadline, bytes calldata sig) external onlyOwner {
        idRegistry.recover(from, to, deadline, sig);
    }

    /**
     * @notice Set the IdRegistry address.
     *         Only owner.
     *
     * @param _idRegistry IDRegistry contract address.
     */
    function setIdRegistry(
        IIdRegistry _idRegistry
    ) external onlyOwner {
        emit SetIdRegistry(idRegistry, _idRegistry);
        idRegistry = _idRegistry;
    }
}
