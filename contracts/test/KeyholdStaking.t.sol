// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {KeyholdMembership} from "../src/KeyholdMembership.sol";
import {KeyholdToken} from "../src/KeyholdToken.sol";
import {KeyholdStaking, IMembership} from "../src/KeyholdStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract KeyholdStakingTest is Test {
    KeyholdMembership internal membership;
    KeyholdToken internal token;
    KeyholdStaking internal staking;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal outsider = makeAddr("outsider");

    uint256 internal constant PRICE = 0.01 ether;

    function setUp() public {
        membership = new KeyholdMembership(admin, PRICE, 100);
        token = new KeyholdToken();
        staking = new KeyholdStaking(
            IERC20(address(token)),
            IMembership(address(membership)),
            admin
        );

        // Alice: member with tokens and approval.
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        membership.mint{value: PRICE}();
        token.faucet();
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();

        // Outsider: tokens but no membership.
        vm.startPrank(outsider);
        token.faucet();
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }

    // ---------- Staking ----------

    function test_StakeUpdatesPosition() public {
        vm.prank(alice);
        staking.stake(100 ether);

        (uint256 staked,,) = staking.positions(alice);
        assertEq(staked, 100 ether);
        assertEq(token.balanceOf(address(staking)), 100 ether);
    }

    function test_RevertWhen_NonMemberStakes() public {
        vm.prank(outsider);
        vm.expectRevert(KeyholdStaking.NotMember.selector);
        staking.stake(100 ether);
    }

    function test_RevertWhen_StakeZero() public {
        vm.prank(alice);
        vm.expectRevert(KeyholdStaking.ZeroAmount.selector);
        staking.stake(0);
    }

    function test_PauseBlocksStake() public {
        vm.prank(admin);
        staking.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        staking.stake(100 ether);
    }

    // ---------- Tiers ----------

    function test_TierBoundaries() public {
        vm.startPrank(alice);

        assertEq(uint8(staking.tierOf(alice)), uint8(KeyholdStaking.Tier.None));

        staking.stake(99 ether);
        assertEq(uint8(staking.tierOf(alice)), uint8(KeyholdStaking.Tier.None));

        staking.stake(1 ether); // 100
        assertEq(uint8(staking.tierOf(alice)), uint8(KeyholdStaking.Tier.Bronze));

        staking.stake(400 ether); // 500
        assertEq(uint8(staking.tierOf(alice)), uint8(KeyholdStaking.Tier.Silver));

        staking.stake(500 ether); // 1000
        assertEq(uint8(staking.tierOf(alice)), uint8(KeyholdStaking.Tier.Gold));

        vm.stopPrank();
    }

    // ---------- Unstaking ----------

    function test_RequestUnstakeDropsTierImmediately() public {
        vm.startPrank(alice);
        staking.stake(500 ether);
        assertEq(uint8(staking.tierOf(alice)), uint8(KeyholdStaking.Tier.Silver));

        staking.requestUnstake(450 ether);
        assertEq(uint8(staking.tierOf(alice)), uint8(KeyholdStaking.Tier.None));
        vm.stopPrank();
    }

    function test_RevertWhen_UnstakeMoreThanStaked() public {
        vm.startPrank(alice);
        staking.stake(100 ether);
        vm.expectRevert(KeyholdStaking.InsufficientStake.selector);
        staking.requestUnstake(101 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimBeforeCooldown() public {
        vm.startPrank(alice);
        staking.stake(100 ether);
        staking.requestUnstake(100 ether);

        vm.warp(block.timestamp + 3 days - 1);
        vm.expectRevert(KeyholdStaking.CooldownActive.selector);
        staking.claimUnstake();
        vm.stopPrank();
    }

    function test_ClaimAfterCooldown() public {
        vm.startPrank(alice);
        uint256 start = token.balanceOf(alice);
        staking.stake(100 ether);
        staking.requestUnstake(100 ether);

        vm.warp(block.timestamp + 3 days);
        staking.claimUnstake();
        vm.stopPrank();

        assertEq(token.balanceOf(alice), start);
        assertEq(token.balanceOf(address(staking)), 0);
    }

    function test_RevertWhen_NothingPending() public {
        vm.prank(alice);
        vm.expectRevert(KeyholdStaking.NothingPending.selector);
        staking.claimUnstake();
    }

    function test_SecondRequestResetsTimer() public {
        vm.startPrank(alice);
        staking.stake(200 ether);
        staking.requestUnstake(100 ether);

        vm.warp(block.timestamp + 2 days);
        staking.requestUnstake(100 ether); // resets timer for full pending amount

        vm.warp(block.timestamp + 2 days); // 4 days since first, 2 since second
        vm.expectRevert(KeyholdStaking.CooldownActive.selector);
        staking.claimUnstake();
        vm.stopPrank();
    }

    // ---------- Pause never traps funds ----------

    function test_UnstakeWorksWhilePaused() public {
        vm.prank(alice);
        staking.stake(100 ether);

        vm.prank(admin);
        staking.pause();

        vm.startPrank(alice);
        staking.requestUnstake(100 ether);
        vm.warp(block.timestamp + 3 days);
        staking.claimUnstake();
        vm.stopPrank();

        assertEq(token.balanceOf(address(staking)), 0);
    }

    // ---------- Fuzz ----------

    function testFuzz_StakeUnstakeAccounting(uint96 amount, uint96 unstakeAmt) public {
        amount = uint96(bound(amount, 1, 1000 ether));
        unstakeAmt = uint96(bound(unstakeAmt, 1, amount));

        vm.startPrank(alice);
        uint256 start = token.balanceOf(alice);
        staking.stake(amount);
        staking.requestUnstake(unstakeAmt);

        (uint256 staked, uint256 pending,) = staking.positions(alice);
        assertEq(staked, uint256(amount) - unstakeAmt);
        assertEq(pending, unstakeAmt);

        // Contract always holds exactly staked + pending.
        assertEq(token.balanceOf(address(staking)), staked + pending);

        vm.warp(block.timestamp + 3 days);
        staking.claimUnstake();
        vm.stopPrank();

        assertEq(token.balanceOf(alice), start - staked);
    }
}