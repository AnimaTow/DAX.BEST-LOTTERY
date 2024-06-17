// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Context} from "../utils/Context.sol";

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address and provides basic authorization control
 * functions, simplifying the implementation of "user permissions".
 */
abstract contract Ownable is Context {
    address private _owner;

    error OwnableUnauthorizedAccount(address account); // Error for unauthorized access
    error OwnableInvalidOwner(address owner); // Error for invalid owner address

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner); // Event emitted when ownership is transferred

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     * @param initialOwner The address of the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0)); // Reverts if the initial owner is the zero address
        }
        _transferOwnership(initialOwner); // Sets the initial owner
    }

    /**
     * @dev Modifier to make a function callable only by the owner.
     * Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner(); // Checks if the caller is the owner
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     * @return The address of the owner.
     */
    function owner() public view virtual returns (address) {
        return _owner; // Returns the address of the current owner
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender()); // Reverts if the caller is not the owner
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0)); // Allows the owner to renounce ownership, setting owner to the zero address
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     * @param newOwner The address of the new owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0)); // Reverts if the new owner is the zero address
        }
        _transferOwnership(newOwner); // Transfers ownership to a new address
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     * @param newOwner The address of the new owner.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner; // Stores the current owner address
        _owner = newOwner; // Updates the owner address
        emit OwnershipTransferred(oldOwner, newOwner); // Emits an event indicating ownership transfer
    }
}
