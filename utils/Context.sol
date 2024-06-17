// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    /**
     * @dev Returns the address of the current message sender.
     */
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    /**
     * @dev Returns the calldata of the current message.
     */
    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev Returns the length of the context suffix, which is zero by default.
     */
    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}
