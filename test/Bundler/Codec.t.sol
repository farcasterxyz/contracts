// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {Codec, PackedUserData, UserData} from "../../src/lib/Codec.sol";

/* solhint-disable state-visibility */

contract CodecTest is Test {
    function testFuzz_encodePackedUserData(PackedUserData[] calldata userData) public {
        bytes memory encoded = Codec.toBytes(userData);
        UserData[] memory decoded = this.decode(encoded);

        assertEq(decoded.length, userData.length);
    }

    function decode(bytes calldata encoded) public pure returns (UserData[] memory) {
        return Codec.toUserData(encoded, bytes2(uint16(2)));
    }
}
