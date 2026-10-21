// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title KeyholdMembership
/// @notice Soulbound-style membership NFT: one per wallet, paid mint, role-based admin.
contract KeyholdMembership is ERC721, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public mintPrice;
    uint256 public maxSupply;
    uint256 public totalSupply;
    uint256 private _nextTokenId = 1;

    mapping(address => bool) public hasMembership;

    event MembershipMinted(address indexed member, uint256 indexed tokenId);
    event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event Withdrawn(address indexed to, uint256 amount);

    error AlreadyMember();
    error IncorrectPayment();
    error MaxSupplyReached();
    error ZeroAddress();
    error WithdrawFailed();

    constructor(address admin, uint256 _mintPrice, uint256 _maxSupply)
        ERC721("Keyhold Membership", "KEY")
    {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        mintPrice = _mintPrice;
        maxSupply = _maxSupply;
    }

    function mint() external payable nonReentrant whenNotPaused {
        if (hasMembership[msg.sender]) revert AlreadyMember();
        if (msg.value != mintPrice) revert IncorrectPayment();
        if (totalSupply >= maxSupply) revert MaxSupplyReached();

        uint256 tokenId = _nextTokenId++;
        hasMembership[msg.sender] = true;
        totalSupply++;

        emit MembershipMinted(msg.sender, tokenId);
        _safeMint(msg.sender, tokenId);
    }

    function setMintPrice(uint256 newPrice) external onlyRole(ADMIN_ROLE) {
        emit MintPriceUpdated(mintPrice, newPrice);
        mintPrice = newPrice;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

        /// @dev Intentionally sends ETH to an admin-chosen address.
    ///      Access restricted to ADMIN_ROLE; lint warning `arbitrary-send-eth` acknowledged.
    function withdraw(address payable to) external nonReentrant onlyRole(ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = address(this).balance;
        emit Withdrawn(to, amount);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert WithdrawFailed();
    }

    /// @dev Block transfers so membership can't be sold or moved (mint only).
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        require(from == address(0), "Membership is non-transferable");
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}