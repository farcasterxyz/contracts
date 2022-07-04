// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {ERC721} from "../lib/solmate/src/tokens/ERC721.sol";

import {Owned} from "../lib/solmate/src/auth/Owned.sol";

import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";

error InsufficientFunds(); // The transaction does not have enough money to pay for this.
error Unauthorized(); // The caller is not authorized to perform this action.
error NotMinted(); // The NFT tokenID has not been minted yet

error InvalidCommit(); // The commit hash was not found
error InvalidName(); // The username had invalid characters
error InvalidTime(); // Time is too far in the future or past
error InvalidOwner(); // The username is owned by someone else

error NotRenewable(); // The username is not yet up for renewal
error NotAuctionable(); // The username is not yet up for auction.
error Expired(); // The username is expired.

error NoRecovery(); // The recovery request for this id could not be found
error InvalidRecovery(); // The address is the custody address for the id and cannot also become its recovery address
error InEscrow(); // The recovery request is still in escrow

contract Namespace is ERC721, Owned {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION EVENTS
    //////////////////////////////////////////////////////////////*/

    event Renew(uint256 indexed tokenId, address indexed to, uint256 expiry);

    event Reclaim(uint256 indexed tokenId);

    /*//////////////////////////////////////////////////////////////
                        RECOVERY EVENTS
    //////////////////////////////////////////////////////////////*/

    event SetRecoveryAddress(address indexed recovery, uint256 indexed tokenId);

    event RequestRecovery(uint256 indexed id, address indexed from, address indexed to);

    event CancelRecovery(uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION STORAGE
    //////////////////////////////////////////////////////////////*/

    // Mapping from commitment hash to block number of commitment
    mapping(bytes32 => uint256) public ageOf;

    // Mapping from tokenID to expiration year
    mapping(uint256 => uint256) public expiryYearOf;

    // The index of the next year in the array
    uint256 internal _nextYearIdx;

    /*//////////////////////////////////////////////////////////////
                        RECOVERY STORAGE
    //////////////////////////////////////////////////////////////*/

    // Mapping from tokenId to recoveryAddress
    mapping(uint256 => address) public recoveryOf;

    // Mapping from tokenId to recovery timestamp in seconds, which is set to zero on cancellation
    // or completion
    mapping(uint256 => uint256) public recoveryClockOf;

    // Mapping from tokenId to recovery destination address, which is not unset and left dirty on
    // cancellation or completion to save gas.
    mapping(uint256 => address) public recoveryDestinationOf;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    string public baseURI = "http://www.farcaster.xyz/";

    uint256 public gracePeriod = 30 days;

    uint256 public fee = 0.01 ether;

    // The epoch timestamp of Jan 1 for each year starting from 2022
    uint256[] internal _yearTimestamps = [
        1640995200,
        1672531200,
        1704067200,
        1735689600,
        1767225600,
        1798761600,
        1830297600,
        1861920000,
        1893456000,
        1924992000,
        1956528000,
        1988150400,
        2019686400,
        2051222400,
        2082758400,
        2114380800,
        2145916800
    ];

    address public vault;

    uint256 escrowPeriod = 3 days;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        address _owner,
        address _vault
    ) ERC721(_name, _symbol) Owned(_owner) {
        vault = _vault;
    }

    /*//////////////////////////////////////////////////////////////
                             REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     *                      REGISTRATION INVARIANTS
     *
     * 1. If an id is not minted, expiryYearOf[id] must be 0 and _ownerOf[id] and recoveryOf[id]
     *    must also be address(0).
     */

    /**
     * @notice Generate a commitment hash to register a new username secretly
     *
     * @param username the username to register
     * @param owner the address that will claim the username
     * @param secret the secret that protects the commitment
     */
    function generateCommit(
        bytes16 username,
        address owner,
        bytes32 secret
    ) public pure returns (bytes32) {
        if (!_isValidUsername(username)) revert InvalidName();

        return keccak256(abi.encode(username, owner, secret));
    }

    /**
     * @notice Make a commitment before registration to prevent frontrunning.
     */
    function makeCommit(bytes32 commit) public {
        ageOf[commit] = block.number;
    }

    /**
     * @notice Mint a new username from a previously submitted commitment and register it for the
     * remainder of the year.
     *
     * @param username the username to register
     * @param owner the address that will claim the username
     * @param secret the secret that protects the commitment
     */
    function register(
        bytes16 username,
        address owner,
        bytes32 secret
    ) external payable {
        bytes32 commit = generateCommit(username, owner, secret);

        uint256 _currYearFee = currYearFee();
        if (msg.value < _currYearFee) revert InsufficientFunds();

        if (ageOf[commit] == 0) revert InvalidCommit();
        delete ageOf[commit];

        uint256 tokenId = uint256(bytes32(username));
        if (expiryYearOf[tokenId] != 0) revert Unauthorized();

        _mint(msg.sender, tokenId);

        unchecked {
            // this value is deterministic and cannot overflow for any known year
            expiryYearOf[tokenId] = currYear() + 1;
        }

        // TODO: this may fail if called by a smart contract
        if (msg.value > _currYearFee) {
            payable(msg.sender).transfer(msg.value - _currYearFee);
        }
    }

    /**
     * @notice Renew an expired name until the end of the year while in the renewal period
     *
     * @param tokenId the token id to register
     * @param owner the current owner of the name
     */
    function renew(uint256 tokenId, address owner) external payable {
        if (msg.value < fee) revert InsufficientFunds();

        if (_ownerOf[tokenId] != owner) revert InvalidOwner();

        uint256 expiryYear = expiryYearOf[tokenId];
        if (expiryYear == 0) revert NotMinted();

        unchecked {
            // this value is deterministic and cannot overflow for any known year
            uint256 expiryTs = timestampOfYear(expiryYear);
            if (block.timestamp >= expiryTs + gracePeriod || block.timestamp < expiryTs)
                revert NotRenewable();

            // this value is deterministic and cannot overflow for any known year
            expiryYearOf[tokenId] = currYear() + 1;
        }

        emit Renew(tokenId, owner, expiryYearOf[tokenId]);

        // TODO: this may fail if called by a smart contract
        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    function bid(uint256 tokenId) public payable {
        uint256 expiryYear = expiryYearOf[tokenId];
        if (expiryYear == 0) revert NotMinted();

        // Optimization: these operations might be safe to perform unchecked
        uint256 auctionStartTimestamp = timestampOfYear(expiryYear) + gracePeriod;
        if (auctionStartTimestamp > block.timestamp) revert NotAuctionable();

        // Calculate the number of 8 hour windows that have passed since the start of the auction
        // as a fixed point signed decimal number. The magic constant 3.57142857e13 approximates
        // division by 28,000 which is the number of seconds in an 8 hour period.
        int256 periodsSD59x18 = int256(3.57142857e13 * (block.timestamp - auctionStartTimestamp));

        // Calculate the price by determining the premium, which 1000 ether reduces by 10% for
        // every 8 hour period that has passed, and adding to it the renewal fee for the year.
        // Optimization: precompute return values for the first few periods and the last one.
        uint256 price = uint256(1000 ether).mulWadDown(
            uint256(FixedPointMathLib.powWad(int256(0.9 ether), periodsSD59x18))
        ) + currYearFee();

        if (msg.value < price) revert InsufficientFunds();

        _unsafeTransfer(msg.sender, tokenId);

        unchecked {
            // this value is deterministic and cannot overflow for any known year
            expiryYearOf[tokenId] = currYear() + 1;
        }

        // TODO: this may revert if called by a smart contract
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ERC-721 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    // balanceOf does not adhere strictly to the ERC-721 specification. If a tokenId is renewable
    // or expired, balanceOf will still return the count, but ownerOf will revert.

    function ownerOf(uint256 id) public view override returns (address) {
        uint256 expiryYear = expiryYearOf[id];

        if (expiryYear == 0) revert NotMinted();

        if (block.timestamp >= timestampOfYear(expiryYear)) revert Expired();

        return _ownerOf[id];
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override {
        if (block.timestamp >= timestampOfYear(expiryYearOf[id])) revert Expired();

        super.transferFrom(from, to, id);

        _clearRecovery(id);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, tokenId, ".json"));
    }

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     *                         INVARIANTS
     *
     * 2. Any change to ownerOf must set recoveryOf to address(0) and recoveryClockOf[id] to 0.
     *
     * 3. If the recoveryClockOf is non-zero, then recoveryDestinationOf must be non-zero, though
     *    the inverse is not guaranteed.
     */

    /**
     * @notice Choose a recovery address which has the ability to transfer the caller's username to
     *         a new address. The transfer happens in two steps - a request, and a complete which
     *         occurs after the escrow period has passed. During escrow, the custody address can
     *         cancel the transaction. The recovery address can be changed by the custody address
     *         at any time, or removed by setting it to 0x0. Changing a recovery address will not
     *         unset a currently active recovery request, that must be explicitly cancelled.
     *
     * @param recoveryAddress the address to set as the recovery.
     */
    function setRecoveryAddress(uint256 tokenId, address recoveryAddress) external payable {
        if (ownerOf(tokenId) != msg.sender) revert InvalidOwner();

        if (recoveryAddress == msg.sender) revert InvalidRecovery();

        recoveryOf[tokenId] = recoveryAddress;
        emit SetRecoveryAddress(recoveryAddress, tokenId);
    }

    /**
     * @notice Request a transfer of an existing username to a new address by calling this from
     *         the recovery address. The request can be completed after escrow period has passed.
     *
     * @param tokenId the uint256 representation of the username.
     * @param from the address that currently owns the id.
     * @param to the address to transfer the id to.
     */
    function requestRecovery(
        uint256 tokenId,
        address from,
        address to
    ) external payable {
        if (to == address(0)) revert InvalidRecovery();

        // Invariant 2 prevents unauthorized access if the name has been re-posessed by another.
        if (msg.sender != recoveryOf[tokenId]) revert Unauthorized();

        recoveryClockOf[tokenId] = block.timestamp;
        recoveryDestinationOf[tokenId] = to;

        emit RequestRecovery(tokenId, from, to);
    }

    /**
     * @notice Complete a transfer of an existing username to a new address by calling this  from
     *         the recovery address. The request can be completed if the escrow period has passed.
     *
     * @param tokenId the uint256 representation of the username.
     */
    function completeRecovery(uint256 tokenId) external payable {
        // Name cannot be recovered after it has expired
        if (block.timestamp >= timestampOfYear(expiryYearOf[tokenId])) revert Unauthorized();

        // Invariant 2 prevents unauthorized access if the name has been re-posessed by another.
        if (msg.sender != recoveryOf[tokenId]) revert Unauthorized();

        if (recoveryClockOf[tokenId] == 0) revert NoRecovery();

        unchecked {
            // this value is set to a block.timestamp and cannot realistically overflow
            if (block.timestamp < recoveryClockOf[tokenId] + escrowPeriod) revert InEscrow();
        }

        // Invariant 3 prevents this from going to a null address.
        _unsafeTransfer(recoveryDestinationOf[tokenId], tokenId);
    }

    /**
     * @notice Cancel the recovery of an existing username by calling this function from a recovery
     *         or custody address. The request can be completed if the escrow period has passed.
     *
     * @param tokenId the uint256 representation of the username.
     */
    function cancelRecovery(uint256 tokenId) external payable {
        if (msg.sender != ownerOf(tokenId) && msg.sender != recoveryOf[tokenId])
            revert Unauthorized();

        if (recoveryClockOf[tokenId] == 0) revert NoRecovery();

        emit CancelRecovery(tokenId);
        delete recoveryClockOf[tokenId];
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Move the username from the current owner to the vault and renew it for another year
     *
     * @param tokenId the uint256 representation of the username.
     */
    function reclaim(uint256 tokenId) external payable onlyOwner {
        if (expiryYearOf[tokenId] == 0) revert NotMinted();

        unchecked {
            // this value is deterministic and cannot overflow for any known year
            expiryYearOf[tokenId] = currYear() + 1;
        }

        _unsafeTransfer(vault, tokenId);

        emit Reclaim(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                          YEARLY PAYMENTS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the timestamp of Jan 1, 0:00:00 for the given year.
     */
    function timestampOfYear(uint256 year) public view returns (uint256) {
        if (year <= 2021) revert InvalidTime();
        return _yearTimestamps[year - 2022];
    }

    /**
     * @notice Returns the current year for any year between 2021 and 2037.
     */
    function currYear() public returns (uint256 year) {
        // _nextYearIdx is a known index and can never overflow for anyknown value.
        unchecked {
            if (block.timestamp < _yearTimestamps[_nextYearIdx]) {
                return _nextYearIdx + 2021;
            }

            uint256 length = _yearTimestamps.length;

            for (uint256 i = _nextYearIdx + 1; i < length; ) {
                if (_yearTimestamps[i] > block.timestamp) {
                    _nextYearIdx = i;
                    return _nextYearIdx + 2021;
                }
                i++;
            }

            revert InvalidTime();
        }
    }

    /**
     * @notice Returns the ETH requires to register a name for the rest of the year.
     */
    function currYearFee() public returns (uint256) {
        uint256 _currYear = currYear();

        unchecked {
            // this value is deterministic and cannot overflow for any known time
            uint256 nextYearTimestamp = timestampOfYear(_currYear + 1);

            return
                ((nextYearTimestamp - block.timestamp) * fee) /
                (nextYearTimestamp - timestampOfYear(_currYear));
        }
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Moves the username to the destination and resets any recovery state. It is similar
     *  to transferFrom, but doesn't check ownership of the token or validity of the destination to
     * save gas, which must be ensured by the caller.
     */
    function _unsafeTransfer(address to, uint256 tokenId) internal {
        address from = _ownerOf[tokenId];

        if (from == address(0)) revert Unauthorized();

        // Underflow is prevented as long as the ownership is verified and overflow is unrealistic
        // given the limited set of usernames available.
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[tokenId] = to;

        delete getApproved[tokenId];

        _clearRecovery(tokenId);

        emit Transfer(from, to, tokenId);
    }

    function _clearRecovery(uint256 tokenId) internal {
        if (recoveryClockOf[tokenId] != 0) delete recoveryClockOf[tokenId];

        delete recoveryOf[tokenId];
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

            // i can never overflow because length is guaranteed to be < 16
            unchecked {
                i++;
            }
        }
        return true;
    }
}
