// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {SpendPermissionManager} from "../../src/SpendPermissionManager.sol";

/// @dev Test wallet with owner-registered, opaque signatures rather than ECDSA signatures.
contract MockERC1271Wallet is Ownable, IERC1271 {
    using SafeERC20 for IERC20;

    bytes32 private _authorizedHash;
    bytes32 private _signatureHash;

    constructor(address owner_) Ownable(owner_) {}

    function authorizeSignature(bytes32 hash, bytes calldata signature) external onlyOwner {
        _authorizedHash = hash;
        _signatureHash = keccak256(signature);
    }

    function approveToken(IERC20 token, address spender, uint256 amount) external onlyOwner {
        token.forceApprove(spender, amount);
    }

    function revokePermission(
        SpendPermissionManager manager,
        SpendPermissionManager.SpendPermission calldata permission
    ) external onlyOwner {
        manager.revoke(permission);
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        return hash == _authorizedHash && keccak256(signature) == _signatureHash
            ? IERC1271.isValidSignature.selector
            : bytes4(0xffffffff);
    }
}
