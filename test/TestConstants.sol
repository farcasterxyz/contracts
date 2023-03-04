// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

// When fuzzing, concern ourselves with functionality for the next 100 years
uint256 constant FUZZ_TIME_PERIOD = 100 * 365.25 days;

address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
