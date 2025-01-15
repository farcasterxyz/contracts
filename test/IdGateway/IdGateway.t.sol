// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {IdGateway, IIdGateway} from "../../src/IdGateway.sol";
import {IIdRegistry} from "../../src/IdRegistry.sol";
import {ISignatures} from "../../src/abstract/Signatures.sol";
import {ERC1271WalletMock, ERC1271MaliciousMockForceRevert} from "../Utils.sol";
import {IdGatewayTestSuite} from "./IdGatewayTestSuite.sol";

/* solhint-disable state-visibility */

contract IdGatewayTest is IdGatewayTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery);
    event SetStorageRegistry(address oldStorageRegistry, address newStorageRegistry);

    /*//////////////////////////////////////////////////////////////
                              PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function testVersion() public {
        assertEq(idGateway.VERSION(), "2023.11.15");
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
        _assumeClean(caller);
        assertEq(idRegistry.idCounter(), 0);

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
        _assumeClean(caller);
        assertEq(idRegistry.idCounter(), 0);

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

    function testFuzzCannotRegisterToAnAddressThatOwnsAnId(address caller, address recovery) public {
        _assumeClean(caller);
        _register(caller);

        assertEq(idRegistry.idCounter(), 1);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));

        uint256 price = idGateway.price();
        vm.deal(caller, price);

        vm.prank(caller);
        vm.expectRevert(IIdRegistry.HasId.selector);
        idGateway.register{value: price}(recovery);

        assertEq(idRegistry.idCounter(), 1);
        assertEq(idRegistry.idOf(caller), 1);
        assertEq(idRegistry.recoveryOf(1), address(0));
    }

    function testFuzzCannotRegisterIfPaused(address caller, address recovery) public {
        assertEq(idRegistry.idCounter(), 0);

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
        _assumeClean(registrar);
        uint256 deadline = _boundDeadline(_deadline);
        recipientPk = _boundPk(recipientPk);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline);

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
        _assumeClean(registrar);
        uint256 deadline = _boundDeadline(_deadline);
        recipientPk = _boundPk(recipientPk);

        address recipient = vm.addr(recipientPk);
        bytes memory sig = _signRegister(recipientPk, recipient, recovery, deadline);

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

        assertEq(idRegistry.idCounter(), 0);
        assertEq(idRegistry.idOf(recipient), 0);
        assertEq(idRegistry.recoveryOf(1), address(0));

        vm.warp(deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(ISignatures.SignatureExpired.selector);
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
        _assumeClean(registrar);
        uint256 deadline = _boundDeadline(_deadline);
        recipientPk = _boundPk(recipientPk);

        address recipient = vm.addr(recipientPk);
        (, address mockWalletAddress) = _createMockERC1271(recipient);

        bytes memory sig = _signRegister(recipientPk, mockWalletAddress, recovery, deadline);

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
                             RECEIVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRevertsDirectPayments(address sender, uint256 amount) public {
        _assumeClean(sender);
        vm.assume(sender != address(storageRegistry));

        vm.deal(sender, amount);
        vm.prank(sender);
        vm.expectRevert(IIdGateway.Unauthorized.selector);
        payable(address(idGateway)).transfer(amount);
    }

    function _pauseManager() internal {
        vm.prank(owner);
        idGateway.pause();
    }

    /*//////////////////////////////////////////////////////////////
                        SET STORAGE REGISTRY
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetStorageRegistry(
        address storageRegistry
    ) public {
        address prevStorageRegistry = address(idGateway.storageRegistry());

        vm.expectEmit();
        emit SetStorageRegistry(prevStorageRegistry, storageRegistry);

        vm.prank(owner);
        idGateway.setStorageRegistry(storageRegistry);

        assertEq(address(idGateway.storageRegistry()), storageRegistry);
    }

    function testFuzzOnlyOwnerCanSetStorageRegistry(address caller, address storageRegistry) public {
        vm.assume(caller != owner);
        address prevStorageRegistry = address(idGateway.storageRegistry());

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        idGateway.setStorageRegistry(storageRegistry);

        assertEq(address(idGateway.storageRegistry()), prevStorageRegistry);
    }
}
