// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMembership {
    function hasMembership(address who) external view returns (bool);
}

/// @title KeyholdStaking
/// @notice Stake KHT to reach a tier. Unstaking has a cooldown. Admin cannot touch user funds.
contract KeyholdStaking is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Tier { None, Bronze, Silver, Gold }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant BRONZE = 100 ether;
    uint256 public constant SILVER = 500 ether;
    uint256 public constant GOLD = 1000 ether;
    uint256 public constant COOLDOWN = 3 days;

    IERC20 public immutable token;
    IMembership public immutable membership;

    struct Position {
        uint256 staked;
        uint256 pending;       // amount in cooldown
        uint256 unlockTime;    // when pending can be claimed
    }

    mapping(address => Position) public positions;

    event Staked(address indexed user, uint256 amount, uint256 totalStaked);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event UnstakeClaimed(address indexed user, uint256 amount);

    error NotMember();
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientStake();
    error NothingPending();
    error CooldownActive();

    constructor(IERC20 _token, IMembership _membership, address admin) {
        if (address(_token) == address(0) || address(_membership) == address(0) || admin == address(0)) {
            revert ZeroAddress();
        }
        token = _token;
        membership = _membership;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (!membership.hasMembership(msg.sender)) revert NotMember();

        Position storage p = positions[msg.sender];
        p.staked += amount;

        emit Staked(msg.sender, amount, p.staked);
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Move tokens into cooldown. Tier drops immediately. Allowed while paused.
    function requestUnstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Position storage p = positions[msg.sender];
        if (amount > p.staked) revert InsufficientStake();

        p.staked -= amount;
        p.pending += amount;
        p.unlockTime = block.timestamp + COOLDOWN;

        emit UnstakeRequested(msg.sender, amount, p.unlockTime);
    }

    /// @notice Withdraw tokens after the cooldown. Allowed while paused.
    function claimUnstake() external nonReentrant {
        Position storage p = positions[msg.sender];
        uint256 amount = p.pending;
        if (amount == 0) revert NothingPending();
        if (block.timestamp < p.unlockTime) revert CooldownActive();

        p.pending = 0;
        p.unlockTime = 0;

        emit UnstakeClaimed(msg.sender, amount);
        token.safeTransfer(msg.sender, amount);
    }

    function tierOf(address user) public view returns (Tier) {
        uint256 s = positions[user].staked;
        if (s >= GOLD) return Tier.Gold;
        if (s >= SILVER) return Tier.Silver;
        if (s >= BRONZE) return Tier.Bronze;
        return Tier.None;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}