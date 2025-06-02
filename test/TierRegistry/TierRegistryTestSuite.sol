// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TierRegistry} from "../../src/TierRegistry.sol";

contract TestToken is ERC20 {
    constructor(
        address source
    ) ERC20("TestToken", "TTK") {
        _mint(source, 1_000_000_000_000);
    }
}

abstract contract TierRegistryTestSuite is TestSuiteSetup {
    TierRegistry tierRegistry;
    TestToken public token;

    address internal deployer = address(this);
    address internal tokenSource = makeAddr("tokenSource");

    uint256 internal immutable DEPLOYED_AT = block.timestamp + 3600;
    uint256 public immutable DEFAULT_MIN_DAYS = 1;
    uint256 public immutable DEFAULT_MAX_DAYS = type(uint64).max;

    function setUp() public virtual override {
        super.setUp();

        token = new TestToken(tokenSource);

        vm.warp(DEPLOYED_AT);

        tierRegistry = new TierRegistry(migrator, owner);

        vm.prank(owner);
        tierRegistry.unpause();

        addKnownContract(address(tierRegistry));
        addKnownContract(address(token));
    }
}
