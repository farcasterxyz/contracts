// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {IDRegistryTestable} from "./Utils.sol";
import {NameRegistry} from "../src/NameRegistry.sol";
import {MinimalForwarder} from "openzeppelin/contracts/metatx/MinimalForwarder.sol";
import {EIP712} from "openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/* solhint-disable state-visibility */
/* solhint-disable avoid-low-level-calls */

contract MetaTxTest is Test {
    IDRegistryTestable idRegistry;
    ERC1967Proxy nameRegistryProxy;
    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistry;
    MinimalForwarder forwarder;

    event Register(address indexed to, uint256 indexed id, address recovery, string url);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant _TYPEHASH_FW_REQ =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)");

    bytes32 private constant _TYPEHASH_EIP712_DS =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // The largest uint256 that can be used as an ECDSA private key
    uint256 constant PKEY_MAX = 115792089237316195423570985008687907852837564279074904382605163141518161494337;

    // A timestamp during which registrations are allowed - Dec 1, 2022 00:00:00 GMT
    uint256 constant DEC1_2022_TS = 1669881600;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        forwarder = new MinimalForwarder();

        // Set up the idRegistry and move to a state where it is no longer in trusted registration
        idRegistry = new IDRegistryTestable(address(forwarder));
        idRegistry.disableTrustedRegister();

        // Set up the nameRegistry and proxy, and move to a state where it is no longer in trusted registration
        nameRegistryImpl = new NameRegistry(address(forwarder));
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", address(this));
        nameRegistry.disableTrustedRegister();
    }

    /*//////////////////////////////////////////////////////////////
                               METATX TEST
    //////////////////////////////////////////////////////////////*/

    function testIDRegistryRegister(
        address trustedSender,
        address recovery,
        uint256 alicePrivateKey
    ) public {
        vm.assume(alicePrivateKey > 0 && alicePrivateKey < PKEY_MAX);
        address alice = vm.addr(alicePrivateKey);

        // 1. Construct the ForwardRequest which contains all the parameters needed to make the call
        MinimalForwarder.ForwardRequest memory req = MinimalForwarder.ForwardRequest({
            // the address that should be credited as the sender of the message
            from: alice,
            // the address of the contract that is being called
            to: address(idRegistry),
            // the nonce that must be supplied to the forwarder (incremented per request)
            nonce: forwarder.getNonce(alice),
            // the amount of ether that should be send with the call
            value: 0,
            // the gas limit that should be used for the call
            gas: 100_000,
            // the call data that should be forwarded to the contract
            data: abi.encodeWithSelector(bytes4(keccak256("register(address,address,string)")), alice, recovery, "") // calldata
        });

        bytes memory signature = _signReq(req, alicePrivateKey);

        // 4. Have the trusted sender call the contract and check that the name is registered to alice.
        vm.prank(trustedSender);
        vm.expectEmit(true, true, true, true);
        emit Register(alice, 1, recovery, "");
        forwarder.execute(req, signature);
        assertEq(idRegistry.idOf(alice), 1);
    }

    function testNameRegistryRegister(
        address trustedSender,
        address recovery,
        uint256 alicePrivateKey
    ) public {
        vm.assume(alicePrivateKey > 0 && alicePrivateKey < PKEY_MAX);
        address alice = vm.addr(alicePrivateKey);

        // 1. Make the commit
        bytes32 commitHash = nameRegistry.generateCommit(bytes16("alice"), alice, "secret");

        MinimalForwarder.ForwardRequest memory makeCommitReq = MinimalForwarder.ForwardRequest({
            from: alice,
            to: address(nameRegistry),
            nonce: forwarder.getNonce(alice),
            value: 0,
            gas: 100_000,
            data: abi.encodeWithSelector(NameRegistry.makeCommit.selector, commitHash) // calldata
        });

        bytes memory makeCommitSig = _signReq(makeCommitReq, alicePrivateKey);

        vm.deal(trustedSender, 1 ether);
        vm.warp(DEC1_2022_TS);
        vm.prank(trustedSender);
        forwarder.execute(makeCommitReq, makeCommitSig);

        // 2. Register the name alice
        MinimalForwarder.ForwardRequest memory registerReq = MinimalForwarder.ForwardRequest({
            from: alice,
            to: address(nameRegistry),
            nonce: forwarder.getNonce(alice),
            value: 0.001 ether,
            gas: 200_000,
            data: abi.encodeWithSelector(
                NameRegistry.register.selector,
                bytes16("alice"),
                alice,
                bytes32("secret"),
                recovery
            )
        });

        bytes memory registerSig = _signReq(registerReq, alicePrivateKey);

        vm.warp(block.timestamp + 60);
        vm.prank(trustedSender);
        forwarder.execute{value: 0.001 ether}(registerReq, registerSig);
        assertEq(nameRegistry.ownerOf(uint256(bytes32("alice"))), alice);
    }

    function _signReq(MinimalForwarder.ForwardRequest memory req, uint256 privateKey) private returns (bytes memory) {
        // Generate the EIP712 hashStruct from the request
        // (s : 𝕊) = keccak256(keccak256(encodeType(typeOf(s))) ‖ encodeData(s))
        bytes32 hashStruct = keccak256(
            abi.encode(_TYPEHASH_FW_REQ, req.from, req.to, req.value, req.gas, req.nonce, keccak256(req.data))
        );

        // Pack the prefix, domain separator and hashStruct into a bytestring, hash it, sign it, and pack the
        // signature into a single value
        bytes32 message = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), hashStruct));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
        return abi.encodePacked(r, s, v);
    }

    // Returns the EIP712 domain separator
    function _domainSeparator() private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _TYPEHASH_EIP712_DS,
                    keccak256("MinimalForwarder"),
                    keccak256("0.0.1"),
                    block.chainid,
                    address(forwarder)
                )
            );
    }
}
