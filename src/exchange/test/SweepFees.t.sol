// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { BaseExchangeTest } from "exchange/test/BaseExchangeTest.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import { IConditionalTokens } from "exchange/interfaces/IConditionalTokens.sol";

contract SweepFeesTest is BaseExchangeTest {
    function setUp() public override {
        super.setUp();
        // Set up approvals for admin (operator) without minting outcome tokens
        vm.startPrank(admin);
        usdc.approve(address(ctf), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        IERC1155(address(ctf)).setApprovalForAll(address(exchange), true);
        vm.stopPrank();
    }

    /// @notice Operator merges equal YES/NO balances into collateral
    function testSweepFees() public {
        uint256 amount = 100_000_000;
        _giveOutcomeTokens(admin, amount, amount);

        uint256 collateralBefore = usdc.balanceOf(admin);

        vm.expectEmit(true, true, true, true);
        emit FeesSwept(admin, yes, amount);

        vm.prank(admin);
        exchange.sweepFees(yes);

        assertEq(IERC1155(address(ctf)).balanceOf(admin, yes), 0);
        assertEq(IERC1155(address(ctf)).balanceOf(admin, no), 0);
        assertEq(usdc.balanceOf(admin), collateralBefore + amount);
    }

    /// @notice Only the min of both balances is merged
    function testSweepFeesPartialBalance() public {
        _giveOutcomeTokens(admin, 100_000_000, 60_000_000);

        uint256 collateralBefore = usdc.balanceOf(admin);

        vm.prank(admin);
        exchange.sweepFees(yes);

        // Only 60M merged (the min)
        assertEq(IERC1155(address(ctf)).balanceOf(admin, yes), 40_000_000);
        assertEq(IERC1155(address(ctf)).balanceOf(admin, no), 0);
        assertEq(usdc.balanceOf(admin), collateralBefore + 60_000_000);
    }

    /// @notice Reverts when one side has zero balance
    function testSweepFeesZeroBalance() public {
        vm.expectRevert(NothingToSweep.selector);
        vm.prank(admin);
        exchange.sweepFees(yes);
    }

    /// @notice Calling with the complement tokenId produces identical results
    function testSweepFeesWithComplement() public {
        uint256 amount = 50_000_000;
        _giveOutcomeTokens(admin, amount, amount);

        uint256 collateralBefore = usdc.balanceOf(admin);

        vm.expectEmit(true, true, true, true);
        emit FeesSwept(admin, no, amount);

        vm.prank(admin);
        exchange.sweepFees(no);

        assertEq(IERC1155(address(ctf)).balanceOf(admin, yes), 0);
        assertEq(IERC1155(address(ctf)).balanceOf(admin, no), 0);
        assertEq(usdc.balanceOf(admin), collateralBefore + amount);
    }

    /// @notice Non-operator cannot sweep
    function testSweepFeesOnlyOperator() public {
        address nobody = address(0xDEAD);
        vm.expectRevert(NotOperator.selector);
        vm.prank(nobody);
        exchange.sweepFees(yes);
    }

    /// @notice Unregistered token reverts
    function testSweepFeesInvalidToken() public {
        vm.expectRevert(InvalidTokenId.selector);
        vm.prank(admin);
        exchange.sweepFees(12345);
    }

    // --- Helpers ---

    function _giveOutcomeTokens(address to, uint256 yesAmount, uint256 noAmount) internal {
        uint256 maxAmount = yesAmount > noAmount ? yesAmount : noAmount;

        // Deal USDC and split into YES/NO tokens
        deal(address(usdc), to, usdc.balanceOf(to) + maxAmount);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        vm.startPrank(to);
        IConditionalTokens(ctf).splitPosition(IERC20(address(usdc)), bytes32(0), conditionId, partition, maxAmount);

        // Burn excess by transferring to a dead address
        if (yesAmount < maxAmount) {
            IERC1155(address(ctf)).safeTransferFrom(to, address(0xBEEF), yes, maxAmount - yesAmount, "");
        }
        if (noAmount < maxAmount) {
            IERC1155(address(ctf)).safeTransferFrom(to, address(0xBEEF), no, maxAmount - noAmount, "");
        }
        vm.stopPrank();
    }
}
