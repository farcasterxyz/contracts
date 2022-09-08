// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {AccessControlUpgradeable} from "openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ContextUpgradeable} from "openzeppelin-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {ERC2771ContextUpgradeable} from "openzeppelin-upgradeable/contracts/metatx/ERC2771ContextUpgradeable.sol";
import {ERC721Upgradeable} from "openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/**
 * @title NameRegistry
 * @author varunsrin
 * @custom:version 2.0.0
 *
 * @notice NameRegistry enables any ETH address to claim a Farcaster Name (fname). A name is a
 *         rentable ERC-721 that can be registered until the end of the calendar year by paying a
 *         fee. On expiry, the owner has 30 to renew the name by paying a fee, or it is places in
 *         a dutch auction. The NameRegistry starts in a trusted mode where only a trusted caller
 *         can register an fname and can move to an untrusted mode where any address can register
 *         an fname. The Registry implements a recovery system which allows the custody address to
 *         nominate a recovery address that can transfer the fname to a new address after a delay.
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

    /// @dev Revert when msg.value does not fully cover the cost of the operation
    error InsufficientFunds();

    /// @dev Revert when the caller does not have the authority to perform the action
    error Unauthorized();

    /// @dev Revert if the caller does not have ADMIN_ROLE
    error NotAdmin();

    /// @dev Revert if the caller does not have OPERATOR_ROLE
    error NotOperator();

    /// @dev Revert if the caller does not have MODERATOR_ROLE
    error NotModerator();

    /// @dev Revert if the caller does not have TREASURER_ROLE
    error NotTreasurer();

    /// @dev Revert if withdraw() is called with an amount greater than the balance
    error WithdrawTooMuch(); // Could not withdraw the requested amount

    /// @dev Revert when excess funds could not be sent back to the caller
    error CallFailed();

    /// @dev Revert when the commit hash is not found
    error InvalidCommit();

    /// @dev Revert when a commit is re-submitted before it has expired
    error CommitReplay();

    /// @dev Revert if the fname has invalid characters during registration
    error InvalidName();

    /// @dev Revert if currYear() is after the year 2172, which is not supported
    error InvalidTime();

    /// @dev Revert if renew() is called on a registered name.
    error Registered();

    /// @dev Revert if an operation is called on a name that hasn't been minted
    error Registrable();

    /// @dev Revert if makeCommit() is invoked before trustedCallerOnly is disabled
    error Invitable();

    /// @dev Revert if trustedRegister() is invoked after trustedCallerOnly is disabled
    error NotInvitable();

    /// @dev Revert if the fname being operated on is renewable or biddable
    error Expired();

    /// @dev Revert if renew() is called after the fname becomes Biddable
    error NotRenewable();

    /// @dev Revert if bid() is called on an fname that has not become Biddable.
    error NotBiddable();

    /// @dev Revert when completeRecovery() is called before the escrow period has elapsed.
    error Escrow();

    /// @dev Revert if a recovery operation is called when there is no active recovery.
    error NoRecovery();

    /// @dev Revert if the recovery address is set to address(0).
    error InvalidRecovery();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emit an event when a Farcaster Name is renewed for another year.
     *
     * @param tokenId The keccak256 hash of the fname
     * @param expiry  The timestamp at which the renewal expires
     */
    event Renew(uint256 indexed tokenId, uint256 expiry);

    /**
     * @dev Emit an event when a user invites another user to register a Farcaster Name
     *
     * @param inviterId The fid of the user with the invite
     * @param inviteeId The fid of the user receiving the invite
     * @param fname     The fname that was registered by the invitee
     */
    event Invite(uint256 indexed inviterId, uint256 indexed inviteeId, bytes16 indexed fname);

    /**
     * @dev Emit an event when a Farcaster Name's recovery address is updated
     *
     * @param tokenId  The keccak256 hash of the fname being updated
     * @param recovery The new recovery address
     */
    event ChangeRecoveryAddress(uint256 indexed tokenId, address indexed recovery);

    /**
     * @dev Emit an event when a recovery request is initiated for a Farcaster Name
     *
     * @param from     The custody address of the fname being recovered.
     * @param to       The destination address for the fname when the recovery is completed.
     * @param tokenId  The keccak256 hash of the fname being recovered
     */
    event RequestRecovery(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emit an event when a recovery request is cancelled
     *
     * @param by      The address that cancelled the recovery request
     * @param tokenId The keccak256 hash of the fname
     */
    event CancelRecovery(address indexed by, uint256 indexed tokenId);

    /**
     * @dev Emit an event when the trusted caller is modified
     *
     * @param trustedCaller The address of the new trusted caller.
     */
    event ChangeTrustedCaller(address indexed trustedCaller);

    /**
     * @dev Emit an event when the trusted only state is disabled.
     */
    event DisableTrustedOnly();

    /**
     * @dev Emit an event when the vault address is modified
     *
     * @param vault The address of the new vault.
     */
    event ChangeVault(address indexed vault);

    /**
     * @dev Emit an event when the pool address is modified
     *
     * @param pool The address of the new pool.
     */
    event ChangePool(address indexed pool);

    /**
     * @dev Emit an event when the fee is changed
     *
     * @param fee The new yearly registration fee
     */
    event ChangeFee(uint256 fee);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// WARNING - DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
    /// Any changes before deployment should be replicated to NameRegistryV2 in NameRegistryUpdate.t.sol

    // Audit: These variables are kept public to make it easier to test the contract, since using the same inherit
    // and extend trick that we used for IDRegistry is harder to pull off here due to the UUPS structure.

    /**
     * @notice The fee to renew a name for a full calendar year
     * @dev    Occupies slot 0.
     */
    uint256 public fee;

    /**
     * @notice The address controlled by the Farcaster Invite service that is allowed to call
     *         trustedRegister
     * @dev    Occupies slot 1
     */
    address public trustedCaller;

    /**
     * @notice Flag that determines if registration can occur through trustedRegister or register
     * @dev    Occupies slot 2, initialized to 1 and can only be changed to zero
     */
    uint256 public trustedOnly;

    /**
     * @notice Maps each commit to the timestamp at which it was created.
     * @dev    Occupies slot 3
     */
    mapping(bytes32 => uint256) public timestampOf;

    /**
     * @notice Maps each the keccak256 hash of an fname to the time at which it expires
     * @dev    Occupies slot 4
     */
    mapping(uint256 => uint256) public expiryOf;

    /**
     * @notice The address that funds can be withdrawn to
     * @dev    Occupies slot 5
     */
    address public vault;

    /**
     * @notice The address that names can be reclaimed to
     * @dev    Occupies slot 6
     */
    address public pool;

    /**
     * @notice Chronological array of timestamps of Jan 1, 0:00:00 GMT from 2022 to 2072
     * @dev    Occupies slot 7
     */
    uint256[] internal _yearTimestamps;

    /**
     * @notice The index of _yearTimestamps[] which returns the timestamp of Jan 1st of the next
     *         calendar year
     * @dev    Occupies slot 8
     */
    uint256 internal _nextYearIdx;

    /**
     * @notice Maps each keccak256 hash of an fname to the address that can recover it
     * @dev    Occupies slot 9
     */
    mapping(uint256 => address) public recoveryOf;

    /**
     * @notice Maps each keccak256 hash of an fname to the timestamp of the recovery attempt or
     *         zero if there is no active recovery.
     * @dev    Occupies slot 10
     */
    mapping(uint256 => uint256) public recoveryClockOf;

    /**
     * @notice Maps each keccak256 hash of an fname to the destination address of the most recent
     *         recovery attempt.
     * @dev    Occupies slot 11, and the value is left dirty after a recovery to save gas and should
     *         not be relied upon to check if there is an active recovery.
     */
    mapping(uint256 => address) public recoveryDestinationOf;

    /**
     * @dev Added to allow future versions to add new variables in case this contract becomes
     *      inherited. See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[38] private __gap;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    string internal constant BASE_URI = "http://www.farcaster.xyz/u/";

    /// @dev enforced delay between makeCommit() and register() to prevent front-running
    uint256 internal constant REVEAL_DELAY = 60 seconds;

    /// @dev enforced delay in makeCommit() to prevent griefing by replaying the commit
    uint256 internal constant COMMIT_REPLAY_DELAY = 10 minutes;

    uint256 internal constant GRACE_PERIOD = 31 days;

    uint256 internal constant ESCROW_PERIOD = 3 days;

    /// @dev Starting price of every bid during the first period
    uint256 internal constant BID_START_PRICE = 1000 ether;

    /// @dev 60.18-decimal fixed-point that decreases the price by 10% when multiplied
    uint256 internal constant BID_PERIOD_DECREASE_UD60X18 = 0.9 ether;

    /// @dev 60.18-decimal fixed-point that approximates divide by 28,800 when multiplied
    uint256 internal constant DIV_28800_UD60X18 = 3.4722222222222e13;

    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    bytes32 internal constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    bytes32 internal constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    uint256 internal constant INITIAL_FEE = 0.01 ether;

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTORS AND INITIALIZERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Disable initialization to protect the contract and configure the trusted forwarder.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor(address _forwarder) ERC2771ContextUpgradeable(_forwarder) {
        // Audit: Is this the safest way to prevent contract initialization attacks?
        // See: https://twitter.com/z0age/status/1551951489354145795
        _disableInitializers();
    }

    /**
     * @notice Initialize default storage values and initialize inherited contracts. This should be
     *         called once after the contract is deployed via the ERC1967 proxy. Slither incorrectly flags
     *         this method as unprotected: https://github.com/crytic/slither/issues/1341
     *
     * @param _tokenName   The ERC-721 name of the fname token
     * @param _tokenSymbol The ERC-721 symbol of the fname token
     * @param _vault       The address that funds can be withdrawn to
     * @param _pool        The address that fnames can be reclaimed to
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

        // Grant the DEFAULT_ADMIN_ROLE to the deployer, which can configure other roles
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        vault = _vault;
        emit ChangeVault(_vault);

        pool = _pool;
        emit ChangePool(_pool);

        fee = INITIAL_FEE;
        emit ChangeFee(INITIAL_FEE);

        trustedOnly = 1;

        // Audit: verify these timestamps using a calculator other than epochconverter.com
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
     * INVARIANT 2: An fname cannot be transferred to address(0) after it is minted.
     */

    /**
     * @notice Generate a commitment that is used as part of a commit-reveal scheme to register a
     *         an fname while protecting the registration from being front-run.
     *
     * @param fname  The fname to be registered
     * @param to     The address that will own the fname
     * @param secret A secret that is known only to the caller
     */
    function generateCommit(
        bytes16 fname,
        address to,
        bytes32 secret
    ) public pure returns (bytes32 commit) {
        // Perf: Do not validate to != address(0) because it happens during register/mint

        _validateName(fname);

        commit = keccak256(abi.encode(fname, to, secret));
    }

    /**
     * @notice Save a commitment on-chain which can be revealed later to register an fname while
     *         protecting the registration from being front-run. This is allowed even when the
     *         contract is paused.
     *
     * @param commit The commitment hash to be persisted on-chain
     */
    function makeCommit(bytes32 commit) external payable {
        if (trustedOnly == 1) revert Invitable();

        unchecked {
            // Safety: timestampOf is always set to block.timestamp and cannot overflow here

            // Commits cannot be re-submitted immediately to prevent griefing by re-submitting commits
            // to reset the REVEAL_DELAY clock
            if (block.timestamp <= timestampOf[commit] + COMMIT_REPLAY_DELAY) revert CommitReplay();
        }

        // Save the commit and start the REVEAL_DELAY clock
        timestampOf[commit] = block.timestamp;
    }

    /**
     * @notice Mint a new fname if the inputs match a previous commit and if it was called at least
     *         60 seconds after the commit's timestamp to prevent frontrunning within the same block.
     *         It fails when paused because it invokes _mint which in turn invokes beforeTransfer()
     *
     * @param fname    The fname to register
     * @param to       The address that will own the fname
     * @param secret   The secret value in the commitment
     * @param recovery The address which can recovery the fname if the custody address is lost
     */
    function register(
        bytes16 fname,
        address to,
        bytes32 secret,
        address recovery
    ) external payable {
        bytes32 commit = generateCommit(fname, to, secret);

        uint256 _currYearFee = currYearFee();
        if (msg.value < _currYearFee) revert InsufficientFunds();

        // Perf: do not check if trustedOnly = 1, because timestampOf[commit] will always be zero
        // while trustedOnly = 1 since makeCommit cannot be called.
        uint256 commitTs = timestampOf[commit];
        if (commitTs == 0) revert InvalidCommit();

        unchecked {
            // Audit: verify that 60s is the right duration to use
            // Safety: makeCommit() sets commitTs to block.timestamp which cannot overflow
            if (block.timestamp < commitTs + REVEAL_DELAY) revert InvalidCommit();
        }

        // Mint checks that to != address(0) and that the tokenId wasn't previously issued
        uint256 tokenId = uint256(bytes32(fname));
        _mint(to, tokenId);

        // Clearing unnecessary storage reduces gas consumption
        delete timestampOf[commit];

        unchecked {
            // Safety: _currYear must be a known calendar year and cannot overflow
            expiryOf[tokenId] = _timestampOfYear(currYear() + 1);
        }

        recoveryOf[tokenId] = recovery;

        unchecked {
            // Safety: msg.value >= _currYearFee by check above, so this cannot overflow

            // Perf: Call msg.sender instead of _msgSender() to save ~100 gas b/c we don't need meta-tx
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = msg.sender.call{value: msg.value - _currYearFee}("");
            if (!success) revert CallFailed();
        }
    }

    /**
     * @notice Mint a fname during the invitation period from the trusted caller.
     *
     * @dev The function is pauseable since it invokes _transfer by way of _mint.
     *
     * @param to the address that will claim the fname
     * @param fname the fname to register
     * @param recovery address which can recovery the fname if the custody address is lost
     */
    function trustedRegister(
        bytes16 fname,
        address to,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) external payable {
        // Trusted Register can only be called during the invite period (when trustedOnly = 1)
        if (trustedOnly == 0) revert NotInvitable();

        // Call msg.sender instead of _msgSender() to prevent meta-txns and allow the function
        // to be called by BatchRegistry. This also saves ~100 gas.
        if (msg.sender != trustedCaller) revert Unauthorized();

        // Perf: this can be omitted to save ~3k gas if we believe that the trusted caller will
        // never call this function with an invalid fname.
        _validateName(fname);

        // Mint checks that to != address(0) and that the tokenId wasn't previously issued
        uint256 tokenId = uint256(bytes32(fname));
        _mint(to, tokenId);

        unchecked {
            // Safety: _currYear must return a known calendar year which cannot overflow here
            expiryOf[tokenId] = _timestampOfYear(currYear() + 1);
        }

        recoveryOf[tokenId] = recovery;

        emit Invite(inviter, invitee, fname);
    }

    /**
     * @notice Renew a name for another year while it is in the renewable period (Jan 1 - Jan 30)
     *
     * @param tokenId the tokenId of the name to renew
     */
    function renew(uint256 tokenId) external payable whenNotPaused {
        if (msg.value < fee) revert InsufficientFunds();

        // Check that the tokenID was previously registered
        uint256 expiryTs = expiryOf[tokenId];
        if (expiryTs == 0) revert Registrable();

        // tokenID is not owned by address(0) because of INVARIANT 1B + 2

        // Check that we are still in the renewable period, and have not passed into biddable
        unchecked {
            // Safety: expiryTs is a timestamp of a known calendar year and cannot overflow
            if (block.timestamp >= expiryTs + GRACE_PERIOD) revert NotRenewable();
        }

        if (block.timestamp < expiryTs) revert Registered();

        unchecked {
            // Safety: _currYear must return a known calendar year which cannot overflow
            expiryOf[tokenId] = _timestampOfYear(currYear() + 1);
        }

        emit Renew(tokenId, expiryOf[tokenId]);

        unchecked {
            // Safety: msg.value >= fee by check above, so this cannot overflow

            // Perf: Call msg.sender instead of _msgSender() to save ~100 gas b/c we don't need meta-tx
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert CallFailed();
        }
    }

    /**
     * @notice Bid to purchase an expired fname in a dutch auction and register it through the end
     *         of the calendar year. The winning bid starts at ~1000.01 ETH on Feb 1st and decays
     *         exponentially until it reaches 0 at the end of Dec 31st.
     *
     * @param to       The address where the fname should be transferred
     * @param tokenId  The tokenId of the fname to bid on
     * @param recovery The address which can recovery the fname if the custody address is lost
     */
    function bid(
        address to,
        uint256 tokenId,
        address recovery
    ) external payable {
        // Check that the tokenID was previously registered
        uint256 expiryTs = expiryOf[tokenId];
        if (expiryTs == 0) revert Registrable();

        uint256 auctionStartTimestamp;

        unchecked {
            // Safety: expiryTs is a timestamp of a known calendar year and adding it to
            // GRACE_PERIOD cannot overflow
            auctionStartTimestamp = expiryTs + GRACE_PERIOD;
        }

        if (block.timestamp < auctionStartTimestamp) revert NotBiddable();

        uint256 price;

        /**
         * The price to win a bid is calculated with formula price = dutch_premium + renewal_fee
         *
         * dutch_premium: 1000 ETH, decreases exponentially by 10% every 8 hours since Jan 31
         * renewal_fee  : 0.01 ETH, decreases linearly by 1/31536000 every second since Jan 1
         *
         * dutch_premium = 1000 ether * (0.9)^(periods), where:
         * periods = (block.timestamp - auctionStartTimestamp) / 28_800
         *
         * Periods are calculated with fixed-point multiplication which causes a slight error
         * that increases the price (DivErr), while dutch_premium is calculated with the identity
         * (x^y = exp(ln(x) * y)) which truncates 3 digits of precision and slightly lowers the
         * price (ExpErr).
         *
         * The two errors interact in different ways keeping the price slightly higher or lower
         * than expected as shown below:
         *
         * +=========+======================+========================+========================+
         * | Periods |        NoErr         |         DivErr         |    PowErr + DivErr     |
         * +=========+======================+========================+========================+
         * |       1 |                900.0 | 900.000000000000606876 | 900.000000000000606000 |
         * +---------+----------------------+------------------------+------------------------+
         * |      10 |          348.6784401 | 348.678440100002351164 | 348.678440100002351000 |
         * +---------+----------------------+------------------------+------------------------+
         * |     100 | 0.026561398887587476 |   0.026561398887589867 |   0.026561398887589000 |
         * +---------+----------------------+------------------------+------------------------+
         * |     393 | 0.000000000000001040 |   0.000000000000001040 |   0.000000000000001000 |
         * +---------+----------------------+------------------------+------------------------+
         * |     394 |                  0.0 |                    0.0 |                    0.0 |
         * +---------+----------------------+------------------------+------------------------+
         *
         */

        unchecked {
            // Safety: cannot underflow because auctionStartTimestamp <= block.timestamp and cannot
            // overflow because block.timestamp - auctionStartTimestamp realistically will stay
            // under 10^10 for the next 50 years, which can be safely multiplied with
            // DIV_28800_UD60X18
            int256 periodsSD59x18 = int256((block.timestamp - auctionStartTimestamp) * DIV_28800_UD60X18);

            // Perf: Precomputing common values might save gas but at the expense of storage which
            // is our biggest constraint and so it was discarded.

            // Safety/Audit: the below cannot intuitively underflow or overflow given the ranges,
            // but needs proof
            price =
                uint256(BID_START_PRICE).mulWadDown(
                    uint256(FixedPointMathLib.powWad(int256(BID_PERIOD_DECREASE_UD60X18), periodsSD59x18))
                ) +
                currYearFee();
        }

        if (msg.value < price) revert InsufficientFunds();

        // call super.ownerOf instead of ownerOf, because the latter reverts if name is expired
        _transfer(super.ownerOf(tokenId), to, tokenId);

        unchecked {
            // Safety: _currYear is guaranteed to be a known calendar year and cannot overflow
            expiryOf[tokenId] = _timestampOfYear(currYear() + 1);
        }

        recoveryOf[tokenId] = recovery;

        unchecked {
            // Safety: msg.value >= price by check above, so this cannot underflow

            // Perf: Call msg.sender instead of _msgSender() to save ~100 gas b/c we don't need meta-tx
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = msg.sender.call{value: msg.value - price}("");
            if (!success) revert CallFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-721 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Override the ownerOf implementation to throw if an fname is renewable or biddable.
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
        // Expired names should not be transferrable by the previous owner
        if (block.timestamp >= expiryOf[id]) revert Expired();

        super.transferFrom(from, to, id);
    }

    /**
     * @notice Return a distinct Uniform Resource Identifier (URI) for a given tokenId and throws
     *         if tokenId is not a valid token ID.
     */
    function tokenURI(uint256 tokenId) public pure override returns (string memory) {
        uint256 lastCharIdx = 0;

        // Safety: fnames are specified as 16 bytes and then converted to uint256, so the reverse
        // can be performed safely to obtain the fname
        bytes16 tokenIdBytes16 = bytes16(bytes32(tokenId));

        _validateName(tokenIdBytes16);

        // Iterate backwards from the last byte until we find the first non-zero byte which marks
        // the end of the fname, which is guaranteed to be <= 16 bytes / chars.
        for (uint256 i = 15; ; --i) {
            // Coverage: false negative, see: https://github.com/foundry-rs/foundry/issues/2993
            if (uint8(tokenIdBytes16[i]) != 0) {
                lastCharIdx = i;
                break;
            }
        }

        // Safety: we can assume that lastCharIndex is always > 0 since registering a fname with
        // all empty bytes is not permitted by _validateName.

        // Construct a new bytes[] with the valid fname characters.
        bytes memory fnameBytes = new bytes(lastCharIdx + 1);

        for (uint256 j = 0; j <= lastCharIdx; ++j) {
            fnameBytes[j] = tokenIdBytes16[j];
        }

        return string(abi.encodePacked(BASE_URI, string(fnameBytes), ".json"));
    }

    /**
     * @dev Hook that ensures that token transfers cannot occur when the contract is paused.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev Hook that ensures that recovery address is reset whenever a transfer occurs.
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
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
     * specific fname if the custodyAddress is lost. The recovery address must first request the
     * transfer on-chain which moves it into escrow. If the custodyAddress does not cancel
     * the request during escrow, the recoveryAddress can then transfer the fname. The custody
     * address can remove or change the recovery address at any time.
     *
     * INVARIANT 3: Changing ownerOf must set recoveryOf to address(0) and recoveryClockOf[id] to 0
     *
     * INVARIANT 4: If recoveryClockOf is non-zero, then recoveryDestinationOf is a non-zero address.
     */

    /**
     * @notice Change the recovery address of the fname and reset any active recovery requests.
     *         Supports ERC 2771 meta-transactions and can be called by a relayer.
     *
     * @param recovery The address which can recover the fname (set to 0x0 to disable recovery)
     */
    function changeRecoveryAddress(uint256 tokenId, address recovery) external payable whenNotPaused {
        if (ownerOf(tokenId) != _msgSender()) revert Unauthorized();

        recoveryOf[tokenId] = recovery;

        // Perf: clear any active recovery requests, but check if they exist before deleting
        // because this usually already zero
        if (recoveryClockOf[tokenId] != 0) delete recoveryClockOf[tokenId];

        emit ChangeRecoveryAddress(tokenId, recovery);
    }

    /**
     * @notice Request a recovery of an fid to a new address if the caller is the recovery address.
     *         Supports ERC 2771 meta-transactions and can be called by a relayer. Requests can be
     *         overwritten by making another request, and can be made if the fname is in
     *         renewable or biddable state.
     *
     * @param tokenId The tokenId of the fname being transferred.
     * @param to      The address to transfer the fname to, which cannot be address(0)
     */
    function requestRecovery(uint256 tokenId, address to) external payable whenNotPaused {
        if (to == address(0)) revert InvalidRecovery();

        // Invariant 3 ensures that a request cannot be made after ownership change without consent
        if (_msgSender() != recoveryOf[tokenId]) revert Unauthorized();

        // Track when the escrow period started
        recoveryClockOf[tokenId] = block.timestamp;

        // Store the final destination so that it cannot be modified unless completed or cancelled
        recoveryDestinationOf[tokenId] = to;

        // Perf: Gas costs can be reduced by omitting the from param, at the cost of breaking
        // compatibility with the IDRegistry's RequestRecovery event
        emit RequestRecovery(ownerOf(tokenId), to, tokenId);
    }

    /**
     * @notice Completes a recovery request and transfers the name if the escrow is complete and
     *         the fname is still registered.
     *
     * @dev The completeRecovery function cannot be called when the contract is paused because _transfer will revert.
     *
     * @param tokenId the uint256 representation of the fname.
     */
    function completeRecovery(uint256 tokenId) external payable {
        if (block.timestamp >= expiryOf[tokenId]) revert Expired();

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
     * @param tokenId the uint256 representation of the fname.
     */
    function cancelRecovery(uint256 tokenId) external payable {
        address sender = _msgSender();

        // Perf: super.ownerOf is called instead of ownerOf since cancellation has no undesirable
        // side effects when expired and it saves some gas.
        if (sender != super.ownerOf(tokenId) && sender != recoveryOf[tokenId]) revert Unauthorized();

        // Check if there is a recovery to avoid emitting incorrect CancelRecovery events
        if (recoveryClockOf[tokenId] == 0) revert NoRecovery();

        // Clear the recovery request so that it cannot be completed
        delete recoveryClockOf[tokenId];

        emit CancelRecovery(sender, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Move the fname from the current owner to the pool and renew it for another year
     *
     * @param tokenId the uint256 representation of the fname.
     */
    function reclaim(uint256 tokenId) external payable {
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(MODERATOR_ROLE, msg.sender)) revert NotModerator();

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
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(OPERATOR_ROLE, msg.sender)) revert NotOperator();
        _pause();
    }

    /**
     * @notice unpause the contract and resume registrations, renewals, recoveries and transfers of names.
     */
    function unpause() external payable {
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(OPERATOR_ROLE, msg.sender)) revert NotOperator();
        _unpause();
    }

    /**
     * @notice Changes the address from which registerTrusted calls can be made
     */
    function changeTrustedCaller(address _trustedCaller) external payable {
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        trustedCaller = _trustedCaller;
        emit ChangeTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Disables registerTrusted and enables register calls from any address.
     */
    function disableTrustedOnly() external payable {
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        trustedOnly = 0;
        emit DisableTrustedOnly();
    }

    /**
     * @notice Changes the address to which funds can be withdrawn
     */
    function changeVault(address _vault) external payable {
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        vault = _vault;
        emit ChangeVault(_vault);
    }

    /**
     * @notice Changes the address to which names are reclaimed
     */
    function changePool(address _pool) external payable {
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
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
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(TREASURER_ROLE, msg.sender)) revert NotTreasurer();

        // Audit does fee == 0 cause any problems with other logic?
        fee = _fee;
        emit ChangeFee(_fee);
    }

    /**
     * @notice Withdraw a specified amount of ether to the vault
     */
    function withdraw(uint256 amount) external payable {
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(TREASURER_ROLE, msg.sender)) revert NotTreasurer();

        // Audit: this will not revert if the requested amount is zero, will that cause problems?
        if (address(this).balance < amount) revert WithdrawTooMuch();

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = vault.call{value: amount}("");
        if (!success) revert CallFailed();
    }

    /*//////////////////////////////////////////////////////////////
                          YEARLY PAYMENTS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the current year for any year between 2021 and 2072. The year is determined by
     *      comparing the current timestamp against an array of known timestamps for Jan 1 of each
     *      year. The array contains timestamps up to 2072 after which the contract will start
     *      failing. This can be resolved by deploying a new contract with updated timestamps.
     */
    function currYear() public returns (uint256 year) {
        // Audit: block.timestamp could "roll back" to a prior year for a block in specific
        // circumstances and this function would return the future year even though the block
        // believes itself to be in the prior year, but it is expected to cause no issues since
        // the rest of the contract relies on currYear() which never moves backward chronologically.

        // Implies that year has not changed since the last call, so return cached value
        if (block.timestamp < _yearTimestamps[_nextYearIdx]) {
            unchecked {
                // Safety: _nextYearIdx is always < _yearTimestamps.length which can't overflow when added to 2021
                return _nextYearIdx + 2021;
            }
        }

        // The year has changed and it may have changed by more than one year since the last call.
        // Iterate through the array of year timestamps starting from the last known year until
        // the first one is found that is higher than the block timestamp. Set the current year to
        // the year that precedes that year.
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

        // Iterated through the array without finding a year, this should never happen until 2072
        revert InvalidTime();
    }

    /**
     * @notice Returns the fee (in ETH) required to register a name for the rest of the year,
     *         prorated by the seconds left in the year.
     *
     */
    function currYearFee() public returns (uint256) {
        uint256 _currYear = currYear();

        unchecked {
            // Safety: _currYear() returns a calendar year and cannot realistically overflow
            uint256 nextYearTimestamp = _timestampOfYear(_currYear + 1);

            // Safety: nextYearTimestamp > block.timestamp >= _timestampOfYear(_currYear) so this
            // cannot underflow
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
     * @dev Reverts if the name contains an invalid fname character
     */
    // solhint-disable-next-line code-complexity
    function _validateName(bytes16 fname) internal pure {
        uint256 length = fname.length;
        bool nameEnded = false;

        /**
         * Iterate over the bytes16 fname one char at a time, ensuring that:
         *   1. The name begins with [a-z 0-9] or the ascii numbers [48-57, 97-122] inclusive
         *   2. The name can contain [a-z 0-9 -] or the ascii numbers [45, 48-57, 97-122] inclusive
         *   3. Once the name is ended with a NULL char (0), the follows character must also be NULLs
         */

        // If the name begins with a hyphen, reject it
        if (uint8(fname[0]) == 45) revert InvalidName();

        for (uint256 i = 0; i < length; ) {
            uint8 charInt = uint8(fname[i]);

            if (nameEnded) {
                // Only NULL characters are allowed after a name has ended
                if (charInt != 0) {
                    revert InvalidName();
                }
            } else {
                // Only valid ASCII characters [45, 48-57, 97-122] are allowed before the name ends
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

                // On seeing the first NULL char in the name, revert if is the first char in the
                // name, otherwise mark the name as ended
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
     * @dev Returns the timestamp of Jan 1, 0:00:00 for the given year between 2022 and 2072
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
