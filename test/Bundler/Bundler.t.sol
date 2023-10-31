// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {stdError} from "forge-std/StdError.sol";

import {Bundler, IBundler} from "../../src/Bundler.sol";
import {IdRegistry} from "../../src/IdRegistry.sol";
import {KeyRegistry} from "../../src/KeyRegistry.sol";
import {StorageRegistry} from "../../src/StorageRegistry.sol";
import {ITrustedCaller} from "../../src/lib/TrustedCaller.sol";
import {BundlerTestSuite} from "./BundlerTestSuite.sol";

/* solhint-disable state-visibility */

contract BundlerTest is BundlerTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SetTrustedCaller(address indexed oldCaller, address indexed newCaller, address owner);
    event Register(address indexed to, uint256 indexed id, address recovery);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Rent(address indexed buyer, uint256 indexed id, uint256 units);

    /*//////////////////////////////////////////////////////////////
                               PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function testHasIDRegistry() public {
        assertEq(address(bundler.idGateway()), address(idGateway));
    }

    function testDefaultTrustedCaller() public {
        assertEq(address(bundler.trustedCaller()), address(this));
    }

    function testVersion() public {
        assertEq(bundler.VERSION(), "2023.10.04");
    }

    /*//////////////////////////////////////////////////////////////
                                REGISTER
    //////////////////////////////////////////////////////////////*/

    function _generateSigners(
        uint256 accountPk,
        address account,
        uint256 deadline,
        uint256 numSigners
    ) internal returns (IBundler.SignerParams[] memory) {
        IBundler.SignerParams[] memory signers = new IBundler.SignerParams[](
            numSigners
        );
        uint256 nonce = keyRegistry.nonces(account);

        // The duplication below is ugly but necessary to work around a stack too deep error.
        for (uint256 i = 0; i < numSigners; i++) {
            _registerValidator(uint32(i + 1), uint8(i + 1));
            signers[i] = IBundler.SignerParams({
                keyType: uint32(i + 1),
                key: abi.encodePacked("key", keccak256(abi.encode(i))),
                metadataType: uint8(i + 1),
                metadata: abi.encodePacked("metadata", keccak256(abi.encode(i))),
                deadline: deadline,
                sig: _signAdd(
                    accountPk,
                    account,
                    uint32(i + 1),
                    abi.encodePacked("key", keccak256(abi.encode(i))),
                    uint8(i + 1),
                    abi.encodePacked("metadata", keccak256(abi.encode(i))),
                    nonce + i,
                    deadline
                    )
            });
        }
        return signers;
    }

    function testFuzzRegister(
        address caller,
        uint256 accountPk,
        address recovery,
        uint256 storageUnits,
        uint8 _numSigners,
        uint40 _deadline
    ) public {
        uint256 numSigners = bound(_numSigners, 0, 10);
        accountPk = _boundPk(accountPk);
        vm.assume(caller != address(bundler)); // the bundle registry cannot call itself
        assumePayable(caller); // caller must be able to receive funds

        uint256 storageBefore = storageRegistry.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageBefore - 1);

        uint256 price = bundler.price(storageUnits);
        address account = vm.addr(accountPk);
        uint256 deadline = _boundDeadline(_deadline);
        bytes memory registerSig = _signRegister(accountPk, account, recovery, deadline);

        IBundler.SignerParams[] memory signers = _generateSigners(accountPk, account, deadline, numSigners);

        vm.deal(caller, price);
        vm.prank(caller);
        bundler.register{value: price}(
            IBundler.RegistrationParams({to: account, recovery: recovery, deadline: deadline, sig: registerSig}),
            signers,
            storageUnits
        );

        _assertSuccessfulRegistration(account, recovery);

        uint256 storageAfter = storageRegistry.rentedUnits();

        assertEq(storageAfter - storageBefore, storageUnits + 1);
        assertEq(address(storageRegistry).balance, price);
        assertEq(address(keyGateway).balance, 0);
        assertEq(address(bundler).balance, 0 ether);
        assertEq(address(caller).balance, 0 ether);
    }

    function testFuzzRegisterZeroStorage(
        address caller,
        uint256 accountPk,
        address recovery,
        uint8 _numSigners,
        uint40 _deadline
    ) public {
        uint256 numSigners = bound(_numSigners, 0, 10);
        accountPk = _boundPk(accountPk);
        vm.assume(caller != address(bundler)); // the bundle registry cannot call itself
        assumePayable(caller); // caller must be able to receive funds

        uint256 storageBefore = storageRegistry.rentedUnits();

        uint256 price = bundler.price(0);
        address account = vm.addr(accountPk);
        uint256 deadline = _boundDeadline(_deadline);
        bytes memory registerSig = _signRegister(accountPk, account, recovery, deadline);

        IBundler.SignerParams[] memory signers = _generateSigners(accountPk, account, deadline, numSigners);

        vm.deal(caller, price);
        vm.prank(caller);
        bundler.register{value: price}(
            IBundler.RegistrationParams({to: account, recovery: recovery, deadline: deadline, sig: registerSig}),
            signers,
            0
        );

        _assertSuccessfulRegistration(account, recovery);

        uint256 storageAfter = storageRegistry.rentedUnits();

        assertEq(storageAfter - storageBefore, 1);
        assertEq(address(storageRegistry).balance, price);
        assertEq(address(keyGateway).balance, 0);
        assertEq(address(bundler).balance, 0 ether);
        assertEq(address(caller).balance, 0 ether);
    }

    function testFuzzRegisterRevertsInsufficientPayment(
        address caller,
        uint256 accountPk,
        address recovery,
        uint40 _deadline,
        uint256 storageUnits,
        uint256 delta
    ) public {
        accountPk = _boundPk(accountPk);
        vm.assume(caller != address(bundler)); // the bundle registry cannot call itself
        assumePayable(caller); // caller must be able to receive funds

        uint256 storageBefore = storageRegistry.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageBefore - 1);

        uint256 price = bundler.price(storageUnits);
        address account = vm.addr(accountPk);
        uint256 deadline = _boundDeadline(_deadline);
        bytes memory sig = _signRegister(accountPk, account, recovery, deadline);
        delta = bound(delta, 1, price - 1);

        IBundler.SignerParams[] memory signers = new IBundler.SignerParams[](0);

        vm.deal(caller, price);
        vm.prank(caller);
        vm.expectRevert(StorageRegistry.InvalidPayment.selector);
        bundler.register{value: price - delta}(
            IBundler.RegistrationParams({to: account, recovery: recovery, deadline: deadline, sig: sig}),
            signers,
            storageUnits
        );
    }

    function testFuzzRegisterReturnsExcessPayment(
        address caller,
        uint256 accountPk,
        address recovery,
        uint40 _deadline,
        uint256 storageUnits,
        uint256 delta
    ) public {
        accountPk = _boundPk(accountPk);
        vm.assume(caller != address(bundler)); // the bundle registry cannot call itself
        assumePayable(caller); // caller must be able to receive funds

        uint256 storageBefore = storageRegistry.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageBefore - 1);

        uint256 price = bundler.price(storageUnits);
        address account = vm.addr(accountPk);
        uint256 deadline = _boundDeadline(_deadline);
        bytes memory sig = _signRegister(accountPk, account, recovery, deadline);
        delta = bound(delta, 1, type(uint256).max - price);

        IBundler.SignerParams[] memory signers = new IBundler.SignerParams[](0);

        vm.deal(caller, price + delta);
        vm.prank(caller);
        bundler.register{value: price + delta}(
            IBundler.RegistrationParams({to: account, recovery: recovery, deadline: deadline, sig: sig}),
            signers,
            storageUnits
        );

        _assertSuccessfulRegistration(account, recovery);

        uint256 storageAfter = storageRegistry.rentedUnits();

        assertEq(storageAfter - storageBefore, storageUnits + 1);
        assertEq(address(storageRegistry).balance, price);
        assertEq(address(bundler).balance, 0 ether);
        assertEq(address(caller).balance, delta);
    }

    /*//////////////////////////////////////////////////////////////
                                  OWNER
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetTrustedCaller(address alice) public {
        vm.assume(alice != address(0));
        assertEq(bundler.owner(), owner);

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit SetTrustedCaller(bundler.trustedCaller(), alice, owner);
        bundler.setTrustedCaller(alice);
        vm.stopPrank();

        assertEq(bundler.trustedCaller(), alice);
    }

    function testFuzzCannotSetTrustedCallerToZeroAddress() public {
        assertEq(bundler.owner(), owner);

        vm.prank(owner);
        vm.expectRevert(ITrustedCaller.InvalidAddress.selector);
        bundler.setTrustedCaller(address(0));

        assertEq(bundler.trustedCaller(), address(this));
    }

    function testFuzzCannotSetTrustedCallerUnlessOwner(address alice, address bob) public {
        vm.assume(alice != address(0));
        vm.assume(bundler.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bundler.setTrustedCaller(bob);
        assertEq(bundler.trustedCaller(), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSFER OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferOwnership(address newOwner, address newOwner2) public {
        vm.assume(newOwner != address(0) && newOwner2 != address(0));
        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), address(0));

        vm.prank(owner);
        bundler.transferOwnership(newOwner);
        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), newOwner);

        vm.prank(owner);
        bundler.transferOwnership(newOwner2);
        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), newOwner2);
    }

    function testFuzzCannotTransferOwnershipUnlessOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && newOwner != address(0));
        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), address(0));

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bundler.transferOwnership(newOwner);

        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            ACCEPT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzAcceptOwnership(address newOwner) public {
        vm.assume(newOwner != owner && newOwner != address(0));
        vm.prank(owner);
        bundler.transferOwnership(newOwner);

        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(owner, newOwner);
        vm.prank(newOwner);
        bundler.acceptOwnership();

        assertEq(bundler.owner(), newOwner);
        assertEq(bundler.pendingOwner(), address(0));
    }

    function testFuzzCannotAcceptOwnershipUnlessPendingOwner(address alice, address newOwner) public {
        vm.assume(alice != owner && alice != address(0));
        vm.assume(newOwner != alice && newOwner != address(0));

        vm.prank(owner);
        bundler.transferOwnership(newOwner);

        vm.prank(alice);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        bundler.acceptOwnership();

        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                             RECEIVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRevertsDirectPayments(address sender, uint256 amount) public {
        vm.assume(sender != address(storageRegistry));
        vm.assume(sender != address(idGateway));
        vm.assume(sender != address(keyGateway));

        deal(sender, amount);
        vm.prank(sender);
        vm.expectRevert(IBundler.Unauthorized.selector);
        payable(address(bundler)).transfer(amount);
    }
}
