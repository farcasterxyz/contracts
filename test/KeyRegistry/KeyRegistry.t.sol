// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {KeyRegistry, IKeyRegistry} from "../../src/KeyRegistry.sol";
import {IGuardians} from "../../src/abstract/Guardians.sol";
import {ISignatures} from "../../src/abstract/Signatures.sol";
import {IMigration} from "../../src/abstract/Migration.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";

import {KeyRegistryTestSuite} from "./KeyRegistryTestSuite.sol";
import {BulkAddDataBuilder, BulkResetDataBuilder} from "./KeyRegistryTestHelpers.sol";

/* solhint-disable state-visibility */

contract KeyRegistryTest is KeyRegistryTestSuite {
    using BulkAddDataBuilder for KeyRegistry.BulkAddData[];
    using BulkResetDataBuilder for KeyRegistry.BulkResetData[];

    function setUp() public override {
        super.setUp();
    }

    event Add(
        uint256 indexed fid,
        uint32 indexed keyType,
        bytes indexed key,
        bytes keyBytes,
        uint8 metadataType,
        bytes metadata
    );
    event Remove(uint256 indexed fid, bytes indexed key, bytes keyBytes);
    event SetValidator(uint32 keyType, uint8 metadataType, address oldValidator, address newValidator);
    event SetIdRegistry(address oldIdRegistry, address newIdRegistry);
    event SetKeyGateway(address oldKeyGateway, address newKeyGateway);
    event SetMaxKeysPerFid(uint256 oldMax, uint256 newMax);
    event FreezeKeyGateway(address keyGateway);

    function testInitialIdRegistry() public {
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
    }

    function testInitialOwner() public {
        assertEq(keyRegistry.owner(), owner);
    }

    function testVersion() public {
        assertEq(keyRegistry.VERSION(), "2023.11.15");
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
        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

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

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(abi.encodeWithSelector(IKeyRegistry.ValidatorNotFound.selector, keyType, metadataType));
        keyRegistry.add(to, keyType, key, metadataType, metadata);

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

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(IKeyRegistry.InvalidMetadata.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsUnlessRegistration(
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

        vm.assume(keyRegistry.keyGateway() != caller);
        _registerValidator(keyType, metadataType);

        uint256 fid = _registerFid(to, recovery);

        vm.prank(caller);
        vm.expectRevert(IKeyRegistry.Unauthorized.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);

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

        vm.startPrank(keyRegistry.keyGateway());

        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);

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

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.prank(to);
        keyRegistry.remove(key);

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);

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
        keyRegistry.pause();

        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert("Pausable: paused");
        keyRegistry.add(to, keyType, key, metadataType, metadata);
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
            vm.prank(keyRegistry.keyGateway());
            keyRegistry.add(to, keyType, bytes.concat(key, bytes32(i)), metadataType, metadata);
        }

        // 11th key reverts
        vm.prank(keyRegistry.keyGateway());
        vm.expectRevert(IKeyRegistry.ExceedsMaximum.selector);
        keyRegistry.add(to, keyType, key, metadataType, metadata);
    }

    /*//////////////////////////////////////////////////////////////
                                 REMOVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRemove(
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

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 1);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.REMOVED), 0);
        assertEq(keyRegistry.keyAt(fid, IKeyRegistry.KeyState.ADDED, 0), key);

        vm.expectEmit();
        emit Remove(fid, key, key);
        vm.prank(to);
        keyRegistry.remove(key);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.REMOVED), 1);
        assertEq(keyRegistry.keyAt(fid, IKeyRegistry.KeyState.REMOVED, 0), key);

        assertRemoved(fid, key, keyType);
    }

    function testFuzzRemoveRevertsUnlessFidOwner(
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
        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.expectRevert(IKeyRegistry.Unauthorized.selector);
        vm.prank(caller);
        keyRegistry.remove(key);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveRevertsIfNull(address to, address recovery, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        vm.prank(to);
        keyRegistry.remove(key);

        assertNull(fid, key);
    }

    function testFuzzRemoveRevertsIfRemoved(
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

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.startPrank(to);
        keyRegistry.remove(key);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.remove(key);

        vm.stopPrank();
        assertRemoved(fid, key, keyType);
    }

    function testFuzzRemoveRevertsWhenPaused(
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

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(to, keyType, key, metadataType, metadata);

        vm.prank(to);
        keyRegistry.remove(key);

        vm.prank(owner);
        keyRegistry.pause();

        vm.prank(to);
        vm.expectRevert("Pausable: paused");
        keyRegistry.remove(key);

        assertRemoved(fid, key, keyType);
    }

    function testFuzzRemoveFor(
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
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 1);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.REMOVED), 0);
        assertEq(keyRegistry.keyAt(fid, IKeyRegistry.KeyState.ADDED, 0), key);

        vm.expectEmit();
        emit Remove(fid, key, key);
        vm.prank(registrar);
        keyRegistry.removeFor(owner, key, deadline, sig);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.REMOVED), 1);
        assertEq(keyRegistry.keyAt(fid, IKeyRegistry.KeyState.REMOVED, 0), key);

        assertRemoved(fid, key, keyType);
    }

    function testFuzzRemoveForRevertsNoFid(
        address registrar,
        uint256 ownerPk,
        bytes calldata key,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);

        address owner = vm.addr(ownerPk);
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(registrar);
        vm.expectRevert(IKeyRegistry.Unauthorized.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);
    }

    function testFuzzRemoveForRevertsInvalidSig(
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
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline + 1);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveForRevertsUsedNonce(
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
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(owner);
        keyRegistry.useNonce();

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveForRevertsBadSig(
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

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveForRevertsExpiredSig(
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
        bytes memory sig = _signRemove(ownerPk, owner, key, deadline);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(owner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.warp(deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        keyRegistry.removeFor(owner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testFuzzRemoveForRevertsWhenPaused(
        address registrar,
        uint256 fidOwnerPk,
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
        fidOwnerPk = _boundPk(fidOwnerPk);
        _registerValidator(keyType, metadataType);

        address fidOwner = vm.addr(fidOwnerPk);
        uint256 fid = _registerFid(fidOwner, recovery);
        bytes memory sig = _signRemove(fidOwnerPk, fidOwner, key, deadline);

        vm.prank(keyRegistry.keyGateway());
        keyRegistry.add(fidOwner, keyType, key, metadataType, metadata);
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);

        vm.prank(owner);
        keyRegistry.pause();

        vm.prank(registrar);
        vm.expectRevert("Pausable: paused");
        keyRegistry.removeFor(fidOwner, key, deadline, sig);

        assertAdded(fid, key, keyType);
    }

    function testRemoveTypeHash() public {
        assertEq(
            keyRegistry.REMOVE_TYPEHASH(), keccak256("Remove(address owner,bytes key,uint256 nonce,uint256 deadline)")
        );
    }

    /*//////////////////////////////////////////////////////////////
                           PAUSABILITY
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanPause(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(IGuardians.OnlyGuardian.selector);
        keyRegistry.pause();
    }

    function testPauseUnpause() public {
        assertEq(keyRegistry.paused(), false);

        vm.prank(owner);
        keyRegistry.pause();

        assertEq(keyRegistry.paused(), true);

        vm.prank(owner);
        keyRegistry.unpause();

        assertEq(keyRegistry.paused(), false);
    }

    /*//////////////////////////////////////////////////////////////
                           SET IDREGISTRY
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetIdRegistry(address caller, address idRegistry) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.setIdRegistry(idRegistry);
    }

    function testFuzzSetIdRegistry(
        address idRegistry
    ) public {
        address currentIdRegistry = address(keyRegistry.idRegistry());

        vm.expectEmit(false, false, false, true);
        emit SetIdRegistry(currentIdRegistry, idRegistry);

        vm.prank(owner);
        keyRegistry.setIdRegistry(idRegistry);

        assertEq(address(keyRegistry.idRegistry()), idRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                           SET VALIDATOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetValidator(
        address caller,
        uint32 keyType,
        uint8 metadataType,
        IMetadataValidator validator
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.setValidator(keyType, metadataType, validator);
    }

    function testFuzzSetValidatorRevertsZeroKeyType(uint8 metadataType, IMetadataValidator validator) public {
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));
        vm.prank(owner);
        vm.expectRevert(IKeyRegistry.InvalidKeyType.selector);
        keyRegistry.setValidator(0, metadataType, validator);
    }

    function testFuzzSetValidatorRevertsZeroMetadataType(uint32 keyType, IMetadataValidator validator) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        vm.prank(owner);
        vm.expectRevert(IKeyRegistry.InvalidMetadataType.selector);
        keyRegistry.setValidator(keyType, 0, validator);
    }

    function testFuzzSetValidator(uint32 keyType, uint8 metadataType, IMetadataValidator validator) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        assertEq(address(keyRegistry.validators(keyType, metadataType)), address(0));

        vm.expectEmit(false, false, false, true);
        emit SetValidator(keyType, metadataType, address(0), address(validator));

        vm.prank(owner);
        keyRegistry.setValidator(keyType, metadataType, validator);

        assertEq(address(keyRegistry.validators(keyType, metadataType)), address(validator));
    }

    /*//////////////////////////////////////////////////////////////
                           SET MAX KEYS PER FID
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetMaxKeysPerFid(address caller, uint256 newMax) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.setMaxKeysPerFid(newMax);
    }

    function testFuzzSetMaxKeysPerFid(
        uint256 newMax
    ) public {
        uint256 currentMax = keyRegistry.maxKeysPerFid();
        newMax = bound(newMax, currentMax + 1, type(uint256).max);

        vm.expectEmit(false, false, false, true);
        emit SetMaxKeysPerFid(currentMax, newMax);

        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(newMax);

        assertEq(keyRegistry.maxKeysPerFid(), newMax);
    }

    function testFuzzSetMaxKeysPerFidRevertsLessThanOrEqualToCurrentMax(
        uint256 newMax
    ) public {
        uint256 currentMax = keyRegistry.maxKeysPerFid();
        newMax = bound(newMax, 0, currentMax);

        vm.expectRevert(IKeyRegistry.InvalidMaxKeys.selector);
        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(newMax);

        assertEq(keyRegistry.maxKeysPerFid(), currentMax);
    }

    /*//////////////////////////////////////////////////////////////
                           SET KEY GATEWAY
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAdminCanSetKeyGateway(address caller, address keyGateway) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.setKeyGateway(keyGateway);
    }

    function testFuzzSetKeyGateway(
        address keyGateway
    ) public {
        address currentKeyGateway = address(keyRegistry.keyGateway());

        vm.expectEmit(false, false, false, true);
        emit SetKeyGateway(currentKeyGateway, keyGateway);

        vm.prank(owner);
        keyRegistry.setKeyGateway(keyGateway);

        assertEq(address(keyRegistry.keyGateway()), keyGateway);
    }

    function testFuzzSetKeyGatewayRevertsWhenFrozen(
        address keyGateway
    ) public {
        address currentKeyGateway = address(keyRegistry.keyGateway());

        vm.prank(owner);
        keyRegistry.freezeKeyGateway();

        vm.prank(owner);
        vm.expectRevert(IKeyRegistry.GatewayFrozen.selector);
        keyRegistry.setKeyGateway(keyGateway);

        assertEq(address(keyRegistry.keyGateway()), currentKeyGateway);
    }

    function testFreezeKeyGatewayRevertsWhenFrozen() public {
        vm.prank(owner);
        keyRegistry.freezeKeyGateway();

        vm.prank(owner);
        vm.expectRevert(IKeyRegistry.GatewayFrozen.selector);
        keyRegistry.freezeKeyGateway();
    }

    function testOnlyOwnerCanFreezeKeyGateway(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyRegistry.freezeKeyGateway();
    }

    /*//////////////////////////////////////////////////////////////
                            ENUMERATION
    //////////////////////////////////////////////////////////////*/

    function testFuzzKeysOf(address to, address recovery, uint32 keyType, uint8 metadataType, uint16 numKeys) public {
        numKeys = uint16(bound(numKeys, 1, 100));
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(100);

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);

        for (uint256 i; i < numKeys; i++) {
            (bytes memory key, bytes memory metadata) = _makeKey(i);
            vm.prank(keyRegistry.keyGateway());
            keyRegistry.add(to, keyType, key, metadataType, metadata);
        }

        bytes[] memory keys = keyRegistry.keysOf(1, IKeyRegistry.KeyState.ADDED);
        assertEq(keys.length, numKeys);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), numKeys);

        // Check keys
        for (uint256 i = 0; i < numKeys; i++) {
            (bytes memory expectedKey,) = _makeKey(i);
            assertEq(keys[i], expectedKey);
        }
        // Remove keys
        for (uint256 i = 0; i < numKeys; i++) {
            (bytes memory key,) = _makeKey(i);
            vm.prank(to);
            keyRegistry.remove(key);
        }
        bytes[] memory added = keyRegistry.keysOf(1, IKeyRegistry.KeyState.ADDED);
        assertEq(added.length, 0);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);

        bytes[] memory removed = keyRegistry.keysOf(1, IKeyRegistry.KeyState.REMOVED);
        assertEq(removed.length, numKeys);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.REMOVED), numKeys);

        // Check keys
        for (uint256 i = 0; i < numKeys; i++) {
            (bytes memory expectedKey,) = _makeKey(i);
            assertEq(removed[i], expectedKey);
        }
    }

    function testFuzzKeyAt(address to, address recovery, uint32 keyType, uint8 metadataType, uint16 numKeys) public {
        numKeys = uint16(bound(numKeys, 1, 100));
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(100);

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);

        for (uint256 i; i < numKeys; i++) {
            (bytes memory key, bytes memory metadata) = _makeKey(i);
            vm.prank(keyRegistry.keyGateway());
            keyRegistry.add(to, keyType, key, metadataType, metadata);
        }

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), numKeys);

        for (uint256 i; i < numKeys; i++) {
            (bytes memory expectedKey,) = _makeKey(i);
            assertEq(keyRegistry.keyAt(fid, IKeyRegistry.KeyState.ADDED, i), expectedKey);
        }

        // Remove keys
        for (uint256 i = 0; i < numKeys; i++) {
            (bytes memory key,) = _makeKey(i);
            vm.prank(to);
            keyRegistry.remove(key);
        }

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.REMOVED), numKeys);

        for (uint256 i; i < numKeys; i++) {
            (bytes memory expectedKey,) = _makeKey(i);
            assertEq(keyRegistry.keyAt(fid, IKeyRegistry.KeyState.REMOVED, i), expectedKey);
        }
    }

    function testFuzzKeyCounts(
        address to,
        address recovery,
        uint32 keyType,
        uint8 metadataType,
        uint16 numKeys,
        uint16 numRemove
    ) public {
        numKeys = uint16(bound(numKeys, 1, 100));
        numRemove = uint16(bound(numRemove, 1, numKeys));
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(100);

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.REMOVED), 0);

        for (uint256 i; i < numKeys; i++) {
            (bytes memory key, bytes memory metadata) = _makeKey(i);
            vm.prank(keyRegistry.keyGateway());
            keyRegistry.add(to, keyType, key, metadataType, metadata);
        }

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), numKeys);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.REMOVED), 0);

        for (uint256 i; i < numRemove; i++) {
            (bytes memory key,) = _makeKey(i);
            vm.prank(to);
            keyRegistry.remove(key);
        }

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), numKeys - numRemove);
        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.REMOVED), numRemove);
    }

    function testFuzzKeysOfPaged(address to, address recovery, bool add, uint32 keyType, uint8 metadataType) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(23);

        for (uint256 i; i < 23; i++) {
            (bytes memory key, bytes memory metadata) = _makeKey(i);
            vm.prank(keyRegistry.keyGateway());
            keyRegistry.add(to, keyType, key, metadataType, metadata);
            if (!add) {
                vm.prank(to);
                keyRegistry.remove(key);
            }
        }
        IKeyRegistry.KeyState state = add ? IKeyRegistry.KeyState.ADDED : IKeyRegistry.KeyState.REMOVED;

        (bytes[] memory page, uint256 nextIdx) = keyRegistry.keysOf(fid, state, 0, 10);
        assertEq(page.length, 10);
        assertEq(nextIdx, 10);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, nextIdx, 10);
        assertEq(page.length, 10);
        assertEq(nextIdx, 20);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, nextIdx, 10);
        assertEq(page.length, 3);
        assertEq(nextIdx, 0);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, 0, 7);
        assertEq(page.length, 7);
        assertEq(nextIdx, 7);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, nextIdx, 7);
        assertEq(page.length, 7);
        assertEq(nextIdx, 14);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, nextIdx, 7);
        assertEq(page.length, 7);
        assertEq(nextIdx, 21);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, nextIdx, 7);
        assertEq(page.length, 2);
        assertEq(nextIdx, 0);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, 0, 100);
        assertEq(page.length, 23);
        assertEq(nextIdx, 0);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, 0, 3);
        assertEq(page.length, 3);
        assertEq(nextIdx, 3);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, nextIdx, 7);
        assertEq(page.length, 7);
        assertEq(nextIdx, 10);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, nextIdx, 2);
        assertEq(page.length, 2);
        assertEq(nextIdx, 12);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, nextIdx, 9);
        assertEq(page.length, 9);
        assertEq(nextIdx, 21);

        (page, nextIdx) = keyRegistry.keysOf(fid, state, nextIdx, 4);
        assertEq(page.length, 2);
        assertEq(nextIdx, 0);
    }

    function testFuzzKeysOfPagedIndexEqualToLength(
        address to,
        address recovery,
        uint32 keyType,
        uint8 metadataType
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(23);

        for (uint256 i; i < 23; i++) {
            (bytes memory key, bytes memory metadata) = _makeKey(i);
            vm.prank(keyRegistry.keyGateway());
            keyRegistry.add(to, keyType, key, metadataType, metadata);
        }

        (bytes[] memory page, uint256 nextIdx) = keyRegistry.keysOf(fid, IKeyRegistry.KeyState.ADDED, 23, 10);
        assertEq(page.length, 0);
        assertEq(nextIdx, 0);
    }

    function testFuzzKeysOfPagedIndexGreaterThanLength(
        address to,
        address recovery,
        uint32 keyType,
        uint8 metadataType
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(23);

        for (uint256 i; i < 23; i++) {
            (bytes memory key, bytes memory metadata) = _makeKey(i);
            vm.prank(keyRegistry.keyGateway());
            keyRegistry.add(to, keyType, key, metadataType, metadata);
        }

        (bytes[] memory page, uint256 nextIdx) = keyRegistry.keysOf(fid, IKeyRegistry.KeyState.ADDED, 100, 100);
        assertEq(page.length, 0);
        assertEq(nextIdx, 0);
    }

    function testFuzzKeysOfPagedNeverReverts(
        address to,
        address recovery,
        uint32 keyType,
        uint8 metadataType,
        uint256 idx,
        uint256 size
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        vm.prank(owner);
        keyRegistry.setMaxKeysPerFid(23);

        for (uint256 i; i < 23; i++) {
            (bytes memory key, bytes memory metadata) = _makeKey(i);
            vm.prank(keyRegistry.keyGateway());
            keyRegistry.add(to, keyType, key, metadataType, metadata);
        }

        keyRegistry.keysOf(fid, IKeyRegistry.KeyState.ADDED, idx, size);
    }

    function testFuzzKeyHelpersRevertInvalidState() public {
        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.totalKeys(0, IKeyRegistry.KeyState.NULL);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.keyAt(0, IKeyRegistry.KeyState.NULL, 0);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.keysOf(0, IKeyRegistry.KeyState.NULL);

        vm.expectRevert(IKeyRegistry.InvalidState.selector);
        keyRegistry.keysOf(0, IKeyRegistry.KeyState.NULL, 0, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _makeKey(
        uint256 i
    ) internal pure returns (bytes memory key, bytes memory metadata) {
        key = abi.encodePacked(keccak256(abi.encodePacked("key", i)));
        metadata = abi.encodePacked(keccak256(abi.encodePacked("metadata", i)));
    }

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
