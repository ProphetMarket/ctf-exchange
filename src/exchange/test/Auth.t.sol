// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { BaseExchangeTest } from "exchange/test/BaseExchangeTest.sol";

/// @title AuthTest
/// @notice Tests for M-02 fix: last admin cannot permanently lock the contract
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
}
