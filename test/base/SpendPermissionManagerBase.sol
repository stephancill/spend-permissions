// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solady/../test/utils/mocks/MockERC20.sol";

import {SpendPermissionManager} from "../../src/SpendPermissionManager.sol";
import {MockSpendPermissionManager} from "../mocks/MockSpendPermissionManager.sol";

abstract contract SpendPermissionManagerBase is Test {
    uint256 internal ownerPk = uint256(keccak256("owner"));
    address internal owner = vm.addr(ownerPk);
    address internal account = owner;
    uint256 internal spenderPk = uint256(keccak256("spender"));
    address internal spender = vm.addr(spenderPk);
    address internal TOKEN;
    MockERC20 internal erc20;
    MockSpendPermissionManager internal mockSpendPermissionManager;

    function _initializeSpendPermissionManager() internal {
        mockSpendPermissionManager = new MockSpendPermissionManager();
        erc20 = new MockERC20("Test Token", "TEST", 18);
        TOKEN = address(erc20);
        vm.prank(account);
        erc20.approve(address(mockSpendPermissionManager), type(uint256).max);
    }

    function _createSpendPermission() internal view returns (SpendPermissionManager.SpendPermission memory) {
        return SpendPermissionManager.SpendPermission({
            account: account,
            spender: spender,
            token: TOKEN,
            allowance: 1 ether,
            period: 7 days,
            start: uint48(block.timestamp),
            end: type(uint48).max,
            salt: 0,
            extraData: hex""
        });
    }

    function _signSpendPermission(SpendPermissionManager.SpendPermission memory spendPermission, uint256 signerPk)
        internal
        view
        returns (bytes memory)
    {
        return _sign({signerPk: signerPk, hash: mockSpendPermissionManager.getHash(spendPermission)});
    }

    function _signSpendPermissionBatch(
        SpendPermissionManager.SpendPermissionBatch memory spendPermissionBatch,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        return _sign({signerPk: signerPk, hash: mockSpendPermissionManager.getBatchHash(spendPermissionBatch)});
    }

    function _sign(uint256 signerPk, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, hash);
        return abi.encodePacked(r, s, v);
    }

    function _safeAddUint48(uint48 a, uint48 b, uint48 end) internal pure returns (uint48) {
        return uint256(a) + b > end ? end : a + b;
    }

    function _assumeERC20Address(address token) internal pure {
        assumeNotPrecompile(token);
        vm.assume(token != address(0));
        vm.assume(token != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }

    function _safeAddUint160(uint160 a, uint160 b) internal pure returns (uint160) {
        return uint256(a) + b > type(uint160).max ? type(uint160).max : a + b;
    }
}
