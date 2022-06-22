// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {ERC721} from "../lib/solmate/src/tokens/ERC721.sol";

// The commit was not found
error InvalidCommit();

// The name contained invalid characters
error InvalidName();

error AlreadyRegistered();

// Invalid Token Id
error TokenDoesNotExist();

// The transaction does not have enough money to pay for this.
error InsufficientFunds();

error Unauthorized();

// The NFT tokenID has not been minted yet
error NotMinted();

// The NFT is still within the registration + grace period
error NotReclaimable();

// The NFT hasn't passed expiry yet
error NotRenewable();

contract Namespace is ERC721 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Renew(uint256 indexed tokenId, address indexed to, uint256 expiry);

    event Reclaim(uint256 indexed tokenId);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    // Mapping from commitment hash to block number of commitment
    mapping(bytes32 => uint256) public ageOf;

    // Mapping from tokenID to expiration date
    mapping(uint256 => uint256) public expiryOf;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    string public baseURI = "http://www.farcaster.xyz/";

    uint256 public gracePeriod = 30 days;
    uint256 public registrationPeriod = 365 days;
    uint256 fee = 0.01 ether;

    address public vault = address(0x1234567890);

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function generateCommit(
        bytes16 username,
        address owner,
        bytes32 secret
    ) public pure returns (bytes32) {
        if (!_isValidUsername(username)) revert InvalidName();
        return keccak256(abi.encode(username, owner, secret));
    }

    function makeCommit(bytes32 commit) public {
        ageOf[commit] = block.number;
    }

    function register(
        bytes16 username,
        address owner,
        bytes32 secret
    ) external payable {
        bytes32 commit = generateCommit(username, owner, secret);

        if (msg.value < 0.01 ether) revert InsufficientFunds();
        if (ageOf[commit] == 0) revert InvalidCommit();

        // TODO: Evaluate this byte conversion.
        uint256 tokenId = uint256(bytes32(username));

        // The username is minted, and can no longer be registered, only renewed or reclaimed.
        if (expiryOf[tokenId] != 0) revert Unauthorized();

        _mint(msg.sender, tokenId);
        expiryOf[tokenId] = block.timestamp + registrationPeriod;

        // Release the commit value and refund
        commit = 0;

        if (msg.value > 0.01 ether) {
            // TODO: should we be using safe transfer here?
            payable(msg.sender).transfer(msg.value - 0.01 ether);
        }
    }

    function renew(uint256 tokenId, address owner) external payable {
        if (msg.value < fee) revert InsufficientFunds();

        // make sure they are the owner, otherwise might have got sniped.
        if (ownerOf(tokenId) != owner) revert Unauthorized();

        // We aren't able to renew yet, it's too soon.
        if (block.timestamp < expiryOf[tokenId]) revert NotRenewable();

        expiryOf[tokenId] += registrationPeriod;

        if (msg.value > 0.01 ether) {
            payable(msg.sender).transfer(msg.value - 0.01 ether);
        }

        emit Renew(tokenId, owner, expiryOf[tokenId]);
    }

    function reclaim(uint256 tokenId) external payable {
        // The username has never been minted
        if (expiryOf[tokenId] == 0) revert NotMinted();

        // The username has been minted, but is not out of the grace period.
        if (expiryOf[tokenId] + gracePeriod > block.timestamp) revert NotReclaimable();

        _forceTransfer(vault, tokenId);

        emit Reclaim(tokenId);
    }

    function _isValidUsername(bytes16 name) internal pure returns (bool) {
        uint256 length = name.length;

        for (uint256 i = 0; i < length; ) {
            uint8 charInt = uint8(name[i]);
            // TODO: can probably be optimized with a bitmask, but write tests first
            // Allow inclusive ranges 45(-), 48 - 57 (0-9), 97-122 (a-z)
            if (
                (charInt >= 1 && charInt <= 44) ||
                (charInt >= 46 && charInt <= 47) ||
                (charInt >= 58 && charInt <= 96) ||
                charInt >= 123
            ) {
                return false;
            }

            // This is safe because name.length will never exceed 16 since it is a bytes16
            unchecked {
                i++;
            }
        }
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             ERC-721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (ownerOf(tokenId) == address(0)) {
            revert TokenDoesNotExist();
        }

        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId, ".json")) : "";
    }

    function _forceTransfer(address to, uint256 tokenId) internal {
        address from = _ownerOf[tokenId];

        if (from == address(0)) revert Unauthorized();

        // Underflow is prevented by ownership check and guaranteed by the ERC-721 impl
        // Overflow is unrealistic given the limited scope of possible names
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[tokenId] = to;

        delete getApproved[tokenId];

        emit Transfer(from, to, tokenId);
    }
}
