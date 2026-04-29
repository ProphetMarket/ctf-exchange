// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { BaseExchangeTest } from "exchange/test/BaseExchangeTest.sol";

/// @title AuthTest
/// @notice Tests for admin/operator role management, adminCount integrity,
///         and two-step admin transfer flow in Auth.sol
contract AuthTest is BaseExchangeTest {
    function test_adminCount_initializedToOne() public {
        assertEq(exchange.adminCount(), 1);
    }

    function test_addAdmin_incrementsCount() public {
        vm.prank(admin);
        exchange.addAdmin(henry);
        assertEq(exchange.adminCount(), 2);
    }

    function test_addAdmin_idempotent_doesNotDoubleCount() public {
        vm.startPrank(admin);
        exchange.addAdmin(henry);
        assertEq(exchange.adminCount(), 2);

        // Adding the same admin again should not increment
        exchange.addAdmin(henry);
        assertEq(exchange.adminCount(), 2);
        vm.stopPrank();
    }

    function test_removeAdmin_decrementsCount() public {
        vm.startPrank(admin);
        exchange.addAdmin(henry);
        assertEq(exchange.adminCount(), 2);

        exchange.removeAdmin(henry);
        assertEq(exchange.adminCount(), 1);
        assertFalse(exchange.isAdmin(henry));
        vm.stopPrank();
    }

    function test_removeAdmin_revertsOnLastAdmin() public {
        assertEq(exchange.adminCount(), 1);

        vm.prank(admin);
        vm.expectRevert(CannotRemoveLastAdmin.selector);
        exchange.removeAdmin(admin);

        // Admin is still active
        assertTrue(exchange.isAdmin(admin));
        assertEq(exchange.adminCount(), 1);
    }

    function test_removeAdmin_noopForNonAdmin() public {
        // Removing a non-admin address should not change the count
        vm.prank(admin);
        exchange.removeAdmin(henry);
        assertEq(exchange.adminCount(), 1);
    }

    function test_renounceAdminRole_revertsOnLastAdmin() public {
        assertEq(exchange.adminCount(), 1);

        vm.prank(admin);
        vm.expectRevert(CannotRemoveLastAdmin.selector);
        exchange.renounceAdminRole();

        assertTrue(exchange.isAdmin(admin));
        assertEq(exchange.adminCount(), 1);
    }

    function test_renounceAdminRole_succeedsWithMultipleAdmins() public {
        vm.prank(admin);
        exchange.addAdmin(henry);
        assertEq(exchange.adminCount(), 2);

        vm.prank(admin);
        exchange.renounceAdminRole();

        assertFalse(exchange.isAdmin(admin));
        assertTrue(exchange.isAdmin(henry));
        assertEq(exchange.adminCount(), 1);
    }

    function test_removeAdmin_twoAdmins_cannotRemoveBoth() public {
        vm.prank(admin);
        exchange.addAdmin(henry);
        assertEq(exchange.adminCount(), 2);

        // Remove one — succeeds
        vm.prank(admin);
        exchange.removeAdmin(henry);
        assertEq(exchange.adminCount(), 1);

        // Remove self (the last one) — reverts
        vm.prank(admin);
        vm.expectRevert(CannotRemoveLastAdmin.selector);
        exchange.removeAdmin(admin);

        assertEq(exchange.adminCount(), 1);
        assertTrue(exchange.isAdmin(admin));
    }

    function test_addAdmin_afterRemove_restoresCount() public {
        vm.startPrank(admin);
        exchange.addAdmin(henry);
        assertEq(exchange.adminCount(), 2);

        exchange.removeAdmin(henry);
        assertEq(exchange.adminCount(), 1);

        exchange.addAdmin(henry);
        assertEq(exchange.adminCount(), 2);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    Two-step admin transfer
    //////////////////////////////////////////////////////////////*/

    /// @notice transferAdmin sets the pendingAdmin without granting the role immediately.
    ///         The proposed address must call acceptAdmin() to complete the transfer.
    function test_transferAdmin_setsPendingWithoutGranting() public {
        vm.prank(admin);
        exchange.transferAdmin(henry);
        assertEq(exchange.pendingAdmin(), henry);

        // Henry is not yet an admin
        assertFalse(exchange.isAdmin(henry));
    }

    /// @notice The full two-step flow: propose then accept. After acceptance the new
    ///         address is an admin, pendingAdmin is cleared, and adminCount increments.
    function test_acceptAdmin_completesTransferAndIncrementsCount() public {
        vm.prank(admin);
        exchange.transferAdmin(henry);

        vm.prank(henry);
        exchange.acceptAdmin();

        assertTrue(exchange.isAdmin(henry));
        assertEq(exchange.pendingAdmin(), address(0));
        assertEq(exchange.adminCount(), 2);
    }

    /// @notice Only the pendingAdmin address can call acceptAdmin. Any other caller
    ///         must be rejected to prevent unauthorized role assumption.
    function test_acceptAdmin_revertsForNonPendingCaller() public {
        vm.prank(admin);
        exchange.transferAdmin(henry);

        vm.prank(brian);
        vm.expectRevert(NotPendingAdmin.selector);
        exchange.acceptAdmin();
    }

    /// @notice transferAdmin must reject the zero address to prevent a proposal that
    ///         could never be accepted (no one can call from address(0)).
    function test_transferAdmin_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ZeroAddress.selector);
        exchange.transferAdmin(address(0));
    }

    /// @notice Only current admins can propose a transfer. Non-admins must be rejected.
    function test_transferAdmin_revertsForNonAdmin() public {
        vm.prank(brian);
        vm.expectRevert(NotAdmin.selector);
        exchange.transferAdmin(henry);
    }

    /// @notice A second call to transferAdmin overwrites the previous pendingAdmin.
    ///         The old candidate can no longer accept; only the latest one can.
    function test_transferAdmin_overwritesPreviousPending() public {
        vm.startPrank(admin);
        exchange.transferAdmin(henry);
        assertEq(exchange.pendingAdmin(), henry);

        exchange.transferAdmin(brian);
        assertEq(exchange.pendingAdmin(), brian);
        vm.stopPrank();

        // Henry can no longer accept
        vm.prank(henry);
        vm.expectRevert(NotPendingAdmin.selector);
        exchange.acceptAdmin();

        // Brian can
        vm.prank(brian);
        exchange.acceptAdmin();
        assertTrue(exchange.isAdmin(brian));
    }

    /// @notice transferAdmin is additive — the proposing admin keeps their role.
    ///         Both the original and the new admin should be active after acceptance.
    function test_transferAdmin_originalAdminRetainsRole() public {
        vm.prank(admin);
        exchange.transferAdmin(henry);

        vm.prank(henry);
        exchange.acceptAdmin();

        assertTrue(exchange.isAdmin(admin));
        assertTrue(exchange.isAdmin(henry));
        assertEq(exchange.adminCount(), 2);
    }

    /// @notice A single admin cannot renounce while a transfer is pending but not yet
    ///         accepted. The last-admin guard must block removal until there are at
    ///         least two confirmed admins.
    function test_renounceAdminRole_blockedUntilTransferAccepted() public {
        vm.prank(admin);
        exchange.transferAdmin(henry);

        // Cannot renounce — still the last confirmed admin
        vm.prank(admin);
        vm.expectRevert(CannotRemoveLastAdmin.selector);
        exchange.renounceAdminRole();

        // After henry accepts, now admin can safely renounce
        vm.prank(henry);
        exchange.acceptAdmin();

        vm.prank(admin);
        exchange.renounceAdminRole();

        assertFalse(exchange.isAdmin(admin));
        assertTrue(exchange.isAdmin(henry));
        assertEq(exchange.adminCount(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                    Admin transfer — existing admin guards
    //////////////////////////////////////////////////////////////*/

    /// @notice An admin proposing themselves as the transfer target is blocked.
    ///         Without this guard, a self-transfer inflates adminCount: the admin
    ///         goes through acceptAdmin() which increments the counter even though
    ///         no new admin was actually added.
    function test_transferAdmin_revertsWhenTargetIsSelf() public {
        vm.prank(admin);
        vm.expectRevert(AlreadyAdmin.selector);
        exchange.transferAdmin(admin);
    }

    /// @notice Proposing a transfer to any address that already holds an admin role
    ///         is rejected. This prevents adminCount inflation and eliminates a
    ///         scenario where the count diverges from the actual number of admins.
    function test_transferAdmin_revertsWhenTargetIsExistingAdmin() public {
        vm.prank(admin);
        exchange.addAdmin(henry);

        vm.prank(admin);
        vm.expectRevert(AlreadyAdmin.selector);
        exchange.transferAdmin(henry);
    }

    /// @notice Defense-in-depth: even if pendingAdmin somehow gets set to an address
    ///         that is already an admin (e.g. via a future code path), acceptAdmin
    ///         must still reject the call to prevent adminCount inflation.
    function test_acceptAdmin_revertsWhenCallerIsAlreadyAdmin() public {
        vm.prank(admin);
        exchange.addAdmin(henry);
        uint256 countBefore = exchange.adminCount();

        // Propose brian, then add brian as admin before he accepts
        vm.prank(admin);
        exchange.transferAdmin(brian);
        vm.prank(admin);
        exchange.addAdmin(brian);

        // Brian tries to accept — should revert since he's already an admin
        vm.prank(brian);
        vm.expectRevert(AlreadyAdmin.selector);
        exchange.acceptAdmin();

        // adminCount reflects only the addAdmin call, not a phantom accept
        assertEq(exchange.adminCount(), countBefore + 1);
    }

    /// @notice Happy path: transferring to a non-admin address works end to end.
    ///         adminCount increments exactly once.
    function test_transferAdmin_succeedsForNonAdminTarget() public {
        uint256 countBefore = exchange.adminCount();

        vm.prank(admin);
        exchange.transferAdmin(henry);

        vm.prank(henry);
        exchange.acceptAdmin();

        assertTrue(exchange.isAdmin(henry));
        assertEq(exchange.adminCount(), countBefore + 1);
    }
}
