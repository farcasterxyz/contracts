// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

library TransferHelper {
    /// @dev Revert when a native token transfer fails.
    error CallFailed();

    /**
     * @dev Native token transfer helper.
     */
    function sendNative(address to, uint256 amount) internal {
        bool success;

        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            // Transfer the native token and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (!success) revert CallFailed();
    }
}
