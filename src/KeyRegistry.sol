// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Ownable2Step} from "openzeppelin/contracts/access/Ownable2Step.sol";
import {IdRegistry} from "./IdRegistry.sol";

contract KeyRegistry is Ownable2Step {
    enum SignerState {
        UNINITIALIZED,
        AUTHORIZED,
        FROZEN,
        REVOKED
    }

    struct Signer {
        SignerState state;
        bytes32 merkleRoot;
    }

    error InvalidState();
    error Unauthorized();
    error AlreadyMigrated();

    event Register(uint256 indexed fid, uint256 indexed scope, bytes indexed key);
    event Revoke(uint256 indexed fid, uint256 indexed scope, bytes indexed key);
    event Freeze(uint256 indexed fid, uint256 indexed scope, bytes indexed key);
    event SignersMigrated();

    IdRegistry public idRegistry;
    uint40 public signersMigratedAt;

    mapping(uint256 fid => mapping(uint256 scope => mapping(bytes key => Signer signer))) public signers;

    constructor(address _idRegistry, address _owner) {
        _transferOwnership(_owner);

        idRegistry = IdRegistry(_idRegistry);
    }

    modifier onlyFidOwner(uint256 fid) {
        if (idRegistry.idOf(msg.sender) != fid) revert Unauthorized();
        _;
    }

    function signerOf(uint256 fid, uint256 scope, bytes calldata key) public view returns (Signer memory) {
        return signers[fid][scope][key];
    }

    function isMigrated() public view returns (bool) {
        return signersMigratedAt != 0;
    }

    function register(uint256 fid, uint256 scope, bytes calldata key) public onlyFidOwner(fid) {
        Signer storage signer = signers[fid][scope][key];
        if (signer.state != SignerState.UNINITIALIZED) revert InvalidState();

        signer.state = SignerState.AUTHORIZED;
        emit Register(fid, scope, key);
    }

    function revoke(uint256 fid, uint256 scope, bytes calldata key) public onlyFidOwner(fid) {
        Signer storage signer = signers[fid][scope][key];
        if (signer.state != SignerState.AUTHORIZED && signer.state != SignerState.FROZEN) revert InvalidState();

        signer.state = SignerState.REVOKED;
        emit Revoke(fid, scope, key);
    }

    function freeze(uint256 fid, uint256 scope, bytes calldata key, bytes32 merkleRoot) public onlyFidOwner(fid) {
        Signer storage signer = signers[fid][scope][key];
        if (signer.state != SignerState.AUTHORIZED) revert InvalidState();

        signer.state = SignerState.FROZEN;
        signer.merkleRoot = merkleRoot;
        emit Freeze(fid, scope, key);
    }

    function migrateSigners() external onlyOwner {
        if (isMigrated()) revert AlreadyMigrated();
        signersMigratedAt = uint40(block.timestamp);
        emit SignersMigrated();
    }
}
