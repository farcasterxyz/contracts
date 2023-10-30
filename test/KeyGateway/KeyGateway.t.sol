// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {KeyGateway} from "../../src/KeyGateway.sol";
import {KeyRegistry, IKeyRegistry} from "../../src/KeyRegistry.sol";
import {TransferHelper} from "../../src/lib/TransferHelper.sol";
import {TrustedCaller} from "../../src/lib/TrustedCaller.sol";
import {Signatures} from "../../src/lib/Signatures.sol";
import {Guardians} from "../../src/lib/Guardians.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";

import {KeyGatewayTestSuite} from "./KeyGatewayTestSuite.sol";

/* solhint-disable state-visibility */

contract KeyGatewayTest is KeyGatewayTestSuite {
    using FixedPointMathLib for uint256;

    event Add(
        uint256 indexed fid,
        uint32 indexed keyType,
        bytes indexed key,
        bytes keyBytes,
        uint8 metadataType,
        bytes metadata
    );
    event SetUsdFee(uint256 oldFee, uint256 newFee);
    event SetVault(address oldVault, address newVault);
    event Withdraw(address indexed to, uint256 amount);

    function testVersion() public {
        assertEq(keyGateway.VERSION(), "2023.10.04");
    }

    /*//////////////////////////////////////////////////////////////
                                   ADD
    //////////////////////////////////////////////////////////////*/

    function testFuzzFeePriceFeedPrice(uint48 usdFee, int256 ethUsdPrice) public {
        // Ensure Chainlink price is in bounds
        ethUsdPrice = bound(
            ethUsdPrice, int256(storageRegistry.priceFeedMinAnswer()), int256(storageRegistry.priceFeedMaxAnswer())
        );

        priceFeed.setPrice(ethUsdPrice);
        vm.startPrank(owner);
        storageRegistry.refreshPrice();
        keyGateway.setUsdFee(usdFee);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(keyGateway.price(), uint256(usdFee).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzFeeFixedEthUsdPrice(uint48 usdFee, uint256 ethUsdPrice) public {
        ethUsdPrice = bound(ethUsdPrice, storageRegistry.priceFeedMinAnswer(), storageRegistry.priceFeedMaxAnswer());
        vm.startPrank(owner);
        storageRegistry.setFixedEthUsdPrice(ethUsdPrice);
        keyGateway.setUsdFee(usdFee);
        vm.stopPrank();
        vm.roll(block.number + 1);

        assertEq(keyGateway.price(), uint256(usdFee).divWadUp(uint256(ethUsdPrice)));
    }

    function testFuzzAdd(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        uint256 fee = keyGateway.price();
        vm.deal(to, fee);

        assertEq(keyRegistry.totalKeys(fid), 0);

        vm.expectEmit();
        emit Add(fid, keyType, key, key, metadataType, metadata);
        vm.prank(to);
        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);

        assertEq(address(keyGateway).balance, fee);
        assertEq(keyRegistry.totalKeys(fid), 1);
        assertAdded(fid, key, keyType);
    }

    function testFuzzAddReturnsOverpayment(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint64 overpayment
    ) public {
        _assumeClean(to);
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        uint256 fee = keyGateway.price();
        vm.deal(to, fee + overpayment);

        assertEq(keyRegistry.totalKeys(fid), 0);

        vm.expectEmit();
        emit Add(fid, keyType, key, key, metadataType, metadata);
        vm.prank(to);
        keyGateway.add{value: fee + overpayment}(keyType, key, metadataType, metadata);

        assertEq(address(to).balance, overpayment);
        assertEq(address(keyGateway).balance, fee);
        assertEq(keyRegistry.totalKeys(fid), 1);
        assertAdded(fid, key, keyType);
    }

    function testFuzzAddRevertsUnderpayment(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        _assumeClean(to);
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        uint256 fee = keyGateway.price();
        uint256 underpayment = bound(fee, 1, fee);
        vm.deal(to, fee - underpayment);

        assertEq(keyRegistry.totalKeys(fid), 0);
        vm.expectRevert(KeyGateway.InvalidPayment.selector);
        vm.prank(to);
        keyGateway.add{value: fee - underpayment}(keyType, key, metadataType, metadata);

        assertEq(address(to).balance, fee - underpayment);
        assertEq(address(keyGateway).balance, 0);
        assertNull(fid, key);
    }

    function testFuzzAddRevertsUnregisteredValidator(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        uint256 fee = keyGateway.price();
        vm.deal(to, fee);

        vm.prank(to);
        vm.expectRevert(abi.encodeWithSelector(KeyRegistry.ValidatorNotFound.selector, keyType, metadataType));
        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsInvalidMetadata(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        _registerValidator(keyType, metadataType);

        stubValidator.setIsValid(false);

        uint256 fid = _registerFid(to, recovery);
        uint256 fee = keyGateway.price();
        vm.deal(to, fee);

        vm.prank(to);
        vm.expectRevert(KeyRegistry.InvalidMetadata.selector);
        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsUnlessFidOwner(
        address to,
        address recovery,
        address caller,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        vm.assume(to != caller);
        _registerValidator(keyType, metadataType);

        uint256 fid = _registerFid(to, recovery);
        uint256 fee = keyGateway.price();
        vm.deal(caller, fee);

        vm.prank(caller);
        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);

        assertNull(fid, key);
    }

    function testFuzzAddRevertsIfStateNotNull(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);
        uint256 fee = keyGateway.price();
        vm.deal(to, fee * 2);

        vm.startPrank(to);

        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);

        vm.stopPrank();
        assertAdded(fid, key, keyType);
    }

    function testFuzzAddRevertsIfRemoved(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 fid = _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        uint256 fee = keyGateway.price();
        vm.deal(to, fee * 2);

        vm.startPrank(to);

        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);
        keyRegistry.remove(key);

        vm.expectRevert(KeyRegistry.InvalidState.selector);
        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);

        vm.stopPrank();
        assertRemoved(fid, key, keyType);
    }

    function testFuzzAddRevertsPaused(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);
        uint256 fee = keyGateway.price();
        vm.deal(to, fee);

        vm.prank(owner);
        keyGateway.pause();

        vm.prank(to);
        vm.expectRevert("Pausable: paused");
        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);
    }

    function testFuzzAddRevertsMaxKeys(
        address to,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        _registerFid(to, recovery);
        _registerValidator(keyType, metadataType);

        uint256 fee = keyGateway.price();
        vm.deal(to, fee * 11);

        // Create 10 keys
        for (uint256 i; i < 10; i++) {
            vm.prank(to);
            keyGateway.add{value: fee}(keyType, bytes.concat(key, bytes32(i)), metadataType, metadata);
        }

        // 11th key reverts
        vm.prank(to);
        vm.expectRevert(KeyRegistry.ExceedsMaximum.selector);
        keyGateway.add{value: fee}(keyType, key, metadataType, metadata);
    }

    function testFuzzAddFor(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        uint256 fee = keyGateway.price();
        vm.deal(registrar, fee);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signAdd(ownerPk, owner, keyType, key, metadataType, metadata, deadline);

        vm.expectEmit();
        emit Add(fid, keyType, key, key, metadataType, metadata);
        vm.prank(registrar);
        keyGateway.addFor{value: fee}(owner, keyType, key, metadataType, metadata, deadline, sig);

        assertAdded(fid, key, keyType);
        assertEq(address(keyGateway).balance, fee);
    }

    function testFuzzAddForReturnsOverpayment(
        address registrar,
        uint256 ownerPk,
        address recovery,
        bytes calldata key,
        bytes memory metadata,
        uint40 _deadline,
        uint64 overpayment
    ) public {
        _assumeClean(registrar);
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(1, 1);

        uint256 fee = keyGateway.price();
        vm.deal(registrar, fee + overpayment);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signAdd(ownerPk, owner, 1, key, 1, metadata, deadline);

        vm.expectEmit();
        emit Add(fid, 1, key, key, 1, metadata);
        vm.prank(registrar);
        keyGateway.addFor{value: fee + overpayment}(owner, 1, key, 1, metadata, deadline, sig);

        assertAdded(fid, key, 1);
        assertEq(address(keyGateway).balance, fee);
        assertEq(address(registrar).balance, overpayment);
    }

    function testFuzzAddForRevertsUnderpayment(
        address registrar,
        uint256 ownerPk,
        bytes calldata key,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        _assumeClean(registrar);
        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(1, 1);

        uint256 fee = keyGateway.price();
        uint256 underpayment = bound(fee, 1, fee);
        vm.deal(registrar, fee - underpayment);

        address owner = vm.addr(ownerPk);
        _registerFid(owner, address(0));
        bytes memory sig = _signAdd(ownerPk, owner, 1, key, 1, metadata, deadline);

        vm.expectRevert(KeyGateway.InvalidPayment.selector);
        vm.prank(registrar);
        keyGateway.addFor{value: fee - underpayment}(owner, 1, key, 1, metadata, deadline, sig);

        assertEq(address(registrar).balance, fee - underpayment);
        assertEq(address(keyGateway).balance, 0);
        assertNull(1, key);
    }

    function testFuzzAddForRevertsNoFid(
        address registrar,
        uint256 ownerPk,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        uint256 fee = keyGateway.price();
        vm.deal(registrar, fee);

        address owner = vm.addr(ownerPk);
        bytes memory sig = _signAdd(ownerPk, owner, keyType, key, metadataType, metadata, deadline);

        vm.prank(registrar);
        vm.expectRevert(KeyRegistry.Unauthorized.selector);
        keyGateway.addFor{value: fee}(owner, keyType, key, metadataType, metadata, deadline, sig);
    }

    function testFuzzAddForRevertsInvalidSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        uint256 fee = keyGateway.price();
        vm.deal(registrar, fee);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = _signAdd(ownerPk, owner, keyType, key, metadataType, metadata, deadline + 1);

        vm.prank(registrar);
        vm.expectRevert(Signatures.InvalidSignature.selector);
        keyGateway.addFor{value: fee}(owner, keyType, key, metadataType, metadata, deadline, sig);

        assertNull(fid, key);
    }

    function testFuzzAddForRevertsBadSig(
        address registrar,
        uint256 ownerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes memory metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));
        metadataType = uint8(bound(metadataType, 1, type(uint8).max));

        uint256 deadline = _boundDeadline(_deadline);
        ownerPk = _boundPk(ownerPk);
        _registerValidator(keyType, metadataType);

        uint256 fee = keyGateway.price();
        vm.deal(registrar, fee);

        address owner = vm.addr(ownerPk);
        uint256 fid = _registerFid(owner, recovery);
        bytes memory sig = abi.encodePacked(bytes32("bad sig"), bytes32(0), bytes1(0));

        vm.prank(registrar);
        vm.expectRevert(Signatures.InvalidSignature.selector);
        keyGateway.addFor{value: fee}(owner, keyType, key, metadataType, metadata, deadline, sig);

        assertNull(fid, key);
    }

    function testFuzzAddForRevertsExpiredSig(
        address registrar,
        uint256 fidOwnerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));

        uint256 deadline = _boundDeadline(_deadline);
        fidOwnerPk = _boundPk(fidOwnerPk);

        address fidOwner = vm.addr(fidOwnerPk);
        uint256 fid = _registerFid(fidOwner, recovery);
        bytes memory sig = _signAdd(fidOwnerPk, fidOwner, keyType, key, metadataType, metadata, deadline);

        vm.prank(owner);
        keyGateway.setUsdFee(0);

        vm.warp(deadline + 1);

        vm.startPrank(registrar);
        vm.expectRevert(Signatures.SignatureExpired.selector);
        keyGateway.addFor(fidOwner, keyType, key, metadataType, metadata, deadline, sig);
        vm.stopPrank();

        assertNull(fid, key);
    }

    function testFuzzAddForRevertsPaused(
        address registrar,
        uint256 fidOwnerPk,
        address recovery,
        uint32 keyType,
        bytes calldata key,
        uint8 metadataType,
        bytes calldata metadata,
        uint40 _deadline
    ) public {
        keyType = uint32(bound(keyType, 1, type(uint32).max));

        uint256 deadline = _boundDeadline(_deadline);
        fidOwnerPk = _boundPk(fidOwnerPk);

        vm.deal(registrar, keyGateway.price());

        address fidOwner = vm.addr(fidOwnerPk);
        uint256 fid = _registerFid(fidOwner, recovery);
        bytes memory sig = _signAdd(fidOwnerPk, fidOwner, keyType, key, metadataType, metadata, deadline);

        vm.prank(owner);
        keyGateway.setUsdFee(0);

        vm.prank(owner);
        keyGateway.pause();

        vm.prank(registrar);
        vm.expectRevert("Pausable: paused");
        keyGateway.addFor(fidOwner, keyType, key, metadataType, metadata, deadline, sig);

        assertNull(fid, key);
    }

    /*//////////////////////////////////////////////////////////////
                           SET FEE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyOwnerCanSetFee(address caller, uint256 newFee) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyGateway.setUsdFee(newFee);
    }

    function testFuzzSetFee(uint256 newFee) public {
        uint256 currentFee = keyGateway.usdFee();

        vm.expectEmit(false, false, false, true);
        emit SetUsdFee(currentFee, newFee);

        vm.prank(owner);
        keyGateway.setUsdFee(newFee);

        assertEq(keyGateway.usdFee(), newFee);
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyAuthorizedCanPause(address caller) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert(Guardians.OnlyGuardian.selector);
        keyGateway.pause();
    }

    function testFuzzOnlyOwnerCanUnpause(address caller) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyGateway.unpause();
    }

    function testFuzzPauseUnpauseOwner() public {
        vm.prank(owner);
        keyGateway.pause();
        assertEq(keyGateway.paused(), true);

        vm.prank(owner);
        keyGateway.unpause();
        assertEq(keyGateway.paused(), false);
    }

    function testFuzzPauseUnpauseGuardian(address caller) public {
        vm.assume(caller != owner);

        vm.prank(owner);
        keyGateway.addGuardian(caller);

        vm.prank(caller);
        keyGateway.pause();
        assertEq(keyGateway.paused(), true);

        vm.prank(owner);
        keyGateway.unpause();
        assertEq(keyGateway.paused(), false);
    }

    /*//////////////////////////////////////////////////////////////
                                SET VAULT
    //////////////////////////////////////////////////////////////*/

    function testFuzzSetVault(address newVault) public {
        vm.assume(newVault != address(0));
        vm.expectEmit(false, false, false, true);
        emit SetVault(vault, newVault);

        vm.prank(owner);
        keyGateway.setVault(newVault);

        assertEq(keyGateway.vault(), newVault);
    }

    function testFuzzOnlyOwnerCanSetVault(address caller, address vault) public {
        vm.assume(caller != owner);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyGateway.setVault(vault);
    }

    function testSetVaultCannotBeZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(KeyGateway.InvalidAddress.selector);
        keyGateway.setVault(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                               WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    function testFuzzWithdrawalRevertsInsufficientFunds(uint256 amount) public {
        // Ensure amount is >=0 and deal a smaller amount to the contract
        amount = bound(amount, 1, type(uint256).max);
        vm.deal(address(keyGateway), amount - 1);

        vm.prank(owner);
        vm.expectRevert(TransferHelper.CallFailed.selector);
        keyGateway.withdraw(amount);
    }

    function testFuzzWithdrawalRevertsCallFailed(uint256 amount) public {
        vm.deal(address(keyGateway), amount);

        vm.prank(owner);
        keyGateway.setVault(address(revertOnReceive));

        vm.prank(owner);
        vm.expectRevert(TransferHelper.CallFailed.selector);
        keyGateway.withdraw(amount);
    }

    function testFuzzOnlyOwnerCanWithdraw(address caller, uint256 amount) public {
        vm.assume(caller != owner);
        vm.deal(address(keyGateway), amount);

        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        keyGateway.withdraw(amount);
    }

    function testFuzzWithdraw(uint256 amount) public {
        // Deal an amount > 1 wei so we can withraw at least 1
        amount = bound(amount, 2, type(uint256).max);
        vm.deal(address(keyGateway), amount);
        uint256 balanceBefore = address(vault).balance;

        // Withdraw at last 1 wei
        uint256 withdrawalAmount = bound(amount, 1, amount - 1);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(vault, withdrawalAmount);

        vm.prank(owner);
        keyGateway.withdraw(withdrawalAmount);

        uint256 balanceChange = address(vault).balance - balanceBefore;
        assertEq(balanceChange, withdrawalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerFid(address to, address recovery) internal returns (uint256) {
        vm.prank(idRegistry.idGateway());
        return idRegistry.register(to, recovery);
    }

    function assertEq(IKeyRegistry.KeyState a, IKeyRegistry.KeyState b) internal {
        assertEq(uint8(a), uint8(b));
    }

    function assertNull(uint256 fid, bytes memory key) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.NULL);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, 0);
        assertEq(keyRegistry.totalKeys(fid), 0);
    }

    function assertAdded(uint256 fid, bytes memory key, uint32 keyType) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
    }

    function assertRemoved(uint256 fid, bytes memory key, uint32 keyType) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, IKeyRegistry.KeyState.REMOVED);
        assertEq(keyRegistry.keyDataOf(fid, key).keyType, keyType);
    }
}
