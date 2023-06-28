// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";

import {IdRegistry} from "./IdRegistry.sol";
import {StorageRent} from "./StorageRent.sol";

contract Bundler is Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Revert when the caller does not have the authority to perform the action
    error Unauthorized();

    /// @dev Revert when excess funds could not be sent back to the caller
    error CallFailed();
    error InsufficientFunds();

    /// @dev Revert when an invalid address is provided as input.
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emit when the trustedCaller is changed by the owner after the contract is deployed
    event ChangeTrustedCaller(address indexed trustedCaller, address indexed owner);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

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
    constructor(address _idRegistry, address _storageRent, address _trustedCaller) Ownable() {
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
        storageRent.rent{value: msg.value}(fid, storageUnits);

        if (address(this).balance > 0) {
            _sendNative(msg.sender, address(this).balance);
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
     * @notice Change the trusted caller that can call trustedRegister
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
