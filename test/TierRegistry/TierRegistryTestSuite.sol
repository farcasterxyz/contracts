// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {MockPriceFeed, MockUptimeFeed, MockChainlinkFeed, RevertOnReceive} from "../Utils.sol";
import {TierRegistryHarness} from "./TierRegistryHarness.sol";
import {TestSuiteSetup} from "../TestSuiteSetup.sol";
import "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("TestToken", "TTK") {
        _mint(msg.sender, 1_000_000);
    }
}

abstract contract TierRegistryTestSuite is TestSuiteSetup {
    TierRegistryHarness tierRegistry;
    RevertOnReceive internal revertOnReceive;
    TestToken internal token;

    address internal deployer = address(this);
    address internal mallory = makeAddr("mallory");
    address internal vault = makeAddr("vault");
    address internal roleAdmin = makeAddr("roleAdmin");
    address internal operator = makeAddr("operator");

    uint256 internal immutable DEPLOYED_AT = block.timestamp + 3600;

    function setUp() public virtual override {
        super.setUp();

        revertOnReceive = new RevertOnReceive();
        token = new TestToken();

        vm.warp(DEPLOYED_AT);

        tierRegistry = new TierRegistryHarness(address(token), vault, roleAdmin, owner, operator, 30, 100_000);

        addKnownContract(address(revertOnReceive));
        addKnownContract(address(tierRegistry));
        addKnownContract(address(token));
    }
}
