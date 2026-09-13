// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC1271} from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";
import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";
import {MockERC1271Wallet} from "../../mocks/MockERC1271Wallet.sol";

contract SpendWithSignatureTest is SpendPermissionManagerBase {
    SpendPermissionManager.SpendPermission private _permission;
    bytes private _signature;
    MockERC1271Wallet private _wallet;

    function setUp() public {
        _initializeSpendPermissionManager();
        erc20.mint(account, 10 ether);
        _permission = _createSpendPermission();
        _signature = _signSpendPermission({spendPermission: _permission, signerPk: ownerPk});
        _wallet = new MockERC1271Wallet(owner);
    }

    /// @notice First spending registers the signature and transfers directly from an EOA.
    function test_spendWithSignature_success_eoa() public {
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionApproved(
            mockSpendPermissionManager.getHash(_permission), _permission
        );
        vm.expectEmit(address(mockSpendPermissionManager));
        emit SpendPermissionManager.SpendPermissionUsed(
            mockSpendPermissionManager.getHash(_permission),
            account,
            spender,
            TOKEN,
            SpendPermissionManager.PeriodSpend(_permission.start, _permission.start + _permission.period, 0.4 ether)
        );
        vm.prank(spender);
        mockSpendPermissionManager.spendWithSignature(_permission, 0.4 ether, _signature);
        assertTrue(mockSpendPermissionManager.isValid(_permission));
        assertEq(mockSpendPermissionManager.getCurrentPeriod(_permission).spend, 0.4 ether);
        assertEq(erc20.balanceOf(account), 9.6 ether);
        assertEq(erc20.balanceOf(spender), 0.4 ether);
    }

    /// @notice Repeated signatures and approval calls cannot reset spent allowance.
    function test_spendWithSignature_revert_replayCannotResetBudget() public {
        vm.prank(spender);
        mockSpendPermissionManager.spendWithSignature(_permission, 0.4 ether, _signature);
        assertTrue(mockSpendPermissionManager.approveWithSignature(_permission, _signature));
        vm.prank(spender);
        mockSpendPermissionManager.spendWithSignature(_permission, 0.6 ether, _signature);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(SpendPermissionManager.ExceededSpendPermission.selector, 1 ether + 1, 1 ether)
        );
        mockSpendPermissionManager.spendWithSignature(_permission, 1, _signature);
        assertEq(erc20.balanceOf(spender), 1 ether);
    }

    /// @notice Revoking a signed but unsubmitted permission makes the signature permanently unusable.
    function test_spendWithSignature_revert_preemptiveRevocation() public {
        vm.prank(account);
        mockSpendPermissionManager.revoke(_permission);
        assertFalse(mockSpendPermissionManager.approveWithSignature(_permission, _signature));
        vm.prank(spender);
        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        mockSpendPermissionManager.spendWithSignature(_permission, 1, _signature);
        assertFalse(mockSpendPermissionManager.isApproved(_permission));
        assertTrue(mockSpendPermissionManager.isRevoked(_permission));
    }

    /// @notice A failed first transfer rolls back the permission approval as well as its usage.
    function test_spendWithSignature_revert_atomicRollback() public {
        vm.prank(account);
        erc20.approve(address(mockSpendPermissionManager), 0);
        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        mockSpendPermissionManager.spendWithSignature(_permission, 1, _signature);
        assertFalse(mockSpendPermissionManager.isApproved(_permission));
        assertEq(mockSpendPermissionManager.getLastUpdatedPeriod(_permission).spend, 0);
        assertEq(erc20.balanceOf(spender), 0);
        vm.prank(account);
        erc20.approve(address(mockSpendPermissionManager), 1);
        vm.prank(spender);
        mockSpendPermissionManager.spendWithSignature(_permission, 1, _signature);
        assertEq(erc20.balanceOf(spender), 1);
    }

    /// @notice An observed signature cannot be used by a different spender.
    function test_spendWithSignature_revert_wrongCaller() public {
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, address(this), spender));
        mockSpendPermissionManager.spendWithSignature(_permission, 1, _signature);
    }

    /// @notice Every permission field is covered by the signature.
    /// @param field Index of the field to tamper with.
    function test_approveWithSignature_revert_tamperedField(uint8 field) public {
        field = uint8(bound(field, 0, 8));
        if (field == 0) _permission.account = spender;
        if (field == 1) _permission.spender = owner;
        if (field == 2) _permission.token = owner;
        if (field == 3) _permission.allowance += 1;
        if (field == 4) _permission.period += 1;
        if (field == 5) _permission.start += 1;
        if (field == 6) _permission.end -= 1;
        if (field == 7) _permission.salt += 1;
        if (field == 8) _permission.extraData = hex"01";
        vm.expectRevert(SpendPermissionManager.InvalidSignature.selector);
        mockSpendPermissionManager.approveWithSignature(_permission, _signature);
    }

    /// @notice Chain ID is part of the EIP-712 signature domain.
    function test_approveWithSignature_revert_crossChainReplay() public {
        vm.chainId(block.chainid + 1);
        vm.expectRevert(SpendPermissionManager.InvalidSignature.selector);
        mockSpendPermissionManager.approveWithSignature(_permission, _signature);
    }

    /// @notice A signature for one manager cannot authorize another deployment.
    function test_approveWithSignature_revert_crossContractReplay() public {
        SpendPermissionManager other = new SpendPermissionManager();
        vm.expectRevert(SpendPermissionManager.InvalidSignature.selector);
        other.approveWithSignature(_permission, _signature);
    }

    /// @notice Malformed EOA signatures cannot accidentally validate for address zero.
    function test_approveWithSignature_revert_zeroAccount() public {
        _permission.account = address(0);
        vm.expectRevert(SpendPermissionManager.InvalidSignature.selector);
        mockSpendPermissionManager.approveWithSignature(_permission, hex"");
    }

    /// @notice Nonstandard contract-wallet signatures work for the atomic spend path.
    function test_spendWithSignature_success_erc1271() public {
        bytes memory signature = _prepareWallet();
        vm.prank(spender);
        mockSpendPermissionManager.spendWithSignature(_permission, 0.5 ether, signature);
        assertEq(erc20.balanceOf(address(_wallet)), 1.5 ether);
        assertEq(erc20.balanceOf(spender), 0.5 ether);
        assertEq(mockSpendPermissionManager.getCurrentPeriod(_permission).spend, 0.5 ether);
        assertEq(erc20.allowance(address(_wallet), address(mockSpendPermissionManager)), 1.5 ether);
    }

    /// @notice The separately callable approval path also validates ERC-1271 signatures.
    function test_approveWithSignature_success_erc1271() public {
        bytes memory signature = _prepareWallet();
        assertTrue(mockSpendPermissionManager.approveWithSignature(_permission, signature));
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 1);
        assertEq(erc20.balanceOf(spender), 1);
    }

    /// @notice A contract wallet can approve a batch with its own signature scheme.
    function test_approveBatchWithSignature_success_erc1271() public {
        bytes memory signature = _prepareWallet();
        SpendPermissionManager.PermissionDetails[] memory details = new SpendPermissionManager.PermissionDetails[](2);
        details[0] = SpendPermissionManager.PermissionDetails(spender, TOKEN, 1 ether, 0, hex"");
        details[1] = SpendPermissionManager.PermissionDetails(spender, TOKEN, 1 ether, 1, hex"");
        SpendPermissionManager.SpendPermissionBatch memory batch = SpendPermissionManager.SpendPermissionBatch({
            account: address(_wallet),
            period: _permission.period,
            start: _permission.start,
            end: _permission.end,
            permissions: details
        });
        bytes32 batchHash = mockSpendPermissionManager.getBatchHash(batch);
        vm.prank(owner);
        _wallet.authorizeSignature({hash: batchHash, signature: signature});
        assertTrue(mockSpendPermissionManager.approveBatchWithSignature(batch, signature));
        assertTrue(mockSpendPermissionManager.isApproved(_permission));
        _permission.salt = 1;
        assertTrue(mockSpendPermissionManager.isApproved(_permission));
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 1);
        assertEq(erc20.balanceOf(spender), 1);
    }

    /// @notice Invalid ERC-1271 signatures are rejected even when the token allowance is present.
    function test_spendWithSignature_revert_invalidERC1271() public {
        _prepareWallet();
        vm.prank(spender);
        vm.expectRevert(SpendPermissionManager.InvalidSignature.selector);
        mockSpendPermissionManager.spendWithSignature(_permission, 1, hex"deadbeef");
        assertFalse(mockSpendPermissionManager.isApproved(_permission));
    }

    /// @notice A reverting validator or malformed return data cannot approve a permission.
    /// @param reverts Whether to mock a revert instead of a short return value.
    function test_approveWithSignature_revert_brokenERC1271(bool reverts) public {
        bytes memory signature = _prepareWallet();
        bytes memory callData =
            abi.encodeCall(IERC1271.isValidSignature, (mockSpendPermissionManager.getHash(_permission), signature));
        if (reverts) vm.mockCallRevert(address(_wallet), callData, hex"deadbeef");
        else vm.mockCall(address(_wallet), callData, hex"1626ba7e");
        vm.expectRevert(SpendPermissionManager.InvalidSignature.selector);
        mockSpendPermissionManager.approveWithSignature(_permission, signature);
    }

    /// @notice Signature-policy changes do not implicitly revoke registered permissions.
    function test_spend_success_erc1271PolicyChangeAndExplicitRevocation() public {
        bytes memory signature = _prepareWallet();
        assertTrue(mockSpendPermissionManager.approveWithSignature(_permission, signature));
        vm.prank(owner);
        _wallet.authorizeSignature({hash: bytes32(0), signature: hex""});
        vm.prank(spender);
        vm.expectRevert(SpendPermissionManager.InvalidSignature.selector);
        mockSpendPermissionManager.spendWithSignature(_permission, 1, signature);
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 1);
        vm.prank(owner);
        _wallet.revokePermission({manager: mockSpendPermissionManager, permission: _permission});
        vm.prank(spender);
        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        mockSpendPermissionManager.spend(_permission, 1);
    }

    function _prepareWallet() private returns (bytes memory signature) {
        _permission.account = address(_wallet);
        signature = hex"1234567890abcdef";
        erc20.mint(address(_wallet), 2 ether);
        vm.startPrank(owner);
        _wallet.approveToken({token: IERC20(TOKEN), spender: address(mockSpendPermissionManager), amount: 2 ether});
        _wallet.authorizeSignature({hash: mockSpendPermissionManager.getHash(_permission), signature: signature});
        vm.stopPrank();
    }
}
