// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {stdError} from "forge-std/StdError.sol";

import {Bundler, IBundler} from "../../src/Bundler.sol";
import {IdRegistry} from "../../src/IdRegistry.sol";
import {KeyRegistry} from "../../src/KeyRegistry.sol";
import {StorageRegistry} from "../../src/StorageRegistry.sol";
import {BundlerTestSuite} from "./BundlerTestSuite.sol";
import {IKeyRegistry} from "../../src/interfaces/IKeyRegistry.sol";

/* solhint-disable state-visibility */

contract BundlerTest is BundlerTestSuite {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Register(address indexed to, uint256 indexed id, address recovery);
    event Rent(address indexed buyer, uint256 indexed id, uint256 units);

    /*//////////////////////////////////////////////////////////////
                               PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function testHasIDRegistry() public {
        assertEq(address(bundler.idGateway()), address(idGateway));
    }

    function testVersion() public {
        assertEq(bundler.VERSION(), "2025.06.16");
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
        IBundler.SignerParams[] memory signers = new IBundler.SignerParams[](numSigners);
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
        _assumeClean(caller);
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
        _assumeClean(caller);
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
        _assumeClean(caller);
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
        _assumeClean(caller);
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

    function testFuzzAddKeys(
        address caller,
        uint256 accountPk,
        address recovery,
        uint256 storageUnits,
        uint8 _numSigners,
        uint40 _deadline
    ) public {
        _assumeClean(caller);
        uint256 numSigners = bound(_numSigners, 0, 10);
        accountPk = _boundPk(accountPk);
        vm.assume(caller != address(bundler)); // the bundle registry cannot call itself
        assumePayable(caller); // caller must be able to receive funds

        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageRegistry.rentedUnits() - 1);

        // Register with no signers
        uint256 price = bundler.price(storageUnits);
        address account = vm.addr(accountPk);
        uint256 deadline = _boundDeadline(_deadline);
        bytes memory registerSig = _signRegister(accountPk, account, recovery, deadline);
        IBundler.SignerParams[] memory emptySigners = new IBundler.SignerParams[](0);

        vm.deal(caller, price);
        vm.prank(caller);
        uint256 fid = bundler.register{value: price}(
            IBundler.RegistrationParams({to: account, recovery: recovery, deadline: deadline, sig: registerSig}),
            emptySigners,
            storageUnits
        );

        _assertSuccessfulRegistration(account, recovery);

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), 0);

        IBundler.SignerParams[] memory signers = _generateSigners(accountPk, account, deadline, numSigners);
        bundler.addKeys(account, signers);

        assertEq(keyRegistry.totalKeys(fid, IKeyRegistry.KeyState.ADDED), numSigners);
        for (uint256 i; i < numSigners; i++) {
            assertEq(uint8(keyRegistry.keyDataOf(1, signers[i].key).state), uint8(IKeyRegistry.KeyState.ADDED));
            assertEq(keyRegistry.keyDataOf(1, signers[i].key).keyType, signers[i].keyType);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             RECEIVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzRevertsDirectPayments(address sender, uint256 amount) public {
        _assumeClean(sender);

        deal(sender, amount);
        vm.prank(sender);
        vm.expectRevert(IBundler.Unauthorized.selector);
        payable(address(bundler)).transfer(amount);
    }
}
