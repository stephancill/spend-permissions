// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

import {SpendPermissionManager} from "../../src/SpendPermissionManager.sol";

/// @dev An ERC-20 which is also an authorized spender and attempts reentry before its transfer.
contract MockReentrantToken is MockERC20 {
    SpendPermissionManager private immutable _manager;
    SpendPermissionManager.SpendPermission private _permission;
    uint160 private _reentrantValue;
    bool private _entered;
    bool public reentrySucceeded;
    bytes public reentryError;

    constructor(SpendPermissionManager manager) MockERC20("Reentrant Token", "REENTER", 18) {
        _manager = manager;
    }

    function spend(SpendPermissionManager.SpendPermission calldata permission, uint160 value, uint160 reentrantValue)
        external
    {
        _permission = permission;
        _reentrantValue = reentrantValue;
        _manager.spend(permission, value);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (!_entered) {
            _entered = true;
            try _manager.spend(_permission, _reentrantValue) {
                reentrySucceeded = true;
            } catch (bytes memory reason) {
                reentryError = reason;
            }
        }
        return super.transferFrom(from, to, amount);
    }
}
