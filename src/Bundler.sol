// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";

import {IdRegistry} from "./IdRegistry.sol";
import {StorageRent} from "./StorageRent.sol";

contract Bundler is Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert when the caller does not have the authority to perform the action.
    error Unauthorized();

    /// @dev Revert when excess funds could not be sent back to the caller.
    error CallFailed();

    /// @dev Revert if there aren't enough funds to return to the caller.
    error InsufficientFunds();

    /// @dev Revert when an invalid address is provided as input.
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emit when the trustedCaller is changed by the owner after the contract is deployed.
    event ChangeTrustedCaller(address indexed trustedCaller, address indexed owner);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The data required to trustedBatchRegister a single user
    struct UserData {
        address to;
        uint256 units;
    }

    /// @dev The only address that can call trustedRegister and partialTrustedRegister
    address public trustedCaller;

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev The address of the IdRegistry contract
    IdRegistry public immutable idRegistry;

    /// @dev The address of the NameRegistry UUPS Proxy contract
    StorageRent public immutable storageRent;

    /**
     * @notice Configure the addresses of the Registry contracts and the trusted caller which is
     *        allowed to register during the bootstrap phase.
     *
     * @param _idRegistry The address of the IdRegistry contract
     * @param _storageRent The address of the StorageRent contract
     * @param _trustedCaller The address that can call trustedRegister and partialTrustedRegister
     */
    constructor(address _idRegistry, address _storageRent, address _trustedCaller) Ownable2Step() {
        idRegistry = IdRegistry(_idRegistry);
        storageRent = StorageRent(_storageRent);
        trustedCaller = _trustedCaller;
    }

    /**
     * @notice Register an fid and rent storage during the final Mainnet phase, where registration is
     *         open to everyone.
     */
    function register(address to, address recovery, uint256 storageUnits) external payable {
        uint256 fid = idRegistry.register(to, recovery);
        uint256 overpayment = storageRent.rent{value: msg.value}(fid, storageUnits);

        if (overpayment > 0) {
            _sendNative(msg.sender, overpayment);
        }
    }

    /**
     * @notice Register an fid and credit storage during the testnet phase, where registration can only be
     *         performed by the Farcaster Bootstrap Server (trustedCaller)
     */
    function trustedRegister(address to, address recovery, uint256 storageUnits) external {
        // Do not allow anyone except the Farcaster Bootstrap Server (trustedCaller) to call this
        if (msg.sender != trustedCaller) revert Unauthorized();

        uint256 fid = idRegistry.trustedRegister(to, recovery);
        storageRent.credit(fid, storageUnits);
    }

    /**
     * @notice Register multiple fids with storage during a migration to a new network, where
     *         registration can only be performed by the Farcaster Bootstrap Server (trustedCaller).
     *         Recovery address is initialized to a default value, which will be the Warpcast server.
     */
    function trustedBatchRegister(UserData[] calldata users, address recovery) external {
        // Do not allow anyone except the Farcaster Bootstrap Server (trustedCaller) to call this
        if (msg.sender != trustedCaller) revert Unauthorized();

        // Safety: calls inside a loop are safe since caller is trusted
        for (uint256 i = 0; i < users.length; i++) {
            uint256 fid = idRegistry.trustedRegister(users[i].to, recovery);
            storageRent.credit(fid, users[i].units);
        }
    }

    /**
     * @notice Change the trusted caller that can call trustedRegister functions
     */
    function changeTrustedCaller(address _trustedCaller) external onlyOwner {
        if (_trustedCaller == address(0)) revert InvalidAddress();

        trustedCaller = _trustedCaller;
        emit ChangeTrustedCaller(_trustedCaller, msg.sender);
    }

    /**
     * @dev Native token transfer helper.
     */
    function _sendNative(address to, uint256 amount) internal {
        if (address(this).balance < amount) revert InsufficientFunds();
        (bool success,) = payable(to).call{value: amount}("");
        if (!success) revert CallFailed();
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
