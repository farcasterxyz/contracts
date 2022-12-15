// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {MinimalForwarder} from "openzeppelin/contracts/metatx/MinimalForwarder.sol";
import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";

import {IdRegistryTestable} from "./Utils.sol";
import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility */
/* solhint-disable avoid-low-level-calls */

contract MetaTxTest is Test {
    IdRegistryTestable idRegistry;
    ERC1967Proxy nameRegistryProxy;
    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistry;
    MinimalForwarder forwarder;

    event Register(address indexed to, uint256 indexed id, address recovery, string url);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address defaultAdmin = address(this);
    address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
    address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);

    bytes32 private constant _TYPEHASH_FW_REQ =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)");

    bytes32 private constant _TYPEHASH_EIP712_DS =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // The largest uint256 that can be used as an ECDSA private key
    uint256 constant PKEY_MAX = 115792089237316195423570985008687907852837564279074904382605163141518161494337;

    // A timestamp during which registrations are allowed - Dec 1, 2022 00:00:00 GMT
    uint256 constant DEC1_2022_TS = 1669881600;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 constant ALICE_TOKEN_ID = uint256(bytes32("alice"));

    address[] knownContracts = [
        address(0xCe71065D4017F316EC606Fe4422e11eB2c47c246), // FuzzerDict
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C), // CREATE2 Factory
        address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84), // address(this)
        address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A), // FORWARDER
        address(0x185a4dc360CE69bDCceE33b3784B0282f7961aea), // ???
        address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D), // ???
        address(0xEFc56627233b02eA95bAE7e19F648d7DcD5Bb132), // ???
        address(0xf5a2fE45F4f1308502b1C136b9EF8af136141382)
    ];

    address constant PRECOMPILE_CONTRACTS = address(9); // some addresses up to 0x9 are precompiled contracts

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        forwarder = new MinimalForwarder();

        // Set up the idRegistry and move to a state where it is no longer in trusted registration
        idRegistry = new IdRegistryTestable(address(forwarder));
        idRegistry.disableTrustedOnly();

        // Set up the nameRegistry and proxy, and move to a state where it is no longer in trusted registration
        nameRegistryImpl = new NameRegistry(address(forwarder));
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        nameRegistry.grantRole(ADMIN_ROLE, defaultAdmin);
        nameRegistry.disableTrustedOnly();
    }

    /*//////////////////////////////////////////////////////////////
                               METATX TEST
    //////////////////////////////////////////////////////////////*/

    function testIdRegistryRegister(address relayer, address recovery, uint256 alicePrivateKey) public {
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
            data: abi.encodeWithSelector(bytes4(keccak256("register(address,address,string)")), alice, recovery, "")
        });

        bytes memory signature = _signReq(req, alicePrivateKey);

        // 4. Have the relayer call the contract and check that the name is registered to alice.
        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit Register(alice, 1, recovery, "");
        forwarder.execute(req, signature);
        assertEq(idRegistry.idOf(alice), 1);
    }

    function testNameRegistryTransfer(address relayer, address recovery, uint256 alicePrivateKey) public {
        _assumeClean(relayer);
        vm.assume(alicePrivateKey > 0 && alicePrivateKey < PKEY_MAX);
        address alice = vm.addr(alicePrivateKey);

        // Register the name alice
        bytes32 commitHash = nameRegistry.generateCommit(bytes16("alice"), alice, "secret", recovery);

        vm.deal(relayer, 1 ether);
        vm.warp(DEC1_2022_TS);
        vm.prank(relayer);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + 60);
        uint256 fee = nameRegistry.fee();
        vm.prank(relayer);
        nameRegistry.register{value: fee}(bytes16("alice"), alice, bytes32("secret"), recovery);
        assertEq(nameRegistry.ownerOf(uint256(bytes32("alice"))), alice);

        address bob = address(bytes20(bytes32("bob")));

        // Transfer the name alice via a meta transaction
        MinimalForwarder.ForwardRequest memory transferReq = MinimalForwarder.ForwardRequest({
            from: alice,
            to: address(nameRegistry),
            nonce: forwarder.getNonce(alice),
            value: 0 ether,
            gas: 200_000,
            data: abi.encodeWithSelector(NameRegistry.transferFrom.selector, alice, bob, ALICE_TOKEN_ID)
        });

        bytes memory transferSig = _signReq(transferReq, alicePrivateKey);

        vm.prank(relayer);
        forwarder.execute(transferReq, transferSig);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
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
        return keccak256(
            abi.encode(
                _TYPEHASH_EIP712_DS,
                keccak256("MinimalForwarder"),
                keccak256("0.0.1"),
                block.chainid,
                address(forwarder)
            )
        );
    }

    function _assumeClean(address a) internal {
        // TODO: extract the general assume functions into a utils so it can be shared with NameRegistry.t.sol
        for (uint256 i = 0; i < knownContracts.length; i++) {
            vm.assume(a != knownContracts[i]);
        }

        vm.assume(a > PRECOMPILE_CONTRACTS);
    }
}
