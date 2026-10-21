// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {KeyholdMembership} from "../src/KeyholdMembership.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @dev Attacker that tries to re-enter mint() from the ERC721 receiver hook.
contract MintReentrancyAttacker is IERC721Receiver {
    KeyholdMembership public target;
    uint256 public price;
    bool public reentered;
    bool public reentryReverted;

    constructor(KeyholdMembership _target, uint256 _price) {
        target = _target;
        price = _price;
    }

    function attack() external payable {
        target.mint{value: price}();
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        override
        returns (bytes4)
    {
        reentered = true;
        // Try to mint again while the first mint is still in progress.
        try target.mint{value: price}() {
            reentryReverted = false;
        } catch {
            reentryReverted = true;
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// @dev Malicious admin receiver that tries to re-enter withdraw().
contract WithdrawReentrancyAttacker {
    KeyholdMembership public target;
    bool public reentryReverted;

    constructor(KeyholdMembership _target) {
        target = _target;
    }

    receive() external payable {
        try target.withdraw(payable(address(this))) {
            reentryReverted = false;
        } catch {
            reentryReverted = true;
        }
    }
}

contract ReentrancyTest is Test {
    KeyholdMembership internal membership;
    address internal admin = makeAddr("admin");
    uint256 internal constant PRICE = 0.01 ether;

    function setUp() public {
        membership = new KeyholdMembership(admin, PRICE, 10);
    }

    function test_MintReentrancyIsBlocked() public {
        MintReentrancyAttacker attacker = new MintReentrancyAttacker(membership, PRICE);
        vm.deal(address(attacker), 1 ether);

        attacker.attack();

        assertTrue(attacker.reentered(), "hook should have been called");
        assertTrue(attacker.reentryReverted(), "re-entry must be blocked");
        assertEq(membership.totalSupply(), 1, "only one membership minted");
        assertEq(membership.balanceOf(address(attacker)), 1);
    }

    function test_WithdrawReentrancyIsBlocked() public {
        // Fund the contract with a legitimate mint.
        address user = makeAddr("user");
        vm.deal(user, 1 ether);
        vm.prank(user);
        membership.mint{value: PRICE}();

        // Make the attacker an admin so it can call withdraw and receive ETH.
        WithdrawReentrancyAttacker attacker = new WithdrawReentrancyAttacker(membership);
        bytes32 adminRole = membership.ADMIN_ROLE();
        vm.prank(admin);
        membership.grantRole(adminRole, address(attacker));

        vm.prank(address(attacker));
        membership.withdraw(payable(address(attacker)));

        assertTrue(attacker.reentryReverted(), "re-entry must be blocked");
        assertEq(address(attacker).balance, PRICE, "attacker gets funds only once");
        assertEq(address(membership).balance, 0);
    }
}