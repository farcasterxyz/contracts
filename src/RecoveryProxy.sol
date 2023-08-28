// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {IdRegistry} from "./IdRegistry.sol";
import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";

contract RecoveryProxy is Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Contract version specified using Farcaster protocol version scheme.
     */
    string public constant VERSION = "2023.08.23";

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Address of the IdRegistry contract
     */
    IdRegistry public immutable idRegistry;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure the address of the IdRegistry contract and
     *         set the initial owner.
     *
     * @param _idRegistry      Address of the IdRegistry contract
     * @param _initialOwner    Address that can set the trusted caller
     */
    constructor(address _idRegistry, address _initialOwner) {
        idRegistry = IdRegistry(_idRegistry);
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
}
