// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  AcademicLedger
 * @notice Immutable, timestamped audit trail for academic contributions.
 *         Logs a researcher's wallet address, the IPFS CID of their uploaded
 *         evidence, and their standardized CRediT taxonomy role.
 *
 * @dev    CRITICAL DESIGN CONSTRAINT:
 *         There is NO scoring, weighting, or percentage calculation in this
 *         contract. It is strictly a logging and validation system.
 *         Every contribution record is append-only and cannot be modified
 *         or deleted after it is written.
 */
contract AcademicLedger {

    // ─────────────────────────────────────────────────────────────────────────
    // Data Structures
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Represents a single logged contribution.
     * @dev    Stored on-chain for direct querying. The ContributionLogged
     *         event mirrors this struct for off-chain indexing via ethers.js.
     */
    struct Contribution {
        address contributor;   // wallet address of the researcher
        string  cid;           // IPFS CID of the uploaded evidence artifact
        string  creditRole;    // CRediT taxonomy role (e.g. "Methodology")
        uint256 timestamp;     // block.timestamp at time of logging
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State Variables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice The address that deployed this contract. Has admin privileges.
    address public owner;

    /**
     * @notice Maps a projectId string to all contributions logged for it.
     * @dev    projectId is an arbitrary string (e.g. "project-alpha-001").
     *         Using a string key keeps the frontend integration simple —
     *         no need to hash or encode project identifiers.
     */
    mapping(string => Contribution[]) private contributions;

    /**
     * @notice Tracks which wallet addresses are authorized to log
     *         contributions for a given project.
     * @dev    mapping: projectId => (walletAddress => isAuthorized)
     */
    mapping(string => mapping(address => bool)) private authorizedCollaborators;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Emitted every time a contribution is successfully logged.
     * @dev    This is the event your AuditTrail.jsx component queries via
     *         contract.queryFilter(). The indexed parameters allow filtering
     *         by projectId and contributor address efficiently.
     *
     * @param projectId   The project this contribution belongs to.
     * @param contributor The wallet address of the researcher (msg.sender).
     * @param cid         The IPFS CID of the evidence artifact.
     * @param creditRole  The CRediT taxonomy role string.
     * @param timestamp   The block timestamp when this was logged.
     */
    event ContributionLogged(
        string  indexed projectId,
        address indexed contributor,
        string          cid,
        string          creditRole,
        uint256         timestamp
    );

    /**
     * @notice Emitted when a collaborator is granted access to a project.
     */
    event CollaboratorAuthorized(string indexed projectId, address indexed collaborator);

    /**
     * @notice Emitted when a collaborator's access is revoked.
     */
    event CollaboratorRevoked(string indexed projectId, address indexed collaborator);

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Restricts a function to the contract owner only.
    modifier onlyOwner() {
        require(msg.sender == owner, "AcademicLedger: caller is not the owner");
        _;
    }

    /**
     * @dev Restricts a function to wallets authorized for a specific project.
     *      The owner is always implicitly authorized for every project.
     */
    modifier onlyAuthorized(string calldata projectId) {
        require(
            msg.sender == owner || authorizedCollaborators[projectId][msg.sender],
            "AcademicLedger: caller is not authorized for this project"
        );
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Sets the deploying wallet as the contract owner.
     */
    constructor() {
        owner = msg.sender;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Write Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Logs a contribution on-chain for a given project.
     * @dev    Called by LogContributionForm.jsx after IPFS upload succeeds.
     *         The contributor address is taken from msg.sender automatically —
     *         it cannot be spoofed since MetaMask signs the transaction.
     *
     * @param projectId  The identifier of the project being contributed to.
     * @param cid        The IPFS CID returned by Pinata after file upload.
     * @param creditRole One of the 14 CRediT taxonomy role strings.
     */
    function logContribution(
        string calldata projectId,
        string calldata cid,
        string calldata creditRole
    ) external onlyAuthorized(projectId) {
        // Validate inputs — prevent empty strings being logged
        require(bytes(projectId).length > 0,  "AcademicLedger: projectId is empty");
        require(bytes(cid).length > 0,         "AcademicLedger: CID is empty");
        require(bytes(creditRole).length > 0,  "AcademicLedger: creditRole is empty");

        // Build the contribution record
        Contribution memory entry = Contribution({
            contributor: msg.sender,
            cid:         cid,
            creditRole:  creditRole,
            timestamp:   block.timestamp
        });

        // Append to the project's contribution array (append-only, never modified)
        contributions[projectId].push(entry);

        // Emit the event — this is what AuditTrail.jsx reads via queryFilter()
        emit ContributionLogged(
            projectId,
            msg.sender,
            cid,
            creditRole,
            block.timestamp
        );
    }

    /**
     * @notice Grants a wallet address permission to log contributions
     *         for a specific project.
     * @dev    Only the owner can call this. Call this once per collaborator
     *         before they can use the LogContributionForm.
     *
     * @param projectId     The project to grant access to.
     * @param collaborator  The wallet address to authorize.
     */
    function authorizeCollaborator(
        string calldata projectId,
        address collaborator
    ) external onlyOwner {
        require(collaborator != address(0), "AcademicLedger: zero address");
        authorizedCollaborators[projectId][collaborator] = true;
        emit CollaboratorAuthorized(projectId, collaborator);
    }

    /**
     * @notice Revokes a collaborator's permission for a specific project.
     * @dev    This does NOT delete their existing contribution records —
     *         those are permanent. It only prevents future logging.
     *
     * @param projectId     The project to revoke access from.
     * @param collaborator  The wallet address to revoke.
     */
    function revokeCollaborator(
        string calldata projectId,
        address collaborator
    ) external onlyOwner {
        authorizedCollaborators[projectId][collaborator] = false;
        emit CollaboratorRevoked(projectId, collaborator);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read Functions
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns all contributions logged for a given project.
     * @dev    Used as a fallback direct read. Your frontend primarily uses
     *         event logs (queryFilter) which is cheaper for large datasets,
     *         but this function is useful for testing and verification.
     *
     * @param projectId  The project to query.
     * @return           Array of all Contribution structs for that project.
     */
    function getContributions(string calldata projectId)
        external
        view
        returns (Contribution[] memory)
    {
        return contributions[projectId];
    }

    /**
     * @notice Returns the total number of contributions for a project.
     * @param projectId  The project to query.
     * @return           The count of logged contributions.
     */
    function getContributionCount(string calldata projectId)
        external
        view
        returns (uint256)
    {
        return contributions[projectId].length;
    }

    /**
     * @notice Checks whether a wallet is authorized for a project.
     * @param projectId     The project to check.
     * @param collaborator  The wallet address to check.
     * @return              True if authorized, false otherwise.
     */
    function isAuthorized(string calldata projectId, address collaborator)
        external
        view
        returns (bool)
    {
        return collaborator == owner || authorizedCollaborators[projectId][collaborator];
    }
}