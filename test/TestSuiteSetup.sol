// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {ERC1271WalletMock, ERC1271MaliciousMockForceRevert} from "./Utils.sol";

abstract contract TestSuiteSetup is Test {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 constant SECP_256K1_ORDER = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;

    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);

    // Known contracts that must not be made to call other contracts in tests
    address[] internal knownContracts = [
        address(0xCe71065D4017F316EC606Fe4422e11eB2c47c246), // FuzzerDict
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C), // CREATE2 Factory
        address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D), // Vm cheatcode address
        address(0x000000000000000000636F6e736F6c652e6c6f67), // console.sol
        address(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f), // Default test contract
        address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496), // address(this)
        address(0x185a4dc360CE69bDCceE33b3784B0282f7961aea), // ???
        address(0x2e234DAe75C793f67A35089C9d99245E1C58470b), // ???
        address(0xEFc56627233b02eA95bAE7e19F648d7DcD5Bb132), // ???
        address(0xf5a2fE45F4f1308502b1C136b9EF8af136141382) // ???
    ];

    address owner = makeAddr("owner");
    address trustedCaller = makeAddr("trustedCaller");
    address migrator = makeAddr("migrator");

    // Address of known contracts, in a mapping for faster lookup when fuzzing
    mapping(address => bool) isKnownContract;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Set up the known contracts map
        for (uint256 i = 0; i < knownContracts.length; i++) {
            isKnownContract[knownContracts[i]] = true;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function addKnownContract(
        address contractAddress
    ) public {
        isKnownContract[contractAddress] = true;
    }

    // Ensures that a fuzzed address input does not match a known contract address
    function _assumeClean(
        address a
    ) internal {
        assumeNotPrecompile(a);
        vm.assume(!isKnownContract[a]);
        vm.assume(a != ADMIN);
        vm.assume(a != address(0));
    }

    function _boundPk(
        uint256 pk
    ) internal view returns (uint256) {
        return bound(pk, 1, SECP_256K1_ORDER - 1);
    }

    function _boundDeadline(
        uint40 deadline
    ) internal view returns (uint256) {
        return block.timestamp + uint256(bound(deadline, 0, type(uint40).max));
    }

    function _createMockERC1271(
        address ownerAddress
    ) internal returns (ERC1271WalletMock mockWallet, address mockWalletAddress) {
        mockWallet = new ERC1271WalletMock(ownerAddress);
        mockWalletAddress = address(mockWallet);
    }

    function _createMaliciousMockERC1271(
        address ownerAddress
    ) internal returns (ERC1271MaliciousMockForceRevert mockWallet, address mockWalletAddress) {
        mockWallet = new ERC1271MaliciousMockForceRevert(ownerAddress);
        mockWalletAddress = address(mockWallet);
    }
}
