// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {IdRegistryHarness, LibAddressSet} from "../../Utils.sol";

import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/* solhint-disable state-visibility */

contract IdRegistryHandler is CommonBase, StdCheats, StdUtils {
    using EnumerableSet for EnumerableSet.AddressSet;
    using LibAddressSet for EnumerableSet.AddressSet;

    IdRegistryHarness idRegistry;

    EnumerableSet.AddressSet internal _fidOwners;
    EnumerableSet.AddressSet internal _recoveryAddrs;

    address internal currentActor;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);

    address owner;

    modifier useFidOwner(uint256 ownerIndexSeed) {
        currentActor = _fidOwners.rand(ownerIndexSeed);
        _;
    }

    constructor(IdRegistryHarness _idRegistry, address _owner) {
        idRegistry = _idRegistry;
        owner = _owner;
    }

    function fidOwners() external view returns (address[] memory) {
        return _fidOwners.values();
    }

    function recoveryAddrs() external view returns (address[] memory) {
        return _recoveryAddrs.values();
    }

    function register(address to, address recovery) public {
        idRegistry.register(to, recovery);

        _fidOwners.add(to);
        _recoveryAddrs.add(recovery);
    }

    function transfer(uint256 seed, address to) public useFidOwner(seed) {
        if (_fidOwners.length() > 0) {
            vm.prank(currentActor);
            idRegistry.transfer(to);

            _fidOwners.remove(currentActor);
            _fidOwners.add(to);
        }
    }

    function changeRecoveryAddress(uint256 seed, address recovery) public useFidOwner(seed) {
        if (_fidOwners.length() > 0) {
            uint256 fid = idRegistry.idOf(currentActor);
            address oldRecovery = idRegistry.getRecoveryOf(fid);

            vm.prank(currentActor);
            idRegistry.changeRecoveryAddress(recovery);

            _recoveryAddrs.remove(oldRecovery);
            _recoveryAddrs.add(recovery);
        }
    }
}
