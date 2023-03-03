// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Script.sol";

import {BundleRegistry} from "../src/BundleRegistry.sol";
import {IdRegistry} from "../src/IdRegistry.sol";
import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility*/

contract BundleRegistryScript is Script {
    address constant GOERLI_FORWARDER = address(0x7A95fA73250dc53556d264522150A940d4C50238);
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address DEPLOYER = vm.addr(vm.envUint("PRIVATE_KEY"));

    // TODO: Update the vault and pool addresses every time
    address VAULT = DEPLOYER;
    address POOL = DEPLOYER;
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
        vm.startBroadcast(DEPLOYER);
        idRegistry = new IdRegistry(GOERLI_FORWARDER);

        nameRegistryImpl = new NameRegistry(GOERLI_FORWARDER);

        proxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(proxy));

        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);

        bundleRegistry = new BundleRegistry(address(idRegistry), address(nameRegistry), DEPLOYER);

        // Set the BundleRegistry as the trusted caller for IdRegistry and NameRegistry
        idRegistry.changeTrustedCaller(address(bundleRegistry));

        nameRegistry.grantRole(ADMIN_ROLE, DEPLOYER);

        nameRegistry.changeTrustedCaller(address(bundleRegistry));

        nameRegistry.renounceRole(ADMIN_ROLE, DEPLOYER);
        vm.stopBroadcast();
    }
}
