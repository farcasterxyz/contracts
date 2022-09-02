// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";

import {IDRegistry} from "./IDRegistry.sol";
import {NameRegistry} from "./NameRegistry.sol";

/**
 * @title BundleRegistry
 * @author varunsrin (@v)
 * @notice BundleRegistry allows user to register a Farcaster Name and Farcaster ID in a single
 *         transaction by wrapping around the IDRegistry and NameRegistry contracts, saving gas and
 *         reducing complexity for the caller.
 */
contract BundleRegistry is Ownable {
    error Unauthorized();
    error CallFailed();

    /// @dev Emit when the trustedSender is changed by the owner after the contract is deployed
    event ChangeTrustedSender(address indexed trustedSender, address indexed owner);

    /// @dev The only address that can call trustedRegister and partialTrustedRegister
    address internal trustedSender;

    /// @dev The address of the IDRegistry contract
    IDRegistry internal immutable idRegistry;

    /// @dev The address of the NameRegistry UUPS Proxy contract
    NameRegistry internal immutable nameRegistry;

    /**
     * @notice Configure the addresses of the Registry contracts and the trusted sender which is
     *        allowed to register during the invitation phase.
     *
     * @param _idRegistry The address of the IDRegistry contract
     * @param _nameRegistry The address of the NameRegistry UUPS Proxy contract
     * @param _trustedSender The address that can call trustedRegister and partialTrustedRegister
     */
    constructor(
        address _idRegistry,
        address _nameRegistry,
        address _trustedSender
    ) Ownable() {
        idRegistry = IDRegistry(_idRegistry);
        nameRegistry = NameRegistry(_nameRegistry);
        trustedSender = _trustedSender;
    }

    /**
     * @notice Register an fid and an fname during the final Mainnet phase, where registration is
     *         open to everyone.
     */
    function register(
        address to,
        address recovery,
        string calldata url,
        bytes16 username,
        bytes32 secret
    ) external payable {
        // Audit: is it possible to end up in a state where one passes but the other fails?
        idRegistry.register(to, recovery, url);

        // Audit: is there a more sane way to forward the entire balance?
        // Forward along any funds send for registration
        nameRegistry.register{value: msg.value}(username, to, secret, recovery);

        // Audit: is there a more sane way to return the entire balance?
        // Return any funds returned by the NameRegistry back to the caller
        if (address(this).balance > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = msg.sender.call{value: address(this).balance}("");
            if (!success) revert CallFailed();
        }
    }

    /**
     * @notice Register an fid and an fname during the Goerli phase, where registration can only be
     *         performed by the Farcaster Invite Server (trustedSender)
     */
    function trustedRegister(
        address to,
        address recovery,
        string calldata url,
        bytes16 username,
        uint256 inviter,
        uint256 invitee
    ) external payable {
        // Do not allow anyone except the Farcaster Invite Server (trustedSender) to call this
        if (msg.sender != trustedSender) revert Unauthorized();

        // Audit: is it possible to end up in a state where one passes but the other fails?
        idRegistry.trustedRegister(to, recovery, url);
        nameRegistry.trustedRegister(username, to, recovery, inviter, invitee);
    }

    /**
     * @notice Register an fid and an fname during the first Mainnet phase, where registration of
     *         the fid is available to all, but registration of the fname can only be performed by
     *         the Farcaster Invite Server (trustedSender)
     */
    function partialTrustedRegister(
        address to,
        address recovery,
        string calldata url,
        bytes16 username,
        uint256 inviter,
        uint256 invitee
    ) external payable {
        // Do not allow anyone except the Farcaster Invite Server (trustedSender) to call this
        if (msg.sender != trustedSender) revert Unauthorized();

        // Audit: is it possible to end up in a state where one passes but the other fails?
        idRegistry.register(to, recovery, url);
        nameRegistry.trustedRegister(username, to, recovery, inviter, invitee);
    }

    /**
     * @notice Change the trusted sender that can call trustedRegister and partialTrustedRegister
     */
    function changeTrustedSender(address newTrustedSender) external onlyOwner {
        trustedSender = newTrustedSender;
        emit ChangeTrustedSender(newTrustedSender, msg.sender);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
