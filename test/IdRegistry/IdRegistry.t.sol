// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {IdRegistry} from "../../src/IdRegistry.sol";
import {TrustedCaller} from "../../src/lib/TrustedCaller.sol";
import {Signatures} from "../../src/lib/Signatures.sol";
import {IdRegistryTestSuite} from "./IdRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract IdRegistryTest is IdRegistryTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery);
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);

    /*//////////////////////////////////////////////////////////////
                             REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegister(address caller, address recovery) public {
        assertEq(idRegistry.getIdCounter(), 0);

        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.expectEmit(true, true, true, true);
        emit Register(caller, 1, recovery);
        vm.prank(caller);
        idRegistry.register(recovery);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotRegisterIfSeedable(address caller, address recovery) public {
        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.getTrustedOnly(), 1);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(caller);
        vm.expectRevert(TrustedCaller.Seedable.selector);
        idRegistry.register(recovery);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterToAnAddressThatOwnsAnId(address caller, address recovery) public {
        _register(caller);

        assertEq(idRegistry.getIdCounter(), 1);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(caller);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.register(recovery);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterIfPaused(address caller, address recovery) public {
        assertEq(idRegistry.getIdCounter(), 0);

        vm.prank(owner);
        idRegistry.disableTrustedOnly();
        _pause();

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(caller);
        vm.expectRevert("Pausable: paused");
        idRegistry.register(recovery);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                           REGISTER FOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegisterFor(address registrar, uint256 recipientPk, address recovery, uint40 _deadline) public {
        uint256 deadline = _boundDeadline(_deadline);
        recipientPk = _boundPk(recipientPk);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline);

        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.expectEmit(true, true, true, true);
        emit Register(recipient, 1, recovery);
        vm.prank(registrar);
        idRegistry.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzRegisterForRevertsInvalidSig(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline
    ) public {
        recipientPk = _boundPk(recipientPk);
        uint256 deadline = _boundDeadline(_deadline);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline + 1);

        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(Signatures.InvalidSignature.selector);
        idRegistry.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzRegisterForRevertsBadSig(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline
    ) public {
        recipientPk = _boundPk(recipientPk);
        uint256 deadline = _boundDeadline(_deadline);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(Signatures.InvalidSignature.selector);
        idRegistry.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzRegisterForRevertsExpiredSig(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline
    ) public {
        recipientPk = _boundPk(recipientPk);
        uint256 deadline = _boundDeadline(_deadline);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline);

        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        vm.warp(deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(Signatures.SignatureExpired.selector);
        idRegistry.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterForIfSeedable(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline
    ) public {
        recipientPk = _boundPk(recipientPk);
        uint256 deadline = _boundDeadline(_deadline);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline);

        assertEq(idRegistry.getTrustedOnly(), 1);
        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(TrustedCaller.Seedable.selector);
        idRegistry.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterForToAnAddressThatOwnsAnId(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline
    ) public {
        recipientPk = _boundPk(recipientPk);
        uint256 deadline = _boundDeadline(_deadline);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline);

        vm.prank(owner);
        idRegistry.disableTrustedOnly();
        _register(recipient);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterForIfPaused(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline
    ) public {
        recipientPk = _boundPk(recipientPk);
        uint256 deadline = _boundDeadline(_deadline);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline);

        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        _pause();

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert("Pausable: paused");
        idRegistry.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         TRUSTED REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTrustedRegister(address recipient, address trustedCaller, address recovery) public {
        vm.assume(trustedCaller != address(0));
        vm.prank(owner);
        idRegistry.setTrustedCaller(trustedCaller);
        assertEq(idRegistry.getIdCounter(), 0);

        vm.prank(trustedCaller);
        vm.expectEmit(true, true, true, true);
        emit Register(recipient, 1, recovery);
        idRegistry.trustedRegister(recipient, recovery);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotTrustedRegisterUnlessTrustedCallerOnly(
        address alice,
        address trustedCaller,
        address recovery
    ) public {
        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        vm.prank(trustedCaller);
        vm.expectRevert(TrustedCaller.Registrable.selector);
        idRegistry.trustedRegister(alice, recovery);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotTrustedRegisterFromUntrustedCaller(
        address alice,
        address trustedCaller,
        address untrustedCaller,
        address recovery
    ) public {
        vm.assume(untrustedCaller != trustedCaller);
        vm.assume(trustedCaller != address(0));
        vm.prank(owner);
        idRegistry.setTrustedCaller(trustedCaller);

        vm.prank(untrustedCaller);
        vm.expectRevert(TrustedCaller.OnlyTrustedCaller.selector);
        idRegistry.trustedRegister(alice, recovery);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotTrustedRegisterToAnAddressThatOwnsAnID(
        address alice,
        address trustedCaller,
        address recovery
    ) public {
        vm.assume(trustedCaller != address(0));
        vm.prank(owner);
        idRegistry.setTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        idRegistry.trustedRegister(alice, address(0));
        assertEq(idRegistry.getIdCounter(), 1);

        vm.prank(trustedCaller);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.trustedRegister(alice, recovery);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotTrustedRegisterWhenPaused(address alice, address trustedCaller, address recovery) public {
        vm.assume(trustedCaller != address(0));
        vm.prank(owner);
        idRegistry.setTrustedCaller(trustedCaller);
        assertEq(idRegistry.getIdCounter(), 0);

        _pause();

        vm.prank(trustedCaller);
        vm.expectRevert("Pausable: paused");
        idRegistry.trustedRegister(alice, recovery);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransfer(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, 1);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 1);
    }

    function testFuzzTransferRevertsInvalidSig(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline + 1);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(from);
        vm.expectRevert(Signatures.InvalidSignature.selector);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferRevertsBadSig(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        _register(from);
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);

        vm.expectRevert(Signatures.InvalidSignature.selector);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferRevertsExpiredSig(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(deadline + 1);

        vm.expectRevert(Signatures.SignatureExpired.selector);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferDoesntResetRecovery(
        address from,
        uint256 toPk,
        uint40 _deadline,
        address recovery
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, 1);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotTransferWhenPaused(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);

        _pause();

        vm.prank(from);
        vm.expectRevert("Pausable: paused");
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzCannotTransferToAddressWithId(
        address from,
        uint256 toPk,
        uint40 _deadline,
        address recovery
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        _registerWithRecovery(to, recovery);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.getIdCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 2);

        vm.expectRevert(IdRegistry.HasId.selector);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 2);
    }

    function testFuzzCannotTransferIfNoId(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = 1;
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 0);

        vm.expectRevert(IdRegistry.HasNoId.selector);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferReregister(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 1);

        _register(from);
        assertEq(idRegistry.getIdCounter(), 2);
        assertEq(idRegistry.idOf(from), 2);
        assertEq(idRegistry.idOf(to), 1);
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzChangeRecoveryAddress(address alice, address oldRecovery, address newRecovery) public {
        _registerWithRecovery(alice, oldRecovery);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ChangeRecoveryAddress(1, newRecovery);
        idRegistry.changeRecoveryAddress(newRecovery);

        assertEq(idRegistry.getRecoveryOf(1), newRecovery);
    }

    function testFuzzCannotChangeRecoveryAddressWhenPaused(
        address alice,
        address oldRecovery,
        address newRecovery
    ) public {
        vm.assume(oldRecovery != newRecovery);
        _registerWithRecovery(alice, oldRecovery);
        _pause();

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        idRegistry.changeRecoveryAddress(newRecovery);

        assertEq(idRegistry.getRecoveryOf(1), oldRecovery);
    }

    function testFuzzCannotChangeRecoveryAddressWithoutId(address alice, address bob) public {
        vm.assume(alice != bob);

        vm.prank(alice);
        vm.expectRevert(IdRegistry.HasNoId.selector);
        idRegistry.changeRecoveryAddress(bob);
    }

    /*//////////////////////////////////////////////////////////////
                            RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRecover(address from, uint256 toPk, uint40 _deadline, address recovery) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);

        vm.prank(recovery);
        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, 1);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzRecoverRevertsInvalidSig(address from, uint256 toPk, uint40 _deadline, address recovery) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline + 1);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);

        vm.expectRevert(Signatures.InvalidSignature.selector);
        vm.prank(recovery);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzRecoverRevertsBadSig(address from, uint256 toPk, uint40 _deadline, address recovery) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        _registerWithRecovery(from, recovery);
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);

        vm.expectRevert(Signatures.InvalidSignature.selector);
        vm.prank(recovery);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzRecoverRevertsExpiredSig(address from, uint256 toPk, uint40 _deadline, address recovery) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(deadline + 1);

        vm.expectRevert(Signatures.SignatureExpired.selector);
        vm.prank(recovery);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.getIdCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzCannotRecoverWhenPaused(address from, uint256 toPk, uint40 _deadline, address recovery) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        _pause();

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);

        vm.prank(recovery);
        vm.expectRevert("Pausable: paused");
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotRecoverWithoutId(address from, uint256 toPk, uint40 _deadline, address recovery) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = 1;
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));

        vm.prank(recovery);
        vm.expectRevert(IdRegistry.HasNoId.selector);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.getRecoveryOf(1), address(0));
    }

    function testFuzzCannotRecoverUnlessRecoveryAddress(
        address from,
        uint256 toPk,
        uint40 _deadline,
        address recovery,
        address notRecovery
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != notRecovery && from != notRecovery);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);

        vm.prank(notRecovery);
        vm.expectRevert(IdRegistry.Unauthorized.selector);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
    }

    function testFuzzCannotRecoverToAddressThatOwnsAnId(
        address from,
        uint256 toPk,
        uint40 _deadline,
        address recovery
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        _register(to);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 2);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
        assertEq(idRegistry.getRecoveryOf(2), address(0));

        vm.prank(recovery);
        vm.expectRevert(IdRegistry.HasId.selector);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.idOf(to), 2);
        assertEq(idRegistry.getRecoveryOf(1), recovery);
        assertEq(idRegistry.getRecoveryOf(2), address(0));
    }
}
