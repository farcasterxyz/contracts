// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SignatureCheckerTestSuite} from "./SignatureCheckerTestSuite.sol";
import {ERC1271WalletMock, ERC1271MaliciousMock} from "../SignatureChecker/SignatureChecker.Mock.sol";
import {console} from "forge-std/console.sol";
import {SignatureChecker} from "openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/* solhint-disable state-visibility */

contract SignatureCheckerTest is SignatureCheckerTestSuite {
    function testMockWalletInitialized(uint256 recipientPk) public {
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);
        ERC1271WalletMock _mockWallet = new ERC1271WalletMock(recipient);
        assertEq(_mockWallet.owner(), recipient);
    }

    function testMockWalletValidSignature(uint256 recipientPk) public {
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);
        ERC1271WalletMock _mockWallet = new ERC1271WalletMock(recipient);
        address walletAddress = address(_mockWallet);

        bytes32 digest = keccak256(bytes("testMsg"));

        assertEq(_mockWallet.owner(), recipient);

        bytes memory signature = _signMsg(recipientPk, digest);

        assertEq(SignatureChecker.isValidSignatureNow(walletAddress, digest, signature), true);
    }

    function testMockWalletInvalidSignatureForDigest(uint256 recipientPk) public {
        recipientPk = _boundPk(recipientPk);
        address recipient = vm.addr(recipientPk);
        ERC1271WalletMock _mockWallet = new ERC1271WalletMock(recipient);
        address walletAddress = address(_mockWallet);

        bytes32 digest = keccak256(bytes("testMsg"));
        bytes32 badDigest = keccak256(bytes("testMsg2"));

        assertEq(_mockWallet.owner(), recipient);

        bytes memory signature = _signMsg(recipientPk, badDigest);
        assertEq(SignatureChecker.isValidSignatureNow(walletAddress, digest, signature), false);
    }

    function testMockWalletInvalidSignatureForSigner(uint256 recipientPk) public {
        recipientPk = _boundPk(recipientPk);
        uint256 maliciousPk = _boundPk(250);
        address recipient = vm.addr(recipientPk);
        ERC1271WalletMock _mockWallet = new ERC1271WalletMock(recipient);
        address walletAddress = address(_mockWallet);

        bytes32 digest = keccak256(bytes("testMsg"));

        assertEq(_mockWallet.owner(), recipient);

        bytes memory signature = _signMsg(maliciousPk, digest);

        assertEq(SignatureChecker.isValidSignatureNow(walletAddress, digest, signature), false);
    }
}
