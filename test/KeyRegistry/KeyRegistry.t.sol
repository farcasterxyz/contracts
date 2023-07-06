// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../TestConstants.sol";
import {KeyRegistry} from "../../src/KeyRegistry.sol";
import {KeyRegistryTestSuite} from "./KeyRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract KeyRegistryTest is KeyRegistryTestSuite {
    event Register(uint256 indexed fid, uint256 indexed scope, bytes indexed key);
    event Revoke(uint256 indexed fid, uint256 indexed scope, bytes indexed key);
    event Freeze(uint256 indexed fid, uint256 indexed scope, bytes indexed key);

    function testInitialIdRegistry() public {
        assertEq(address(keyRegistry.idRegistry()), address(idRegistry));
    }

    function testInitialMigrationTimestamp() public {
        assertEq(keyRegistry.signersMigratedAt(), 0);
    }

    function testInitialOwner() public {
        assertEq(keyRegistry.owner(), admin);
    }

    function testInitialStateIsNotMigrated() public {
        assertEq(keyRegistry.isMigrated(), false);
    }

    function testFuzzAddRevokeSigner(address to, address recovery, uint256 scope, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);
        assertEq(keyRegistry.signerOf(fid, scope, key).state, KeyRegistry.SignerState.AUTHORIZED);

        keyRegistry.revoke(fid, scope, key);
        assertEq(keyRegistry.signerOf(fid, scope, key).state, KeyRegistry.SignerState.REVOKED);

        vm.stopPrank();
    }

    function testFuzzAddEmitsEvent(address to, address recovery, uint256 scope, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        vm.expectEmit();
        emit Register(fid, scope, key);
        keyRegistry.register(fid, scope, key);

        vm.stopPrank();
    }

    function testFuzzRevokeEmitsEvent(address to, address recovery, uint256 scope, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);

        vm.expectEmit();
        emit Revoke(fid, scope, key);
        keyRegistry.revoke(fid, scope, key);

        vm.stopPrank();
    }

    function testFuzzFreezeEmitsEvent(
        address to,
        address recovery,
        uint256 scope,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);

        vm.expectEmit();
        emit Freeze(fid, scope, key);
        keyRegistry.freeze(fid, scope, key, merkleRoot);

        vm.stopPrank();
    }

    function testFuzzAddRevertsNonOwner(
        address to,
        address recovery,
        address caller,
        uint256 scope,
        bytes calldata key
    ) public {
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(caller);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyRegistry.register(fid, scope, key);

        vm.stopPrank();
    }

    function testFuzzAddRevertsAuthorized(address to, address recovery, uint256 scope, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.register(fid, scope, key);

        vm.stopPrank();
    }

    function testFuzzAddRevertsFrozen(
        address to,
        address recovery,
        uint256 scope,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);
        keyRegistry.freeze(fid, scope, key, merkleRoot);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.register(fid, scope, key);

        vm.stopPrank();
    }

    function testFuzzAddRevertsRevoked(address to, address recovery, uint256 scope, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);
        keyRegistry.revoke(fid, scope, key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.register(fid, scope, key);

        vm.stopPrank();
    }

    function testFuzzRevokeRevertsNonOwner(
        address to,
        address recovery,
        address caller,
        uint256 scope,
        bytes calldata key
    ) public {
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);
        vm.prank(to);
        keyRegistry.register(fid, scope, key);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        vm.prank(caller);
        keyRegistry.revoke(fid, scope, key);
    }

    function testFuzzRevokeRevertsUninitialized(
        address to,
        address recovery,
        uint256 scope,
        bytes calldata key
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.revoke(fid, scope, key);

        vm.stopPrank();
    }

    function testFuzzRevokeRevertsRevoked(address to, address recovery, uint256 scope, bytes calldata key) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);
        keyRegistry.revoke(fid, scope, key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.revoke(fid, scope, key);

        vm.stopPrank();
    }

    function testFuzzAddFreezeSigner(
        address to,
        address recovery,
        uint256 scope,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);
        assertEq(keyRegistry.signerOf(fid, scope, key).state, KeyRegistry.SignerState.AUTHORIZED);

        keyRegistry.freeze(fid, scope, key, merkleRoot);
        KeyRegistry.Signer memory signer = keyRegistry.signerOf(fid, scope, key);
        assertEq(signer.state, KeyRegistry.SignerState.FROZEN);
        assertEq(signer.merkleRoot, merkleRoot);

        vm.stopPrank();
    }

    function testFuzzFreezeRevertsNonOwner(
        address to,
        address recovery,
        address caller,
        uint256 scope,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        vm.assume(to != caller);

        uint256 fid = _registerFid(to, recovery);
        vm.prank(to);
        keyRegistry.register(fid, scope, key);

        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        vm.prank(caller);
        keyRegistry.freeze(fid, scope, key, merkleRoot);
    }

    function testFuzzFreezeRevertsUninitialized(
        address to,
        address recovery,
        uint256 scope,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.freeze(fid, scope, key, merkleRoot);

        vm.stopPrank();
    }

    function testFuzzFreezeRevertsFrozen(
        address to,
        address recovery,
        uint256 scope,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);
        assertEq(keyRegistry.signerOf(fid, scope, key).state, KeyRegistry.SignerState.AUTHORIZED);

        keyRegistry.freeze(fid, scope, key, merkleRoot);
        KeyRegistry.Signer memory signer = keyRegistry.signerOf(fid, scope, key);
        assertEq(signer.state, KeyRegistry.SignerState.FROZEN);
        assertEq(signer.merkleRoot, merkleRoot);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.freeze(fid, scope, key, merkleRoot);

        vm.stopPrank();
    }

    function testFuzzFreezeRevertsRevoked(
        address to,
        address recovery,
        uint256 scope,
        bytes calldata key,
        bytes32 merkleRoot
    ) public {
        uint256 fid = _registerFid(to, recovery);
        vm.startPrank(to);

        keyRegistry.register(fid, scope, key);
        assertEq(keyRegistry.signerOf(fid, scope, key).state, KeyRegistry.SignerState.AUTHORIZED);

        keyRegistry.revoke(fid, scope, key);
        assertEq(keyRegistry.signerOf(fid, scope, key).state, KeyRegistry.SignerState.REVOKED);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyRegistry.freeze(fid, scope, key, merkleRoot);

        vm.stopPrank();
    }

    function _registerFid(address to, address recovery) internal returns (uint256) {
        return idRegistry.register(to, recovery);
    }

    function assertEq(KeyRegistry.SignerState a, KeyRegistry.SignerState b) internal {
        assertEq(uint8(a), uint8(b));
    }
}
