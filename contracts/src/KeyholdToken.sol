// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Testnet-only token with a public faucet. Not for production.
contract KeyholdToken is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 1000 ether;
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    mapping(address => uint256) public lastClaim;

    error FaucetCooldown();

    constructor() ERC20("Keyhold Token", "KHT") {}

    function faucet() external {
        if (block.timestamp < lastClaim[msg.sender] + FAUCET_COOLDOWN) revert FaucetCooldown();
        lastClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}