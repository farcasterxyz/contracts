// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {IdRegistry, IIdRegistry} from "../../src/IdRegistry.sol";
import {ISignatures} from "../../src/abstract/Signatures.sol";
import {IMigration} from "../../src/interfaces/abstract/IMigration.sol";
import {ERC1271WalletMock, ERC1271MaliciousMockForceRevert} from "../Utils.sol";

import {IdRegistryTestSuite} from "./IdRegistryTestSuite.sol";
import {BulkRegisterDataBuilder, BulkRegisterDefaultRecoveryDataBuilder} from "./IdRegistryTestHelpers.sol";

/* solhint-disable state-visibility */

contract IdRegistryTest is IdRegistryTestSuite {
    using BulkRegisterDataBuilder for IIdRegistry.BulkRegisterData[];
    using BulkRegisterDefaultRecoveryDataBuilder for IIdRegistry.BulkRegisterDefaultRecoveryData[];

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery);
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Recover(address indexed from, address indexed to, uint256 indexed id);
    event ChangeRecoveryAddress(uint256 indexed id, address indexed recovery);
    event SetIdGateway(address oldIdGateway, address newIdGateway);
    event FreezeIdGateway(address idGateway);

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function testVersion() public {
        assertEq(idRegistry.VERSION(), "2023.11.15");
    }

    function testName() public {
        assertEq(idRegistry.name(), "Farcaster FID");
    }

    /*//////////////////////////////////////////////////////////////
                             REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegister(address to, address recovery) public {
        assertEq(idRegistry.idCounter(), 0);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.custodyOf(1), address(0));
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.expectEmit();
        emit Register(to, 1, recovery);
        vm.prank(idRegistry.idGateway());
        idRegistry.register(to, recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzCannotRegisterToAnAddressThatOwnsAnId(address to, address recovery) public {
        _register(to);

        assertEq(idRegistry.idCounter(), 1);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(idRegistry.idGateway());
        vm.expectRevert(IIdRegistry.HasId.selector);
        idRegistry.register(to, recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterIfPaused(address to, address recovery) public {
        assertEq(idRegistry.idCounter(), 0);

        _pause();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.custodyOf(1), address(0));
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(idRegistry.idGateway());
        vm.expectRevert("Pausable: paused");
        idRegistry.register(to, recovery);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.custodyOf(1), address(0));
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzRegisterRevertsUnauthorized(address caller, address to, address recovery) public {
        vm.assume(caller != idRegistry.idGateway());
        assertEq(idRegistry.idCounter(), 0);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.custodyOf(1), address(0));
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.Unauthorized.selector);
        idRegistry.register(to, recovery);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.custodyOf(1), address(0));
        assertEq(idRegistry.recoveryOf(1), address(0));
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

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, 1);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.idOf(to), 1);
    }

    function testFuzzTransferRevertsInvalidSig(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        /* generate a signature with an invalid parameter (wrong deadline) */
        bytes memory sig = _signTransfer(toPk, fid, to, deadline + 1);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(from);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferRevertsBadSig(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        _register(from);
        /* generate an invalid signature */
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.expectRevert(ISignatures.InvalidSignature.selector);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferRevertsExpiredSig(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(deadline + 1);

        vm.expectRevert(ISignatures.SignatureExpired.selector);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
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

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), recovery);

        vm.expectEmit();
        emit Transfer(from, to, 1);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzCannotTransferWhenPaused(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        _pause();

        vm.prank(from);
        vm.expectRevert("Pausable: paused");
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
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

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);

        vm.expectRevert(IIdRegistry.HasId.selector);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);
    }

    function testFuzzCannotTransferIfNoId(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = 1;
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(fid), address(0));
        assertEq(idRegistry.idOf(to), 0);

        vm.expectRevert(IIdRegistry.HasNoId.selector);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(fid), address(0));
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferReregister(address from, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.idOf(to), 1);

        _register(from);
        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 2);
        assertEq(idRegistry.custodyOf(2), from);
        assertEq(idRegistry.idOf(to), 1);
    }

    function testTransferTypehash() public {
        assertEq(
            idRegistry.TRANSFER_TYPEHASH(), keccak256("Transfer(uint256 fid,address to,uint256 nonce,uint256 deadline)")
        );
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER FOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferFor(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        address recoveryBefore = idRegistry.recoveryOf(fid);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, 1);
        vm.prank(caller);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.recoveryOf(fid), recoveryBefore);
    }

    function testFuzzTransferForRevertsInvalidFromSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        /* generate a signature with an invalid parameter (wrong deadline) */
        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline + 1);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsInvalidToSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline);
        /* generate a signature with an invalid parameter (wrong deadline) */
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline + 1);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsUsedFromNonce(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        vm.prank(from);
        idRegistry.useNonce();

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsUsedToNonce(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        vm.prank(to);
        idRegistry.useNonce();

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsBadFromSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        /* generate an invalid signature */
        bytes memory fromSig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsBadToSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline);
        /* generate an invalid signature */
        bytes memory toSig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsExpiredFromSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(fromDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsExpiredToSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(toDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzCannotTransferForToAddressWithId(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);
        _register(to);

        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);

        vm.warp(toDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);
    }

    function testFuzzCannotTransferForFromAddressWithNoId(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);

        bytes memory fromSig = _signTransfer(fromPk, 1, to, fromDeadline);
        bytes memory toSig = _signTransfer(toPk, 1, to, toDeadline);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(0), address(0));
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(toDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.HasNoId.selector);
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(0), address(0));
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsWhenPaused(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransfer(fromPk, fid, to, fromDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(owner);
        idRegistry.pause();

        vm.prank(caller);
        vm.expectRevert("Pausable: paused");
        idRegistry.transferFor(from, to, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    /*//////////////////////////////////////////////////////////////
                  TRANSFER AND CHANGE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferAndChangeRecovery(address from, address recovery, uint256 toPk, uint40 _deadline) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, deadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, 1);

        vm.expectEmit();
        emit ChangeRecoveryAddress(1, recovery);

        vm.prank(from);
        idRegistry.transferAndChangeRecovery(to, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzTransferAndChangeRecoveryRevertsInvalidSig(
        address from,
        address recovery,
        uint256 toPk,
        uint40 _deadline
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        /* generate a signature with an invalid parameter (wrong deadline) */
        bytes memory sig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, deadline + 1);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(from);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferAndChangeRecovery(to, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzTransferAndChangeRecoveryRevertsBadSig(
        address from,
        address recovery,
        uint256 toPk,
        uint40 _deadline
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        _register(from);
        /* generate an invalid signature */
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.expectRevert(ISignatures.InvalidSignature.selector);
        vm.prank(from);
        idRegistry.transferAndChangeRecovery(to, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzTransferAndChangeRecoveryRevertsExpiredSig(
        address from,
        address recovery,
        uint256 toPk,
        uint40 _deadline
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, deadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.warp(deadline + 1);

        vm.expectRevert(ISignatures.SignatureExpired.selector);
        vm.prank(from);
        idRegistry.transfer(to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzTransferAndChangeRecoverySetsRecovery(
        address from,
        uint256[10] calldata toPks,
        uint40 _deadline,
        address oldRecovery,
        address[10] calldata recoveries
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, oldRecovery);

        for (uint256 i; i < toPks.length; i++) {
            uint256 toPk = _boundPk(toPks[i]);
            address to = vm.addr(toPk);
            vm.assume(from != to);
            address newRecovery = recoveries[i];

            bytes memory sig = _signTransferAndChangeRecovery(toPk, fid, to, newRecovery, deadline);

            assertEq(idRegistry.idCounter(), 1);
            assertEq(idRegistry.idOf(from), 1);
            assertEq(idRegistry.custodyOf(1), from);
            assertEq(idRegistry.idOf(to), 0);
            assertEq(idRegistry.recoveryOf(1), oldRecovery);

            vm.expectEmit();
            emit Transfer(from, to, 1);

            vm.expectEmit();
            emit ChangeRecoveryAddress(1, newRecovery);

            vm.prank(from);
            idRegistry.transferAndChangeRecovery(to, newRecovery, deadline, sig);

            assertEq(idRegistry.idCounter(), 1);
            assertEq(idRegistry.idOf(from), 0);
            assertEq(idRegistry.custodyOf(1), to);
            assertEq(idRegistry.idOf(to), 1);
            assertEq(idRegistry.recoveryOf(1), newRecovery);

            oldRecovery = newRecovery;
            from = to;
        }
    }

    function testFuzzCannotTransferAndChangeRecoveryWhenPaused(
        address from,
        address recovery,
        uint256 toPk,
        uint40 _deadline
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _register(from);
        bytes memory sig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, deadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        _pause();

        vm.prank(from);
        vm.expectRevert("Pausable: paused");
        idRegistry.transferAndChangeRecovery(to, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzCannotTransferAndChangeToAddressWithId(
        address from,
        uint256 toPk,
        uint40 _deadline,
        address recovery,
        address newRecovery
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        _registerWithRecovery(to, recovery);
        bytes memory sig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, deadline);

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);
        assertEq(idRegistry.recoveryOf(1), recovery);

        vm.expectRevert(IIdRegistry.HasId.selector);
        vm.prank(from);
        idRegistry.transferAndChangeRecovery(to, newRecovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzCannotTransferAndChangeRecoveryIfNoId(
        address from,
        address recovery,
        uint256 toPk,
        uint40 _deadline
    ) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = 1;
        bytes memory sig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, deadline);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(fid), address(0));
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.expectRevert(IIdRegistry.HasNoId.selector);
        vm.prank(from);
        idRegistry.transferAndChangeRecovery(to, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(fid), address(0));
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    function testTransferAndChangeRecoveryTypehash() public {
        assertEq(
            idRegistry.TRANSFER_AND_CHANGE_RECOVERY_TYPEHASH(),
            keccak256(
                "TransferAndChangeRecovery(uint256 fid,address to,address recovery,uint256 nonce,uint256 deadline)"
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
              TRANSFER AND CHANGE RECOVERY FOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferAndChangeRecoveryFor(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline);
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, 1);

        vm.expectEmit();
        emit ChangeRecoveryAddress(fid, recovery);

        vm.prank(caller);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.recoveryOf(fid), recovery);
    }

    function testFuzzTransferAndChangeRecoveryForRevertsInvalidFromSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        /* generate a signature with an invalid parameter (wrong deadline) */
        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline + 1);
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    function testFuzzTransferForRevertsInvalidToSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline);
        /* generate a signature with an invalid parameter (wrong deadline) */
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline + 1);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    function testFuzzTransferForRevertsUsedFromNonce(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline);
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline);

        vm.prank(from);
        idRegistry.useNonce();

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    function testFuzzTransferForRevertsUsedToNonce(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline);
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline);

        vm.prank(to);
        idRegistry.useNonce();

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    function testFuzzTransferForRevertsBadFromSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        /* generate an invalid signature */
        bytes memory fromSig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    function testFuzzTransferAndChangeRecoveryForRevertsBadToSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline);
        /* generate an invalid signature */
        bytes memory toSig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    function testFuzzTransferAndChangeRecoveryForRevertsExpiredFromSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline);
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.warp(fromDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    function testFuzzTransferAndChangeRecoveryForRevertsExpiredToSig(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline);
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.warp(toDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    function testFuzzCannotTransferAndChangeRecoveryForToAddressWithId(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);
        _register(to);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline);
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline);

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);

        vm.warp(toDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);
    }

    function testFuzzCannotTransferForFromAddressWithNoId(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, 1, to, recovery, fromDeadline);
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, 1, to, recovery, toDeadline);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(1), address(0));
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(toDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.HasNoId.selector);
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.custodyOf(1), address(0));
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferAndChangeRecoveryForRevertsWhenPaused(
        address caller,
        uint256 fromPk,
        uint256 toPk,
        address recovery,
        uint40 _fromDeadline,
        uint40 _toDeadline
    ) public {
        fromPk = _boundPk(fromPk);
        toPk = _boundPk(toPk);
        address from = vm.addr(fromPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 fromDeadline = _boundDeadline(_fromDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _register(from);

        bytes memory fromSig = _signTransferAndChangeRecovery(fromPk, fid, to, recovery, fromDeadline);
        bytes memory toSig = _signTransferAndChangeRecovery(toPk, fid, to, recovery, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));

        vm.prank(owner);
        idRegistry.pause();

        vm.prank(caller);
        vm.expectRevert("Pausable: paused");
        idRegistry.transferAndChangeRecoveryFor(from, to, recovery, fromDeadline, fromSig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(fid), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzChangeRecoveryAddress(address alice, address oldRecovery, address newRecovery) public {
        _registerWithRecovery(alice, oldRecovery);

        vm.prank(alice);
        vm.expectEmit();
        emit ChangeRecoveryAddress(1, newRecovery);
        idRegistry.changeRecoveryAddress(newRecovery);

        assertEq(idRegistry.recoveryOf(1), newRecovery);
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

        assertEq(idRegistry.recoveryOf(1), oldRecovery);
    }

    function testFuzzCannotChangeRecoveryAddressWithoutId(address alice, address bob) public {
        vm.assume(alice != bob);

        vm.prank(alice);
        vm.expectRevert(IIdRegistry.HasNoId.selector);
        idRegistry.changeRecoveryAddress(bob);
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE RECOVERY FOR
    //////////////////////////////////////////////////////////////*/

    function testFuzzChangeRecoveryAddressFor(
        address caller,
        uint256 alicePk,
        address oldRecovery,
        address newRecovery,
        uint40 _deadline
    ) public {
        alicePk = _boundPk(alicePk);
        uint256 deadline = _boundDeadline(_deadline);
        address alice = vm.addr(alicePk);
        _registerWithRecovery(alice, oldRecovery);

        bytes memory sig = _signChangeRecoveryAddress(alicePk, 1, oldRecovery, newRecovery, deadline);

        vm.prank(caller);
        vm.expectEmit();
        emit ChangeRecoveryAddress(1, newRecovery);
        idRegistry.changeRecoveryAddressFor(alice, newRecovery, deadline, sig);

        assertEq(idRegistry.recoveryOf(1), newRecovery);
    }

    function testFuzzChangeRecoveryAddressForRevertsInvalidSig(
        address caller,
        uint256 alicePk,
        address oldRecovery,
        address newRecovery,
        uint40 _deadline
    ) public {
        alicePk = _boundPk(alicePk);
        uint256 deadline = _boundDeadline(_deadline);
        address alice = vm.addr(alicePk);
        _registerWithRecovery(alice, oldRecovery);

        bytes memory sig = _signChangeRecoveryAddress(alicePk, 1, oldRecovery, newRecovery, deadline + 1);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.changeRecoveryAddressFor(alice, newRecovery, deadline, sig);

        assertEq(idRegistry.recoveryOf(1), oldRecovery);
    }

    function testFuzzChangeRecoveryAddressForRevertsUsedNonce(
        address caller,
        uint256 alicePk,
        address oldRecovery,
        address newRecovery,
        uint40 _deadline
    ) public {
        alicePk = _boundPk(alicePk);
        uint256 deadline = _boundDeadline(_deadline);
        address alice = vm.addr(alicePk);
        _registerWithRecovery(alice, oldRecovery);

        bytes memory sig = _signChangeRecoveryAddress(alicePk, 1, oldRecovery, newRecovery, deadline);

        vm.prank(alice);
        idRegistry.useNonce();

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.changeRecoveryAddressFor(alice, newRecovery, deadline, sig);

        assertEq(idRegistry.recoveryOf(1), oldRecovery);
    }

    function testFuzzChangeRecoveryAddressForRevertsBadSig(
        address caller,
        uint256 alicePk,
        address oldRecovery,
        address newRecovery,
        uint40 _deadline
    ) public {
        alicePk = _boundPk(alicePk);
        uint256 deadline = _boundDeadline(_deadline);
        address alice = vm.addr(alicePk);
        _registerWithRecovery(alice, oldRecovery);

        /* generate an invalid signature */
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.changeRecoveryAddressFor(alice, newRecovery, deadline, sig);

        assertEq(idRegistry.recoveryOf(1), oldRecovery);
    }

    function testFuzzChangeRecoveryAddressForRevertsExpired(
        address caller,
        uint256 alicePk,
        address oldRecovery,
        address newRecovery,
        uint40 _deadline
    ) public {
        alicePk = _boundPk(alicePk);
        uint256 deadline = _boundDeadline(_deadline);
        address alice = vm.addr(alicePk);
        _registerWithRecovery(alice, oldRecovery);

        bytes memory sig = _signChangeRecoveryAddress(alicePk, 1, oldRecovery, newRecovery, deadline);

        vm.warp(deadline + 1);

        vm.prank(caller);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        idRegistry.changeRecoveryAddressFor(alice, newRecovery, deadline, sig);

        assertEq(idRegistry.recoveryOf(1), oldRecovery);
    }

    function testFuzzCannotChangeRecoveryAddressForWithoutId(
        address caller,
        uint256 alicePk,
        address oldRecovery,
        address newRecovery,
        uint40 _deadline
    ) public {
        alicePk = _boundPk(alicePk);
        uint256 deadline = _boundDeadline(_deadline);
        address alice = vm.addr(alicePk);

        bytes memory sig = _signChangeRecoveryAddress(alicePk, 1, oldRecovery, newRecovery, deadline);

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.HasNoId.selector);
        idRegistry.changeRecoveryAddressFor(alice, newRecovery, deadline, sig);
    }

    function testFuzzCannotChangeRecoveryAddressForWhenPaused(
        address caller,
        uint256 alicePk,
        address oldRecovery,
        address newRecovery,
        uint40 _deadline
    ) public {
        alicePk = _boundPk(alicePk);
        uint256 deadline = _boundDeadline(_deadline);
        address alice = vm.addr(alicePk);
        _registerWithRecovery(alice, oldRecovery);

        bytes memory sig = _signChangeRecoveryAddress(alicePk, 1, oldRecovery, newRecovery, deadline);

        vm.prank(owner);
        idRegistry.pause();

        vm.prank(caller);
        vm.expectRevert("Pausable: paused");
        idRegistry.changeRecoveryAddressFor(alice, newRecovery, deadline, sig);

        assertEq(idRegistry.recoveryOf(1), oldRecovery);
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
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), recovery);

        vm.prank(recovery);
        vm.expectEmit();
        emit Recover(from, to, 1);
        vm.expectEmit();
        emit Transfer(from, to, 1);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzRecoverRevertsInvalidSig(address from, uint256 toPk, uint40 _deadline, address recovery) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline + 1);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.expectRevert(ISignatures.InvalidSignature.selector);
        vm.prank(recovery);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzRecoverRevertsBadSig(address from, uint256 toPk, uint40 _deadline, address recovery) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        _registerWithRecovery(from, recovery);
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.expectRevert(ISignatures.InvalidSignature.selector);
        vm.prank(recovery);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzRecoverRevertsExpiredSig(address from, uint256 toPk, uint40 _deadline, address recovery) public {
        toPk = _boundPk(toPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);

        uint256 deadline = _boundDeadline(_deadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        bytes memory sig = _signTransfer(toPk, fid, to, deadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(deadline + 1);

        vm.expectRevert(ISignatures.SignatureExpired.selector);
        vm.prank(recovery);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
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
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), recovery);

        vm.prank(recovery);
        vm.expectRevert("Pausable: paused");
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), recovery);
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
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(recovery);
        vm.expectRevert(IIdRegistry.HasNoId.selector);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
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
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), recovery);

        vm.prank(notRecovery);
        vm.expectRevert(IIdRegistry.Unauthorized.selector);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
        assertEq(idRegistry.recoveryOf(1), recovery);
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
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);
        assertEq(idRegistry.custodyOf(2), to);
        assertEq(idRegistry.recoveryOf(1), recovery);
        assertEq(idRegistry.recoveryOf(2), address(0));

        vm.prank(recovery);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idRegistry.recover(from, to, deadline, sig);

        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);
        assertEq(idRegistry.custodyOf(2), to);
        assertEq(idRegistry.recoveryOf(1), recovery);
        assertEq(idRegistry.recoveryOf(2), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        RECOVER FOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRecoverFor(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        address recoveryBefore = idRegistry.recoveryOf(fid);

        vm.expectEmit();
        emit Recover(from, to, 1);
        vm.expectEmit();
        emit Transfer(from, to, 1);
        vm.prank(caller);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 1);
        assertEq(idRegistry.custodyOf(1), to);
        assertEq(idRegistry.recoveryOf(fid), recoveryBefore);
    }

    function testFuzzRecoverForRevertsInvalidRecoverySig(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline + 1);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzRecoverForForRevertsInvalidToSig(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline + 1);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzRecoverForForRevertsUsedRecoveryNonce(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        vm.prank(recovery);
        idRegistry.useNonce();

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzRecoverForForRevertsUsedToNonce(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        vm.prank(to);
        idRegistry.useNonce();

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsBadRecoverySig(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsBadToSig(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline);
        bytes memory toSig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsExpiredRecoverySig(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(recoveryDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzTransferForRevertsExpiredToSig(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.warp(toDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzCannotRecoverForToAddressWithId(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);
        _register(to);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);
        assertEq(idRegistry.custodyOf(2), to);

        vm.warp(toDeadline + 1);

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 2);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 2);
        assertEq(idRegistry.custodyOf(2), to);
    }

    function testFuzzCannotRecoverForFromAddressWithNoId(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);

        bytes memory recoverySig = _signTransfer(recoveryPk, 1, to, recoveryDeadline);
        bytes memory toSig = _signTransfer(toPk, 1, to, toDeadline);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.HasNoId.selector);
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(from), 0);
        assertEq(idRegistry.idOf(to), 0);
    }

    function testFuzzRecoverForRevertsWhenPaused(
        address caller,
        uint256 recoveryPk,
        uint256 toPk,
        address from,
        uint40 _recoveryDeadline,
        uint40 _toDeadline
    ) public {
        recoveryPk = _boundPk(recoveryPk);
        toPk = _boundPk(toPk);
        address recovery = vm.addr(recoveryPk);
        address to = vm.addr(toPk);
        vm.assume(from != to);
        vm.assume(recovery != to);

        uint256 recoveryDeadline = _boundDeadline(_recoveryDeadline);
        uint256 toDeadline = _boundDeadline(_toDeadline);
        uint256 fid = _registerWithRecovery(from, recovery);

        bytes memory recoverySig = _signTransfer(recoveryPk, fid, to, recoveryDeadline);
        bytes memory toSig = _signTransfer(toPk, fid, to, toDeadline);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);

        vm.prank(owner);
        idRegistry.pause();

        vm.prank(caller);
        vm.expectRevert("Pausable: paused");
        idRegistry.recoverFor(from, to, recoveryDeadline, recoverySig, toDeadline, toSig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(from), 1);
        assertEq(idRegistry.custodyOf(1), from);
        assertEq(idRegistry.idOf(to), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EOA VERIFY FID SIGNATURE
    //////////////////////////////////////////////////////////////*/

    function testFuzzVerifyFidSignature(uint256 recipientPk, bytes32 digest) public {
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);

        _register(recipient);
        assertEq(idRegistry.idCounter(), 1);

        bytes memory msgSig = _signDigest(recipientPk, digest);
        assertEq(idRegistry.verifyFidSignature(recipient, 1, digest, msgSig), true);
    }

    function testFuzzCannotVerifyFidSignatureIfBadDigest(
        uint256 recipientPk,
        bytes32 digest,
        bytes32 badDigest
    ) public {
        vm.assume(digest != badDigest);
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);

        _register(recipient);
        assertEq(idRegistry.idCounter(), 1);

        bytes memory msgSig = _signDigest(recipientPk, digest);
        assertEq(idRegistry.verifyFidSignature(recipient, 1, badDigest, msgSig), false);
    }

    function testFuzzCannotVerifyFidSignatureIfBadFid(uint256 recipientPk, bytes32 digest) public {
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);

        _register(recipient);
        assertEq(idRegistry.idCounter(), 1);

        bytes memory msgSig = _signDigest(recipientPk, digest);
        assertEq(idRegistry.verifyFidSignature(recipient, 2, digest, msgSig), false);
    }

    function testFuzzCannotVerifyFidSignatureIfBadCustodyAddress(
        uint256 recipientPk,
        bytes32 digest,
        address badCustodyAddress
    ) public {
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);
        vm.assume(recipient != badCustodyAddress);

        _register(recipient);
        assertEq(idRegistry.idCounter(), 1);

        bytes memory msgSig = _signDigest(recipientPk, digest);
        assertEq(idRegistry.verifyFidSignature(badCustodyAddress, 1, digest, msgSig), false);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC1271 VERIFY FID SIGNATURE
    //////////////////////////////////////////////////////////////*/

    function testFuzzVerifyFidSignatureERC1271(uint256 recipientPk, bytes32 digest) public {
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);
        (, address mockWalletAddress) = _createMockERC1271(recipient);

        _register(mockWalletAddress);
        assertEq(idRegistry.idCounter(), 1);

        bytes memory msg_sig = _signDigest(recipientPk, digest);
        assertEq(idRegistry.verifyFidSignature(mockWalletAddress, 1, digest, msg_sig), true);
    }

    function testFuzzCannotVerifyFidSignatureERC1271IfBadDigest(
        uint256 recipientPk,
        bytes32 digest,
        bytes32 badDigest
    ) public {
        vm.assume(digest != badDigest);
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);
        (, address mockWalletAddress) = _createMockERC1271(recipient);

        _register(mockWalletAddress);
        assertEq(idRegistry.idCounter(), 1);

        bytes memory msgSig = _signDigest(recipientPk, digest);
        assertEq(idRegistry.verifyFidSignature(mockWalletAddress, 1, badDigest, msgSig), false);
    }

    function testFuzzCannotVerifyFidSignatureERC1271IfBadCustodyAddress(uint256 recipientPk, bytes32 digest) public {
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);
        (, address mockWalletAddress) = _createMockERC1271(recipient);

        _register(mockWalletAddress);
        assertEq(idRegistry.idCounter(), 1);

        bytes memory msgSig = _signDigest(recipientPk, digest);
        assertEq(idRegistry.verifyFidSignature(recipient, 1, digest, msgSig), false);
    }

    function testFuzzCannotVerifyFidSignatureERC1271IfMalicious(uint256 recipientPk, bytes32 digest) public {
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);
        (ERC1271MaliciousMockForceRevert mockWallet, address mockWalletAddress) = _createMaliciousMockERC1271(recipient);

        mockWallet.setForceRevert(false);
        _register(mockWalletAddress);
        assertEq(idRegistry.idCounter(), 1);

        mockWallet.setForceRevert(true);

        bytes memory msgSig = _signDigest(recipientPk, digest);
        assertEq(idRegistry.verifyFidSignature(mockWalletAddress, 1, digest, msgSig), false);
    }

    /*//////////////////////////////////////////////////////////////
                          SET ID GATEWAY
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetIdGateway(
        address idGateway
    ) public {
        address prevIdGateway = idRegistry.idGateway();

        vm.expectEmit();
        emit SetIdGateway(prevIdGateway, idGateway);

        vm.prank(owner);
        idRegistry.setIdGateway(idGateway);

        assertEq(idRegistry.idGateway(), idGateway);
    }

    function testFuzzOnlyOwnerCanSetIdGateway(address caller, address idGateway) public {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        idRegistry.setIdGateway(idGateway);
    }

    function testFuzzFreezeIdGateway(
        address idGateway
    ) public {
        assertEq(idRegistry.gatewayFrozen(), false);

        vm.prank(owner);
        idRegistry.setIdGateway(idGateway);

        vm.expectEmit();
        emit FreezeIdGateway(idGateway);

        vm.prank(owner);
        idRegistry.freezeIdGateway();

        assertEq(idRegistry.gatewayFrozen(), true);
    }

    function testFuzzOnlyOwnerCanFreezeIdGateway(
        address caller
    ) public {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        idRegistry.freezeIdGateway();
    }

    function testFuzzSetIdGatewayRevertsWhenFrozen(
        address idGateway
    ) public {
        assertEq(idRegistry.gatewayFrozen(), false);

        vm.prank(owner);
        idRegistry.freezeIdGateway();

        assertEq(idRegistry.gatewayFrozen(), true);

        vm.prank(owner);
        vm.expectRevert(IIdRegistry.GatewayFrozen.selector);
        idRegistry.setIdGateway(idGateway);
    }

    function testFreezeIdGatewayRevertsWhenFrozen() public {
        vm.prank(owner);
        idRegistry.freezeIdGateway();

        assertEq(idRegistry.gatewayFrozen(), true);

        vm.prank(owner);
        vm.expectRevert(IIdRegistry.GatewayFrozen.selector);
        idRegistry.freezeIdGateway();
    }
}
