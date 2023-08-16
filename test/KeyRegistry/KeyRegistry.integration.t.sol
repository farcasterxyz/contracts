// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {KeyRegistry} from "../../src/KeyRegistry.sol";
import {IMetadataValidator} from "../../src/interfaces/IMetadataValidator.sol";
import {AppIdValidator} from "../../src/validators/AppIdValidator.sol";

import {AppIdValidatorTestSuite} from "../validators/AppIdValidator/AppIdValidatorTestSuite.sol";
import {KeyRegistryTestSuite} from "./KeyRegistryTestSuite.sol";

/* solhint-disable state-visibility */

contract KeyRegistryIntegrationTest is KeyRegistryTestSuite, AppIdValidatorTestSuite {
    function setUp() public override(KeyRegistryTestSuite, AppIdValidatorTestSuite) {
        super.setUp();

        vm.prank(owner);
        idRegistry.disableTrustedOnly();

        vm.prank(owner);
        keyRegistry.setValidator(1, 1, IMetadataValidator(address(validator)));
    }

    event Add(uint256 indexed fid, uint32 indexed scheme, bytes indexed key, bytes keyBytes, bytes metadata);

    function testFuzzAdd(address to, uint256 signerPk, address recovery, bytes calldata key) public {
        signerPk = _boundPk(signerPk);
        address signer = vm.addr(signerPk);

        uint256 userFid = _registerFid(to, recovery);
        uint256 appFid = _register(signer);

        uint32 scheme = 1;
        uint8 typeId = 1;

        bytes memory sig = _signMetadata(signerPk, userFid, appFid, key);

        bytes memory metadata = bytes.concat(
            abi.encodePacked(typeId),
            abi.encode(AppIdValidator.AppId({appFid: appFid, appSigner: signer, signature: sig}))
        );

        vm.expectEmit();
        emit Add(userFid, scheme, key, key, metadata);
        vm.prank(to);
        keyRegistry.add(scheme, key, metadata);

        assertAdded(userFid, key, scheme);
    }

    function testFuzzAddRevertsInvalidSig(
        address to,
        uint256 signerPk,
        uint256 otherPk,
        address recovery,
        bytes calldata key
    ) public {
        signerPk = _boundPk(signerPk);
        otherPk = _boundPk(otherPk);
        vm.assume(signerPk != otherPk);
        address signer = vm.addr(signerPk);

        uint256 userFid = _registerFid(to, recovery);
        uint256 appFid = _register(signer);

        uint32 scheme = 1;
        uint8 typeId = 1;

        bytes memory sig = _signMetadata(otherPk, userFid, appFid, key);

        bytes memory metadata = bytes.concat(
            abi.encodePacked(typeId),
            abi.encode(AppIdValidator.AppId({appFid: appFid, appSigner: signer, signature: sig}))
        );

        vm.expectRevert(KeyRegistry.InvalidMetadata.selector);
        vm.prank(to);
        keyRegistry.add(scheme, key, metadata);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _registerFid(address to, address recovery) internal returns (uint256) {
        vm.prank(to);
        return idRegistry.register(recovery);
    }

    function assertEq(KeyRegistry.KeyState a, KeyRegistry.KeyState b) internal {
        assertEq(uint8(a), uint8(b));
    }

    function assertNull(uint256 fid, bytes memory key) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.NULL);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, 0);
    }

    function assertAdded(uint256 fid, bytes memory key, uint32 scheme) internal {
        assertEq(keyRegistry.keyDataOf(fid, key).state, KeyRegistry.KeyState.ADDED);
        assertEq(keyRegistry.keyDataOf(fid, key).scheme, scheme);
    }
}
