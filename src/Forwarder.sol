// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC2771Forwarder} from "openzeppelin-latest/contracts/metatx/ERC2771Forwarder.sol";

contract Forwarder is ERC2771Forwarder {
    constructor(string memory name) ERC2771Forwarder(name) {}
}
