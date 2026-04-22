// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { BaseExchangeTest } from "exchange/test/BaseExchangeTest.sol";
import { CTFExchange } from "exchange/CTFExchange.sol";
import { Order, Side } from "exchange/libraries/OrderStructs.sol";

/// @title AuditFixesTest
/// @notice Tests for M-09, L-02, L-03, L-05 audit findings
contract AuditFixesTest is BaseExchangeTest {
    function setUp() public override {
        super.setUp();
        _mintTestTokens(bob, address(exchange), 20_000_000_000);
        _mintTestTokens(carla, address(exchange), 20_000_000_000);
    }

    /*//////////////////////////////////////////////////////////////
                    M-09: Zero-address checks on factory setters
    //////////////////////////////////////////////////////////////*/

    function test_M09_setProxyFactory_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("zero address");
        exchange.setProxyFactory(address(0));
    }

    function test_M09_setSafeFactory_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("zero address");
        exchange.setSafeFactory(address(0));
    }

    function test_M09_setProxyFactory_succeedsWithValidAddress() public {
        address newFactory = address(0xBEEF);
        vm.prank(admin);
        exchange.setProxyFactory(newFactory);
        assertEq(exchange.getProxyFactory(), newFactory);
    }

    function test_M09_setSafeFactory_succeedsWithValidAddress() public {
        address newFactory = address(0xCAFE);
        vm.prank(admin);
        exchange.setSafeFactory(newFactory);
        assertEq(exchange.getSafeFactory(), newFactory);
    }

    /*//////////////////////////////////////////////////////////////
                    L-02: Array-length checks in fillOrders / matchOrders
    //////////////////////////////////////////////////////////////*/

    function test_L02_fillOrders_revertsOnLengthMismatch() public {
        Order[] memory orders = new Order[](2);
        orders[0] = _createAndSignOrder(bobPK, yes, 50_000_000, 100_000_000, Side.BUY);
        orders[1] = _createAndSignOrder(bobPK, no, 50_000_000, 100_000_000, Side.BUY);

        // Only 1 fill amount for 2 orders
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 50_000_000;

        vm.prank(admin);
        vm.expectRevert(ArrayLengthMismatch.selector);
        exchange.fillOrders(orders, fillAmounts);
    }

    function test_L02_fillOrders_succeedsWithMatchingLengths() public {
        _mintTestTokens(admin, address(exchange), 20_000_000_000);

        Order[] memory orders = new Order[](1);
        orders[0] = _createAndSignOrder(bobPK, yes, 50_000_000, 100_000_000, Side.BUY);

        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 50_000_000;

        vm.prank(admin);
        exchange.fillOrders(orders, fillAmounts);
    }

    function test_L02_matchOrders_revertsOnMakerArrayLengthMismatch() public {
        Order memory takerOrder = _createAndSignOrder(bobPK, yes, 50_000_000, 100_000_000, Side.BUY);

        Order[] memory makerOrders = new Order[](2);
        makerOrders[0] = _createAndSignOrder(carlaPK, yes, 100_000_000, 50_000_000, Side.SELL);
        makerOrders[1] = _createAndSignOrder(carlaPK, yes, 100_000_000, 50_000_000, Side.SELL);

        // Only 1 fill amount for 2 maker orders
        uint256[] memory makerFillAmounts = new uint256[](1);
        makerFillAmounts[0] = 50_000_000;

        vm.prank(admin);
        vm.expectRevert(ArrayLengthMismatch.selector);
        exchange.matchOrders(takerOrder, makerOrders, 50_000_000, makerFillAmounts);
    }

    /*//////////////////////////////////////////////////////////////
                    L-03: domainSeparator updates on chain fork
    //////////////////////////////////////////////////////////////*/

    function test_L03_domainSeparator_matchesLiveValue() public {
        // The public getter should return a value consistent with the current chain
        bytes32 ds = exchange.domainSeparator();
        assertTrue(ds != bytes32(0), "domainSeparator should not be zero");
    }

    function test_L03_domainSeparator_updatesOnChainFork() public {
        bytes32 dsBefore = exchange.domainSeparator();

        // Simulate a chain fork by changing the chain ID
        vm.chainId(999);

        bytes32 dsAfter = exchange.domainSeparator();

        // After fork, the domain separator should change
        assertTrue(dsBefore != dsAfter, "domainSeparator should change on chain fork");
    }

    function test_L03_domainSeparator_stableWithSameChainId() public {
        bytes32 ds1 = exchange.domainSeparator();
        bytes32 ds2 = exchange.domainSeparator();
        assertEq(ds1, ds2, "domainSeparator should be stable for same chain");
    }

    /*//////////////////////////////////////////////////////////////
                    L-05: Two-step admin transfer
    //////////////////////////////////////////////////////////////*/

    function test_L05_transferAdmin_proposesNewAdmin() public {
        vm.prank(admin);
        exchange.transferAdmin(henry);
        assertEq(exchange.pendingAdmin(), henry);

        // Henry is not yet an admin
        assertFalse(exchange.isAdmin(henry));
    }

    function test_L05_acceptAdmin_completesTransfer() public {
        vm.prank(admin);
        exchange.transferAdmin(henry);

        vm.prank(henry);
        exchange.acceptAdmin();

        assertTrue(exchange.isAdmin(henry));
        assertEq(exchange.pendingAdmin(), address(0));
        assertEq(exchange.adminCount(), 2);
    }

    function test_L05_acceptAdmin_revertsForNonPending() public {
        vm.prank(admin);
        exchange.transferAdmin(henry);

        // Brian tries to accept — should fail
        vm.prank(brian);
        vm.expectRevert(NotPendingAdmin.selector);
        exchange.acceptAdmin();
    }

    function test_L05_transferAdmin_revertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ZeroAddress.selector);
        exchange.transferAdmin(address(0));
    }

    function test_L05_transferAdmin_onlyAdmin() public {
        vm.prank(brian);
        vm.expectRevert(NotAdmin.selector);
        exchange.transferAdmin(henry);
    }

    function test_L05_transferAdmin_overwritesPendingAdmin() public {
        vm.startPrank(admin);
        exchange.transferAdmin(henry);
        assertEq(exchange.pendingAdmin(), henry);

        // Change mind — propose someone else
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

    function test_L05_transferAdmin_originalAdminRetainsRole() public {
        vm.prank(admin);
        exchange.transferAdmin(henry);

        vm.prank(henry);
        exchange.acceptAdmin();

        // Original admin still has their role
        assertTrue(exchange.isAdmin(admin));
        assertTrue(exchange.isAdmin(henry));
        assertEq(exchange.adminCount(), 2);
    }

    function test_L05_lastAdmin_cannotLockOut() public {
        // Single admin proposes transfer, then tries to renounce before acceptance
        vm.prank(admin);
        exchange.transferAdmin(henry);

        // Cannot renounce — still the last admin
        vm.prank(admin);
        vm.expectRevert(CannotRemoveLastAdmin.selector);
        exchange.renounceAdminRole();

        // After henry accepts, now admin can renounce
        vm.prank(henry);
        exchange.acceptAdmin();

        vm.prank(admin);
        exchange.renounceAdminRole();

        assertFalse(exchange.isAdmin(admin));
        assertTrue(exchange.isAdmin(henry));
        assertEq(exchange.adminCount(), 1);
    }
}
