// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./ImmutableCreate2Deployer.sol";

/**
 * @title CanonicalCreate2Deployer
 *
 * @notice Routes registered deployments through the canonical deterministic-deployment proxy at
 *         0x4e59b44847b379578588920cA78FbF26c0B4956C instead of the ImmutableCreate2Factory.
 *
 * @dev The proxy is the one Foundry deploys and `cast create2` assumes by default, and it is present
 *      with identical code on every chain this repo targets. Its runtime is nine instructions: copy
 *      calldata past the first word into memory, CREATE2 with that word as the salt, revert if the
 *      address comes back zero, return the 20-byte address. There is no ABI -- the calldata is
 *      `salt ++ initCode` -- and, unlike `safeCreate2`, no check on who is calling.
 *
 *      That last difference is the reason to choose between them rather than treat them as
 *      interchangeable:
 *
 *      - **The whole salt is free.** `safeCreate2` requires the salt's first 20 bytes to be the
 *        caller, which is why every salt in .env.example carries a deployer prefix and only the
 *        trailing 12 bytes are mined. Here all 32 bytes are searchable, and the salt is not bound to
 *        the address that broadcasts.
 *      - **Anyone can deploy the registered init code at the mined address.** Harmless for a
 *        contract whose constructor takes its owner as an argument -- a stranger's deployment
 *        produces the same contract, at the same address, owned by the same address, at their
 *        expense -- but it does mean a script must not assume that finding a contract already
 *        deployed implies its own earlier run put it there. See the setup gate in
 *        DeploySnapchainConfigRegistry.
 */
abstract contract CanonicalCreate2Deployer is ImmutableCreate2Deployer {
    /// @dev The proxy call reverted, or returned something other than a 20-byte address.
    error Create2ProxyFailed(bytes returnData);

    /// @dev Deterministic address of the canonical deterministic-deployment proxy.
    address internal constant CANONICAL_CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function create2Factory() public pure override returns (address) {
        return CANONICAL_CREATE2_PROXY;
    }

    /**
     * @dev The proxy keeps no record of what it has deployed, so presence of code is the only signal
     *      available. Equivalent to `hasBeenDeployed` for this purpose: CREATE2 to an address that
     *      already holds code fails, whoever put the code there.
     */
    function _hasBeenDeployed(
        address deploymentAddress
    ) internal view override returns (bool) {
        return deploymentAddress.code.length != 0;
    }

    /**
     * @dev Called rather than expressed as `new Contract{salt: ...}` on purpose. Solidity compiles a
     *      salted `new` to a CREATE2 executed by whoever runs the code; `forge script` rewrites that
     *      into a proxy transaction under --broadcast, but `forge test` does not, so the same
     *      expression would produce one address in tests and another in production. An explicit call
     *      is the same call in both.
     */
    function _create2(bytes32 salt, bytes memory initCode) internal override returns (address) {
        (bool success, bytes memory returnData) = CANONICAL_CREATE2_PROXY.call(abi.encodePacked(salt, initCode));
        if (!success || returnData.length != 20) revert Create2ProxyFailed(returnData);
        return address(bytes20(returnData));
    }
}
