// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

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

    /// @dev Emit when the trustedCaller is changed by the owner after the contract is deployed
    event ChangeTrustedCaller(address indexed trustedCaller, address indexed owner);

    /// @dev The only address that can call trustedRegister and partialTrustedRegister
    address internal trustedCaller;

    /// @dev The address of the IDRegistry contract
    IDRegistry internal immutable idRegistry;

    /// @dev The address of the NameRegistry UUPS Proxy contract
    NameRegistry internal immutable nameRegistry;

    /**
     * @notice Configure the addresses of the Registry contracts and the trusted caller which is
     *        allowed to register during the invitation phase.
     *
     * @param _idRegistry The address of the IDRegistry contract
     * @param _nameRegistry The address of the NameRegistry UUPS Proxy contract
     * @param _trustedCaller The address that can call trustedRegister and partialTrustedRegister
     */
    constructor(
        address _idRegistry,
        address _nameRegistry,
        address _trustedCaller
    ) Ownable() {
        idRegistry = IDRegistry(_idRegistry);
        nameRegistry = NameRegistry(_nameRegistry);
        trustedCaller = _trustedCaller;
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

        nameRegistry.register{value: msg.value}(username, to, secret, recovery);

        // Return any funds returned by the NameRegistry back to the caller
        if (address(this).balance > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = msg.sender.call{value: address(this).balance}("");
            if (!success) revert CallFailed();
        }
    }

    /**
     * @notice Register an fid and an fname during the Goerli phase, where registration can only be
     *         performed by the Farcaster Invite Server (trustedCaller)
     */
    function trustedRegister(
        address to,
        address recovery,
        string calldata url,
        bytes16 username,
        uint256 inviter
    ) external payable {
        // Do not allow anyone except the Farcaster Invite Server (trustedCaller) to call this
        if (msg.sender != trustedCaller) revert Unauthorized();

        // Audit: is it possible to end up in a state where one passes but the other fails?
        idRegistry.trustedRegister(to, recovery, url);
        nameRegistry.trustedRegister(username, to, recovery, inviter, idRegistry.idOf(to));
    }

    /**
     * @notice Register an fid and an fname during the first Mainnet phase, where registration of
     *         the fid is available to all, but registration of the fname can only be performed by
     *         the Farcaster Invite Server (trustedCaller)
     */
    function partialTrustedRegister(
        address to,
        address recovery,
        string calldata url,
        bytes16 username,
        uint256 inviter
    ) external payable {
        // Do not allow anyone except the Farcaster Invite Server (trustedCaller) to call this
        if (msg.sender != trustedCaller) revert Unauthorized();

        // Audit: is it possible to end up in a state where one passes but the other fails?
        idRegistry.register(to, recovery, url);
        nameRegistry.trustedRegister(username, to, recovery, inviter, idRegistry.idOf(to));
    }

    /**
     * @notice Change the trusted caller that can call trustedRegister and partialTrustedRegister
     */
    function changeTrustedCaller(address newTrustedCaller) external onlyOwner {
        trustedCaller = newTrustedCaller;
        emit ChangeTrustedCaller(newTrustedCaller, msg.sender);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
