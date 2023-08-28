// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {stdError} from "forge-std/StdError.sol";

import {Bundler, IBundler} from "../../src/Bundler.sol";
import {IdRegistry} from "../../src/IdRegistry.sol";
import {KeyRegistry} from "../../src/KeyRegistry.sol";
import {StorageRegistry} from "../../src/StorageRegistry.sol";
import {TrustedCaller} from "../../src/lib/TrustedCaller.sol";
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

    function testHasStorageRegistry() public {
        assertEq(address(bundler.storageRegistry()), address(storageRegistry));
    }

    function testHasKeyRegistry() public {
        assertEq(address(bundler.keyRegistry()), address(keyRegistry));
    }

    function testDefaultTrustedCaller() public {
        assertEq(address(bundler.trustedCaller()), address(this));
    }

    function testVersion() public {
        assertEq(bundler.VERSION(), "2023.08.23");
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
        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageBefore);

        // State: Trusted Registration is disabled in ID registry
        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        uint256 price = storageRegistry.price(storageUnits);
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

        assertEq(storageAfter - storageBefore, storageUnits);
        assertEq(address(storageRegistry).balance, price);
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
        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageBefore);

        // State: Trusted Registration is disabled in ID registry
        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        uint256 price = storageRegistry.price(storageUnits);
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

    function testFuzzRegisterRevertsZeroUnits(
        address caller,
        uint256 accountPk,
        address recovery,
        uint40 _deadline
    ) public {
        accountPk = _boundPk(accountPk);
        vm.assume(caller != address(bundler)); // the bundle registry cannot call itself
        assumePayable(caller); // caller must be able to receive funds

        uint256 storageUnits = 0;

        // State: Trusted Registration is disabled in ID registry
        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        address account = vm.addr(accountPk);
        uint256 deadline = _boundDeadline(_deadline);
        bytes memory sig = _signRegister(accountPk, account, recovery, deadline);

        IBundler.SignerParams[] memory signers = new IBundler.SignerParams[](0);

        vm.prank(caller);
        vm.expectRevert(StorageRegistry.InvalidAmount.selector);
        bundler.register(
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
        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageBefore);

        // State: Trusted Registration is disabled in ID registry
        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        uint256 price = storageRegistry.price(storageUnits);
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

        assertEq(storageAfter - storageBefore, storageUnits);
        assertEq(address(storageRegistry).balance, price);
        assertEq(address(bundler).balance, 0 ether);
        assertEq(address(caller).balance, delta);
    }

    /*//////////////////////////////////////////////////////////////
                            TRUSTED REGISTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzTrustedRegister(
        address account,
        address recovery,
        uint256 storageUnits,
        uint32 keyType,
        bytes memory key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 storageBefore = storageRegistry.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageBefore);
        _registerValidator(keyType, metadataType);

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        IBundler.SignerData[] memory signers = new IBundler.SignerData[](1);
        signers[0] = IBundler.SignerData({keyType: keyType, key: key, metadataType: metadataType, metadata: metadata});

        vm.prank(bundler.trustedCaller());
        bundler.trustedRegister(
            IBundler.UserData({to: account, recovery: recovery, signers: signers, units: storageUnits})
        );

        _assertSuccessfulRegistration(account, recovery);

        // Check that the key was registered
        KeyRegistry.KeyData memory keyData = keyRegistry.keyDataOf(1, key);
        assertEq(keyData.keyType, keyType);
        assertEq(uint256(keyData.state), uint256(1));

        uint256 storageAfter = storageRegistry.rentedUnits();

        assertEq(storageAfter - storageBefore, storageUnits);
        assertEq(address(storageRegistry).balance, 0);
        assertEq(address(bundler).balance, 0 ether);
    }

    function testFuzzTrustedRegisterWithoutSigners(address account, address recovery, uint256 storageUnits) public {
        uint256 storageBefore = storageRegistry.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageBefore);

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        IBundler.SignerData[] memory signers = new IBundler.SignerData[](0);

        vm.prank(bundler.trustedCaller());
        bundler.trustedRegister(
            IBundler.UserData({to: account, recovery: recovery, signers: signers, units: storageUnits})
        );

        _assertSuccessfulRegistration(account, recovery);

        uint256 storageAfter = storageRegistry.rentedUnits();

        assertEq(storageAfter - storageBefore, storageUnits);
        assertEq(address(storageRegistry).balance, 0);
        assertEq(address(bundler).balance, 0 ether);
    }

    function testFuzzTrustedRegisterRevertsUntrustedCaller(
        address caller,
        address account,
        address recovery,
        uint32 keyType,
        bytes memory key,
        uint8 metadataType,
        bytes memory metadata,
        uint256 storageUnits
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        vm.assume(caller != bundler.trustedCaller());

        uint256 storageBefore = storageRegistry.rentedUnits();
        storageUnits = bound(storageUnits, 1, storageRegistry.maxUnits() - storageBefore);

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        IBundler.SignerData[] memory signers = new IBundler.SignerData[](1);
        signers[0] = IBundler.SignerData({keyType: keyType, key: key, metadataType: metadataType, metadata: metadata});

        vm.prank(caller);
        vm.expectRevert(TrustedCaller.OnlyTrustedCaller.selector);
        bundler.trustedRegister(
            IBundler.UserData({to: account, recovery: recovery, signers: signers, units: storageUnits})
        );

        _assertUnsuccessfulRegistration(account);
    }

    /*//////////////////////////////////////////////////////////////
                         TRUSTED BATCH REGISTER
    //////////////////////////////////////////////////////////////*/

    function testFuzzTrustedBatchRegister(uint256 registrations, uint256 storageUnits) public {
        uint256 storageBefore = storageRegistry.rentedUnits();
        registrations = bound(registrations, 1, 100);
        storageUnits = bound(storageUnits, 1, (storageRegistry.maxUnits() - storageBefore) / registrations);

        // Configure the trusted callers correctly
        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        IBundler.UserData[] memory batchArray = new IBundler.UserData[](
            registrations
        );

        for (uint256 i = 0; i < registrations; i++) {
            uint32 keyType = uint32(i + 1);
            _registerValidator(keyType, 1);
        }

        for (uint256 i = 0; i < registrations; i++) {
            uint160 fid = uint160(i + 1);
            address account = address(fid);
            address recovery = address(uint160(i + 1000));
            uint32 keyType = uint32(i + 1);
            bytes memory key = bytes.concat(bytes("key"), abi.encode(i));
            bytes memory metadata = abi.encodePacked(bytes("metadata"), abi.encode(i));
            IBundler.SignerData[] memory signers = new IBundler.SignerData[](1);
            signers[0] = IBundler.SignerData({keyType: keyType, key: key, metadataType: 1, metadata: metadata});
            batchArray[i] = IBundler.UserData({to: account, recovery: recovery, signers: signers, units: storageUnits});

            vm.expectEmit(true, true, true, true);
            emit Register(account, fid, recovery);

            vm.expectEmit(true, true, true, true);
            emit Rent(address(bundler), fid, storageUnits);
        }

        bundler.trustedBatchRegister(batchArray);

        for (uint256 i = 0; i < registrations; i++) {
            uint160 fid = uint160(i + 1);
            address recovery = address(uint160(i + 1000));
            assertEq(idRegistry.idOf(address(fid)), fid);
            assertEq(idRegistry.recoveryOf(fid), recovery);
        }

        // Check that the keys were registered
        for (uint256 i = 0; i < registrations; i++) {
            uint160 fid = uint160(i + 1);
            bytes memory key = bytes.concat(bytes("key"), abi.encode(i));
            uint32 keyType = uint32(i + 1);

            KeyRegistry.KeyData memory keyData = keyRegistry.keyDataOf(fid, key);
            assertEq(keyData.keyType, keyType);
            assertEq(uint256(keyData.state), uint256(1));
        }

        // Check that the correct amount of storage was rented
        uint256 storageAfter = storageRegistry.rentedUnits();
        assertEq(storageAfter - storageBefore, storageUnits * registrations);
        assertEq(address(storageRegistry).balance, 0);
        assertEq(address(bundler).balance, 0 ether);
    }

    function testFuzzTrustedBatchRegisterWithoutSigners(uint256 registrations, uint256 storageUnits) public {
        uint256 storageBefore = storageRegistry.rentedUnits();
        registrations = bound(registrations, 1, 100);
        storageUnits = bound(storageUnits, 1, (storageRegistry.maxUnits() - storageBefore) / registrations);

        // Configure the trusted callers correctly
        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        IBundler.UserData[] memory batchArray = new IBundler.UserData[](
            registrations
        );

        for (uint256 i = 0; i < registrations; i++) {
            uint160 fid = uint160(i + 1);
            address account = address(fid);
            address recovery = address(uint160(i + 1000));

            IBundler.SignerData[] memory signers = new IBundler.SignerData[](0);
            batchArray[i] = IBundler.UserData({to: account, recovery: recovery, signers: signers, units: storageUnits});

            vm.expectEmit(true, true, true, true);
            emit Register(account, fid, recovery);

            vm.expectEmit(true, true, true, true);
            emit Rent(address(bundler), fid, storageUnits);
        }

        bundler.trustedBatchRegister(batchArray);

        for (uint256 i = 0; i < registrations; i++) {
            uint160 fid = uint160(i + 1);
            address recovery = address(uint160(i + 1000));
            assertEq(idRegistry.idOf(address(fid)), fid);
            assertEq(idRegistry.recoveryOf(fid), recovery);
        }

        // Check that the correct amount of storage was rented
        uint256 storageAfter = storageRegistry.rentedUnits();
        assertEq(storageAfter - storageBefore, storageUnits * registrations);
        assertEq(address(storageRegistry).balance, 0);
        assertEq(address(bundler).balance, 0 ether);
    }

    function testFuzzCannotTrustedBatchRegisterWithInvalidBatch(address account) public {
        vm.assume(account != address(0));

        // Configure the trusted callers correctly
        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        _registerValidator(1, 1);

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        IBundler.SignerData[] memory signers = new IBundler.SignerData[](1);
        signers[0] = IBundler.SignerData({keyType: 1, key: "", metadataType: 1, metadata: ""});

        IBundler.UserData[] memory batchArray = new IBundler.UserData[](2);
        batchArray[0] = IBundler.UserData({to: account, recovery: address(0), signers: signers, units: 1});

        vm.expectRevert(StorageRegistry.InvalidAmount.selector);
        bundler.trustedBatchRegister(batchArray);

        _assertUnsuccessfulRegistration(account);
    }

    function testFuzzCannotTrustedBatchRegisterFromUntrustedCaller(address alice, address untrustedCaller) public {
        // Call is made from an address that is not address(this), since address(this) is the deployer
        // and therefore the trusted caller for Bundler
        vm.assume(untrustedCaller != address(this));

        // Configure the trusted callers correctly
        vm.startPrank(owner);
        idRegistry.setTrustedCaller(address(bundler));
        keyRegistry.setTrustedCaller(address(bundler));
        vm.stopPrank();

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        IBundler.SignerData[] memory signers = new IBundler.SignerData[](1);
        signers[0] = IBundler.SignerData({keyType: 1, key: "", metadataType: 1, metadata: ""});

        IBundler.UserData[] memory batchArray = new IBundler.UserData[](1);
        batchArray[0] = IBundler.UserData({to: alice, recovery: address(0), signers: signers, units: 1});

        vm.prank(untrustedCaller);
        vm.expectRevert(TrustedCaller.OnlyTrustedCaller.selector);
        bundler.trustedBatchRegister(batchArray);

        _assertUnsuccessfulRegistration(alice);
    }

    function testFuzzTrustedBatchRegisterIfIdRegistryDisabled(address alice) public {
        // State: Trusted registration is disabled in IdRegistry
        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        bytes32 operatorRoleId = storageRegistry.operatorRoleId();
        vm.prank(roleAdmin);
        storageRegistry.grantRole(operatorRoleId, address(bundler));

        IBundler.SignerData[] memory signers = new IBundler.SignerData[](1);
        signers[0] = IBundler.SignerData({keyType: 1, key: "key", metadataType: 1, metadata: "metadata"});

        IBundler.UserData[] memory batchArray = new IBundler.UserData[](1);
        batchArray[0] = IBundler.UserData({to: alice, recovery: address(0), signers: signers, units: 1});

        vm.expectRevert(TrustedCaller.Registrable.selector);
        bundler.trustedBatchRegister(batchArray);

        _assertUnsuccessfulRegistration(alice);
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
        vm.expectRevert(TrustedCaller.InvalidAddress.selector);
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

        deal(sender, amount);
        vm.prank(sender);
        vm.expectRevert(Bundler.Unauthorized.selector);
        payable(address(bundler)).transfer(amount);
    }
}
