// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

// Address of the last precompile contract
address constant MAX_PRECOMPILE = address(9);

address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);
address constant RECOVERY = address(0x456);

uint256 constant COMMIT_REVEAL_DELAY = 60 seconds;
uint256 constant COMMIT_REPLAY_DELAY = 10 minutes;
uint256 constant COMMIT_REGISTER_DELAY = 60;

uint256 constant ESCROW_PERIOD = 3 days;
uint256 constant REGISTRATION_PERIOD = 365 days;
uint256 constant RENEWAL_PERIOD = 30 days;

uint256 constant BID_START = 1_000 ether;
uint256 constant FEE = 0.01 ether;

// Max value to use when fuzzing msg.value amounts, to prevent impractical overflow failures
uint256 constant AMOUNT_FUZZ_MAX = 1_000_000_000_000 ether;

uint256 constant JAN1_2023_TS = 1672531200; // Jan 1, 2023 0:00:00 GMT
uint256 constant DEC1_2022_TS = 1669881600; // Dec 1, 2022 00:00:00 GMT

uint256 constant ALICE_TOKEN_ID = uint256(bytes32("alice"));
uint256 constant BOB_TOKEN_ID = uint256(bytes32("bob"));
uint256 constant CAROL_TOKEN_ID = uint256(bytes32("carol"));
uint256 constant DAN_TOKEN_ID = uint256(bytes32("dan"));

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
bytes32 constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
bytes32 constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
bytes32 constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
