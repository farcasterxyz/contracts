// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {KeyGateway} from "../../src/KeyGateway.sol";
import {KeyRegistry, IKeyRegistry} from "../../src/KeyRegistry.sol";
import {TransferHelper} from "../../src/libraries/TransferHelper.sol";
import {ISignatures} from "../../src/abstract/Signatures.sol";
import {IGuardians} from "../../src/abstract/Guardians.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";

import {KeyGatewayTestSuite} from "./KeyGatewayTestSuite.sol";

/* solhint-disable state-visibility */

contract KeyGatewayTest is KeyGatewayTestSuite {
    event Add(
        uint256 indexed fid,
        uint32 indexed keyType,
        bytes indexed key,
        bytes keyBytes,
        uint8 metadataType,
        bytes metadata
    );
    event SetUsdFee(uint256 oldFee, uint256 newFee);
    event SetVault(address oldVault, address newVault);
    event Withdraw(address indexed to, uint256 amount);

    function testVersion() public {
        assertEq(keyGateway.VERSION(), "2023.11.15");
    }

    /*//////////////////////////////////////////////////////////////
                                   ADD
    //////////////////////////////////////////////////////////////*/

    function testFuzzAdd(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);

        vm.expectEmit();
        emit Add(fid, keyType, key, key, metadataType, metadata);
        vm.prank(to);
        keyGateway.add(keyType, key, metadataType, metadata);

        assertEq(address(keyGateway).balance, 0);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 1);
        assertAdded(fid, key, keyType);
    }

    function testFuzzAddRevertsUnregisteredValidator(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);

        vm.prank(to);
        vm.expectRevert(abi.encodeWithSelector(IKeyRegistry.ValidatorNotFound.selector, keyType, metadataType));
        keyGateway.add(keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsInvalidMetadata(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        _registerValidator(keyType, metadataType);

        stubValidator.setIsValid(false);

        uint256 fid = _registerFid(to, recovery);

        vm.prank(to);
        vm.expectRevert(IKeyRegistry.InvalidMetadata.selector);
        keyGateway.add(keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsUnlessFidOwner(
        address to,
        address recovery,
        address caller,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        vm.assume(to != caller);
        _registerValidator(keyType, metadataType);

        uint256 fid = _registerFid(to, recovery);

        vm.prank(caller);
        vm.expectRevert(IKeyRegistry.Unauthorized.selector);
        keyGateway.add(keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsIfStateNotNull(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.startPrank(to);
        keyGateway.add(keyType, key, metadataType, metadata);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyGateway.add(keyType, key, metadataType, metadata);
        vm.stopPrank();

        assertAdded(fid, key, keyType);
    }

    function testFuzzAddRevertsIfRemoved(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.startPrank(to);

        keyGateway.add(keyType, key, metadataType, metadata);
        keyRegistry.remove(key);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyGateway.add(keyType, key, metadataType, metadata);

        vm.stopPrank();
        assertRemoved(fid, key, keyType);
    }

    function testFuzzAddRevertsPaused(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(owner);
        keyGateway.pause();

        vm.prank(to);
        vm.expectRevert("Pausable: paused");
        keyGateway.add(keyType, key, metadataType, metadata);
    }

    function testFuzzAddRevertsMaxKeys(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        // Create 10 keys
        for (uint256 i; i < 10; i++) {
            vm.prank(to);
            keyGateway.add(keyType, bytes.concat(key, bytes32(i)), metadataType, metadata);
        }

        // 11th key reverts
        vm.prank(to);
        vm.expectRevert(IKeyRegistry.ExceedsMaximum.selector);
        keyGateway.add(keyType, key, metadataType, metadata);
    }

    function testFuzzAddFor(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signAdd(ownerPk, owner, keyType, key, metadataType, metadata, deadline);

        vm.expectEmit();
        emit Add(fid, keyType, key, key, metadataType, metadata);
        vm.prank(registrar);
        keyGateway.addFor(owner, keyType, key, metadataType, metadata, deadline, sig);

        assertAdded(fid, key, keyType);
        assertEq(address(keyGateway).balance, 0);
    }

    function testFuzzAddForRevertsNoFid(
        address registrar,
        uint256 ownerPk,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        bytes memory sig = _signAdd(ownerPk, owner, keyType, key, metadataType, metadata, deadline);

        vm.prank(registrar);
        vm.expectRevert(IKeyRegistry.Unauthorized.selector);
        keyGateway.addFor(owner, keyType, key, metadataType, metadata, deadline, sig);
    }

    function testFuzzAddForRevertsInvalidSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signAdd(ownerPk, owner, keyType, key, metadataType, metadata, deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        keyGateway.addFor(owner, keyType, key, metadataType, metadata, deadline, sig);

        assertNull(fid, key);
    }

    function testFuzzAddForRevertsUsedNonce(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signAdd(ownerPk, owner, keyType, key, metadataType, metadata, deadline);

        vm.prank(owner);
        keyGateway.useNonce();

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        keyGateway.addFor(owner, keyType, key, metadataType, metadata, deadline, sig);

        assertNull(fid, key);
    }

    function testFuzzAddForRevertsBadSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        keyGateway.addFor(owner, keyType, key, metadataType, metadata, deadline, sig);

        assertNull(fid, key);
    }

    function testFuzzAddForRevertsExpiredSig(
        address registrar,
        uint256 fidOwnerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));

        uint256 deadline = _boundDeadline(_deadline);
        fidOwnerPk = _boundPk(fidOwnerPk);

        address fidOwner = vm.addr(fidOwnerPk);
        uint256 fid = _registerFid(fidOwner, recovery);
        bytes memory sig = _signAdd(fidOwnerPk, fidOwner, keyType, key, metadataType, metadata, deadline);

        vm.warp(deadline + 1);

        vm.startPrank(registrar);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        keyGateway.addFor(fidOwner, keyType, key, metadataType, metadata, deadline, sig);
        vm.stopPrank();

        assertNull(fid, key);
    }

    function testFuzzAddForRevertsPaused(
        address registrar,
        uint256 fidOwnerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));

        uint256 deadline = _boundDeadline(_deadline);
        fidOwnerPk = _boundPk(fidOwnerPk);

        address fidOwner = vm.addr(fidOwnerPk);
        uint256 fid = _registerFid(fidOwner, recovery);
        bytes memory sig = _signAdd(fidOwnerPk, fidOwner, keyType, key, metadataType, metadata, deadline);

        vm.prank(owner);
        keyGateway.pause();

        vm.prank(registrar);
        vm.expectRevert("Pausable: paused");
        keyGateway.addFor(fidOwner, keyType, key, metadataType, metadata, deadline, sig);

        assertNull(fid, key);
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAuthorizedCanPause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(IGuardians.OnlyGuardian.selector);
        keyGateway.pause();
    }

    function testFuzzOnlyOwnerCanUnpause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyGateway.unpause();
    }

    function testFuzzPauseUnpauseOwner() public {
        vm.prank(owner);
        keyGateway.pause();
        assertEq(keyGateway.paused(), true);

        vm.prank(owner);
        keyGateway.unpause();
        assertEq(keyGateway.paused(), false);
    }

    function testFuzzPauseUnpauseGuardian(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(owner);
        keyGateway.addGuardian(caller);

        vm.prank(caller);
        keyGateway.pause();
        assertEq(keyGateway.paused(), true);

        vm.prank(owner);
        keyGateway.unpause();
        assertEq(keyGateway.paused(), false);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerFid(address to, address recovery) internal returns (uint256) {
        vm.prank(idRegistry.idGateway());
        return idRegistry.register(to, recovery);
    }

    function assertEq(IKeyRegistry.KeyState a, IKeyRegistry.KeyState b) internal {
        assertEq(uint8(a), uint8(b));
    }

    function assertNull(uint256 fid, bytes memory key) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.NULL);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, 0);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);
    }

    function assertAdded(uint256 fid, bytes memory key, uint32 keyType) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
    }

    function assertRemoved(uint256 fid, bytes memory key, uint32 keyType) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
    }
}
