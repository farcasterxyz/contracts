// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

library TransferHelper {
    /// @dev Revert when a native token transfer fails.
    error CallFailed();

    /// @dev Revert when there are not enough funds for a native token transfer.
    error InsufficientFunds();

    /**
     * @dev Native token transfer helper.
     */
    function sendNative(address to, uint256 amount) internal {
        if (address(this).balance < amount) revert InsufficientFunds();

        /**
         *  This Slither detector requires all return values to be
         *  used, but we are intentionally ignoring returndata here.
         *  This is safe since we still check success and revert if
         *  the call failed. We're not using the returndata.
         */

        // slither-disable-next-line unchecked-lowlevel, unused-return
        (bool success,) = payable(to).call{value: amount}("");
        if (!success) revert CallFailed();
    }
}
