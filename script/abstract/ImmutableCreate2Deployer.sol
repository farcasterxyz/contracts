// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

interface ImmutableCreate2Factory {
    function hasBeenDeployed(
        address deploymentAddress
    ) external view returns (bool);

    function findCreate2Address(
        bytes32 salt,
        bytes calldata initializationCode
    ) external view returns (address deploymentAddress);

    function safeCreate2(
        bytes32 salt,
        bytes calldata initializationCode
    ) external payable returns (address deploymentAddress);
}

abstract contract ImmutableCreate2Deployer is Script {
    enum Status {
        UNKNOWN,
        FOUND,
        DEPLOYED
    }

    /**
     * @dev Deployment information for a contract.
     *
     * @param name               Contract name
     * @param salt               CREATE2 salt
     * @param creationCode       Contract creationCode bytes
     * @param constructorArgs    ABI-encoded constructor argument bytes
     * @param initCodeHash       Contract initCode (creationCode + constructorArgs) hash
     * @param deploymentAddress  Deterministic deployment address
     */
    struct Deployment {
        string name;
        bytes32 salt;
        bytes creationCode;
        bytes constructorArgs;
        bytes32 initCodeHash;
        address deploymentAddress;
        Status status;
    }

    /// @dev Deterministic address of the cross-chain ImmutableCreate2Factory
    ImmutableCreate2Factory private constant IMMUTABLE_CREATE2_FACTORY =
        ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

    /// @dev Default CREATE2 salt
    bytes32 private constant DEFAULT_SALT = bytes32(0);

    /// @dev Array of contract names, used to track contracts "registered" for later deployment.
    string[] internal names;

    /// @dev Mapping of contract name to deployment details.
    mapping(string name => Deployment deployment) internal contracts;

    /**
     * @dev "Register" a contract to be deployed by deploy().
     *
     * @param name         Contract name
     * @param creationCode Contract creationCode bytes
     */
    function register(string memory name, bytes memory creationCode) internal returns (address) {
        return register(name, DEFAULT_SALT, creationCode, "");
    }

    /**
     * @dev "Register" a contract to be deployed by deploy().
     *
     * @param name         Contract name
     * @param salt         CREATE2 salt
     * @param creationCode Contract creationCode bytes
     */
    function register(string memory name, bytes32 salt, bytes memory creationCode) internal returns (address) {
        return register(name, salt, creationCode, "");
    }

    /**
     * @dev "Register" a contract to be deployed by deploy().
     *
     * @param name            Contract name
     * @param creationCode    Contract creationCode bytes
     * @param constructorArgs ABI-encoded constructor argument bytes
     */
    function register(
        string memory name,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal returns (address) {
        return register(name, DEFAULT_SALT, creationCode, constructorArgs);
    }

    /**
     * @dev "Register" a contract to be deployed by deploy().
     *
     * @param name            Contract name
     * @param salt            CREATE2 salt
     * @param creationCode    Contract creationCode bytes
     * @param constructorArgs ABI-encoded constructor argument bytes
     */
    function register(
        string memory name,
        bytes32 salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal returns (address) {
        bytes memory initCode = bytes.concat(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(initCode);
        address deploymentAddress = address(
            uint160(
                uint256(keccak256(abi.encodePacked(hex"ff", address(IMMUTABLE_CREATE2_FACTORY), salt, initCodeHash)))
            )
        );
        names.push(name);
        contracts[name] = Deployment({
            name: name,
            salt: salt,
            creationCode: creationCode,
            constructorArgs: constructorArgs,
            initCodeHash: initCodeHash,
            deploymentAddress: deploymentAddress,
            status: Status.UNKNOWN
        });
        return deploymentAddress;
    }

    /**
     * @dev Deploy all registered contracts.
     */
    function deploy(
        bool broadcast
    ) internal {
        console.log(pad("State", 10), pad("Name", 27), pad("Address", 43), "Initcode hash");
        for (uint256 i; i < names.length; i++) {
            _deploy(names[i], broadcast);
        }
    }

    function deploy() internal {
        deploy(true);
    }

    /**
     * @dev Deploy a registered contract by name.
     *
     * @param name Contract name
     */
    function deploy(string memory name, bool broadcast) public {
        console.log(pad("State", 10), pad("Name", 17), pad("Address", 43), "Initcode hash");
        _deploy(name, broadcast);
    }

    function deploy(
        string memory name
    ) internal {
        deploy(name, true);
    }

    function _deploy(string memory name, bool broadcast) internal {
        Deployment storage deployment = contracts[name];
        if (!IMMUTABLE_CREATE2_FACTORY.hasBeenDeployed(deployment.deploymentAddress)) {
            if (broadcast) vm.broadcast();
            deployment.deploymentAddress = IMMUTABLE_CREATE2_FACTORY.safeCreate2(
                deployment.salt, bytes.concat(deployment.creationCode, deployment.constructorArgs)
            );
            deployment.status = Status.DEPLOYED;
        } else {
            deployment.status = Status.FOUND;
        }
        console.log(
            pad((deployment.status == Status.DEPLOYED) ? "Deploying" : "Found", 10),
            pad(deployment.name, 27),
            pad(Strings.toHexString(deployment.deploymentAddress), 43),
            Strings.toHexString(uint256(deployment.initCodeHash))
        );
    }

    function deploymentChanged() public view returns (bool) {
        for (uint256 i; i < names.length; i++) {
            Deployment storage deployment = contracts[names[i]];
            if (deployment.status == Status.DEPLOYED) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Pad string to given length.
     *
     * @param str string to pad
     * @param n   length to pad to
     */
    function pad(string memory str, uint256 n) internal pure returns (string memory) {
        string memory padded = str;
        while (bytes(padded).length < n) {
            padded = string.concat(padded, " ");
        }
        return padded;
    }
}
