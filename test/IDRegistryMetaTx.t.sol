// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {IDRegistry} from "../src/IDRegistry.sol";
import {MinimalForwarder} from "openzeppelin/contracts/metatx/MinimalForwarder.sol";
import {EIP712} from "openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

/* solhint-disable state-visibility */

contract IDRegistryMetaTx is Test {
    IDRegistry idRegistry; // The contract being called
    MinimalForwarder forwarder; // The trusted forwarder

    event Register(address indexed to, uint256 indexed id, address recovery);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant _TYPEHASH_FW_REQ =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)");

    bytes32 private constant _TYPEHASH_FW =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    uint256 privateKeyMax = 115792089237316195423570985008687907852837564279074904382605163141518161494337;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        forwarder = new MinimalForwarder();
        idRegistry = new IDRegistry(address(forwarder));
        idRegistry.disableTrustedRegister();
    }

    /*//////////////////////////////////////////////////////////////
                               METATX TEST
    //////////////////////////////////////////////////////////////*/

    function testCallRegisterViaForwarderViaRelay(
        address trustedSender,
        address recovery,
        uint256 alicePrivateKey
    ) public {
        vm.assume(alicePrivateKey > 0 && alicePrivateKey < privateKeyMax);
        address alice = vm.addr(alicePrivateKey);

        // 1. Construct the ForwardRequest which contains all the parameters needed to make the call
        MinimalForwarder.ForwardRequest memory req = MinimalForwarder.ForwardRequest({
            from: alice, // the address performing the registration
            to: address(idRegistry), // the contract being invoked
            nonce: 0, // the nonce of this request from this address in the forwrder
            value: 0, // the amount of eth to send with the request
            gas: 100_000, // the gas limit for the caller contract
            data: abi.encodeWithSelector(bytes4(keccak256("register(address)")), recovery) // calldata
        });

        // 2. Generate the prefix bytes for the EIP712 signable bytestring
        bytes memory prefixBytes = "\x19\x01";

        // 3. Generate the MinimalForwarder's EIP712 domain signature which follows the prefix
        bytes32 domainSeparator = keccak256(
            abi.encode(
                _TYPEHASH_FW,
                keccak256("MinimalForwarder"),
                keccak256("0.0.1"),
                block.chainid,
                address(forwarder)
            )
        );

        // 4. Generate the EIP712 hashStruct (s : 𝕊) = keccak256(keccak256(encodeType(typeOf(s))) ‖ encodeData(s))
        //    which follows the domain signature
        bytes32 hashStruct = keccak256(
            abi.encode(_TYPEHASH_FW_REQ, req.from, req.to, req.value, req.gas, req.nonce, keccak256(req.data))
        );

        // 5. Pack the data into a single message, sign it, and pack the signature into a single value
        bytes32 message = keccak256(abi.encodePacked(prefixBytes, domainSeparator, hashStruct));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, message);
        bytes memory packed = abi.encodePacked(r, s, v);

        // 6. Have the trusted sender call the contract and check that the name is registered to alice.
        vm.deal(trustedSender, 1 ether);
        vm.prank(trustedSender);
        vm.expectEmit(true, true, true, true);
        emit Register(alice, 1, recovery);
        forwarder.execute(req, packed);

        assertEq(idRegistry.idOf(alice), 1);
    }
}
