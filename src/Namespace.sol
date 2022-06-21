// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {ERC721} from "../lib/solmate/src/tokens/ERC721.sol";

// The commit was not found
error InvalidCommit();

// The name contained invalid characters
error InvalidName();

contract Namespace {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // event Register(uint256 indexed id, address indexed to);

    /*//////////////////////////////////////////////////////////////
                         STORAGE
    //////////////////////////////////////////////////////////////*/

    // Mapping from commitment hash to block number of commitment
    mapping(bytes32 => uint256) public ageOf;

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function generateCommit(
        bytes16 username,
        address owner,
        bytes32 salt
    ) public pure returns (bytes32) {
        if (!_isValidUsername(username)) revert InvalidName();
        return keccak256(abi.encode(username, owner, salt));
    }

    function makeCommit(bytes32 commit) public {
        // someone can keep spamming the commit? is that a problem?
        ageOf[commit] = block.number;
    }

    function register(
        bytes16 username,
        address owner,
        bytes32 salt
    ) external payable {
        bytes32 commit = generateCommit(username, owner, salt);

        if (ageOf[commit] == 0) revert InvalidCommit();

        commit = 0;

        // if the username not available, revert
        // if the username does not match standards, revert
        // call the mint function on the ERC-721
    }

    function _isValidUsername(bytes16 name) internal pure returns (bool) {
        uint256 length = name.length;

        for (uint256 i = 0; i < length; ) {
            uint8 charInt = uint8(name[i]);
            // TODO: can probably be optimized with a bitmask, but write tests first
            // Allow inclusive ranges 45, 48 - 57, 97-122,
            if (
                (charInt >= 1 && charInt <= 44) ||
                (charInt >= 46 && charInt <= 47) ||
                (charInt >= 58 && charInt <= 96) ||
                charInt >= 123
            ) {
                return false;
            }

            // This is safe because name.length will never exceed 16 since it is a bytes16
            unchecked {
                i++;
            }
        }
        return true;
    }
}
