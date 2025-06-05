// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/console.sol";
import "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TierRegistry, DeployTierRegistry} from "../../script/DeployTierRegistry.s.sol";

/* solhint-disable state-visibility */

contract DeployTierRegistryTest is DeployTierRegistry {
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public vault = makeAddr("vault");
    address public owner = makeAddr("owner");
    address public migrator = makeAddr("migrator");
    address public deployer = makeAddr("deployer");

    TierRegistry public tierRegistry;

    event PurchasedTier(uint256 indexed fid, uint256 indexed tier, uint256 forDays, address indexed payer);

    function setUp() public {
        vm.createSelectFork("base_mainnet", 31172413);

        DeployTierRegistry.DeploymentParams memory params = DeployTierRegistry.DeploymentParams({
            deployer: deployer,
            vault: vault,
            owner: owner,
            migrator: migrator,
            salts: DeployTierRegistry.Salts({tierRegistry: 0})
        });

        vm.startPrank(deployer);
        DeployTierRegistry.Contracts memory contracts = runDeploy(params, false);
        runSetup(contracts, params, false);
        vm.stopPrank();

        tierRegistry = contracts.tierRegistry;
    }

    function test_deploymentParams() public {
        // Ownership parameters
        assertEq(tierRegistry.owner(), deployer);
        assertEq(tierRegistry.pendingOwner(), owner);
        assertEq(tierRegistry.migrator(), migrator);
        assertEq(tierRegistry.isMigrated(), false);
        assertEq(tierRegistry.paused(), true);

        // Initial tier
        TierRegistry.TierInfo memory tier = tierRegistry.tierInfo(1);
        assertEq(tier.minDays, 30);
        assertEq(tier.maxDays, 365);
        assertEq(tier.vault, vault);
        assertEq(address(tier.paymentToken), BASE_USDC);
        assertEq(tier.tokenPricePerDay, PRICE_PER_DAY);
    }

    function test_e2e() public {
        // Owner accepts ownership
        vm.prank(owner);
        tierRegistry.acceptOwnership();
        assertEq(tierRegistry.owner(), owner);

        // Migrator backfills and migrates
        vm.startPrank(migrator);
        uint256[] memory fids = new uint256[](2);
        fids[0] = 1;
        fids[1] = 2;

        vm.expectEmit();
        emit PurchasedTier(1, 1, 365, migrator);
        emit PurchasedTier(2, 1, 365, migrator);
        tierRegistry.batchCreditTier(1, fids, 365);
        tierRegistry.migrate();
        vm.stopPrank();

        // Cannot purchase
        vm.expectRevert("Pausable: paused");
        vm.prank(alice);
        tierRegistry.purchaseTier(3, 1, 30);

        // Owner unpauses
        vm.prank(owner);
        tierRegistry.unpause();

        // Public purchase
        deal(BASE_USDC, alice, 100 * 1e6);
        vm.startPrank(alice);
        uint256 price = tierRegistry.price(1, 30);
        IERC20(BASE_USDC).approve(address(tierRegistry), price);
        tierRegistry.purchaseTier(3, 1, 30);
        vm.stopPrank();
    }
}
