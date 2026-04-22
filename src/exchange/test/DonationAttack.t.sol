// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { BaseExchangeTest } from "exchange/test/BaseExchangeTest.sol";

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC1155 } from "openzeppelin-contracts/token/ERC1155/IERC1155.sol";

import { Order, Side } from "exchange/libraries/OrderStructs.sol";

/// @title DonationAttackTest
/// @notice Tests that delta-based accounting in _matchOrders prevents
///         donated tokens from inflating taker payouts (H-04) or refunds (H-06).
contract DonationAttackTest is BaseExchangeTest {
    address public attacker;

    function setUp() public override {
        super.setUp();
        attacker = makeAddr("attacker");
        _mintTestTokens(bob, address(exchange), 20_000_000_000);
        _mintTestTokens(carla, address(exchange), 20_000_000_000);
        _mintTestTokens(attacker, address(exchange), 20_000_000_000);
    }

    /*//////////////////////////////////////////////////////////////
                    H-04: TAKER PAYOUT DONATION ATTACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Donated CTF tokens sitting in the exchange before matchOrders
    ///         must NOT inflate the taker's payout (complementary match).
    function testDonatedCTFTokensIgnoredInComplementaryMatch() public {
        // Setup: buy YES at 50c, sell YES at 50c
        Order memory buy = _createAndSignOrder(bobPK, yes, 50_000_000, 100_000_000, Side.BUY);
        Order memory sell = _createAndSignOrder(carlaPK, yes, 100_000_000, 50_000_000, Side.SELL);

        Order[] memory makerOrders = new Order[](1);
        makerOrders[0] = sell;
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 100_000_000;

        // Attacker donates YES tokens to the exchange before the match
        uint256 donatedAmount = 50_000_000;
        vm.prank(attacker);
        IERC1155(address(ctf)).safeTransferFrom(attacker, address(exchange), yes, donatedAmount, "");

        // Snapshot bob's YES balance before the match
        uint256 bobYesBefore = getCTFBalance(bob, yes);

        // Execute match
        vm.prank(admin);
        exchange.matchOrders(buy, makerOrders, 50_000_000, fillAmounts);

        // Bob should receive exactly 100_000_000 YES tokens (the fill amount),
        // NOT 100_000_000 + 50_000_000 (inflated by donation)
        uint256 bobYesAfter = getCTFBalance(bob, yes);
        assertEq(bobYesAfter - bobYesBefore, 100_000_000, "taker received donated tokens");
    }

    /// @notice Donated CTF tokens must NOT inflate taker payout in a MINT match.
    function testDonatedCTFTokensIgnoredInMintMatch() public {
        // YES buy at 50c, NO buy at 50c → MINT match
        Order memory yesBuy = _createAndSignOrder(bobPK, yes, 50_000_000, 100_000_000, Side.BUY);
        Order memory noBuy = _createAndSignOrder(carlaPK, no, 50_000_000, 100_000_000, Side.BUY);

        Order[] memory makerOrders = new Order[](1);
        makerOrders[0] = noBuy;
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 50_000_000;

        // Attacker donates YES tokens to the exchange
        uint256 donatedAmount = 30_000_000;
        vm.prank(attacker);
        IERC1155(address(ctf)).safeTransferFrom(attacker, address(exchange), yes, donatedAmount, "");

        uint256 bobYesBefore = getCTFBalance(bob, yes);

        vm.prank(admin);
        exchange.matchOrders(yesBuy, makerOrders, 50_000_000, fillAmounts);

        // Bob should get exactly 100_000_000 YES from the mint, not 130_000_000
        uint256 bobYesAfter = getCTFBalance(bob, yes);
        assertEq(bobYesAfter - bobYesBefore, 100_000_000, "taker received donated tokens in mint match");
    }

    /// @notice Donated collateral must NOT inflate taker payout in a MERGE match.
    function testDonatedCollateralIgnoredInMergeMatch() public {
        // YES sell at 50c, NO sell at 50c → MERGE match
        Order memory yesSell = _createAndSignOrder(bobPK, yes, 100_000_000, 50_000_000, Side.SELL);
        Order memory noSell = _createAndSignOrder(carlaPK, no, 100_000_000, 50_000_000, Side.SELL);

        Order[] memory makerOrders = new Order[](1);
        makerOrders[0] = noSell;
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 100_000_000;

        // Attacker donates collateral (USDC) to the exchange
        uint256 donatedAmount = 25_000_000;
        vm.prank(attacker);
        IERC20(address(usdc)).transfer(address(exchange), donatedAmount);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        vm.prank(admin);
        exchange.matchOrders(yesSell, makerOrders, 100_000_000, fillAmounts);

        // Bob should receive exactly 50_000_000 USDC from the merge, not 75_000_000
        uint256 bobUsdcAfter = usdc.balanceOf(bob);
        assertEq(bobUsdcAfter - bobUsdcBefore, 50_000_000, "taker received donated collateral in merge match");
    }

    /*//////////////////////////////////////////////////////////////
                    H-06: REFUND DONATION ATTACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Donated collateral sitting in the exchange must NOT be swept
    ///         as a "refund" to the taker in a complementary BUY match.
    function testDonatedCollateralNotRefundedInBuyMatch() public {
        // Bob BUY YES: offers 50M USDC for 100M YES (price 0.50)
        // Carla SELL YES: offers 100M YES for 40M USDC (price 0.40 — crosses)
        // After fill: exchange uses 40M of bob's 50M USDC → legitimate refund = 10M USDC
        Order memory buy = _createAndSignOrder(bobPK, yes, 50_000_000, 100_000_000, Side.BUY);
        Order memory sell = _createAndSignOrder(carlaPK, yes, 100_000_000, 40_000_000, Side.SELL);

        Order[] memory makerOrders = new Order[](1);
        makerOrders[0] = sell;
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 100_000_000;

        // Attacker donates collateral to the exchange
        uint256 donatedAmount = 20_000_000;
        vm.prank(attacker);
        IERC20(address(usdc)).transfer(address(exchange), donatedAmount);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        vm.prank(admin);
        exchange.matchOrders(buy, makerOrders, 50_000_000, fillAmounts);

        // Bob sent 50M USDC. Legitimate refund = 10M. Net USDC spent = 40M.
        // Without the fix, refund would be 30M (10M + 20M donated), net spend = 20M.
        uint256 bobUsdcAfter = usdc.balanceOf(bob);
        uint256 netUsdcSpent = bobUsdcBefore - bobUsdcAfter;
        assertEq(netUsdcSpent, 40_000_000, "taker received donated collateral as refund");
    }

    /// @notice Donated CTF tokens must NOT be swept as a "refund" to the taker
    ///         in a SELL match where the taker's asset is a CTF token.
    function testDonatedCTFTokensNotRefundedInSellMatch() public {
        // Bob SELL YES: offers 100M YES for 50M USDC (price 0.50)
        // Carla BUY YES: offers 60M USDC for 100M YES (price 0.60 — crosses)
        // Carla's buy consumes 100M of bob's YES. Legitimate YES refund = 0.
        // Bob gets surplus: 60M USDC (more than his 50M ask).
        Order memory yesSell = _createAndSignOrder(bobPK, yes, 100_000_000, 50_000_000, Side.SELL);
        Order memory yesBuy = _createAndSignOrder(carlaPK, yes, 60_000_000, 100_000_000, Side.BUY);

        Order[] memory makerOrders = new Order[](1);
        makerOrders[0] = yesBuy;
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 60_000_000; // Full fill of carla's buy

        // Attacker donates YES tokens to the exchange
        uint256 donatedAmount = 15_000_000;
        vm.prank(attacker);
        IERC1155(address(ctf)).safeTransferFrom(attacker, address(exchange), yes, donatedAmount, "");

        uint256 bobYesBefore = getCTFBalance(bob, yes);

        vm.prank(admin);
        exchange.matchOrders(yesSell, makerOrders, 100_000_000, fillAmounts);

        // Bob sent 100M YES. Carla consumed all 100M. Legitimate YES refund = 0.
        // Without the fix, the 15M donated YES would be swept as a "refund" to bob.
        // Net YES loss should be exactly 100M (no refund).
        uint256 bobYesAfter = getCTFBalance(bob, yes);
        uint256 netYesLost = bobYesBefore - bobYesAfter;
        assertEq(netYesLost, 100_000_000, "taker received donated CTF tokens as refund");
    }

    /*//////////////////////////////////////////////////////////////
                    COMBINED: NORMAL OPERATION UNAFFECTED
    //////////////////////////////////////////////////////////////*/

    /// @notice Verify that normal match operations (no donations) still work
    ///         correctly with the delta-based accounting.
    function testNormalMatchStillWorksWithDeltaAccounting() public {
        Order memory buy = _createAndSignOrder(bobPK, yes, 60_000_000, 100_000_000, Side.BUY);
        Order memory sell = _createAndSignOrder(carlaPK, yes, 50_000_000, 25_000_000, Side.SELL);

        Order[] memory makerOrders = new Order[](1);
        makerOrders[0] = sell;
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 50_000_000;

        checkpointCollateral(carla);
        checkpointCTF(bob, yes);

        vm.prank(admin);
        exchange.matchOrders(buy, makerOrders, 25_000_000, fillAmounts);

        // Carla receives 25_000_000 USDC (collateral from bob's buy)
        assertCollateralBalance(carla, 25_000_000);
        // Bob receives 50_000_000 YES tokens
        assertCTFBalance(bob, yes, 50_000_000);
    }

    /// @notice Verify that legitimate surplus (price improvement) is still
    ///         captured correctly — delta accounting doesn't suppress real surplus.
    function testLegitSurplusPreservedWithDeltaAccounting() public {
        // Taker sells YES at 50c, maker buys YES at 60c → 10c surplus per token
        Order memory yesSell = _createAndSignOrder(bobPK, yes, 100_000_000, 50_000_000, Side.SELL);
        Order memory yesBuy = _createAndSignOrder(carlaPK, yes, 60_000_000, 100_000_000, Side.BUY);

        Order[] memory makerOrders = new Order[](1);
        makerOrders[0] = yesBuy;
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 60_000_000;

        checkpointCollateral(bob);

        vm.prank(admin);
        exchange.matchOrders(yesSell, makerOrders, 100_000_000, fillAmounts);

        // Bob (taker) signed for 50c but gets filled at 60c → 60_000_000 USDC
        assertCollateralBalance(bob, 60_000_000);
    }
}
