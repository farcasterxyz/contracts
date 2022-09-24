// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

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
 *         rentable ERC-721 that can be registered for one year by paying a fee. On expiry, the
 *         owner has 30 days to renew the name by paying a fee, or it is placed in a dutch
 *         auction. The NameRegistry starts in a trusted mode where only a trusted caller can
 *         register an fname and can move to an untrusted mode where any address can register an
 *         fname. The Registry implements a recovery system which allows the custody address to
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

    /// @dev Revert when there are not enough funds to complete the transaction
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

    /// @dev Revert when excess funds could not be sent back to the caller
    error CallFailed();

    /// @dev Revert when the commit hash is not found
    error InvalidCommit();

    /// @dev Revert when a commit is re-submitted before it has expired
    error CommitReplay();

    /// @dev Revert if the fname has invalid characters during registration
    error InvalidName();

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
     * @param tokenId The uint256 representation of the fname
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
     * @param tokenId  The uint256 representation of the fname being updated
     * @param recovery The new recovery address
     */
    event ChangeRecoveryAddress(uint256 indexed tokenId, address indexed recovery);

    /**
     * @dev Emit an event when a recovery request is initiated for a Farcaster Name
     *
     * @param from     The custody address of the fname being recovered.
     * @param to       The destination address for the fname when the recovery is completed.
     * @param tokenId  The uint256 representation of the fname being recovered
     */
    event RequestRecovery(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emit an event when a recovery request is cancelled
     *
     * @param by      The address that cancelled the recovery request
     * @param tokenId The uint256 representation of the fname
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
    /// Changes should be replicated to NameRegistryV2 in NameRegistryUpdate.t.sol

    // Audit: These variables are kept public to make it easier to test the contract, since using
    // the same inherit and extend trick that we used for IdRegistry is harder to pull off here
    //  due to the UUPS structure.

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
     * @notice Maps each uint256 representation of an fname to the time at which it expires
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
     * @notice Maps each uint256 representation of an fname to the address that can recover it
     * @dev    Occupies slot 7
     */
    mapping(uint256 => address) public recoveryOf;

    /**
     * @notice Maps each uint256 representation of an fname to the timestamp of the recovery
     *         attempt or zero if there is no active recovery.
     * @dev    Occupies slot 8
     */
    mapping(uint256 => uint256) public recoveryClockOf;

    /**
     * @notice Maps each uint256 representation of an fname to the destination address of the most
     *         recent recovery attempt.
     * @dev    Occupies slot 9, and the value is left dirty after a recovery to save gas and should
     *         not be relied upon to check if there is an active recovery.
     */
    mapping(uint256 => address) public recoveryDestinationOf;

    /**
     * @dev Added to allow future versions to add new variables in case this contract becomes
     *      inherited. See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[40] private __gap;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    string internal constant BASE_URI = "http://www.farcaster.xyz/u/";

    /// @dev enforced delay between makeCommit() and register() to prevent front-running
    uint256 internal constant REVEAL_DELAY = 60 seconds;

    /// @dev enforced delay in makeCommit() to prevent griefing by replaying the commit
    uint256 internal constant COMMIT_REPLAY_DELAY = 10 minutes;

    uint256 internal constant REGISTRATION_PERIOD = 365 days;

    uint256 internal constant RENEWAL_PERIOD = 30 days;

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
        string calldata _tokenName,
        string calldata _tokenSymbol,
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
        bytes32 secret,
        address recovery
    ) public pure returns (bytes32 commit) {
        // Perf: Do not validate to != address(0) because it happens during register/mint

        _validateName(fname);

        commit = keccak256(abi.encode(fname, to, recovery, secret));
    }

    /**
     * @notice Save a commitment on-chain which can be revealed later to register an fname while
     *         protecting the registration from being front-run. This is allowed even when the
     *         contract is paused.
     *
     * @param commit The commitment hash to be persisted on-chain
     */
    function makeCommit(bytes32 commit) external {
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
        bytes32 commit = generateCommit(fname, to, secret, recovery);

        uint256 _fee = fee;
        if (msg.value < _fee) revert InsufficientFunds();

        // Perf: do not check if trustedOnly = 1, because timestampOf[commit] will always be zero
        // while trustedOnly = 1 since makeCommit cannot be called.
        uint256 commitTs = timestampOf[commit];
        if (commitTs == 0) revert InvalidCommit();

        unchecked {
            // Audit: verify that 60s is the right duration to use
            // Safety: makeCommit() sets commitTs to block.timestamp which cannot overflow
            if (block.timestamp < commitTs + REVEAL_DELAY) revert InvalidCommit();
        }

        // ERC-721's require a unique token number for each fname token, and we calculate this by
        // converting the byte16 representation into a uint256
        uint256 tokenId = uint256(bytes32(fname));

        // Mint checks that to != address(0) and that the tokenId wasn't previously issued
        _mint(to, tokenId);

        // Clearing unnecessary storage reduces gas consumption
        delete timestampOf[commit];

        unchecked {
            // Safety: expiryOf will not overflow given the expected sizes of block.timestamp
            expiryOf[tokenId] = block.timestamp + REGISTRATION_PERIOD;
        }

        recoveryOf[tokenId] = recovery;

        uint256 overpayment;

        unchecked {
            // Safety: msg.value >= _fee by check above, so this cannot overflow
            overpayment = msg.value - _fee;
        }

        if (overpayment > 0) {
            // Perf: Call msg.sender instead of _msgSender() to save ~100 gas b/c we don't need meta-tx
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = msg.sender.call{value: overpayment}("");
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
     * @param inviter the fid of the user who invited the new user to get an fname
     * @param invitee the fid of the user who was invited to get an fname
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
            // Safety: expiryOf will not overflow given the expected sizes of block.timestamp
            expiryOf[tokenId] = block.timestamp + REGISTRATION_PERIOD;
        }

        recoveryOf[tokenId] = recovery;

        emit Invite(inviter, invitee, fname);
    }

    /**
     * @notice Renew a name for another year while it is in the renewable period.
     *
     * @param tokenId The uint256 representation of the fname to renew
     */
    function renew(uint256 tokenId) external payable whenNotPaused {
        uint256 _fee = fee;
        if (msg.value < _fee) revert InsufficientFunds();

        // Check that the tokenID was previously registered
        uint256 expiryTs = expiryOf[tokenId];
        if (expiryTs == 0) revert Registrable();

        // tokenID is not owned by address(0) because of INVARIANT 1B + 2

        // Check that we are still in the renewable period, and have not passed into biddable
        unchecked {
            // Safety: expiryTs is a timestamp of a known calendar year and cannot overflow
            if (block.timestamp >= expiryTs + RENEWAL_PERIOD) revert NotRenewable();
        }

        if (block.timestamp < expiryTs) revert Registered();

        expiryOf[tokenId] = block.timestamp + REGISTRATION_PERIOD;

        emit Renew(tokenId, expiryOf[tokenId]);

        uint256 overpayment;

        unchecked {
            // Safety: msg.value >= _fee by check above, so this cannot overflow
            overpayment = msg.value - _fee;
        }

        if (overpayment > 0) {
            // Perf: Call msg.sender instead of _msgSender() to save ~100 gas b/c we don't need meta-tx
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = msg.sender.call{value: overpayment}("");
            if (!success) revert CallFailed();
        }
    }

    /**
     * @notice Bid to purchase an expired fname in a dutch auction and register it through the end
     *         of the calendar year. The winning bid starts at ~1000.01 ETH on Feb 1st and decays
     *         exponentially until it reaches 0 at the end of Dec 31st.
     *
     * @param to       The address where the fname should be transferred
     * @param tokenId  The uint256 representation of the fname to bid on
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
            // RENEWAL_PERIOD cannot overflow
            auctionStartTimestamp = expiryTs + RENEWAL_PERIOD;
        }

        if (block.timestamp < auctionStartTimestamp) revert NotBiddable();

        uint256 price;

        /**
         * The price to win a bid is calculated with formula price = dutch_premium + renewal_fee,
         * where the dutch_premium starts at 1,000 ETH and decreases exponentially by 10% every
         * 8 hours after bidding starts.
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
                BID_START_PRICE.mulWadDown(
                    uint256(FixedPointMathLib.powWad(int256(BID_PERIOD_DECREASE_UD60X18), periodsSD59x18))
                ) +
                fee;
        }

        if (msg.value < price) revert InsufficientFunds();

        // call super.ownerOf instead of ownerOf, because the latter reverts if name is expired
        _transfer(super.ownerOf(tokenId), to, tokenId);

        unchecked {
            // Safety: expiryOf will not overflow given the expected sizes of block.timestamp
            expiryOf[tokenId] = block.timestamp + REGISTRATION_PERIOD;
        }

        recoveryOf[tokenId] = recovery;

        uint256 overpayment;

        unchecked {
            // Safety: msg.value >= price by check above, so this cannot underflow
            overpayment = msg.value - price;
        }

        if (overpayment > 0) {
            // Perf: Call msg.sender instead of _msgSender() to save ~100 gas b/c we don't need meta-tx
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = msg.sender.call{value: overpayment}("");
            if (!success) revert CallFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-721 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Override the ownerOf implementation to throw if an fname is renewable or biddable.
     *
     * @param tokenId The uint256 representation of the fname to check
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
     * @notice Override transferFrom to throw if the name is renewable or biddable.
     *
     * @param from    The address which currently holds the fname
     * @param to      The address to transfer the fname to
     * @param tokenId The uint256 representation of the fname to transfer
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        uint256 expiryTs = expiryOf[tokenId];

        // Expired names should not be transferrable by the previous owner
        if (expiryTs != 0 && block.timestamp >= expiryOf[tokenId]) revert Expired();

        super.transferFrom(from, to, tokenId);
    }

    /**
     * @notice Override safeTransferFrom to throw if the name is renewable or biddable.
     *
     * @param from     The address which currently holds the fname
     * @param to       The address to transfer the fname to
     * @param tokenId  The uint256 representation of the fname to transfer
     * @param data     Additional data with no specified format, sent in call to `to`
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override {
        uint256 expiryTs = expiryOf[tokenId];

        // Expired names should not be transferrable by the previous owner
        if (expiryTs != 0 && block.timestamp >= expiryOf[tokenId]) revert Expired();

        super.safeTransferFrom(from, to, tokenId, data);
    }

    /**
     * @notice Return a distinct Uniform Resource Identifier (URI) for a given tokenId even if it
     *         is not registered. Throws if the tokenId cannot be converted to a valid fname.
     *
     * @param tokenId The uint256 representation of the fname
     */
    function tokenURI(uint256 tokenId) public pure override returns (string memory) {
        uint256 lastCharIdx;

        // Safety: fnames are byte16's that are cast to uint256 tokenIds, so inverting this is safe
        bytes16 fname = bytes16(bytes32(tokenId));

        _validateName(fname);

        // Step back from the last byte to find the first non-zero byte
        for (uint256 i = 15; ; ) {
            if (uint8(fname[i]) != 0) {
                lastCharIdx = i;
                break;
            }

            unchecked {
                // Safety: i cannot underflow because the loop terminates when i == 0
                --i;
            }
        }

        // Safety: this non-zero byte must exist at some position because of _validateName and
        // therefore lastCharIdx must be > 1

        // Construct a new bytes[] with the valid fname characters.
        bytes memory fnameBytes = new bytes(lastCharIdx + 1);

        for (uint256 j = 0; j <= lastCharIdx; ) {
            fnameBytes[j] = fname[j];

            unchecked {
                // Safety: j cannot overflow because the loop terminates when j > lastCharIdx
                ++j;
            }
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
     * @param tokenId  The uint256 representation of the fname
     * @param recovery The address which can recover the fname (set to 0x0 to disable recovery)
     */
    function changeRecoveryAddress(uint256 tokenId, address recovery) external whenNotPaused {
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
     *         overwritten by making another request.
     *
     * @param tokenId The uint256 representation of the fname
     * @param to      The address to transfer the fname to, which cannot be address(0)
     */
    function requestRecovery(uint256 tokenId, address to) external whenNotPaused {
        if (to == address(0)) revert InvalidRecovery();

        // Invariant 3 ensures that a request cannot be made after ownership change without consent
        if (_msgSender() != recoveryOf[tokenId]) revert Unauthorized();

        // Perf: don't check if in renewable or biddable state since it saves gas and
        // completeRecovery will revert when it runs

        // Track when the escrow period started
        recoveryClockOf[tokenId] = block.timestamp;

        // Store the final destination so that it cannot be modified unless completed or cancelled
        recoveryDestinationOf[tokenId] = to;

        // Perf: Gas costs can be reduced by omitting the from param, at the cost of breaking
        // compatibility with the IdRegistry's RequestRecovery event
        emit RequestRecovery(ownerOf(tokenId), to, tokenId);
    }

    /**
     * @notice Complete a recovery request and transfer the fname if the caller is the recovery
     *         address and the escrow period has passed. Supports ERC 2771 meta-transactions and
     *         can be called by a relayer. Cannot be called when paused because _transfer reverts.
     *
     * @param tokenId The uint256 representation of the fname
     */
    function completeRecovery(uint256 tokenId) external {
        if (block.timestamp >= expiryOf[tokenId]) revert Expired();

        // Invariant 3 ensures that a request cannot be completed after ownership change without consent
        if (_msgSender() != recoveryOf[tokenId]) revert Unauthorized();

        uint256 _recoveryClock = recoveryClockOf[tokenId];
        if (_recoveryClock == 0) revert NoRecovery();

        unchecked {
            // Safety: _recoveryClock is always set to block.timestamp and cannot realistically overflow
            if (block.timestamp < _recoveryClock + ESCROW_PERIOD) revert Escrow();
        }

        // Assumption: Invariant 4 prevents this from going to address(0).
        _transfer(ownerOf(tokenId), recoveryDestinationOf[tokenId], tokenId);
    }

    /**
     * @notice Cancel an active recovery request if the caller is the recovery address or the
     *         custody address. Supports ERC 2771 meta-transactions and can be called by a relayer.
     *         Can be called even if the contract is paused to avoid griefing before a known pause.
     *
     * @param tokenId The uint256 representation of the fname
     */
    function cancelRecovery(uint256 tokenId) external {
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
                            MODERATOR ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Move the fname from the current owner to the pool and renew it for another year.
     *         Does not work when paused because it calls _transfer.
     *
     * @param tokenId the uint256 representation of the fname.
     */
    function reclaim(uint256 tokenId) external payable {
        // call msg.sender instead of _msgSender() since we don't need meta-tx for admin actions
        // and it reduces our attack surface area
        if (!hasRole(MODERATOR_ROLE, msg.sender)) revert NotModerator();

        uint256 _expiry = expiryOf[tokenId];

        // If an fname hasn't been minted, it should be minted instead of reclaimed
        if (_expiry == 0) revert Registrable();

        // Call super.ownerOf instead of ownerOf because we want the admin to transfer the name
        // even if is expired and there is no current owner.
        _transfer(super.ownerOf(tokenId), pool, tokenId);

        // If an fname expires in the near future, extend its registration by the renewal period
        if (block.timestamp >= _expiry - RENEWAL_PERIOD) {
            expiryOf[tokenId] = block.timestamp + RENEWAL_PERIOD;
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Changes the address from which registerTrusted calls can be made
     *
     * @param _trustedCaller The address of the new trusted caller
     */
    function changeTrustedCaller(address _trustedCaller) external {
        // avoid _msgSender() since meta-tx are unnecessary here and increase attack surface area
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        trustedCaller = _trustedCaller;
        emit ChangeTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Disables registerTrusted and enables register calls from any address.
     */
    function disableTrustedOnly() external {
        // avoid _msgSender() since meta-tx are unnecessary here and increase attack surface area
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        delete trustedOnly;
        emit DisableTrustedOnly();
    }

    /**
     * @notice Changes the address to which funds can be withdrawn
     *
     * @param _vault The address of the new vault
     */
    function changeVault(address _vault) external {
        // avoid _msgSender() since meta-tx are unnecessary here and increase attack surface area
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        vault = _vault;
        emit ChangeVault(_vault);
    }

    /**
     * @notice Changes the address to which names are reclaimed
     *
     * @param _pool The address of the new pool
     */
    function changePool(address _pool) external {
        // avoid _msgSender() since meta-tx are unnecessary here and increase attack surface area
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        pool = _pool;
        emit ChangePool(_pool);
    }

    /*//////////////////////////////////////////////////////////////
                            TREASURER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the fee charged to register an fname for a full year
     *
     * @param _fee The new yearly fee
     */
    function changeFee(uint256 _fee) external {
        // avoid _msgSender() since meta-tx are unnecessary here and increase attack surface area
        if (!hasRole(TREASURER_ROLE, msg.sender)) revert NotTreasurer();

        // Audit does fee == 0 cause any problems with other logic?
        fee = _fee;
        emit ChangeFee(_fee);
    }

    /**
     * @notice Withdraw a specified amount of ether to the vault
     *
     * @param amount The amount of ether to withdraw
     */
    function withdraw(uint256 amount) external {
        // avoid _msgSender() since meta-tx are unnecessary here and increase attack surface area
        if (!hasRole(TREASURER_ROLE, msg.sender)) revert NotTreasurer();

        // Audit: this will not revert if the requested amount is zero, will that cause problems?
        if (address(this).balance < amount) revert InsufficientFunds();

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = vault.call{value: amount}("");
        if (!success) revert CallFailed();
    }

    /*//////////////////////////////////////////////////////////////
                            OPERATOR ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice pause the contract and prevent registrations, renewals, recoveries and transfers of names.
     */
    function pause() external {
        // avoid _msgSender() since meta-tx are unnecessary here and increase attack surface area
        if (!hasRole(OPERATOR_ROLE, msg.sender)) revert NotOperator();
        _pause();
    }

    /**
     * @notice unpause the contract and resume registrations, renewals, recoveries and transfers of names.
     */
    function unpause() external {
        // avoid _msgSender() since meta-tx are unnecessary here and increase attack surface area
        if (!hasRole(OPERATOR_ROLE, msg.sender)) revert NotOperator();
        _unpause();
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
        bool nameEnded;

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

            unchecked {
                // Safety: i can never overflow because length is guaranteed to be <= 16
                i++;
            }

            if (nameEnded) {
                // Only NULL characters are allowed after a name has ended
                if (charInt != 0) {
                    revert InvalidName();
                }
            } else {
                // Only valid ASCII characters [45, 48-57, 97-122] are allowed before the name ends

                // Check if the character is a-z
                if ((charInt >= 97 && charInt <= 122)) {
                    continue;
                }

                // Check if the character is 0-9
                if ((charInt >= 48 && charInt <= 57)) {
                    continue;
                }

                // Check if the character is a hyphen
                if ((charInt == 45)) {
                    continue;
                }

                // On seeing the first NULL char in the name, revert if is the first char in the
                // name, otherwise mark the name as ended
                if (charInt == 0) {
                    // We check i==1 instead of i==0 because i is incremented before the check
                    if (i == 1) revert InvalidName();
                    nameEnded = true;
                    continue;
                }

                revert InvalidName();
            }
        }
    }
}
