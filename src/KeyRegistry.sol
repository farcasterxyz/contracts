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
    error InvalidBatchInput();

    event Register(uint256 indexed fid, uint256 indexed scope, bytes indexed key);
    event Remove(uint256 indexed fid, uint256 indexed scope, bytes indexed key);
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
        _register(fid, scope, key);
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

    function bulkAddSignersForMigration(uint256[] calldata fids, bytes[][] calldata keys) external onlyOwner {
        if (isMigrated()) revert AlreadyMigrated();
        if (fids.length != keys.length) revert InvalidBatchInput();

        unchecked {
            for (uint256 i = 0; i < fids.length; i++) {
                uint256 fid = fids[i];
                for (uint256 j = 0; j < keys[i].length; j++) {
                    _register(fid, 1, keys[i][j]);
                }
            }
        }
    }

    function bulkRemoveSignersForMigration(uint256[] calldata fids, bytes[][] calldata keys) external onlyOwner {
        if (isMigrated()) revert AlreadyMigrated();
        if (fids.length != keys.length) revert InvalidBatchInput();

        unchecked {
            for (uint256 i = 0; i < fids.length; i++) {
                uint256 fid = fids[i];
                for (uint256 j = 0; j < keys[i].length; j++) {
                    _remove(fid, 1, keys[i][j]);
                }
            }
        }
    }

    function _register(uint256 fid, uint256 scope, bytes calldata key) internal {
        Signer storage signer = signers[fid][scope][key];
        if (signer.state != SignerState.UNINITIALIZED) revert InvalidState();

        signer.state = SignerState.AUTHORIZED;
        emit Register(fid, scope, key);
    }

    function _remove(uint256 fid, uint256 scope, bytes calldata key) internal {
        Signer storage signer = signers[fid][scope][key];
        if (signer.state != SignerState.AUTHORIZED && signer.state != SignerState.FROZEN) revert InvalidState();

        signer.state = SignerState.UNINITIALIZED;
        emit Remove(fid, scope, key);
    }
}
