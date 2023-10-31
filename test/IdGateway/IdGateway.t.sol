// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {IdGateway, IIdGateway} from "../../src/IdGateway.sol";
import {IIdRegistry} from "../../src/IdRegistry.sol";
import {ITrustedCaller} from "../../src/lib/TrustedCaller.sol";
import {ISignatures} from "../../src/lib/Signatures.sol";
import {ERC1271WalletMock, ERC1271MaliciousMockForceRevert} from "../Utils.sol";
import {IdGatewayTestSuite} from "./IdGatewayTestSuite.sol";

/* solhint-disable state-visibility */

contract IdGatewayTest is IdGatewayTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery);

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function testVersion() public {
        assertEq(idGateway.VERSION(), "2023.10.04");
    }

    function testIdRegistry() public {
        assertEq(address(idGateway.idRegistry()), address(idRegistry));
    }

    function testStorageRegistry() public {
        assertEq(address(idGateway.storageRegistry()), address(storageRegistry));
    }

    /*//////////////////////////////////////////////////////////////
                             REGISTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegister(address caller, address recovery) public {
        assertEq(idRegistry.idCounter(), 0);

        vm.prank(owner);
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = idGateway.price();
        vm.deal(caller, price);

        vm.expectEmit();
        emit Register(caller, 1, recovery);
        vm.prank(caller);
        idGateway.register{value: price}(recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzRegisterExtraStorage(address caller, address recovery, uint16 extraStorage) public {
        assertEq(idRegistry.idCounter(), 0);

        vm.prank(owner);
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = idGateway.price(extraStorage);
        vm.deal(caller, price);

        vm.expectEmit();
        emit Register(caller, 1, recovery);
        vm.prank(caller);
        idGateway.register{value: price}(recovery, extraStorage);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzRegisterReturnsOverpayment(address caller, address recovery, uint32 overpayment) public {
        _assumeClean(caller);
        assertEq(idRegistry.idCounter(), 0);

        vm.prank(owner);
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = idGateway.price();
        vm.deal(caller, price + overpayment);

        vm.expectEmit();
        emit Register(caller, 1, recovery);
        vm.prank(caller);
        idGateway.register{value: price + overpayment}(recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
        assertEq(address(caller).balance, overpayment);
    }

    function testFuzzCannotRegisterIfSeedable(address caller, address recovery) public {
        assertEq(idRegistry.idCounter(), 0);
        assertEq(idGateway.trustedOnly(), 1);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(caller);
        vm.expectRevert(ITrustedCaller.Seedable.selector);
        idGateway.register(recovery);

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

        uint256 price = idGateway.price();
        vm.deal(caller, price);

        vm.prank(owner);
        idGateway.disableTrustedOnly();

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idGateway.register{value: price}(recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterIfPaused(address caller, address recovery) public {
        assertEq(idRegistry.idCounter(), 0);

        vm.prank(owner);
        idGateway.disableTrustedOnly();
        _pauseManager();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(caller), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(caller);
        vm.expectRevert("Pausable: paused");
        idGateway.register(recovery);

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
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = idGateway.price();
        vm.deal(registrar, price);

        vm.expectEmit();
        emit Register(recipient, 1, recovery);
        vm.prank(registrar);
        idGateway.registerFor{value: price}(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.recoveryOf(1), recovery);
    }

    function testFuzzRegisterForExtraStorage(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline,
        uint16 extraStorage
    ) public {
        uint256 deadline = _boundDeadline(_deadline);
        recipientPk = _boundPk(recipientPk);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline);

        vm.prank(owner);
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = idGateway.price(extraStorage);
        vm.deal(registrar, price);

        vm.expectEmit();
        emit Register(recipient, 1, recovery);
        vm.prank(registrar);
        idGateway.registerFor{value: price}(recipient, recovery, deadline, sig, extraStorage);

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
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idGateway.registerFor(recipient, recovery, deadline, sig);

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
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idGateway.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzRegisterForRevertsUsedNonce(
        address registrar,
        uint256 recipientPk,
        address recovery,
        uint40 _deadline
    ) public {
        recipientPk = _boundPk(recipientPk);
        uint256 deadline = _boundDeadline(_deadline);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline);

        // User bumps their nonce, invalidating the signature
        vm.prank(recipient);
        idGateway.useNonce();

        vm.prank(owner);
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idGateway.registerFor(recipient, recovery, deadline, sig);

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
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(owner);
        idGateway.disableTrustedOnly();

        vm.warp(deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
        idGateway.registerFor(recipient, recovery, deadline, sig);

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

        assertEq(idGateway.trustedOnly(), 1);
        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(ITrustedCaller.Seedable.selector);
        idGateway.registerFor(recipient, recovery, deadline, sig);

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
        idGateway.disableTrustedOnly();
        _register(recipient);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(recipient), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idGateway.registerFor(recipient, recovery, deadline, sig);

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
        idGateway.disableTrustedOnly();

        _pauseManager();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert("Pausable: paused");
        idGateway.registerFor(recipient, recovery, deadline, sig);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testRegisterTypehash() public {
        assertEq(
            idGateway.REGISTER_TYPEHASH(),
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
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(mockWalletAddress), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = idGateway.price();
        vm.deal(registrar, price);

        vm.expectEmit(true, true, true, true);
        emit Register(mockWalletAddress, 1, recovery);
        vm.prank(registrar);
        idGateway.registerFor{value: price}(mockWalletAddress, recovery, deadline, sig);

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
        idGateway.disableTrustedOnly();

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(mockWalletAddress), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.prank(registrar);
        vm.expectRevert(ISignatures.InvalidSignature.selector);
        idGateway.registerFor(mockWalletAddress, recovery, deadline, sig);

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
        idGateway.setTrustedCaller(trustedCaller);
        assertEq(idRegistry.idCounter(), 0);

        vm.prank(trustedCaller);
        vm.expectEmit();
        emit Register(recipient, 1, recovery);
        idGateway.trustedRegister(recipient, recovery);

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
        idGateway.disableTrustedOnly();

        vm.prank(trustedCaller);
        vm.expectRevert(ITrustedCaller.Registrable.selector);
        idGateway.trustedRegister(alice, recovery);

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
        idGateway.setTrustedCaller(trustedCaller);

        vm.prank(untrustedCaller);
        vm.expectRevert(ITrustedCaller.OnlyTrustedCaller.selector);
        idGateway.trustedRegister(alice, recovery);

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
        idGateway.setTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        idGateway.trustedRegister(alice, address(0));
        assertEq(idRegistry.idCounter(), 1);

        vm.prank(trustedCaller);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idGateway.trustedRegister(alice, recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(alice), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzCannotTrustedRegisterWhenPaused(address alice, address trustedCaller, address recovery) public {
        vm.assume(trustedCaller != address(0));
        vm.prank(owner);
        idGateway.setTrustedCaller(trustedCaller);
        assertEq(idRegistry.idCounter(), 0);

        _pauseManager();

        vm.prank(trustedCaller);
        vm.expectRevert("Pausable: paused");
        idGateway.trustedRegister(alice, recovery);

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(alice), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                             RECEIVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRevertsDirectPayments(address sender, uint256 amount) public {
        vm.assume(sender != address(storageRegistry));

        deal(sender, amount);
        vm.prank(sender);
        vm.expectRevert(IIdGateway.Unauthorized.selector);
        payable(address(idGateway)).transfer(amount);
    }

    function _pauseManager() internal {
        vm.prank(owner);
        idGateway.pause();
    }
}
