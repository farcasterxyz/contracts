// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC2771Forwarder} from "openzeppelin-latest/contracts/metatx/ERC2771Forwarder.sol";

import {Forwarder} from "../../src/Forwarder.sol";

import {IdRegistryHarness} from "../Utils.sol";

import {TestSuiteSetup} from "../TestSuiteSetup.sol";

/* solhint-disable state-visibility */
/* solhint-disable avoid-low-level-calls */

contract IdRegistryMetaTxTest is TestSuiteSetup {
    IdRegistryHarness idRegistry;
    Forwarder forwarder;

    event Register(address indexed to, uint256 indexed id, address recovery);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address defaultAdmin = address(this);

    bytes32 private constant _TYPEHASH_FW_REQ = keccak256(
        "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)"
    );

    bytes32 private constant _TYPEHASH_EIP712_DS =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // The largest uint256 that can be used as an ECDSA private key
    uint256 constant PKEY_MAX = 115792089237316195423570985008687907852837564279074904382605163141518161494337;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        TestSuiteSetup.setUp();

        forwarder = new Forwarder("Farcaster Forwarder");

        // Set up the idRegistry and move to a state where it is no longer in trusted registration
        idRegistry = new IdRegistryHarness(address(forwarder));
        idRegistry.disableTrustedOnly();
    }

    /*//////////////////////////////////////////////////////////////
                               METATX TEST
    //////////////////////////////////////////////////////////////*/

    function testFuzzIdRegistryRegister(address relayer, address recovery, uint256 alicePrivateKey) public {
        alicePrivateKey = bound(alicePrivateKey, 1, PKEY_MAX - 1);
        address alice = vm.addr(alicePrivateKey);

        // 1. Construct the ForwardRequest which contains all the parameters needed to make the call
        ERC2771Forwarder.ForwardRequestData memory req = ERC2771Forwarder.ForwardRequestData({
            // the address that should be credited as the sender of the message
            from: alice,
            // the address of the contract that is being called
            to: address(idRegistry),
            // the amount of ether that should be send with the call
            value: 0,
            // the gas limit that should be used for the call
            gas: 100_000,
            // deadline at which this request is no longer valid
            deadline: 1,
            // the call data that should be forwarded to the contract
            data: abi.encodeWithSelector(bytes4(keccak256("register(address,address)")), alice, recovery),
            // empty signature, added with _signReq
            signature: ""
        });

        _signReq(req, forwarder.nonces(alice), alicePrivateKey);

        // 4. Have the relayer call the contract and check that the name is registered to alice.
        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit Register(alice, 1, recovery);
        forwarder.execute(req);
        assertEq(idRegistry.idOf(alice), 1);
    }

    function _signReq(ERC2771Forwarder.ForwardRequestData memory req, uint256 nonce, uint256 privateKey) private view {
        // Generate the EIP712 hashStruct from the request
        // (s : 𝕊) = keccak256(keccak256(encodeType(typeOf(s))) ‖ encodeData(s))
        bytes32 hashStruct = keccak256(
            abi.encode(_TYPEHASH_FW_REQ, req.from, req.to, req.value, req.gas, nonce, req.deadline, keccak256(req.data))
        );

        // Pack the prefix, domain separator and hashStruct into a bytestring, hash it, sign it,
        // and pack the signature into a single value
        bytes32 message = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), hashStruct));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
        req.signature = abi.encodePacked(r, s, v);
    }

    // Returns the EIP712 domain separator
    function _domainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                _TYPEHASH_EIP712_DS, keccak256("Farcaster Forwarder"), keccak256("1"), block.chainid, address(forwarder)
            )
        );
    }
}
