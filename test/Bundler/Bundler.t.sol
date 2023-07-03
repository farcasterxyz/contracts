// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Bundler} from "../../src/Bundler.sol";
import {IdRegistry} from "../../src/IdRegistry.sol";
import {StorageRent} from "../../src/StorageRent.sol";
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
        assertEq(address(bundler.idRegistry()), address(idRegistry));
    }

    function testHasStorageRent() public {
        assertEq(address(bundler.storageRent()), address(storageRent));
    }

    function testDefaultTrustedCaller() public {
        assertEq(address(bundler.trustedCaller()), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                REGISTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzRegister(address account, address caller, address recovery, uint256 storageUnits) public {
        vm.assume(caller != address(bundler)); // the bundle registry cannot call itself
        assumePayable(caller); // caller must be able to receive funds

        uint256 storageBefore = storageRent.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRent.maxUnits() - storageBefore);

        // State: Trusted Registration is disabled in ID registry
        idRegistry.disableTrustedOnly();

        uint256 price = storageRent.price(storageUnits);

        vm.deal(caller, price);
        vm.prank(caller);
        bundler.register{value: price}(account, recovery, storageUnits);

        _assertSuccessfulRegistration(account, recovery);

        uint256 storageAfter = storageRent.rentedUnits();

        assertEq(storageAfter - storageBefore, storageUnits);
        assertEq(address(storageRent).balance, price);
        assertEq(address(bundler).balance, 0 ether);
        assertEq(address(caller).balance, 0 ether);
    }

    function testFuzzRegisterRevertsInsufficientPayment(
        address account,
        address caller,
        address recovery,
        uint256 storageUnits,
        uint256 delta
    ) public {
        vm.assume(caller != address(bundler)); // the bundle registry cannot call itself
        assumePayable(caller); // caller must be able to receive funds

        uint256 storageBefore = storageRent.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRent.maxUnits() - storageBefore);

        // State: Trusted Registration is disabled in ID registry
        idRegistry.disableTrustedOnly();

        uint256 price = storageRent.price(storageUnits);
        delta = bound(delta, 1, price - 1);

        vm.deal(caller, price);
        vm.prank(caller);
        vm.expectRevert(StorageRent.InvalidPayment.selector);
        bundler.register{value: price - delta}(account, recovery, storageUnits);
    }

    function testFuzzRegisterReturnsExcessPayment(
        address account,
        address caller,
        address recovery,
        uint256 storageUnits,
        uint256 delta
    ) public {
        vm.assume(caller != address(bundler)); // the bundle registry cannot call itself
        assumePayable(caller); // caller must be able to receive funds

        uint256 storageBefore = storageRent.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRent.maxUnits() - storageBefore);

        // State: Trusted Registration is disabled in ID registry
        idRegistry.disableTrustedOnly();

        uint256 price = storageRent.price(storageUnits);
        delta = bound(delta, 1, type(uint256).max - price);

        vm.deal(caller, price + delta);
        vm.prank(caller);
        bundler.register{value: price + delta}(account, recovery, storageUnits);

        _assertSuccessfulRegistration(account, recovery);

        uint256 storageAfter = storageRent.rentedUnits();

        assertEq(storageAfter - storageBefore, storageUnits);
        assertEq(address(storageRent).balance, price);
        assertEq(address(bundler).balance, 0 ether);
        assertEq(address(caller).balance, delta);
    }

    /*//////////////////////////////////////////////////////////////
                            TRUSTED REGISTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzTrustedRegister(address account, address recovery, uint256 storageUnits) public {
        uint256 storageBefore = storageRent.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRent.maxUnits() - storageBefore);

        bytes32 operatorRoleId = storageRent.operatorRoleId();
        vm.prank(roleAdmin);
        storageRent.grantRole(operatorRoleId, address(bundler));

        idRegistry.setTrustedCaller(address(bundler));

        vm.prank(bundler.trustedCaller());
        bundler.trustedRegister(account, recovery, storageUnits);

        _assertSuccessfulRegistration(account, recovery);

        uint256 storageAfter = storageRent.rentedUnits();

        assertEq(storageAfter - storageBefore, storageUnits);
        assertEq(address(storageRent).balance, 0);
        assertEq(address(bundler).balance, 0 ether);
    }

    function testFuzzTrustedRegisterReverts(
        address caller,
        address account,
        address recovery,
        uint256 storageUnits
    ) public {
        vm.assume(caller != bundler.trustedCaller());

        uint256 storageBefore = storageRent.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRent.maxUnits() - storageBefore);

        bytes32 operatorRoleId = storageRent.operatorRoleId();
        vm.prank(roleAdmin);
        storageRent.grantRole(operatorRoleId, address(bundler));

        idRegistry.setTrustedCaller(address(bundler));

        vm.prank(caller);
        vm.expectRevert(Bundler.Unauthorized.selector);
        bundler.trustedRegister(account, recovery, storageUnits);

        _assertUnsuccessfulRegistration(account);
    }

    /*//////////////////////////////////////////////////////////////
                         TRUSTED BATCH REGISTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzTrustedBatchRegister(uint256 registrations, uint256 storageUnits, address recovery) public {
        uint256 storageBefore = storageRent.rentedUnits();
        registrations = bound(registrations, 1, 100);
        storageUnits = bound(storageUnits, 1, (storageRent.maxUnits() - storageBefore) / registrations);

        // Configure the trusted callers correctly
        idRegistry.setTrustedCaller(address(bundler));

        bytes32 operatorRoleId = storageRent.operatorRoleId();
        vm.prank(roleAdmin);
        storageRent.grantRole(operatorRoleId, address(bundler));

        Bundler.UserData[] memory batchArray = new Bundler.UserData[](registrations);

        for (uint256 i = 0; i < registrations; i++) {
            uint160 fid = uint160(i + 1);
            address account = address(fid);
            batchArray[i] = Bundler.UserData({to: account, units: storageUnits});

            vm.expectEmit(true, true, true, true);
            emit Register(account, fid, recovery);

            vm.expectEmit(true, true, true, true);
            emit Rent(address(bundler), fid, storageUnits);
        }

        bundler.trustedBatchRegister(batchArray, recovery);

        for (uint256 i = 0; i < registrations; i++) {
            uint160 fid = uint160(i + 1);
            assertEq(idRegistry.idOf(address(fid)), fid);
            assertEq(idRegistry.getRecoveryOf(fid), recovery);
        }

        // Check that the correct amount of storage was rented
        uint256 storageAfter = storageRent.rentedUnits();
        assertEq(storageAfter - storageBefore, storageUnits * registrations);
        assertEq(address(storageRent).balance, 0);
        assertEq(address(bundler).balance, 0 ether);
    }

    function testFuzzCannotTrustedBatchRegisterFromUntrustedCaller(address alice, address untrustedCaller) public {
        // Call is made from an address that is not address(this), since address(this) is the deployer
        // and therefore the trusted caller for Bundler
        vm.assume(untrustedCaller != address(this));

        // Configure the trusted callers correctly
        idRegistry.setTrustedCaller(address(bundler));

        bytes32 operatorRoleId = storageRent.operatorRoleId();
        vm.prank(roleAdmin);
        storageRent.grantRole(operatorRoleId, address(bundler));

        Bundler.UserData[] memory batchArray = new Bundler.UserData[](1);
        batchArray[0] = Bundler.UserData({to: alice, units: 1});

        vm.prank(untrustedCaller);
        vm.expectRevert(Bundler.Unauthorized.selector);
        bundler.trustedBatchRegister(batchArray, address(0));

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzTrustedBatchRegisterIfIdRegistryDisabled(address alice) public {
        // State: Trusted registration is disabled in IdRegistry
        idRegistry.disableTrustedOnly();

        bytes32 operatorRoleId = storageRent.operatorRoleId();
        vm.prank(roleAdmin);
        storageRent.grantRole(operatorRoleId, address(bundler));

        Bundler.UserData[] memory batchArray = new Bundler.UserData[](1);
        batchArray[0] = Bundler.UserData({to: alice, units: 1});

        vm.expectRevert(IdRegistry.Registrable.selector);
        bundler.trustedBatchRegister(batchArray, address(0));

        _assertUnsuccessfulRegistration(alice);
    }

    /*//////////////////////////////////////////////////////////////
                                  OWNER
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetTrustedCaller(address alice) public {
        vm.assume(alice != FORWARDER && alice != address(0));
        assertEq(bundler.owner(), owner);

        vm.expectEmit(true, true, true, true);
        emit SetTrustedCaller(bundler.trustedCaller(), alice, address(this));
        bundler.setTrustedCaller(alice);
        assertEq(bundler.trustedCaller(), alice);
    }

    function testFuzzCannotSetTrustedCallerToZeroAddress(address alice) public {
        vm.assume(alice != FORWARDER);
        assertEq(bundler.owner(), owner);

        vm.expectRevert(Bundler.InvalidAddress.selector);
        bundler.setTrustedCaller(address(0));

        assertEq(bundler.trustedCaller(), owner);
    }

    function testFuzzCannotSetTrustedCallerUnlessOwner(address alice, address bob) public {
        vm.assume(alice != FORWARDER && alice != address(0));
        vm.assume(bundler.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bundler.setTrustedCaller(bob);
        assertEq(bundler.trustedCaller(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSFER OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testFuzzTransferOwnership(address newOwner, address newOwner2) public {
        vm.assume(newOwner != address(0) && newOwner2 != address(0));
        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), address(0));

        bundler.transferOwnership(newOwner);
        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), newOwner);

        bundler.transferOwnership(newOwner2);
        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), newOwner2);
    }

    function testFuzzCannotTransferOwnershipUnlessOwner(address alice, address newOwner) public {
        vm.assume(alice != FORWARDER && alice != owner && newOwner != address(0));
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
        vm.assume(newOwner != FORWARDER && newOwner != owner && newOwner != address(0));
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
        vm.assume(alice != FORWARDER && alice != owner && alice != address(0));
        vm.assume(newOwner != alice && newOwner != address(0));

        vm.prank(owner);
        bundler.transferOwnership(newOwner);

        vm.prank(alice);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        bundler.acceptOwnership();

        assertEq(bundler.owner(), owner);
        assertEq(bundler.pendingOwner(), newOwner);
    }
}
