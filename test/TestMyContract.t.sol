// test/TestMyContract.t.sol
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MyContract.sol";

contract TestMyContract is Test {
    MyContract myContract;

    function setUp() public {
        myContract = new MyContract();
    }

    function testNewFunction() public {
        string memory result = myContract.newFunction();
        assertEq(result, "Hello, Farcaster!");
    }
}
