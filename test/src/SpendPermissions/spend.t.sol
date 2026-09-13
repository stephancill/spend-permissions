// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20LikeUSDT} from "solady/../test/utils/mocks/MockERC20LikeUSDT.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

import {SpendPermissionManager} from "../../../src/SpendPermissionManager.sol";
import {SpendPermissionManagerBase} from "../../base/SpendPermissionManagerBase.sol";
import {MockERC20MissingReturn} from "../../mocks/MockERC20MissingReturn.sol";
import {MockFeeToken} from "../../mocks/MockFeeToken.sol";
import {MockReentrantToken} from "../../mocks/MockReentrantToken.sol";

contract SpendTest is SpendPermissionManagerBase {
    SpendPermissionManager.SpendPermission private _permission;

    function setUp() public {
        _initializeSpendPermissionManager();
        _permission = _createSpendPermission();
        erc20.mint(account, 10 ether);
        vm.prank(account);
        mockSpendPermissionManager.approve(_permission);
    }

    /// @notice A finite master allowance is consumed independently of the recurring budget.
    /// @param value Requested spend, bounded to the period's allowance.
    function test_spend_success_finiteAllowance(uint160 value) public {
        value = uint160(bound(value, 1, _permission.allowance));
        vm.prank(account);
        erc20.approve(address(mockSpendPermissionManager), 2 ether);
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, value);
        assertEq(erc20.balanceOf(account), 10 ether - value);
        assertEq(erc20.balanceOf(spender), value);
        assertEq(erc20.balanceOf(address(mockSpendPermissionManager)), 0);
        assertEq(erc20.allowance(account, address(mockSpendPermissionManager)), 2 ether - value);
        assertEq(mockSpendPermissionManager.getCurrentPeriod(_permission).spend, value);
    }

    /// @notice Only the spender named in the permission may initiate a transfer.
    function test_spend_revert_wrongCaller() public {
        vm.expectRevert(abi.encodeWithSelector(SpendPermissionManager.InvalidSender.selector, address(this), spender));
        mockSpendPermissionManager.spend(_permission, 1);
    }

    /// @notice Possession of the token allowance alone does not authorize a permission.
    function test_spend_revert_unapprovedPermission() public {
        _permission.salt = 1;
        vm.prank(spender);
        vm.expectRevert(SpendPermissionManager.UnauthorizedSpendPermission.selector);
        mockSpendPermissionManager.spend(_permission, 1);
    }

    /// @notice Zero spends cannot trigger a token interaction.
    function test_spend_revert_zeroValue() public {
        vm.prank(spender);
        vm.expectRevert(SpendPermissionManager.ZeroValue.selector);
        mockSpendPermissionManager.spend(_permission, 0);
    }

    /// @notice An approved permission cannot exceed the available ERC-20 allowance.
    function test_spend_revert_insufficientAllowanceRollsBack() public {
        vm.prank(account);
        erc20.approve(address(mockSpendPermissionManager), 1);
        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        mockSpendPermissionManager.spend(_permission, 2);
        assertEq(mockSpendPermissionManager.getLastUpdatedPeriod(_permission).spend, 0);
        assertEq(erc20.balanceOf(account), 10 ether);
        assertEq(erc20.allowance(account, address(mockSpendPermissionManager)), 1);
    }

    /// @notice Failed token transfers preserve prior period usage and balances.
    function test_spend_revert_insufficientBalanceRollsBack() public {
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 1);
        erc20.burn(account, erc20.balanceOf(account));
        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        mockSpendPermissionManager.spend(_permission, 2);
        assertEq(mockSpendPermissionManager.getLastUpdatedPeriod(_permission).spend, 1);
        assertEq(erc20.balanceOf(spender), 1);
    }

    /// @notice Restoring token approval resumes a permission without resetting its period usage.
    function test_spend_success_allowanceRemovalAndRestoration() public {
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 0.4 ether);
        vm.prank(account);
        erc20.approve(address(mockSpendPermissionManager), 0);
        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        mockSpendPermissionManager.spend(_permission, 1);
        assertTrue(mockSpendPermissionManager.isValid(_permission));
        vm.prank(account);
        erc20.approve(address(mockSpendPermissionManager), 1 ether);
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 0.6 ether);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(SpendPermissionManager.ExceededSpendPermission.selector, 1 ether + 1, 1 ether)
        );
        mockSpendPermissionManager.spend(_permission, 1);
    }

    /// @notice Period resets do not replenish the token's finite master allowance.
    function test_spend_success_newPeriodSameTokenAllowance() public {
        vm.prank(account);
        erc20.approve(address(mockSpendPermissionManager), 1.5 ether);
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 1 ether);
        vm.warp(uint256(_permission.start) + _permission.period);
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 0.5 ether);
        assertEq(mockSpendPermissionManager.getCurrentPeriod(_permission).spend, 0.5 ether);
        assertEq(erc20.allowance(account, address(mockSpendPermissionManager)), 0);
        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        mockSpendPermissionManager.spend(_permission, 1);
    }

    /// @notice Distinct permissions share token approval but have independent period budgets.
    function test_spend_success_independentPermissions() public {
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 1 ether);
        SpendPermissionManager.SpendPermission memory second = _permission;
        second.salt = 1;
        vm.prank(account);
        mockSpendPermissionManager.approve(second);
        vm.prank(spender);
        mockSpendPermissionManager.spend(second, 1 ether);
        assertEq(mockSpendPermissionManager.getCurrentPeriod(_permission).spend, 1 ether);
        assertEq(mockSpendPermissionManager.getCurrentPeriod(second).spend, 1 ether);
        assertEq(erc20.balanceOf(spender), 2 ether);
    }

    /// @notice USDT-style tokens work with residual allowances across multiple spends.
    function test_spend_success_usdtResidualAllowance() public {
        MockERC20LikeUSDT token = new MockERC20LikeUSDT();
        token.mint(account, 100);
        _permission.token = address(token);
        vm.startPrank(account);
        token.approve(address(mockSpendPermissionManager), 100);
        mockSpendPermissionManager.approve(_permission);
        vm.stopPrank();
        vm.startPrank(spender);
        mockSpendPermissionManager.spend(_permission, 30);
        mockSpendPermissionManager.spend(_permission, 20);
        vm.stopPrank();
        assertEq(token.balanceOf(spender), 50);
        assertEq(token.allowance(account, address(mockSpendPermissionManager)), 50);
    }

    /// @notice SafeERC20 handles ERC-20s whose transfers return no data.
    function test_spend_success_noReturnValue() public {
        MockERC20MissingReturn token = new MockERC20MissingReturn("No Return", "NONE", 18);
        token.mint(account, 100);
        _permission.token = address(token);
        vm.startPrank(account);
        token.approve(address(mockSpendPermissionManager), 100);
        mockSpendPermissionManager.approve(_permission);
        vm.stopPrank();
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 60);
        assertEq(token.balanceOf(spender), 60);
        assertEq(token.allowance(account, address(mockSpendPermissionManager)), 40);
    }

    /// @notice A false token return is a failed transfer, with usage rolled back.
    function test_spend_revert_falseReturnValue() public {
        vm.mockCall(TOKEN, abi.encodeCall(IERC20.transferFrom, (account, spender, 1)), abi.encode(false));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, TOKEN));
        mockSpendPermissionManager.spend(_permission, 1);
        assertEq(mockSpendPermissionManager.getLastUpdatedPeriod(_permission).spend, 0);
    }

    /// @notice An address without token code cannot falsely report a successful transfer.
    function test_spend_revert_undeployedToken() public {
        _permission.token = makeAddr("undeployed token");
        vm.prank(account);
        mockSpendPermissionManager.approve(_permission);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, _permission.token));
        mockSpendPermissionManager.spend(_permission, 1);
        assertEq(mockSpendPermissionManager.getLastUpdatedPeriod(_permission).spend, 0);
    }

    /// @notice Fee-on-transfer tokens are metered by the requested amount and transferred in one hop.
    function test_spend_success_feeOnTransfer() public {
        MockFeeToken token = new MockFeeToken();
        token.mint(account, 100);
        _permission.token = address(token);
        vm.startPrank(account);
        token.approve(address(mockSpendPermissionManager), 100);
        mockSpendPermissionManager.approve(_permission);
        vm.stopPrank();
        vm.prank(spender);
        mockSpendPermissionManager.spend(_permission, 100);
        assertEq(token.balanceOf(account), 0);
        assertEq(token.balanceOf(spender), 99);
        assertEq(token.balanceOf(address(mockSpendPermissionManager)), 0);
        assertEq(mockSpendPermissionManager.getCurrentPeriod(_permission).spend, 100);
    }

    /// @notice A token callback sees the outer spend recorded and cannot exceed the budget by reentering.
    function test_spend_revert_reentrantOverspend() public {
        MockReentrantToken token = new MockReentrantToken(mockSpendPermissionManager);
        token.mint(account, 100);
        _permission.token = address(token);
        _permission.spender = address(token);
        _permission.allowance = 100;
        vm.startPrank(account);
        token.approve(address(mockSpendPermissionManager), 100);
        mockSpendPermissionManager.approve(_permission);
        vm.stopPrank();
        token.spend({permission: _permission, value: 60, reentrantValue: 41});
        assertFalse(token.reentrySucceeded());
        assertEq(
            token.reentryError(),
            abi.encodeWithSelector(SpendPermissionManager.ExceededSpendPermission.selector, 101, 100)
        );
        assertEq(token.balanceOf(account), 40);
        assertEq(token.balanceOf(address(token)), 60);
        assertEq(mockSpendPermissionManager.getCurrentPeriod(_permission).spend, 60);
    }

    /// @notice Native token sentinels are rejected at approval.
    function test_approve_revert_nativeToken() public {
        _permission.token = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        vm.prank(account);
        vm.expectRevert(SpendPermissionManager.NativeTokenNotSupported.selector);
        mockSpendPermissionManager.approve(_permission);
    }

    /// @notice Native ETH cannot be sent to the manager through a payable entry point.
    function test_receive_revert_nativeETH() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(mockSpendPermissionManager).call{value: 1}("");
        assertFalse(success);
    }
}
