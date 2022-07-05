// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {ERC721} from "../lib/solmate/src/tokens/ERC721.sol";

import {Owned} from "../lib/solmate/src/auth/Owned.sol";

import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";

error InsufficientFunds(); // The transaction does not have enough money to pay for this.
error Unauthorized(); // The caller is not authorized to perform this action.

error InvalidCommit(); // The commitment hash was not found
error InvalidName(); // The username had invalid characters
error InvalidTime(); // Time is too far in the future or past
error IncorrectOwner(); // The username is not owned by the expected address

error Registered(); // The username is registered.
error NotRegistered(); // The username has never been registered.
error Expired(); // The username is expired.
error NotExpired(); // The username is still registered or in renewal.

error InEscrow(); // The recovery request is still in escrow
error NoRecovery(); // The recovery request could not be found
error InvalidRecovery(); // The recovery address is being set to the custody address

/**
 * @title Namespace
 * @author varunsrin
 */
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

    // Mapping from commitment hash to state
    mapping(bytes32 => bool) public stateOf;

    // Mapping from tokenID to expiration year
    mapping(uint256 => uint256) public expiryOf;

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

    uint256 public immutable gracePeriod = 30 days;

    uint256 public immutable fee = 0.01 ether;

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

    address public immutable vault;

    uint256 immutable escrowPeriod = 3 days;

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
     * INVARIANT 1A: If an id is not minted, expiryOf[id] must be 0 and  _ownerOf[id] and
     *               recoveryOf[id] must also be address(0).
     *
     * INVARIANT 1B: If an id is minted, expiryOf[id] and _ownerOf[id] must be non-zero.
     *
     * INVARIANT 2: A username cannot be transferred to address(0) after it is minted.
     */

    /**
     * @notice Generate a commitment hash used to secretly lock down a username for registration.
     *
     * @dev The commitment process prevents front-running of the username registration.
     *
     * @param username the username to be registered
     * @param owner the address that will own the username
     * @param secret a salt that randomizes and secures the commitment hash
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
     * @notice Save a generated commitment hash on-chain, which must be done before a registration
     *         can occur
     *
     * @dev The commitment process prevents front-running of the username registration.
     *
     * @param commit the commitment hash to be persisted on-chain
     */
    function makeCommit(bytes32 commit) public {
        stateOf[commit] = true;
    }

    /**
     * @notice Mint a new username if a commitment was made previously and send it to the owner.
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

        if (!stateOf[commit]) revert InvalidCommit();
        delete stateOf[commit];

        uint256 tokenId = uint256(bytes32(username));
        if (expiryOf[tokenId] != 0) revert Unauthorized();

        _mint(owner, tokenId);

        unchecked {
            // currYear is selected from a pre-determined list and cannot overflow
            expiryOf[tokenId] = timestampOfYear(currYear() + 1);
        }

        // TODO: this may fail if called by a smart contract
        if (msg.value > _currYearFee) {
            payable(msg.sender).transfer(msg.value - _currYearFee);
        }
    }

    /**
     * @notice Renew a name for another year while it is in the renewable period
     *
     * @param tokenId the tokenId of the name to renew
     * @param owner the current owner of the name
     */
    function renew(uint256 tokenId, address owner) external payable {
        if (msg.value < fee) revert InsufficientFunds();

        uint256 expiryTs = expiryOf[tokenId];
        if (expiryTs == 0) revert NotRegistered();

        // Invariant 1B + 2 guarantee that the name is not owned by address(0) at this point.
        if (_ownerOf[tokenId] != owner) revert IncorrectOwner();

        unchecked {
            // renewTs and gracePeriod are pre-determined values and cannot overflow
            if (block.timestamp >= expiryTs + gracePeriod) revert Expired();

            if (block.timestamp < expiryTs) revert Registered();

            // currYear is selected from a pre-determined list and cannot overflow
            expiryOf[tokenId] = timestampOfYear(currYear() + 1);
        }

        emit Renew(tokenId, owner, expiryOf[tokenId]);

        // TODO: this may fail if called by a smart contract
        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    /**
     * @notice Bid to purchase an expired username in the dutch auction, whose price is the sum of
     *         the current year's fee and a premium. The premium is set to 1000 ether on Feb 1st
     *         and decays by ~10% per period (8 hours) until it reaches zero mid-year.
     *
     * @dev The premium reduction is computed with the identity (x^y = exp(ln(x) * y)) with
     *      gas-optimzied approximations for exp and ln that introduce a -3% error for every period
     *
     * @param tokenId the tokenId of the username to bid on
     */
    function bid(uint256 tokenId) public payable {
        uint256 expiryTs = expiryOf[tokenId];
        if (expiryTs == 0) revert NotRegistered();

        // Optimization: these operations might be safe to perform unchecked
        uint256 auctionStartTimestamp;

        unchecked {
            // timestampOfYear is taken from a pre-determined list and cannot overflow.
            auctionStartTimestamp = expiryTs + gracePeriod;
        }

        if (auctionStartTimestamp > block.timestamp) revert NotExpired();

        // Calculate the num of 8 hr periods since expiry as a fixed point signed decimal. The
        // constant approximates fixed point division by 28,000 (num of seconds in 8 hours)
        int256 periodsSD59x18 = int256(3.57142857e13 * (block.timestamp - auctionStartTimestamp));

        // Optimization: precompute return values for the first few periods and the last one.

        // Calculate the price by taking the 1000 ETH premium and discounting it by 10% for every
        // period and adding to it the renewal fee for the current year.
        uint256 price = uint256(1_000 ether).mulWadDown(
            uint256(FixedPointMathLib.powWad(int256(0.9 ether), periodsSD59x18))
        ) + currYearFee();

        if (msg.value < price) revert InsufficientFunds();

        _unsafeTransfer(msg.sender, tokenId);

        unchecked {
            // currentYear is taken from a pre-determined list and cannot overflow
            expiryOf[tokenId] = timestampOfYear(currYear() + 1);
        }

        // TODO: this may revert if called by a smart contract
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ERC-721 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Override the ownerOf implementation to throw if a username is expired or renewable.
     */
    function ownerOf(uint256 tokenId) public view override returns (address) {
        uint256 expiryTs = expiryOf[tokenId];

        // Invariant 1A will ensure a throw if a name was not minted, as per the ERC-721 spec.
        if (expiryTs == 0) revert NotRegistered();

        if (block.timestamp >= expiryTs) revert Expired();

        return _ownerOf[tokenId];
    }

    // balanceOf does not work as expected and also includes names that have become renewable or
    // expired. tracking correct status would incur significant gas costs and has been avoided.

    /**
     * @notice Override the ownerOf implementation to throw if a username is expired or renewable
     *          and to clear the recovery address if it is set.
     */
    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override {
        if (block.timestamp >= expiryOf[id]) revert Expired();

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
     * The custodyAddress (i.e. owner) can appoint a recoveryAddress which can transfer a
     * specific username if the custodyAddress is lost. The recovery address must first request the
     * transfer on-chain which moves it into escrow. If the custodyAddress does not cancel
     * the request during escrow, the recoveryAddress can then transfer the username. The custody
     * address can remove or change the recovery address at any time.
     *
     * INVARIANT 3: Changing ownerOf must set recoveryOf to address(0) and recoveryClockOf[id] to 0
     *
     * INVARIANT 4: If the recoveryClockOf is non-zero, then recoveryDestinationOf is non-zero.
     */

    /**
     * @notice Set a recovery address which can transfer the caller's username to a new address.
     *
     * @param recoveryAddress the recoveryAddress, which must not be the custodyAddress. It can be
     *                        set to zero to disable the recovery functionality.
     */
    function setRecoveryAddress(uint256 tokenId, address recoveryAddress) external payable {
        if (ownerOf(tokenId) != msg.sender) revert Unauthorized();

        if (recoveryAddress == msg.sender) revert InvalidRecovery();

        recoveryOf[tokenId] = recoveryAddress;
        emit SetRecoveryAddress(recoveryAddress, tokenId);
    }

    /**
     * @notice Request a transfer of a username if the caller is the recoveryAddress
     *
     * @param tokenId the uint256 representation of the username.
     * @param from the address that currently owns the username.
     * @param to the address to transfer the username to, which cannot be address(0).
     */
    function requestRecovery(
        uint256 tokenId,
        address from,
        address to
    ) external payable {
        if (to == address(0)) revert InvalidRecovery();

        // Invariant 3 ensures that a recovery request cannot be made directly after a change of
        // ownership without explicit consent from the new owner
        if (msg.sender != recoveryOf[tokenId]) revert Unauthorized();

        recoveryClockOf[tokenId] = block.timestamp;
        recoveryDestinationOf[tokenId] = to;

        emit RequestRecovery(tokenId, from, to);
    }

    /**
     * @notice Completes a transfer request if the escrow period has passed and the caller is the
     *         recoveryAddress.
     *
     * @param tokenId the uint256 representation of the username.
     */
    function completeRecovery(uint256 tokenId) external payable {
        // Name cannot be recovered after it has expired
        if (block.timestamp >= expiryOf[tokenId]) revert Unauthorized();

        // Invariant 3 prevents unauthorized access if the name has been re-posessed by another.
        if (msg.sender != recoveryOf[tokenId]) revert Unauthorized();

        // Invariant 3 ensures that a recovery request cannot be compeleted after a change of
        // ownership without explicit consent from the new owner
        if (recoveryClockOf[tokenId] == 0) revert NoRecovery();

        unchecked {
            // recoveryClockOf is always set to block.timestamp and cannot realistically overflow
            if (block.timestamp < recoveryClockOf[tokenId] + escrowPeriod) revert InEscrow();
        }

        // Invariant 4 prevents this from going to a null address.
        _unsafeTransfer(recoveryDestinationOf[tokenId], tokenId);
    }

    /**
     * @notice Cancels a transfer request if the caller is the recoveryAddress or the
     *         custodyAddress
     *
     * @dev Cancellation is permitted even if the username is in the renewable or expired state,
     *      it is a more gas-efficient check and has no adverse effects.
     *
     * @param tokenId the uint256 representation of the username.
     */
    function cancelRecovery(uint256 tokenId) external payable {
        if (msg.sender != _ownerOf[tokenId] && msg.sender != recoveryOf[tokenId])
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
        if (expiryOf[tokenId] == 0) revert NotRegistered();

        unchecked {
            // this value is deterministic and cannot overflow for any known year
            expiryOf[tokenId] = timestampOfYear(currYear() + 1);
        }

        _unsafeTransfer(vault, tokenId);

        emit Reclaim(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                          YEARLY PAYMENTS LOGIC
    //////////////////////////////////////////////////////////////*/

    // Optimization: these could be made private functions which may slightly reduce their gas
    // cost in solidity, though we would need to rewrite the tests accordingly.

    /**
     * @notice Returns the timestamp of Jan 1, 0:00:00 for the given year.
     */
    function timestampOfYear(uint256 year) public view returns (uint256) {
        unchecked {
            if (year <= 2021) revert InvalidTime();

            // year can never underflow because we check its value, or overflow because of subtract
            return _yearTimestamps[year - 2022];
        }
    }

    /**
     * @notice Returns the current year for any year between 2021 and 2037.
     */
    function currYear() public returns (uint256 year) {
        unchecked {
            // _nextYearIdx is a predetermined value and can never overflow.
            if (block.timestamp < _yearTimestamps[_nextYearIdx]) {
                return _nextYearIdx + 2021;
            }

            uint256 length = _yearTimestamps.length;

            for (uint256 i = _nextYearIdx + 1; i < length; ) {
                if (_yearTimestamps[i] > block.timestamp) {
                    _nextYearIdx = i;
                    // _nextYearIdx is a predetermined value and can never overflow.
                    return _nextYearIdx + 2021;
                }

                // length and _nextyearIdx are predetermined values and can never overflow.
                i++;
            }

            revert InvalidTime();
        }
    }

    /**
     * @notice Returns the ETH requires to register a name for the rest of the year.
     *
     * @dev the fee is pro-rated for the remainder of the year by the number of seconds left.
     */
    function currYearFee() public returns (uint256) {
        uint256 _currYear = currYear();

        unchecked {
            // timestampOfYear and currYear are pretermined values and cannot overflow.
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
     * @dev Moves the username to the destination and resets recovery state. Similar to
     *      transferFrom but more gas-efficient since it doesn't check ownership or destination
     *      validity which can be ensured by the caller explicitly or implicitly.
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

    /**
     * @dev Resets the recoveryAddress and any ongoing recoveries
     */
    function _clearRecovery(uint256 tokenId) internal {
        // Checking state before clearing is more gas-efficient than always clearing
        if (recoveryClockOf[tokenId] != 0) delete recoveryClockOf[tokenId];

        delete recoveryOf[tokenId];
    }

    /**
     * @dev Returns true if the name is only composed of [a-z0-9] and the hyphen characters.
     */
    function _isValidUsername(bytes16 name) internal pure returns (bool) {
        uint256 length = name.length;

        for (uint256 i = 0; i < length; ) {
            uint8 charInt = uint8(name[i]);
            // Optimize: consider using a bitmask to check for valid characters which may be more
            // efficient.
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
