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

    mapping(uint256 => address) internal _ownerOf;
    mapping(address => uint256[]) internal _fidsByRecoveryAddr;

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
        if (idRegistry.idOf(to) == 0 && idRegistry.idOf(to) == 0) {
            idRegistry.register(to, recovery);
            uint256 fid = idRegistry.idOf(to);

            _ownerOf[fid] = to;
            _fidOwners.add(to);
            _recoveryAddrs.add(recovery);
            _saveFidByRecoveryAddr(fid, recovery);
        }
    }

    function transfer(uint256 seed, address to) public useFidOwner(seed) {
        if (_fidOwners.length() > 0 && idRegistry.idOf(to) == 0) {
            uint256 fid = idRegistry.idOf(currentActor);
            address recovery = idRegistry.getRecoveryOf(fid);

            vm.prank(currentActor);
            idRegistry.transfer(to);

            _ownerOf[fid] = to;
            _fidOwners.remove(currentActor);
            _fidOwners.add(to);
            _removeFidByRecoveryAddr(fid, recovery);
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
            _removeFidByRecoveryAddr(fid, oldRecovery);
        }
    }

    function fidsByRecoveryAddr(address recovery) public view returns (uint256[] memory) {
        return _fidsByRecoveryAddr[recovery];
    }

    function ownerOf(uint256 fid) public view returns (address) {
        return _ownerOf[fid];
    }

    function _saveFidByRecoveryAddr(uint256 fid, address recovery) internal {
        _fidsByRecoveryAddr[recovery].push(fid);
    }

    function _removeFidByRecoveryAddr(uint256 fid, address recovery) internal {
        uint256[] memory fids = _fidsByRecoveryAddr[recovery];
        uint256[] memory newFids = new uint256[](fids.length);
        uint256 len;
        for (uint256 i; i < fids.length; ++i) {
            if (fids[i] != fid) {
                newFids[i] = fids[i];
                ++len;
            }
        }
        assembly {
            mstore(newFids, len)
        }
        _fidsByRecoveryAddr[recovery] = newFids;
    }
}
