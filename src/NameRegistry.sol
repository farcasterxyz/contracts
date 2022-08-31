// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ContextUpgradeable} from "openzeppelin-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {ERC721Upgradeable} from "openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC2771ContextUpgradeable} from "openzeppelin-upgradeable/contracts/metatx/ERC2771ContextUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";

import {UUPSUpgradeable} from "openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/**
 * @title NameRegistry
 * @author varunsrin
 */
contract NameRegistry is
    Initializable,
    ERC721Upgradeable,
    ERC2771ContextUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientFunds(); // The transaction does not have enough money to pay for this.
    error Unauthorized(); // The caller is not authorized to perform this action.
    error CallFailed(); // Could not .call to transfer the funds

    error InvalidCommit(); // The commitment hash was not found
    error InvalidName(); // The username had invalid characters
    error InvalidTime(); // Time is too far in the future or past
    error IncorrectOwner(); // The username is not owned by the expected address

    error Registered(); // The username is currently registered.
    error NotRegistrable(); // The username has been registered and cannot be registered again.
    error Registrable(); // The username has never been registered.

    error Expired(); // The username is expired (renewable or biddable)
    error Biddable(); // The username is biddable
    error NotBiddable(); // The username is still registered or in renewal.

    error Escrow(); // The recovery request is still in escrow
    error NoRecovery(); // The recovery request could not be found
    error InvalidRecovery(); // The recovery address is being set to the custody address

    error NotAdmin();
    error NotOperator();
    error NotModerator();
    error NotTreasurer();

    error WithdrawTooMuch(); // Could not withdraw the requested amount

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Renew(uint256 indexed tokenId, uint256 expiry);

    event ChangeRecoveryAddress(uint256 indexed tokenId, address indexed recovery);

    event RequestRecovery(address indexed from, address indexed to, uint256 indexed id);

    event CancelRecovery(uint256 indexed id);

    event ChangeVault(address indexed vault);

    event ChangePool(address indexed pool);

    event ChangeTrustedSender(address indexed trustedSender);

    event DisableTrustedRegister();

    event ChangeFee(uint256 fee);

    event Invite(uint256 indexed inviterId, uint256 indexed inviteeId, bytes16 indexed username);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// WARNING - DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
    /// Any changes before deployment should be replicated to NameRegistryV2 in NameRegistryUpdate.t.sol

    // Audit: These variables are kept public to make it easier to test the contract, since using the same inherit
    // and extend trick that we used for IDRegistry is harder to pull off here due to the UUPS structure.

    /// @notice The fee to renew a name for a full calendar year
    uint256 public fee;

    /// @notice The address controlled by the Farcaster Invite service that is allowed to call trustedRegister
    address public trustedSender;

    /// @notice Flag that determines if registration can occur through trustedRegister or register
    /// @dev This value is initialized to 1 can only be changed to zero
    uint256 public trustedRegisterEnabled;

    /// @notice Returns the block.timestamp of a commit
    mapping(bytes32 => uint256) public timestampOf;

    /// @notice Returns the expiration timestamp of a farcaster name
    mapping(uint256 => uint256) public expiryOf;

    /// @notice The address that funds can be withdrawn to
    address public vault;

    /// @notice The address that names can be reclaimed to
    address public pool;

    /// @notice Contains the timestamps of Jan 1, 0:00:00 GMT for each year from 2022 to 2072
    uint256[] internal _yearTimestamps;

    /// @notice The index of _yearTimestamps which will return the timestamp of Jan 1st of the next calendar year
    uint256 internal _nextYearIdx;

    /// @notice Returns the recovery address for a farcaster name
    mapping(uint256 => address) public recoveryOf;

    /// @notice Returns the block timestamp if there is an active recovery for a farcaster name, or 0 if none
    mapping(uint256 => uint256) public recoveryClockOf;

    /// @notice Returns the destination address for the most recent recovery attempt for a farcaster id
    /// @dev This value is left dirty to save gas and should not be used to determine the state of a recovery
    mapping(uint256 => address) public recoveryDestinationOf;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    string internal constant BASE_URI = "http://www.farcaster.xyz/u/";

    uint256 internal constant GRACE_PERIOD = 30 days;

    uint256 internal constant ESCROW_PERIOD = 3 days;

    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    bytes32 internal constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    bytes32 internal constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTORS AND INITIALIZERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Disables initialization to prevent attacks and only calls the ERC2771ContextUpgradeable constructor.
     *      All other storage values must be initialized in the implementation function. For more details:
     *
     * https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#initializing_the_implementation_contract
     * https://github.com/OpenZeppelin/openzeppelin-contracts/pull/2917
     */
    // solhint-disable-next-line no-empty-blocks
    constructor(address _forwarder) ERC2771ContextUpgradeable(_forwarder) {
        // Audit: Is this the safest way to prevent contract initialization attacks?
        // See: https://twitter.com/z0age/status/1551951489354145795
        _disableInitializers();
    }

    /**
     *  @dev Initializes the contract with default values and calls the initialize functions on the Base contracts. The
     *       constructor ensures that this function can never be called directly on the implementation contract itself,
     *       but only via the ERC1967 proxy  contract, which prevents initialize attacks. For more details:
     *
     *       https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies#the-constructor-caveat
     *       https://forum.openzeppelin.com/t/uupsupgradeable-vulnerability-post-mortem/15680
     *
     *       Slither: incorrectly flags this method as unprotected: https://github.com/crytic/slither/issues/1341
     */
    function initialize(
        string memory _tokenName,
        string memory _tokenSymbol,
        address _vault,
        address _pool
    ) external initializer {
        __ERC721_init(_tokenName, _tokenSymbol);

        __Pausable_init();

        __AccessControl_init();

        __UUPSUpgradeable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        vault = _vault;

        pool = _pool;

        // Audit: verify the accuracy of these timestamps using an alternative calculator
        // epochconverter.com was used to generate these
        _yearTimestamps = [
            1640995200, // 2022
            1672531200,
            1704067200,
            1735689600,
            1767225600,
            1798761600,
            1830297600,
            1861920000,
            1893456000,
            1924992000,
            1956528000, // 2032
            1988150400,
            2019686400,
            2051222400,
            2082758400,
            2114380800,
            2145916800,
            2177452800,
            2208988800,
            2240611200,
            2272147200, // 2042
            2303683200,
            2335219200,
            2366841600,
            2398377600,
            2429913600,
            2461449600,
            2493072000,
            2524608000,
            2556144000,
            2587680000, // 2052
            2619302400,
            2650838400,
            2682374400,
            2713910400,
            2745532800,
            2777068800,
            2808604800,
            2840140800,
            2871763200,
            2903299200, // 2062
            2934835200,
            2966371200,
            2997993600,
            3029529600,
            3061065600,
            3092601600,
            3124224000,
            3155760000,
            3187296000,
            3218832000 // 2072
        ];

        fee = 0.01 ether;

        trustedRegisterEnabled = 1;
    }

    /*//////////////////////////////////////////////////////////////
                           REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * INVARIANT 1A: If an id is not minted, expiryOf[id] must be 0 and ownerOf(id) and
     *               recoveryOf[id] must also be address(0).
     *
     * INVARIANT 1B: If an id is minted, expiryOf[id] and ownerOf(id) must be non-zero.
     *
     * INVARIANT 2: A username cannot be transferred to address(0) after it is minted.
     */

    /**
     * @notice Generate a commitment hash used to secretly lock down a username for registration.
     *
     * @dev The commitment process prevents front-running of the username registration.
     *
     * @param username the username to be registered
     * @param to the address that will own the username
     * @param secret a salt that randomizes and secures the commitment hash
     */
    function generateCommit(
        bytes16 username,
        address to,
        bytes32 secret
    ) public pure returns (bytes32) {
        _validateName(username);
        return keccak256(abi.encode(username, to, secret));
    }

    /**
     * @notice Save a generated commitment hash on-chain, which must be done before a registration
     *         can occur
     *
     * @dev The commitment process prevents front-running of the username registration. Commits can be made even when
     *      the contract is paused because it does not affect frontrunning.
     *
     * @param commit the commitment hash to be persisted on-chain
     */
    function makeCommit(bytes32 commit) external payable {
        if (trustedRegisterEnabled == 1) revert NotRegistrable();

        timestampOf[commit] = block.timestamp;
    }

    /**
     * @notice Mint a new username if a commitment was made previously and send it to the owner.
     *
     * @dev The registration must be made at least 5 blocks after commit to minimize front-running,
     * or approximately 1 minute after commit. The function is pauseable since it invokes _transfer
     * by way of _mint.
     *
     * @param username the username to register
     * @param to the address that will claim the username
     * @param secret the secret that protects the commitment
     * @param recovery address which can recovery the username if the custody address is lost
     */
    function register(
        bytes16 username,
        address to,
        bytes32 secret,
        address recovery
    ) external payable {
        bytes32 commit = generateCommit(username, to, secret);

        uint256 _currYearFee = currYearFee();
        if (msg.value < _currYearFee) revert InsufficientFunds();

        // Assumption: timestampOf[commit] will always be zero while trustedRegisterEnabled = 1
        // causing this to fail, since makeCommit reverts when trustedRegisterEnabled = 1.
        uint256 commitTs = timestampOf[commit];

        if (commitTs == 0) revert InvalidCommit();

        unchecked {
            // Audit: verify that 60s is the right duration to use

            // Safety: commitTs is always set to block.timestamp in makeCommit and cannot overflow
            if (commitTs + 60 > block.timestamp) revert InvalidCommit();
        }

        // Safety: this interaction is performed before the checks below, because the commit
        // should be released if the name was invalid and the transaction reverted.
        delete timestampOf[commit];

        // Assumption: checking that to is non-zero and that the tokenId wasn't previously issued
        // is handled inside _mint before any state change is made.
        uint256 tokenId = uint256(bytes32(username));
        _mint(to, tokenId);

        unchecked {
            // Safety: _currYear is guaranteed to be a known gregorian calendar year and cannot overflow
            expiryOf[tokenId] = _timestampOfYear(currYear() + 1);
        }

        recoveryOf[tokenId] = recovery;

        // Safety: usage of call over transfer or send is encouraged to protect against gas pricing changes
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = _msgSender().call{value: msg.value - _currYearFee}("");
        if (!success) revert CallFailed();
    }

    /**
     * @notice Mint a username during the invitation period from the trusted sender.
     *
     * @dev The function is pauseable since it invokes _transfer by way of _mint.
     *
     * @param to the address that will claim the username
     * @param username the username to register
     * @param recovery address which can recovery the username if the custody address is lost
     */
    function trustedRegister(
        bytes16 username,
        address to,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) external payable {
        if (trustedRegisterEnabled == 0) revert Registrable();

        // Assumption: front running is not possible when registrations are restricted to a single sender
        if (_msgSender() != trustedSender) revert Unauthorized();

        _validateName(username);

        // Assumption: checking that to is non-zero and that the tokenId wasn't previously issued
        // is handled inside _mint before any state change is made.
        uint256 tokenId = uint256(bytes32(username));
        _mint(to, tokenId);

        unchecked {
            // Safety: _currYear must return a known calendar year which cannot overflow here
            expiryOf[tokenId] = _timestampOfYear(currYear() + 1);
        }

        recoveryOf[tokenId] = recovery;

        emit Invite(inviter, invitee, username);
    }

    /**
     * @notice Renew a name for another year while it is in the renewable period
     *
     * @param tokenId the tokenId of the name to renew
     */
    function renew(uint256 tokenId) external payable whenNotPaused {
        if (msg.value < fee) revert InsufficientFunds();

        uint256 expiryTs = expiryOf[tokenId];
        if (expiryTs == 0) revert Registrable();
        // Assumption: tokenID is not owned by address(0) because of INVARIANT 1B + 2

        unchecked {
            // Safety: expiryTs is a timestamp of a known calendar year and adding it to
            // GRACE_PERIOD cannot overflow
            if (block.timestamp >= expiryTs + GRACE_PERIOD) revert Biddable();
        }

        if (block.timestamp < expiryTs) revert Registered();

        unchecked {
            // Safety: _currYear must return a known calendar year which cannot overflow here
            expiryOf[tokenId] = _timestampOfYear(currYear() + 1);
        }

        emit Renew(tokenId, expiryOf[tokenId]);

        // Safety: usage of call over transfer or send is encouraged to protect against gas pricing changes
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = _msgSender().call{value: msg.value - fee}("");
        if (!success) revert CallFailed();
    }

    /**
     * @notice Bid to purchase an expired username in the dutch auction, whose price is the sum of
     *         the current year's fee and a premium. The premium is set to 1000 ether on Feb 1st
     *         and decays by ~10% per period (8 hours) until it reaches zero mid-year.
     *
     * @dev The premium reduction is computed with the identity (x^y = exp(ln(x) * y)) with
     *      gas-optimized approximations for exp and ln that introduce a -3% error for every period
     *
     * @param tokenId the tokenId of the username to bid on
     * @param recovery address which can recovery the username if the custody address is lost
     */
    function bid(uint256 tokenId, address recovery) external payable {
        uint256 expiryTs = expiryOf[tokenId];
        if (expiryTs == 0) revert Registrable();

        uint256 auctionStartTimestamp;

        unchecked {
            // Safety: expiryTs is a timestamp of a known calendar year and adding it to
            // GRACE_PERIOD cannot overflow
            auctionStartTimestamp = expiryTs + GRACE_PERIOD;
        }

        if (auctionStartTimestamp > block.timestamp) revert NotBiddable();

        // Calculate the num of 8 hr periods since expiry as a fixed point signed decimal. The
        // constant approximates fixed point division by 28,800 (num of seconds in 8 hours)
        int256 periodsSD59x18 = int256(3.47222222e13 * (block.timestamp - auctionStartTimestamp));

        // Perf: pre-compute return values for the first few periods and the last one.

        // Calculate the price by taking the 1000 ETH premium and discounting it by 10% for every
        // period and adding to it the renewal fee for the current year.
        uint256 price = uint256(1_000 ether).mulWadDown(
            uint256(FixedPointMathLib.powWad(int256(0.9 ether), periodsSD59x18))
        ) + currYearFee();

        if (msg.value < price) revert InsufficientFunds();

        address msgSender = _msgSender();

        // call super.ownerOf instead of ownerOf, because the latter reverts if name is expired
        _transfer(super.ownerOf(tokenId), msgSender, tokenId);

        unchecked {
            // Safety: _currYear is guaranteed to be a known calendar year and cannot overflow
            expiryOf[tokenId] = _timestampOfYear(currYear() + 1);
        }

        recoveryOf[tokenId] = recovery;

        // Safety: usage of call over transfer or send is encouraged to protect against gas pricing changes
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = msgSender.call{value: msg.value - price}("");
        if (!success) revert CallFailed();
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-721 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Override the ownerOf implementation to throw if a username is renewable or biddable.
     */
    function ownerOf(uint256 tokenId) public view override returns (address) {
        uint256 expiryTs = expiryOf[tokenId];

        if (expiryTs != 0 && block.timestamp >= expiryTs) revert Expired();

        // Assumption: If the token is unregistered, super.ownerOf will revert
        return super.ownerOf(tokenId);
    }

    /**
     * Audit: ERC721 balanceOf will over report the balance of the owner even if the name is expired.
     */

    /**
     * @notice Override the transferFrom implementation to throw if the name is renewable or biddable.
     */
    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override {
        if (block.timestamp >= expiryOf[id]) revert Expired();

        super.transferFrom(from, to, id);
    }

    /**
     * @notice A distinct Uniform Resource Identifier (URI) for a given asset.
     *
     * @dev Throws if tokenId is not a valid token ID.
     */
    function tokenURI(uint256 tokenId) public pure override returns (string memory) {
        uint256 lastCharIdx = 0;

        // Safety: usernames are specified as 16 bytes and then converted to uint256, so the reverse
        // can be performed safely to obtain the username
        bytes16 tokenIdBytes16 = bytes16(bytes32(tokenId));

        _validateName(tokenIdBytes16);

        // Iterate backwards from the last byte until we find the first non-zero byte which marks
        // the end of the username, which is guaranteed to be <= 16 bytes / chars.
        for (uint256 i = 15; ; --i) {
            // Coverage: false negative, see: https://github.com/foundry-rs/foundry/issues/2993
            if (uint8(tokenIdBytes16[i]) != 0) {
                lastCharIdx = i;
                break;
            }
        }

        // Safety: we can assume that lastCharIndex is always > 0 since registering a username with
        // all empty bytes is not permitted by _validateName.

        // Construct a new bytes[] with the valid username characters.
        bytes memory usernameBytes = new bytes(lastCharIdx + 1);

        for (uint256 j = 0; j <= lastCharIdx; ++j) {
            usernameBytes[j] = tokenIdBytes16[j];
        }

        return string(abi.encodePacked(BASE_URI, string(usernameBytes), ".json"));
    }

    /**
     * @dev Hook that ensures that token transfers cannot occur when the contract is paused.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev Hook that ensures that recovery address is reset whenever a transfer occurs.
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._afterTokenTransfer(from, to, tokenId);

        // Checking state before clearing is more gas-efficient than always clearing
        if (recoveryClockOf[tokenId] != 0) delete recoveryClockOf[tokenId];
        delete recoveryOf[tokenId];
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
     * INVARIANT 4: If recoveryClockOf is non-zero, then recoveryDestinationOf is a non-zero address.
     */

    /**
     * @notice Set a recovery address which can transfer the caller's username to a new address.
     *
     * @param recovery address which can recovery the username if the custody address is lost
     */
    function changeRecoveryAddress(uint256 tokenId, address recovery) external payable whenNotPaused {
        if (ownerOf(tokenId) != _msgSender()) revert Unauthorized();

        recoveryOf[tokenId] = recovery;

        // If there is an ongoing recovery, cancel it
        if (recoveryClockOf[tokenId] != 0) delete recoveryClockOf[tokenId];

        emit ChangeRecoveryAddress(tokenId, recovery);
    }

    /**
     * @notice Requests a recovery of a username and moves it into escrow.
     *
     * @dev Requests can be overwritten by making another request, and can be made even if the username is in renewal
     *      or expired status.
     *
     * @param tokenId the uint256 representation of the username.
     * @param to the address to transfer the username to, which cannot be address(0).
     */
    function requestRecovery(uint256 tokenId, address to) external payable whenNotPaused {
        if (to == address(0)) revert InvalidRecovery();

        // Invariant 3 ensures that a request cannot be made after ownership change without consent
        if (_msgSender() != recoveryOf[tokenId]) revert Unauthorized();

        recoveryClockOf[tokenId] = block.timestamp;
        recoveryDestinationOf[tokenId] = to;

        // Perf: the from param can be emitted to save gas, at the cost of breaking compat with
        // IDRegistry's RequestRecovery event
        emit RequestRecovery(ownerOf(tokenId), to, tokenId);
    }

    /**
     * @notice Completes a recovery request and transfers the name if the escrow is complete and
     *         the username is still registered.
     *
     * @dev The completeRecovery function cannot be called when the contract is paused because _transfer will revert.
     *
     * @param tokenId the uint256 representation of the username.
     */
    function completeRecovery(uint256 tokenId) external payable {
        if (block.timestamp >= expiryOf[tokenId]) revert Unauthorized();

        // Invariant 3 ensures that a request cannot be completed after ownership change without consent
        if (_msgSender() != recoveryOf[tokenId]) revert Unauthorized();
        if (recoveryClockOf[tokenId] == 0) revert NoRecovery();

        unchecked {
            // Safety: recoveryClockOf is always set to block.timestamp and cannot realistically overflow
            if (block.timestamp < recoveryClockOf[tokenId] + ESCROW_PERIOD) revert Escrow();
        }

        // Assumption: Invariant 4 prevents this from going to address(0).
        _transfer(ownerOf(tokenId), recoveryDestinationOf[tokenId], tokenId);
    }

    /**
     * @notice Cancels a transfer request if the caller is the recovery or the custodyAddress
     *
     * @dev cancelRecovery is allowed even when the contract is paused to prevent the state where a user might be
     *      unable to cancel a recovery request because the contract was paused for the escrow duration.
     *
     * @param tokenId the uint256 representation of the username.
     */
    function cancelRecovery(uint256 tokenId) external payable {
        address msgSender = _msgSender();

        // Safety: super.ownerOf is called here instead of ownerOf since cancellation has no
        // undesirable side effects when called in the expired state and it saves some gas.
        if (msgSender != super.ownerOf(tokenId) && msgSender != recoveryOf[tokenId]) revert Unauthorized();

        if (recoveryClockOf[tokenId] == 0) revert NoRecovery();
        delete recoveryClockOf[tokenId];

        emit CancelRecovery(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Move the username from the current owner to the pool and renew it for another year
     *
     * @param tokenId the uint256 representation of the username.
     */
    function reclaim(uint256 tokenId) external payable {
        if (!hasRole(MODERATOR_ROLE, _msgSender())) revert NotModerator();

        if (expiryOf[tokenId] == 0) revert Registrable();

        // Call super.ownerOf instead of ownerOf because we want the admin to transfer the name
        // even if is expired and there is no current owner.
        _transfer(super.ownerOf(tokenId), pool, tokenId);

        unchecked {
            // Safety: _currYear() returns a calendar year and cannot realistically overflow
            expiryOf[tokenId] = _timestampOfYear(currYear() + 1);
        }
    }

    /**
     * @notice pause the contract and prevent registrations, renewals, recoveries and transfers of names.
     */
    function pause() external payable {
        if (!hasRole(OPERATOR_ROLE, _msgSender())) revert NotOperator();
        _pause();
    }

    /**
     * @notice unpause the contract and resume registrations, renewals, recoveries and transfers of names.
     */
    function unpause() external payable {
        if (!hasRole(OPERATOR_ROLE, _msgSender())) revert NotOperator();
        _unpause();
    }

    /**
     * @notice Changes the address from which registerTrusted calls can be made
     */
    function changeTrustedSender(address _trustedSender) external payable {
        if (!hasRole(ADMIN_ROLE, _msgSender())) revert NotAdmin();
        trustedSender = _trustedSender;
        emit ChangeTrustedSender(_trustedSender);
    }

    /**
     * @notice Disables registerTrusted and enables register calls from any address.
     */
    function disableTrustedRegister() external payable {
        if (!hasRole(ADMIN_ROLE, _msgSender())) revert NotAdmin();
        trustedRegisterEnabled = 0;
        emit DisableTrustedRegister();
    }

    /**
     * @notice Changes the address to which funds can be withdrawn
     */
    function changeVault(address _vault) external payable {
        if (!hasRole(ADMIN_ROLE, _msgSender())) revert NotAdmin();
        vault = _vault;
        emit ChangeVault(_vault);
    }

    /**
     * @notice Changes the address to which names are reclaimed
     */
    function changePool(address _pool) external payable {
        if (!hasRole(ADMIN_ROLE, _msgSender())) revert NotAdmin();
        pool = _pool;
        emit ChangePool(_pool);
    }

    /*//////////////////////////////////////////////////////////////
                            TREASURER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the yearly fee
     */
    function changeFee(uint256 _fee) external payable {
        if (!hasRole(TREASURER_ROLE, _msgSender())) revert NotTreasurer();
        fee = _fee;
        emit ChangeFee(_fee);
    }

    /**
     * @notice Withdraw a specified amount of ether to the vault
     */
    function withdraw(uint256 amount) external payable {
        if (!hasRole(TREASURER_ROLE, _msgSender())) revert NotTreasurer();
        if (address(this).balance < amount) revert WithdrawTooMuch();

        // Audit: use call instead of transfer of send to avoid breaking gas changes
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = vault.call{value: amount}("");
        if (!success) revert CallFailed();
    }

    /*//////////////////////////////////////////////////////////////
                          YEARLY PAYMENTS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current year for any year between 2021 and 2072.
     *
     * @dev The year is determined by comparing the current timestamp against an array of known timestamps for Jan 1
     *      of each year. The array contains timestamps up to 2072 after which the contract will start failing. This
     *      can be resolved by deploying a new contract with updated timestamps in the initializer.
     */
    // Audit: this function is kept public for testing
    function currYear() public returns (uint256 year) {
        // Coverage: false negative, see: https://github.com/foundry-rs/foundry/issues/2993
        if (block.timestamp < _yearTimestamps[_nextYearIdx]) {
            unchecked {
                // Safety: _nextYearIdx is always < _yearTimestamps.length which can't overflow when added to 2021
                return _nextYearIdx + 2021;
            }
        }

        uint256 length = _yearTimestamps.length;

        uint256 idx;
        unchecked {
            // Safety: _nextYearIdx is always < _yearTimestamps.length which can't overflow when added to 1
            idx = _nextYearIdx + 1;
        }

        for (uint256 i = idx; i < length; ) {
            if (_yearTimestamps[i] > block.timestamp) {
                // Slither false positive: https://github.com/crytic/slither/issues/1338
                // slither-disable-next-line costly-loop
                _nextYearIdx = i;

                unchecked {
                    // Safety: _nextYearIdx is always <= _yearTimestamps.length which can't overflow when added to 2021
                    return _nextYearIdx + 2021;
                }
            }

            unchecked {
                // Safety: i cannot overflow because length is a pre-determined constant value.
                i++;
            }
        }

        revert InvalidTime();
    }

    /**
     * @notice Returns the ETH requires to register a name for the rest of the year.
     *
     * @dev the fee is pro-rated for the remainder of the year by the number of seconds left.
     */
    // Audit: this function is kept public for testing
    function currYearFee() public returns (uint256) {
        uint256 _currYear = currYear();

        unchecked {
            // Safety: _currYear() returns a gregorian calendar year and cannot realistically overflow
            uint256 nextYearTimestamp = _timestampOfYear(_currYear + 1);

            // Safety: nextYearTimestamp is guaranteed to be > block.timestamp and > _timestampOfYear(_currYear) so
            // this cannot underflow
            return ((nextYearTimestamp - block.timestamp) * fee) / (nextYearTimestamp - _timestampOfYear(_currYear));
        }
    }

    /*//////////////////////////////////////////////////////////////
                         OPEN ZEPPELIN OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function _msgSender()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        sender = ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, ERC721Upgradeable)
        returns (bool)
    {
        return ERC721Upgradeable.supportsInterface(interfaceId);
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal view override {
        if (!hasRole(ADMIN_ROLE, _msgSender())) revert NotAdmin();
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns true if the name meets our conditions for a valid username.
     */
    // solhint-disable-next-line code-complexity
    function _validateName(bytes16 username) internal pure {
        uint256 length = username.length;
        bool nameEnded = false;

        // Iterate over the bytes16 username one char at a time, ensuring that:
        //   1. The name begins with [a-z 0-9] or the ascii numbers [48-57, 97-122] inclusive
        //   2. The name can contain [a-z 0-9 -] or the ascii numbers [45, 48-57, 97-122] inclusive
        //   3. Once the name is ended with a NULL char (0), the follows character must also be NULLs

        // If the name begins with a hyphen, reject it
        if (uint8(username[0]) == 45) revert InvalidName();

        for (uint256 i = 0; i < length; ) {
            uint8 charInt = uint8(username[i]);

            if (nameEnded) {
                // Since the name has ended, ensure that this character is NULL.
                if (charInt != 0) {
                    revert InvalidName();
                }
            } else {
                // Since the name hasn't ended ensure that this character does not contain any invalid ascii values
                if ((charInt >= 1 && charInt <= 44)) {
                    revert InvalidName();
                }

                if ((charInt >= 46 && charInt <= 47)) {
                    revert InvalidName();
                }

                if ((charInt >= 58 && charInt <= 96)) {
                    revert InvalidName();
                }

                if (charInt >= 123) {
                    revert InvalidName();
                }

                // On seeing the first NULL char in the name, revert if is the first char in the name, otherwise
                // mark the name as ended
                if (charInt == 0) {
                    if (i == 0) revert InvalidName();
                    nameEnded = true;
                }
            }

            unchecked {
                // Safety: i can never overflow because length is guaranteed to be <= 16
                i++;
            }
        }
    }

    /**
     * @notice Returns the timestamp of Jan 1, 0:00:00 for the given year between 2022 and 2072
     */
    function _timestampOfYear(uint256 year) internal view returns (uint256) {
        unchecked {
            // Safety: The array index will not go below zero, since year is always set to at least currYear(),
            // which must be >= 2022. The array index will not go above array.length(51) until the year 2072, since
            // year is always set to at most currYear() + 1, which must be <= 2072 in the year 2071
            return _yearTimestamps[year - 2022];
        }
    }
}
