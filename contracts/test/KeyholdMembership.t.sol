// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {KeyholdMembership} from "../src/KeyholdMembership.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract KeyholdMembershipTest is Test {
    KeyholdMembership internal membership;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant PRICE = 0.01 ether;
    uint256 internal constant MAX_SUPPLY = 3;

    function setUp() public {
        membership = new KeyholdMembership(admin, PRICE, MAX_SUPPLY);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    // ---------- Minting ----------

    function test_MintSucceeds() public {
        vm.prank(alice);
        membership.mint{value: PRICE}();

        assertEq(membership.ownerOf(1), alice);
        assertTrue(membership.hasMembership(alice));
        assertEq(membership.totalSupply(), 1);
    }

    function test_RevertWhen_WrongPayment() public {
        vm.prank(alice);
        vm.expectRevert(KeyholdMembership.IncorrectPayment.selector);
        membership.mint{value: PRICE - 1}();
    }

    function test_RevertWhen_MintTwice() public {
        vm.startPrank(alice);
        membership.mint{value: PRICE}();
        vm.expectRevert(KeyholdMembership.AlreadyMember.selector);
        membership.mint{value: PRICE}();
        vm.stopPrank();
    }

    function test_RevertWhen_MaxSupplyReached() public {
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            address user = address(uint160(0x1000 + i));
            vm.deal(user, 1 ether);
            vm.prank(user);
            membership.mint{value: PRICE}();
        }
        vm.prank(bob);
        vm.expectRevert(KeyholdMembership.MaxSupplyReached.selector);
        membership.mint{value: PRICE}();
    }

    // ---------- Non-transferable ----------

    function test_RevertWhen_Transfer() public {
        vm.prank(alice);
        membership.mint{value: PRICE}();

        vm.prank(alice);
        vm.expectRevert("Membership is non-transferable");
        membership.transferFrom(alice, bob, 1);
    }

    // ---------- Pause ----------

    function test_PauseBlocksMint() public {
        vm.prank(admin);
        membership.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        membership.mint{value: PRICE}();
    }

    function test_RevertWhen_NonPauserPauses() public {
        vm.prank(alice);
        vm.expectRevert();
        membership.pause();
    }

    // ---------- Admin ----------

    function test_AdminCanSetPrice() public {
        vm.prank(admin);
        membership.setMintPrice(0.02 ether);
        assertEq(membership.mintPrice(), 0.02 ether);
    }

    function test_RevertWhen_NonAdminSetsPrice() public {
        vm.prank(alice);
        vm.expectRevert();
        membership.setMintPrice(1 ether);
    }

    function test_AdminCanWithdraw() public {
        vm.prank(alice);
        membership.mint{value: PRICE}();

        uint256 before = admin.balance;
        vm.prank(admin);
        membership.withdraw(payable(admin));

        assertEq(admin.balance, before + PRICE);
        assertEq(address(membership).balance, 0);
    }

    function test_RevertWhen_NonAdminWithdraws() public {
        vm.prank(alice);
        vm.expectRevert();
        membership.withdraw(payable(alice));
    }

    // ---------- Fuzz ----------

    function testFuzz_MintWithAnyPrice(uint96 price) public {
        vm.prank(admin);
        membership.setMintPrice(price);

        address user = makeAddr("fuzzUser");
        vm.deal(user, uint256(price) + 1 ether);
        vm.prank(user);
        membership.mint{value: price}();

        assertEq(membership.ownerOf(1), user);
    }

    function testFuzz_WrongPaymentAlwaysReverts(uint96 sent) public {
        vm.assume(sent != PRICE);
        vm.deal(alice, uint256(sent) + 1 ether);
        vm.prank(alice);
        vm.expectRevert(KeyholdMembership.IncorrectPayment.selector);
        membership.mint{value: sent}();
    }
}