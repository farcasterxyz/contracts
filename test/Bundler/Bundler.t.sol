// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Bundler} from "../../src/Bundler.sol";
import {StorageRent} from "../../src/StorageRent.sol";
import {BundlerTestSuite} from "./BundlerTestSuite.sol";

/* solhint-disable state-visibility */

contract BundlerTest is BundlerTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ChangeTrustedCaller(address indexed trustedCaller, address indexed owner);

    function testHasIDRegistry() public {
        assertEq(address(bundler.idRegistry()), address(idRegistry));
    }

    function testHasStorageRent() public {
        assertEq(address(bundler.storageRent()), address(storageRent));
    }

    function testDefaultTrustedCaller() public {
        assertEq(address(bundler.trustedCaller()), address(this));
    }

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

    function testFuzzTrustedRegister(address account, address recovery, uint256 storageUnits) public {
        uint256 storageBefore = storageRent.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRent.maxUnits() - storageBefore);

        bytes32 operatorRoleId = storageRent.operatorRoleId();
        vm.prank(roleAdmin);
        storageRent.grantRole(operatorRoleId, address(bundler));

        idRegistry.changeTrustedCaller(address(bundler));

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

        idRegistry.changeTrustedCaller(address(bundler));

        vm.prank(caller);
        vm.expectRevert(Bundler.Unauthorized.selector);
        bundler.trustedRegister(account, recovery, storageUnits);

        _assertUnsuccessfulRegistration(account);
    }

    /*//////////////////////////////////////////////////////////////
                               OWNER TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzChangeTrustedCaller(address alice) public {
        vm.assume(alice != FORWARDER && alice != address(0));
        assertEq(bundler.owner(), owner);

        vm.expectEmit(true, true, true, true);
        emit ChangeTrustedCaller(alice, address(this));
        bundler.changeTrustedCaller(alice);
        assertEq(bundler.trustedCaller(), alice);
    }

    function testFuzzCannotChangeTrustedCallerToZeroAddress(address alice) public {
        vm.assume(alice != FORWARDER);
        assertEq(bundler.owner(), owner);

        vm.expectRevert(Bundler.InvalidAddress.selector);
        bundler.changeTrustedCaller(address(0));

        assertEq(bundler.trustedCaller(), owner);
    }

    function testFuzzCannotChangeTrustedCallerUnlessOwner(address alice, address bob) public {
        vm.assume(alice != FORWARDER && alice != address(0));
        vm.assume(bundler.owner() != alice);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        bundler.changeTrustedCaller(bob);
        assertEq(bundler.trustedCaller(), owner);
    }
}
