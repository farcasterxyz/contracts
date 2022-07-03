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
error NotForAuction(); // The username is not yet up for auction.
error Expired(); // The username is expired.

error RecoveryAddressInvalid(); // The address is the custody address for the id and cannot also become its recovery address

error RecoveryNotFound(); // The recovery request for this id could not be found

error RecoveryInEscrow(); // The recovery request is still in escrow

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

    // Mapping from tokenId to recovery address
    mapping(uint256 => address) public recoveryOf;

    // Mapping from tokenId to recovery start (in blocks)
    mapping(uint256 => uint256) public recoveryClockOf;

    // Mapping from tokenId to recovery destination address
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

    // TODO: Replace it with an external smart contract.
    address public vault = address(this);

    uint256 escrowPeriod = 3 days;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        address _owner
    ) ERC721(_name, _symbol) Owned(_owner) {}

    /*//////////////////////////////////////////////////////////////
                            TIME & MONEY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the timestamp of Jan 1, 0:00:00 for the given year.
     *
     * @param year the gregorian calendar year to fetch the timestamp for.
     */
    function timestampOfYear(uint256 year) public view returns (uint256) {
        if (year <= 2021) revert InvalidTime();
        return _yearTimestamps[year - 2022];
    }

    /**
     * @notice Returns the current year, for any year until 2122.
     */
    function currentYear() public returns (uint256 year) {
        // If the year is too early, this will always return 2021, but that is impossible since
        // the contract is launched in 2022
        if (block.timestamp < _yearTimestamps[_nextYearIdx]) {
            return _nextYearIdx + 2021;
        }

        uint256 startIdx = _nextYearIdx + 1;
        uint256 length = _yearTimestamps.length;

        for (uint256 i = startIdx; i < length; ) {
            if (_yearTimestamps[i] > block.timestamp) {
                _nextYearIdx = i;
                return _nextYearIdx + 2021;
            }
            unchecked {
                i++;
            }
        }

        revert InvalidTime();
    }

    /**
     * @notice Returns the  eth required to register a username for the remainder of the year,
     *         which is prorated by the amount of time left in the year.
     */
    function currentYearPayment() public returns (uint256) {
        // TODO: Test for overflows
        uint256 currentYearValue = currentYear();
        uint256 nextYearTimestamp = timestampOfYear(currentYearValue + 1);

        uint256 timeLeftInYear = nextYearTimestamp - block.timestamp;
        uint256 timeInYear = nextYearTimestamp - timestampOfYear(currentYearValue);

        return (timeLeftInYear * fee) / timeInYear;
    }

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

        if (msg.value < currentYearPayment()) revert InsufficientFunds();
        if (ageOf[commit] == 0) revert InvalidCommit();

        // The username is minted, and can no longer be registered, only renewed or reclaimed.
        // TODO: Evaluate this byte conversion.
        uint256 tokenId = uint256(bytes32(username));
        if (expiryYearOf[tokenId] != 0) revert Unauthorized();

        _mint(msg.sender, tokenId);

        expiryYearOf[tokenId] = currentYear() + 1;

        // Release the commit value and refund
        commit = 0;

        // TODO: this may fail if called by a smart contract
        if (msg.value > currentYearPayment()) {
            payable(msg.sender).transfer(msg.value - currentYearPayment());
        }
    }

    function renew(uint256 tokenId, address owner) external payable {
        if (msg.value < fee) revert InsufficientFunds();

        // TODO: is this check necessary? can you just renew it to its current owner?
        if (_ownerOf[tokenId] != owner) revert InvalidOwner();

        uint256 expiryYear = expiryYearOf[tokenId];
        if (expiryYear == 0) revert NotMinted();

        // The name is not in the renewal period
        uint256 expiryTs = timestampOfYear(expiryYear);
        if (block.timestamp >= expiryTs + gracePeriod || block.timestamp < expiryTs)
            revert NotRenewable();

        // TODO: check that this 3 way assignment works as expected and saves gas
        expiryYear = expiryYearOf[tokenId] = currentYear() + 1;

        emit Renew(tokenId, owner, expiryYear);

        // TODO: test that renewal can happen from any address.

        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    function bid(uint256 tokenId) public payable {
        uint256 expiryYear = expiryYearOf[tokenId];
        if (expiryYear == 0) revert NotMinted();

        // The username has been minted, but is not out of the grace period.
        uint256 auctionStartTimestamp = timestampOfYear(expiryYear) + gracePeriod;
        if (auctionStartTimestamp > block.timestamp) revert NotForAuction();

        // Calculate the number of 8 hour windows that have passed since the start of the auction
        // as a fixed point signed decimal number. The magic constant 3.57142857e13 approximates
        // division by 28,000 which is the number of seconds in an 8 hour period.
        int256 periodsSD59x18 = int256(3.57142857e13 * (block.timestamp - auctionStartTimestamp));

        // Calculate the price by determining the premium, which 1000 ether reduces by 10% for
        // every 8 hour period that has passed, and adding to it the renewal fee for the year.
        // Optimization: precompute return values for the first few periods and the last one.
        uint256 price = uint256(1000 ether).mulWadDown(
            uint256(FixedPointMathLib.powWad(int256(0.9 ether), periodsSD59x18))
        ) + currentYearPayment();

        if (msg.value < price) revert InsufficientFunds();

        _unsafeTransfer(msg.sender, tokenId);

        expiryYearOf[tokenId] = currentYear() + 1;

        // TODO: this may revert if called by a smart contract
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ERC-721 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, tokenId, ".json"));
    }

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
        // If the registration is expired, no one currently owns it
        if (block.timestamp >= timestampOfYear(expiryYearOf[id])) revert Expired();

        super.transferFrom(from, to, id);

        _clearRecovery(id);
    }

    /*//////////////////////////////////////////////////////////////
                             RECOVERY LOGIC
    //////////////////////////////////////////////////////////////*/

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

        if (recoveryAddress == msg.sender) revert RecoveryAddressInvalid();

        // Statement: you are allowed to set a recovery address even after your ownership has expired.
        // We must ensure that any kind of request or completion cannot be performed in such a case.

        recoveryOf[tokenId] = recoveryAddress;
        emit SetRecoveryAddress(recoveryAddress, tokenId);
    }

    /**
     * @notice Request a transfer of an existing username to a new address by calling this from
     *         the recovery address. The request can be completed after escrow period has passed.
     *
     * @param tokenId the uint256 representation of the username.
     *
     * @param from the address that currently owns the id.
     *
     * @param to the address to transfer the id to.
     */
    function requestRecovery(
        uint256 tokenId,
        address from,
        address to
    ) external payable {
        // Do not allow recovery 3 days before the expiration of the name since complete will not
        // work anyway
        if (block.timestamp >= timestampOfYear(expiryYearOf[tokenId]) - escrowPeriod)
            revert Unauthorized();

        // Invariant: if the token is unminted, then recoveryOf will also be set to null
        if (msg.sender != recoveryOf[tokenId]) revert Unauthorized();

        if (to == address(0)) revert RecoveryAddressInvalid();

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
        // TODO: two error naming styles (NotRecoveralke) vs. (RecoveryInEscrow) - standardize them
        // Name cannot be recovered after it has expired
        if (block.timestamp >= timestampOfYear(expiryYearOf[tokenId])) revert Unauthorized();

        if (msg.sender != recoveryOf[tokenId]) revert Unauthorized();

        // Invariant: if a transfer is performed, this would have been reset to zero, so we don't need
        // to worry about this
        if (recoveryClockOf[tokenId] == 0) revert RecoveryNotFound();

        if (block.timestamp < recoveryClockOf[tokenId] + escrowPeriod) revert RecoveryInEscrow();

        // Investigate: seems like potential for mischief if a single token is recovery of two different
        // addresses and a recovery is completed after one is reset.
        _unsafeTransfer(recoveryDestinationOf[tokenId], tokenId);

        recoveryClockOf[tokenId] = 0;
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
        if (recoveryClockOf[tokenId] == 0) revert RecoveryNotFound();

        emit CancelRecovery(tokenId);
        recoveryClockOf[tokenId] = 0;
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    function reclaim(uint256 tokenId) external payable onlyOwner {
        // The username has never been minted
        if (expiryYearOf[tokenId] == 0) revert NotMinted();

        // Must ensure that the expiry is set to next year, otherwise reclaiming a name in auction
        // may allow someone to purchase it back immediately.
        expiryYearOf[tokenId] = currentYear() + 1;

        _unsafeTransfer(vault, tokenId);

        emit Reclaim(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    // Does not check that the transaction comes from the sender of the message (caller must ensure authority, required)
    // Does not check for 0x0 address (caller must ensure this, saves gas)
    // Does not allow approved senders to perform operations -- they should caller transfer from.

    function _unsafeTransfer(address to, uint256 tokenId) internal {
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

        _clearRecovery(tokenId);

        emit Transfer(from, to, tokenId);
    }

    function _clearRecovery(uint256 tokenId) internal {
        // since this is rarely true, checking before assigning is more gas efficient
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

            // This is safe because name.length will never exceed 16 since it is a bytes16
            unchecked {
                i++;
            }
        }
        return true;
    }
}
