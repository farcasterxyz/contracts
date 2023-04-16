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

    EnumerableSet.AddressSet internal _actors;
    EnumerableSet.AddressSet internal _fidOwners;
    EnumerableSet.AddressSet internal _recoveryAddrs;

    address internal currentActor;

    mapping(uint256 => address) internal _ownersByFid;
    mapping(address => uint256[]) internal _fidsByRecoveryAddr;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    IdRegistryHarness idRegistry;
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
        if (idRegistry.idOf(to) == 0) {
            idRegistry.register(to, recovery);

            _actors.add(to);
            _actors.add(recovery);
            _fidOwners.add(to);
            _recoveryAddrs.add(recovery);
        }
    }

    function transfer(uint256 seed, address to) public useFidOwner(seed) {
        if (_fidOwners.length() > 0 && idRegistry.idOf(to) == 0) {
            vm.prank(currentActor);
            idRegistry.transfer(to);

            _actors.add(to);
            _fidOwners.remove(currentActor);
            _fidOwners.add(to);
        }
    }

    function changeRecoveryAddress(uint256 seed, address recovery) public useFidOwner(seed) {
        if (_fidOwners.length() > 0) {
            vm.prank(currentActor);
            idRegistry.changeRecoveryAddress(recovery);

            _actors.add(recovery);
        }
    }

    function fidsByRecoveryAddr(address recovery) public returns (uint256[] memory) {
        _constructOwnersByFidMapping();
        return _fidsByRecoveryAddr[recovery];
    }

    function ownerOf(uint256 fid) public returns (address) {
        _constructOwnersByFidMapping();
        return _ownersByFid[fid];
    }

    function _constructFidsByRecoveryAddrMapping() internal {
        for (uint256 i; i < idRegistry.getIdCounter(); ++i) {
            address recovery = idRegistry.getRecoveryOf(i);
            if (recovery != address(0)) {
                _fidsByRecoveryAddr[recovery].push(i);
            }
        }
    }

    function _constructOwnersByFidMapping() internal {
        for (uint256 i; i < _actors.length(); ++i) {
            address actor = _actors.at(i);
            uint256 fid = idRegistry.idOf(actor);
            if (fid != 0) {
                _ownersByFid[fid] = actor;
            }
        }
    }
}
