// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

struct UserData {
    address to;
    address recovery;
    uint32 scheme;
    bytes key;
    bytes metadata;
    uint256 units;
}

struct PackedUserData {
    address to;
    address recovery;
    bytes32 key;
    bytes32 metadataSig;
}

uint256 constant PACKED_USER_DATA_SIZE = 104;

error InvalidLength();

library Codec {
    function toUserData(bytes calldata data, bytes2 metadataAppFid) internal pure returns (UserData[] memory) {
        if (data.length % PACKED_USER_DATA_SIZE != 0) revert InvalidLength();
        uint256 numUsers = data.length / PACKED_USER_DATA_SIZE;
        UserData[] memory userData = new UserData[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            uint256 offset = i * PACKED_USER_DATA_SIZE;

            bytes32 metadataSig = abi.decode(data[offset + 72:offset + 104], (bytes32));

            userData[i] = UserData({
                to: abi.decode(bytes.concat(bytes12(0), data[offset:offset + 20]), (address)),
                recovery: abi.decode(bytes.concat(bytes12(0), data[offset + 20:offset + 40]), (address)),
                scheme: 1,
                key: bytes.concat(abi.decode(data[offset + 40:offset + 72], (bytes32))),
                metadata: bytes.concat(bytes1(uint8(1)), metadataAppFid, metadataSig),
                units: 2
            });
        }
        return userData;
    }

    function toBytes(PackedUserData[] memory packedUserData) internal pure returns (bytes memory) {
        bytes memory encoded;
        for (uint256 i = 0; i < packedUserData.length; i++) {
            encoded = bytes.concat(
                encoded,
                abi.encodePacked(
                    packedUserData[i].to,
                    packedUserData[i].recovery,
                    packedUserData[i].key,
                    packedUserData[i].metadataSig
                )
            );
        }
        return encoded;
    }
}
