// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {IdRegistry} from "../../src/IdRegistry.sol";
import {TrustedCaller} from "../../src/lib/TrustedCaller.sol";
import {Signatures} from "../../src/lib/Signatures.sol";
import {ERC1271WalletMock, ERC1271MaliciousMockForceRevert} from "../Utils.sol";
import {RegistrationTestSuite} from "./RegistrationTestSuite.sol";

/* solhint-disable state-visibility */

contract RegistrationTest is RegistrationTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery);

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function testVersion() public {
        assertEq(idRegistry.VERSION(), "2023.08.23");
    }

    /*//////////////////////////////////////////////////////////////
                             REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegister(address caller, address recovery) public {
        assertEq(idRegistry.idCounter(), 0);

        vm.prank(owner);
        registration.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = storageRegistry.price(1);
        vm.deal(caller, price);

        vm.expectEmit();
        emit Register(caller, 1, recovery);
        vm.prank(caller);
        registration.register{value: price}(recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzCannotRegisterIfSeedable(address caller, address recovery) public {
        assertEq(idRegistry.idCounter(), 0);
        assertEq(registration.trustedOnly(), 1);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(caller);
        vm.expectRevert(TrustedCaller.Seedable.selector);
        registration.register(recovery);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterToAnAddressThatOwnsAnId(address caller, address recovery) public {
        _register(caller);

        assertEq(idRegistry.idCounter(), 1);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = storageRegistry.price(1);
        vm.deal(caller, price);

        vm.prank(owner);
        registration.disableTrustedOnly();

        vm.prank(caller);
        vm.expectRevert(IdRegistry.HasId.selector);
        registration.register{value: price}(recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterIfPaused(address caller, address recovery) public {
        assertEq(idRegistry.idCounter(), 0);

        vm.prank(owner);
        registration.disableTrustedOnly();
        _pause();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(caller);
        vm.expectRevert("Pausable: paused");
        registration.register(recovery);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
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
        registration.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = storageRegistry.price(1);
        vm.deal(registrar, price);

        vm.expectEmit();
        emit Register(recipient, 1, recovery);
        vm.prank(registrar);
        registration.registerFor{value: price}(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
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
        /* generate a signature with an invalid parameter (wrong deadline) */
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline + 1);

        vm.prank(owner);
        registration.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(Signatures.InvalidSignature.selector);
        registration.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
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
        /* generate an invalid signature */
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        vm.prank(owner);
        registration.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(Signatures.InvalidSignature.selector);
        registration.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
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
        registration.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(owner);
        registration.disableTrustedOnly();

        vm.warp(deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(Signatures.SignatureExpired.selector);
        registration.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
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

        assertEq(registration.trustedOnly(), 1);
        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(TrustedCaller.Seedable.selector);
        registration.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
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
        registration.disableTrustedOnly();
        _register(recipient);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(IdRegistry.HasId.selector);
        registration.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));
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
        registration.disableTrustedOnly();

        _pause();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert("Pausable: paused");
        registration.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testRegisterTypehash() public {
        assertEq(
            registration.REGISTER_TYPEHASH(),
            keccak256("Register(address to,address recovery,uint256 nonce,uint256 deadline)")
        );
    }

    /*//////////////////////////////////////////////////////////////
                       ERC1271 REGISTER FOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegisterForERC1271(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        recipientPk = _boundPk(recipientPk);

        address recipient = vm.addr(recipientPk);
        (, address mockWalletAddress) = _createMockERC1271(recipient);

        bytes memory sig = _signRegister(recipientPk, mockWalletAddress, recovery, deadline);

        vm.prank(owner);
        registration.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(mockWalletAddress), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = storageRegistry.price(1);
        vm.deal(registrar, price);

        vm.expectEmit(true, true, true, true);
        emit Register(mockWalletAddress, 1, recovery);
        vm.prank(registrar);
        registration.registerFor{value: price}(mockWalletAddress, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(mockWalletAddress), 1);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzRegisterForRevertsMaliciousERC1271(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline
    ) public {
        recipientPk = _boundPk(recipientPk);
        uint256 deadline = _boundDeadline(_deadline);
        address recipient = vm.addr(recipientPk);
        (, address mockWalletAddress) = _createMaliciousMockERC1271(recipient);
        bytes memory sig = _signRegister(recipientPk, mockWalletAddress, recovery, deadline);

        vm.prank(owner);
        registration.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(mockWalletAddress), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(Signatures.InvalidSignature.selector);
        registration.registerFor(mockWalletAddress, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(mockWalletAddress), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         TRUSTED REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzTrustedRegister(address recipient, address trustedCaller, address recovery) public {
        vm.assume(trustedCaller != address(0));
        vm.prank(owner);
        registration.setTrustedCaller(trustedCaller);
        assertEq(idRegistry.idCounter(), 0);

        vm.prank(trustedCaller);
        vm.expectEmit();
        emit Register(recipient, 1, recovery);
        registration.trustedRegister(recipient, recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzCannotTrustedRegisterUnlessTrustedOnly(
        address alice,
        address trustedCaller,
        address recovery
    ) public {
        vm.prank(owner);
        registration.disableTrustedOnly();

        vm.prank(trustedCaller);
        vm.expectRevert(TrustedCaller.Registrable.selector);
        registration.trustedRegister(alice, recovery);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
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
        registration.setTrustedCaller(trustedCaller);

        vm.prank(untrustedCaller);
        vm.expectRevert(TrustedCaller.OnlyTrustedCaller.selector);
        registration.trustedRegister(alice, recovery);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzCannotTrustedRegisterToAnAddressThatOwnsAnID(
        address alice,
        address trustedCaller,
        address recovery
    ) public {
        vm.assume(trustedCaller != address(0));
        vm.prank(owner);
        registration.setTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        registration.trustedRegister(alice, address(0));
        assertEq(idRegistry.idCounter(), 1);

        vm.prank(trustedCaller);
        vm.expectRevert(IdRegistry.HasId.selector);
        registration.trustedRegister(alice, recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzCannotTrustedRegisterWhenPaused(address alice, address trustedCaller, address recovery) public {
        vm.assume(trustedCaller != address(0));
        vm.prank(owner);
        registration.setTrustedCaller(trustedCaller);
        assertEq(idRegistry.idCounter(), 0);

        _pause();

        vm.prank(trustedCaller);
        vm.expectRevert("Pausable: paused");
        registration.trustedRegister(alice, recovery);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }
}
