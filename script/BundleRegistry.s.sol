// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Script.sol";

import {BundleRegistry} from "../src/BundleRegistry.sol";
import {IdRegistry} from "../src/IdRegistry.sol";
import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility*/

contract BundleRegistryScript is Script {
    address constant GOERLI_FORWARDER = address(0x7A95fA73250dc53556d264522150A940d4C50238);
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // TODO: Always update this to the address of the private key used to deploy the contracts on the network
    address constant DEPLOYER = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266); // anvil deployer

    // TODO: Update the vault and pool addresses every time
    address constant VAULT = DEPLOYER;
    address constant POOL = DEPLOYER;

    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistry;
    ERC1967Proxy proxy;
    IdRegistry idRegistry;
    BundleRegistry bundleRegistry;

    /**
     * @dev Deploys IdRegistry, NameRegistry and BundleRegistry contracts with the following config:
     *
     * IdRegistry
     *  - trusted_caller: DEPLOYER
     *  - owner         : DEPLOYER
     *
     * NameRegistry
     *  - trusted_caller: BundleRegistry
     *  - default_admin : DEPLOYER
     *  - admin         : none
     *
     * BundleRegistry
     *  - trusted_caller: DEPLOYER
     *  - owner         : DEPLOYER
     */
    function run() public {
        vm.broadcast();
        idRegistry = new IdRegistry(GOERLI_FORWARDER);

        vm.broadcast();
        nameRegistryImpl = new NameRegistry(GOERLI_FORWARDER);

        vm.broadcast();
        proxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(proxy));

        vm.broadcast();
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);

        vm.broadcast();
        bundleRegistry = new BundleRegistry(address(idRegistry), address(nameRegistry), DEPLOYER);

        // Set the BundleRegistry as the trusted caller for IdRegistry and NameRegistry
        vm.broadcast();
        idRegistry.changeTrustedCaller(address(bundleRegistry));

        vm.broadcast();
        nameRegistry.grantRole(ADMIN_ROLE, DEPLOYER);

        vm.broadcast();
        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        vm.broadcast();
        nameRegistry.renounceRole(ADMIN_ROLE, DEPLOYER);
    }
}
