// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

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
 * @notice NameRegistry lets any ETH address claim a Farcaster Name (fname). A name is a rentable
 *         ERC-721 that can be registered for one year by paying a fee. On expiry, the owner has
 *         30 days to renew the name by paying a fee, or it is placed in a dutch autction.
 *
 *         The NameRegistry starts in the seedable state where only a trusted caller can register
 *         fnames and can be moved to an open state where any address can register an fname. The
 *         Registry implements a recovery system which lets the address nominate a recovery address
 *         that can transfer the fname to a new address after a delay.
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

    /**
     * @dev Contains the metadata for an fname
     * @param recovery Address that can recover the fname.
     * @param expiryTs The time at which the fname expires.
     */
    struct Metadata {
        address recovery;
        uint40 expiryTs;
    }

    /**
     * @dev Contains the state of the most recent recovery attempt.
     * @param destination Destination of the current recovery or address(0) if no active recovery.
     * @param timestamp Timestamp of the current recovery or zero if no active recovery.
     */
    struct RecoveryState {
        address destination;
        uint40 timestamp;
    }

    /**
     * @dev Contains information about a reclaim action performed on an fname.
     * @param tokenId The uint256 representation of the fname.
     * @param destination The address that the fname is being reclaimed to.
     */
    struct ReclaimAction {
        uint256 tokenId;
        address destination;
    }

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
    error Seedable();

    /// @dev Revert if trustedRegister() is invoked after trustedCallerOnly is disabled
    error NotSeedable();

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

    /// @dev Revert when an invalid address is provided as input.
    error InvalidAddress();

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

    /* 
     * WARNING - DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED 
     * 
     * Any changes before deployment should be copied to NameRegistryV2 in NameRegistryUpdate.t.sol
     * 
     * Many variables are kept public to test the contract, since the inherit and extend trick in 
     * IdRegistry is harder to pull off due to the UUPS structure.
     */

    /**
     * @notice The fee to renew a name for a full calendar year
     * @dev    Occupies slot 0.
     */
    uint256 public fee;

    /**
     * @notice The address controlled by the Farcaster Bootstrap service allowed to call
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
     * @notice The address that funds can be withdrawn to
     * @dev    Occupies slot 4
     */
    address public vault;

    /**
     * @notice The address that names can be reclaimed to
     * @dev    Occupies slot 5
     */
    address public pool;

    /**
     * @notice Maps each uint256 representation of an fname to registration metadata
     * @dev    Occupies slot 6
     */
    mapping(uint256 => Metadata) public metadataOf;

    /**
     * @notice Maps each uint256 representation of an fname to recovery metadata
     * @dev    Occupies slot 7
     */
    mapping(uint256 => RecoveryState) public recoveryStateOf;

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
     * @notice Initialize default storage values and inherited contracts. This should be called
     *         once after the contract is deployed via the ERC1967 proxy.
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
        /* Initialize inherited contracts */
        __ERC721_init(_tokenName, _tokenSymbol);
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        /* Grant the DEFAULT_ADMIN_ROLE to the deployer,which can configure other roles */
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        vault = _vault;
        emit ChangeVault(_vault);

        pool = _pool;
        emit ChangePool(_pool);

        fee = INITIAL_FEE;
        emit ChangeFee(INITIAL_FEE);

        /* Set the contract to the seedable state */
        trustedOnly = 1;
    }

    /*//////////////////////////////////////////////////////////////
                           REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * INVARIANT 1A: If an fname is not minted:
     *               metadataOf[id].expiryTs == 0 &&
     *               ownerOf(id) == address(0) &&
     *               metadataOf[id].recovery[id] == address(0)
     *
     * INVARIANT 1B: If an fname is minted:
     *               metadataOf[id].expiryTs != 0 &&
     *               ownerOf(id) != address(0).
     *
     * INVARIANT 2: An fname cannot be transferred to address(0) after it is minted.
     */

    /**
     * @notice Generate a commitment to use in a commit-reveal scheme to register an fname and
     *         prevent front-running.
     *
     * @param fname  The fname to be registered
     * @param to     The address that will own the fname
     * @param secret A secret that will be broadcast on-chain during the reveal
     */
    function generateCommit(
        bytes16 fname,
        address to,
        bytes32 secret,
        address recovery
    ) public pure returns (bytes32 commit) {
        /* Revert unless the fname is valid */
        _validateName(fname);

        /* Perf: Do not validate to != address(0) because it happens during register */
        commit = keccak256(abi.encodePacked(fname, to, recovery, secret));
    }

    /**
     * @notice Save a commitment on-chain which can be revealed later to register an fname. The
     *         commit reveal scheme protects the register action from being front run. makeCommit
     *         can be called even when the contract is paused.
     *
     * @param commit The commitment hash to be saved on-chain
     */
    function makeCommit(bytes32 commit) external {
        /* Revert if the contract is in the Seedable state */
        if (trustedOnly == 1) revert Seedable();

        /**
         * Revert unless some time has passed since the last commit to prevent griefing by
         * replaying the commit and restarting the REVEAL_DELAY timer.
         *
         *  Safety: cannot overflow because timestampOf[commit] is a block.timestamp or zero
         */
        unchecked {
            if (block.timestamp <= timestampOf[commit] + COMMIT_REPLAY_DELAY) {
                revert CommitReplay();
            }
        }

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
     * @param recovery The address which can recover the fname if the custody address is lost
     */
    function register(bytes16 fname, address to, bytes32 secret, address recovery) external payable {
        /* Revert if the registration fee was not provided */
        uint256 _fee = fee;
        if (msg.value < _fee) revert InsufficientFunds();

        /**
         * Revert unless a matching commit was found
         *
         * Perf: do not check if trustedOnly = 1, because timestampOf[commit] must be zero when
         * trustedOnly = 1 since makeCommit() cannot be called.
         */
        bytes32 commit = generateCommit(fname, to, secret, recovery);
        uint256 commitTs = timestampOf[commit];
        if (commitTs == 0) revert InvalidCommit();

        /**
         * Revert unless the reveal delay has passed, which prevents frontrunning within the block.
         *
         * Audit: verify that 60s is the right duration to use
         * Safety: makeCommit() sets commitTs to block.timestamp which cannot overflow
         */
        unchecked {
            if (block.timestamp < commitTs + REVEAL_DELAY) {
                revert InvalidCommit();
            }
        }

        /**
         * Mints the token by calling the ERC-721 _mint() function and using the uint256 value of
         * the username as the tokenId. The _mint() function ensures that the to address isnt 0
         * and that the tokenId is not already minted.
         */
        uint256 tokenId = uint256(bytes32(fname));
        _mint(to, tokenId);

        /* Perf: Clearing timestamp reduces gas consumption */
        delete timestampOf[commit];

        /**
         * Set the expiration timestamp and the recovery address
         *
         * Safety: expiryTs will not overflow given that block.timestamp < block.timestamp
         */
        unchecked {
            metadataOf[tokenId].expiryTs = uint40(block.timestamp + REGISTRATION_PERIOD);
        }

        metadataOf[tokenId].recovery = recovery;

        /**
         * Refund overpayment to the caller and revert if the refund fails.
         *
         * Safety: msg.value >= _fee by check above, so this cannot overflow
         * Perf: Call msg.sender instead of _msgSender() to save ~100 gas b/c we don't need meta-tx
         */
        uint256 overpayment;

        unchecked {
            overpayment = msg.value - _fee;
        }

        if (overpayment > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = msg.sender.call{value: overpayment}("");
            if (!success) revert CallFailed();
        }
    }

    /**
     * @notice Mint an fname during the bootstrap period from the trusted caller.
     *
     * @dev The function is pauseable since it invokes _transfer by way of _mint.
     *
     * @param to the address that will claim the fname
     * @param fname the fname to register
     * @param recovery address which can recovery the fname if the custody address is lost
     */
    function trustedRegister(bytes16 fname, address to, address recovery) external payable {
        /* Revert if called after the bootstrap period */
        if (trustedOnly == 0) revert NotSeedable();

        /**
         * Revert if the caller is not the trusted caller.
         *
         * Perf: Using msg.sender saves ~100 gas and prevents meta-txns while allowing the function
         * to be called by BatchRegistry.
         */
        if (msg.sender != trustedCaller) revert Unauthorized();

        /* Perf: this can be omitted to save ~3k gas */
        _validateName(fname);

        /**
         * Mints the token by calling the ERC-721 _mint() function and using the uint256 value of
         * the username as the tokenId. The _mint() function ensures that the to address isnt 0
         * and that the tokenId is not already minted.
         */
        uint256 tokenId = uint256(bytes32(fname));
        _mint(to, tokenId);

        /**
         * Set the expiration timestamp and the recovery address
         *
         * Safety: expiryTs will not overflow given that block.timestamp < block.timestamp
         */
        unchecked {
            metadataOf[tokenId].expiryTs = uint40(block.timestamp + REGISTRATION_PERIOD);
        }

        metadataOf[tokenId].recovery = recovery;
    }

    /**
     * @notice Renew a name for another year while it is in the renewable period.
     *
     * @param tokenId The uint256 representation of the fname to renew
     */
    function renew(uint256 tokenId) external payable whenNotPaused {
        /* Revert if the registration fee was not provided */
        uint256 _fee = fee;
        if (msg.value < _fee) revert InsufficientFunds();

        /* Revert if the fname's tokenId has never been registered */
        uint256 expiryTs = uint256(metadataOf[tokenId].expiryTs);
        if (expiryTs == 0) revert Registrable();

        /**
         * Revert if the fname have passed out of the renewable period into the biddable period.
         *
         * Safety: expiryTs is set one year ahead of block.timestamp and cannot overflow.
         */
        unchecked {
            if (block.timestamp >= expiryTs + RENEWAL_PERIOD) {
                revert NotRenewable();
            }
        }

        /* Revert if the fname is not expired and has not entered the renewable period. */
        if (block.timestamp < expiryTs) revert Registered();

        /**
         * Renew the name by setting the new expiration timestamp
         *
         * Safety: tokenId is not owned by address(0) because of INVARIANT 1B + 2
         */
        metadataOf[tokenId].expiryTs = uint40(block.timestamp + REGISTRATION_PERIOD);

        emit Renew(tokenId, uint256(metadataOf[tokenId].expiryTs));

        /**
         * Refund overpayment to the caller and revert if the refund fails.
         *
         * Safety: msg.value >= _fee by check above, so this cannot overflow
         * Perf: Call msg.sender instead of _msgSender() to save ~100 gas b/c we don't need meta-tx
         */
        uint256 overpayment;

        unchecked {
            overpayment = msg.value - _fee;
        }

        if (overpayment > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = msg.sender.call{value: overpayment}("");
            if (!success) revert CallFailed();
        }
    }

    /**
     * @notice Bid to purchase an expired fname in a dutch auction and register it for a year. The
     *         winning bid starts at ~1000.01 ETH decays exponentially until it reaches 0.
     *
     * @param to       The address where the fname should be transferred
     * @param tokenId  The uint256 representation of the fname to bid on
     * @param recovery The address which can recovery the fname if the custody address is lost
     */
    function bid(address to, uint256 tokenId, address recovery) external payable {
        /* Revert if the token was never registered */
        uint256 expiryTs = uint256(metadataOf[tokenId].expiryTs);
        if (expiryTs == 0) revert Registrable();

        /**
         * Revert if the fname is not yet in the auction period.
         *
         * Safety: expiryTs is set one year ahead of block.timestamp and cannot overflow.
         */
        uint256 auctionStartTimestamp;
        unchecked {
            auctionStartTimestamp = expiryTs + RENEWAL_PERIOD;
        }
        if (block.timestamp < auctionStartTimestamp) revert NotBiddable();

        /**
         * Calculate the bid price for the dutch auction which the dutchPremium + renewalFee.
         *
         * dutchPremium starts at 1,000 ETH and decreases by 10% every 8 hours or 28,800 seconds:
         * dutchPremium = 1000 ether * (0.9)^(numPeriods)
         * numPeriods = (block.timestamp - auctionStartTimestamp) / 28_800
         *
         * numPeriods is calculated with fixed-point multiplication which causes a slight error
         * that increases the price (DivErr), while dutchPremium is calculated by the identity
         * (x^y = exp(ln(x) * y)) which loses 3 digits of precision and lowers the price (ExpErr).
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
         * The values are not precomputed since space is the major constraint in this contract.
         *
         * Safety: auctionStartTimestamp <= block.timestamp and their difference will be under
         * 10^10 for the next 50 years, which can be safely multiplied with DIV_28800_UD60X18
         *
         * Safety/Audit: price calcuation cannot intuitively over or underflow, but needs proof
         */

        uint256 price;

        unchecked {
            int256 periodsSD59x18 = int256((block.timestamp - auctionStartTimestamp) * DIV_28800_UD60X18);

            price = BID_START_PRICE.mulWadDown(
                uint256(FixedPointMathLib.powWad(int256(BID_PERIOD_DECREASE_UD60X18), periodsSD59x18))
            ) + fee;
        }

        /* Revert if the transaction cannot pay the full price of the bid */
        if (msg.value < price) revert InsufficientFunds();

        /**
         * Transfer the fname to the new owner by calling the ERC-721 transfer function, and update
         * the expiration date and recovery addres. The current owner is determined with
         * super.ownerOf which will not revert even if expired.
         *
         * Safety: expiryTs cannot overflow given block.timestamp and registration period sizes.
         */
        _transfer(super.ownerOf(tokenId), to, tokenId);

        unchecked {
            metadataOf[tokenId].expiryTs = uint40(block.timestamp + REGISTRATION_PERIOD);
        }

        metadataOf[tokenId].recovery = recovery;

        /**
         * Refund overpayment to the caller and revert if the refund fails.
         *
         * Safety: msg.value >= _fee by check above, so this cannot overflow
         * Perf: Call msg.sender instead of _msgSender() to save ~100 gas b/c we don't need meta-tx
         */
        uint256 overpayment;

        unchecked {
            overpayment = msg.value - price;
        }

        if (overpayment > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = msg.sender.call{value: overpayment}("");
            if (!success) revert CallFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-721 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Override the ownerOf implementation to throw if an fname is renewable or biddable.
     *
     * @param tokenId The uint256 tokenId of the fname
     */
    function ownerOf(uint256 tokenId) public view override returns (address) {
        /* Revert if fname was registered once and the expiration time has passed */
        uint256 expiryTs = uint256(metadataOf[tokenId].expiryTs);
        if (expiryTs != 0 && block.timestamp >= expiryTs) revert Expired();

        /* Safety: If the token is unregistered, super.ownerOf will revert */
        return super.ownerOf(tokenId);
    }

    /* Audit: ERC721 balanceOf will over report owner balance if the name is expired */

    /**
     * @notice Override transferFrom to throw if the name is renewable or biddable.
     *
     * @param from    The address which currently holds the fname
     * @param to      The address to transfer the fname to
     * @param tokenId The uint256 representation of the fname to transfer
     */
    function transferFrom(address from, address to, uint256 tokenId) public override {
        /* Revert if fname was registered once and the expiration time has passed */
        uint256 expiryTs = uint256(metadataOf[tokenId].expiryTs);
        if (expiryTs != 0 && block.timestamp >= expiryTs) revert Expired();

        super.transferFrom(from, to, tokenId);
    }

    /**
     * @notice Override safeTransferFrom to throw if the name is renewable or biddable.
     *
     * @param from     The address which currently holds the fname
     * @param to       The address to transfer the fname to
     * @param tokenId  The uint256 tokenId of the fname to transfer
     * @param data     Additional data with no specified format, sent in call to `to`
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        /* Revert if fname was registered once and the expiration time has passed */
        uint256 expiryTs = uint256(metadataOf[tokenId].expiryTs);
        if (expiryTs != 0 && block.timestamp >= expiryTs) revert Expired();

        super.safeTransferFrom(from, to, tokenId, data);
    }

    /**
     * @notice Return a distinct URI for a tokenId of the form
     *         https://www.farcaster.xyz/u/<fname>.json
     *
     * @param tokenId The uint256 tokenId of the fname
     */
    function tokenURI(uint256 tokenId) public pure override returns (string memory) {
        /**
         * Revert if the fname is invalid
         *
         * Safety: fnames are 16 bytes long, so truncating the token id is safe.
         */
        bytes16 fname = bytes16(bytes32(tokenId));
        _validateName(fname);

        /**
         * Find the index of the last character of the fname.
         *
         * Since fnames are between 1 and 16 bytes long, there must be at least one non-zero value
         * and there may be trailing zeros that can be discarded. Loop back from the last value
         * until the first non-zero value is found.
         */
        uint256 lastCharIdx;
        for (uint256 i = 15;;) {
            if (uint8(fname[i]) != 0) {
                lastCharIdx = i;
                break;
            }

            unchecked {
                --i; // Safety: cannot underflow because the loop ends when i == 0
            }
        }

        /* Construct a bytes[] with only valid fname characters */
        bytes memory fnameBytes = new bytes(lastCharIdx + 1);

        for (uint256 j = 0; j <= lastCharIdx;) {
            fnameBytes[j] = fname[j];

            unchecked {
                ++j; // Safety: cannot overflow because the loop ends when j > lastCharIdx
            }
        }

        /* Return a URI of the form https://www.farcaster.xyz/u/<fname>.json */
        return string(abi.encodePacked(BASE_URI, string(fnameBytes), ".json"));
    }

    /**
     * @dev Hook that ensures that token transfers cannot occur when the contract is paused.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev Hook that ensures that recovery state and address is reset whenever a transfer occurs.
     */
    function _afterTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._afterTokenTransfer(from, to, tokenId, batchSize);
        delete recoveryStateOf[tokenId];
        delete metadataOf[tokenId].recovery;
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
     * INVARIANT 3: Changing ownerOf must set recovery to address(0) and
     *              recoveryState[id].timestamp to 0
     *
     * INVARIANT 4: If RecoveryState.timestamp is non-zero, then RecoveryState.destination is
     *              also non zero. If RecoveryState.timestamp 0, then
     *              RecoveryState.destination must also be address(0)
     */

    /**
     * @notice Change the recovery address of the fname, resetting active recovery requests.
     *         Supports ERC 2771 meta-transactions and can be called by a relayer.
     *
     * @param tokenId  The uint256 representation of the fname
     * @param recovery The address which can recover the fname (set to 0x0 to disable recovery)
     */
    function changeRecoveryAddress(uint256 tokenId, address recovery) external whenNotPaused {
        /* Revert if the caller is not the owner of the fname */
        if (ownerOf(tokenId) != _msgSender()) revert Unauthorized();

        /* Change the recovery address and reset active recovery requests */
        metadataOf[tokenId].recovery = recovery;
        delete recoveryStateOf[tokenId];

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
        /* Revert if the destination is the zero address */
        if (to == address(0)) revert InvalidRecovery();

        /* Revert if the caller is not the recovery address */
        if (_msgSender() != metadataOf[tokenId].recovery) {
            revert Unauthorized();
        }

        /**
         * Start the recovery by setting the timestamp and destination of the request.
         *
         * Safety: requestRecovery is allowed to be performed on a renewable or biddable name,
         * to save gas since completeRecovery will fail anyway.
         */
        recoveryStateOf[tokenId].timestamp = uint40(block.timestamp);
        recoveryStateOf[tokenId].destination = to;

        emit RequestRecovery(ownerOf(tokenId), to, tokenId);
    }

    /**
     * @notice Complete a recovery request and transfer the fname if the escrow period has passed.
     *         Supports ERC 2771 meta-transactions and can be called by a relayer. Cannot be called
     *         when paused because _transfer reverts.
     *
     * @param tokenId The uint256 representation of the fname
     */
    function completeRecovery(uint256 tokenId) external {
        /* Revert if fname ownership has expired and it's state is renwable or biddable */
        if (block.timestamp >= uint256(metadataOf[tokenId].expiryTs)) {
            revert Expired();
        }

        /* Revert if the caller is not the recovery address */
        if (_msgSender() != metadataOf[tokenId].recovery) {
            revert Unauthorized();
        }

        /* Revert if there is no active recovery request */
        uint256 recoveryTimestamp = recoveryStateOf[tokenId].timestamp;
        if (recoveryTimestamp == 0) revert NoRecovery();

        /**
         * Revert if there recovery request is still in the escrow period, which gives the custody
         * address time to cancel the request if it was unauthorized.
         *
         * Safety: recoveryTimestamp was a block.timestamp and cannot realistically overflow.
         */
        unchecked {
            if (block.timestamp < recoveryTimestamp + ESCROW_PERIOD) {
                revert Escrow();
            }
        }

        /* Safety: Invariant 4 prevents this from going to address(0) */
        _transfer(ownerOf(tokenId), recoveryStateOf[tokenId].destination, tokenId);
    }

    /**
     * @notice Cancel an active recovery request from the recovery address or the custody address.
     *  Supports ERC 2771 meta-transactions and can be called by a relayer. Can be called even if
     *  the contract is paused to avoid griefing before a known pause.
     *
     * @param tokenId The uint256 representation of the fname
     */
    function cancelRecovery(uint256 tokenId) external {
        /**
         * Revert if the caller is not the custody or recovery address.
         *
         * Perf: ownerOf is called instead of super.ownerOf to save gas since cancellation is safe
         * even if the name has expired.
         */
        address sender = _msgSender();
        if (sender != super.ownerOf(tokenId) && sender != metadataOf[tokenId].recovery) {
            revert Unauthorized();
        }

        /* Revert if there is no active recovery request */
        if (recoveryStateOf[tokenId].timestamp == 0) revert NoRecovery();

        delete recoveryStateOf[tokenId];

        emit CancelRecovery(sender, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                            MODERATOR ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Move the fnames from their current owners to their new destinations and renew them
     *         for 30 days if they expire within the next 30 days. Does not work when paused
     *         because it calls _transfer.
     *
     * @param reclaimActions an array of ReclaimAction structs representing the fnames and their
     *                       destination addresses.
     */
    function reclaim(ReclaimAction[] calldata reclaimActions) external payable {
        /**
         * Revert if the caller is not a moderator
         *
         * Safety: use msg.sender since metaTxns are unnecessary for admin actions.
         */
        if (!hasRole(MODERATOR_ROLE, msg.sender)) revert NotModerator();

        uint256 reclaimActionsLength = reclaimActions.length;

        for (uint256 i = 0; i < reclaimActionsLength;) {
            /* Revert if the fname was never registered */
            uint256 tokenId = reclaimActions[i].tokenId;
            uint256 _expiry = uint256(metadataOf[tokenId].expiryTs);
            if (_expiry == 0) revert Registrable();

            /* Transfer the name with super.ownerOf so that it works even if the name is expired */
            _transfer(super.ownerOf(tokenId), reclaimActions[i].destination, tokenId);

            /* If the fname expires soon, extend its expiry by 30 days */
            if (block.timestamp >= _expiry - RENEWAL_PERIOD) {
                metadataOf[tokenId].expiryTs = uint40(block.timestamp + RENEWAL_PERIOD);
            }

            unchecked {
                i++; // Safety: the loop ends if i is >= reclaimActions.length
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Changes the address from which trustedRegister calls can be made
     *
     * @param _trustedCaller The address of the new trusted caller
     */
    function changeTrustedCaller(address _trustedCaller) external {
        /**
         * Revert if the caller is not an admin.
         *
         * Safety: use msg.sender since metaTxns are unnecessary for admin actions.
         */
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();

        /* Revert if the trustedCaller is being set to the zero address */
        if (_trustedCaller == address(0)) revert InvalidAddress();

        trustedCaller = _trustedCaller;

        emit ChangeTrustedCaller(_trustedCaller);
    }

    /**
     * @notice Disables trustedRegister and enables register calls from any address.
     */
    function disableTrustedOnly() external {
        /**
         * Revert if the caller is not an admin.
         *
         * Safety: use msg.sender since metaTxns are unnecessary for admin actions.
         */
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
        /**
         * Revert if the caller is not an admin.
         *
         * Safety: use msg.sender since metaTxns are unnecessary for admin actions.
         */
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();

        /* Revert if the vault is being set to the zero address */
        if (_vault == address(0)) revert InvalidAddress();

        vault = _vault;

        emit ChangeVault(_vault);
    }

    /**
     * @notice Changes the address to which names are reclaimed
     *
     * @param _pool The address of the new pool
     */
    function changePool(address _pool) external {
        /**
         * Revert if the caller is not an admin.
         *
         * Safety: use msg.sender since metaTxns are unnecessary for admin actions.
         */
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        if (_pool == address(0)) revert InvalidAddress();

        pool = _pool;
        emit ChangePool(_pool);
    }

    /*//////////////////////////////////////////////////////////////
                            TREASURER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Change the fee charged to register an fname for a year
     *
     * @param _fee The new yearly fee
     */
    function changeFee(uint256 _fee) external {
        /**
         * Revert if the caller is not a treasurer.
         *
         * Safety: use msg.sender since metaTxns are unnecessary for admin actions.
         */
        if (!hasRole(TREASURER_ROLE, msg.sender)) revert NotTreasurer();

        /* Audit does fee == 0 cause any problems with other logic? */
        fee = _fee;

        emit ChangeFee(_fee);
    }

    /**
     * @notice Withdraw a specified amount of ether to the vault
     *
     * @param amount The amount of ether to withdraw
     */
    function withdraw(uint256 amount) external {
        /**
         * Revert if the caller is not a treasurer.
         *
         * Safety: use msg.sender since metaTxns are unnecessary for admin actions.
         */
        if (!hasRole(TREASURER_ROLE, msg.sender)) revert NotTreasurer();

        /* Audit: this will not revert if the requested amount is zero, will that cause problems? */
        if (address(this).balance < amount) revert InsufficientFunds();

        /* Transfer the funds to the vault and revert if the transfer fails */
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = vault.call{value: amount}("");
        if (!success) revert CallFailed();
    }

    /*//////////////////////////////////////////////////////////////
                            OPERATOR ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause contract and stop fname registrations, renewals, recoveries and transfers.
     */
    function pause() external {
        /**
         * Revert if the caller is not an operator.
         *
         * Safety: use msg.sender since metaTxns are unnecessary for admin actions.
         */
        if (!hasRole(OPERATOR_ROLE, msg.sender)) revert NotOperator();

        _pause();
    }

    /**
     * @notice Unpause contract and resume fname registrations, renewals, recoveries and transfers.
     */
    function unpause() external {
        /**
         * Revert if the caller is not an operator.
         *
         * Safety: use msg.sender since metaTxns are unnecessary for admin actions.
         */
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

    function _msgData()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
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
     * @dev Reverts if the fname contains an invalid character
     *
     * Iterate over the bytes16 fname one char at a time, ensuring that:
     *   1. The name begins with [a-z 0-9] or the ascii numbers [48-57, 97-122] inclusive
     *   2. The name can contain [a-z 0-9 -] or the ascii numbers [45, 48-57, 97-122] inclusive
     *   3. Once the name is ended with a NULL char (0), the follows character must also be NULLs
     */
    // solhint-disable-next-line code-complexity
    function _validateName(bytes16 fname) internal pure {
        /* Revert if the name begins with a hyphen */
        if (uint8(fname[0]) == 45) revert InvalidName();

        uint256 length = fname.length;
        bool nameEnded = false;

        for (uint256 i = 0; i < length;) {
            uint8 charInt = uint8(fname[i]);

            unchecked {
                i++; // Safety: i can never overflow because length is <= 16
            }

            if (nameEnded) {
                /* Revert if non NULL characters are found after a NULL character */
                if (charInt != 0) {
                    revert InvalidName();
                }
            } else {
                if ((charInt >= 97 && charInt <= 122)) {
                    continue; // The character is one of a-z
                }

                if ((charInt >= 48 && charInt <= 57)) {
                    continue; // The character is one of 0-9
                }

                if ((charInt == 45)) {
                    continue; // The character is a hyphen
                }

                /**
                 * If a null character is discovered in the fname:
                 * - revert if it is the first character, since the name must have at least 1 non NULL character
                 * - otherwise, mark the name as having ended, with the null indicating unused bytes.
                 */
                if (charInt == 0) {
                    if (i == 1) revert InvalidName(); // Check i==1 since i is incremented before the check

                    nameEnded = true;
                    continue;
                }

                /* Revert if invalid ASCII characters are found before the name ends    */
                revert InvalidName();
            }
        }
    }
}
