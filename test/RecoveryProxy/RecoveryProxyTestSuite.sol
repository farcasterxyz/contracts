// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {RecoveryProxy} from "../../src/RecoveryProxy.sol";
import {IdRegistryTestSuite} from "../IdRegistry/IdRegistryTestSuite.sol";

/* solhint-disable state-visibility */

abstract contract RecoveryProxyTestSuite is IdRegistryTestSuite {
    RecoveryProxy recoveryProxy;

    function setUp() public virtual override {
        super.setUp();

        recoveryProxy = new RecoveryProxy(address(idRegistry), owner);
    }
}
