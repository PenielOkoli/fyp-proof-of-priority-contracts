// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  AcademicLedger v5
 * @notice DLT Proof-of-Priority with dispute flagging and configurable finalization state machine.
 *
 * NEW IN v5:
 *   - Dispute Flags: isDisputed mapping by contribution hash; flagByAdmin() emits event
 *   - Finalization State Machine: admin-selected countdown, opt-out, sealed projects
 *   - ContributionDisputed event logs dispute reason off-chain (zero storage)
 *   - FinalizationInitiated, FinalizationHalted, FinalizationExecuted events
 *   - getProjectCollaborators() remains for roster iteration
 */
contract AcademicLedger {

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    struct Contribution {
        address contributor;
        string  cid;
        string  creditRole;
        uint256 timestamp;
    }

    struct ResearcherProfile {
        string  name;
        string  orcid;
        address walletAddress;
        uint256 registeredAt;
        bool    exists;
    }

    struct ProjectFinalization {
        bool    isFinalizationActive;
        uint256 finalizationDeadline;
        bool    isFinalized;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State Variables
    // ─────────────────────────────────────────────────────────────────────────

    address public owner;

    mapping(string  => Contribution[])            private contributions;
    mapping(string  => mapping(address => bool))  public  authorizedCollaborators;
    mapping(address => ResearcherProfile)          public  researcherProfiles;
    mapping(string  => address)                    public  projectAdmins;
    mapping(address => string[])                   public  userProjects;
    mapping(string  => bool)                       private projectExists;
    string[]                                       public  allProjects;

    // Roster of all addresses ever authorized per project
    mapping(string  => address[])                  public  projectCollaborators;

    // NEW: Dispute flags and finalization state
    mapping(bytes32 => bool)                       public  isDisputed;
    mapping(string  => ProjectFinalization)        public  projectFinalization;

    uint256 public constant MIN_FINALIZATION_DURATION = 1 days;
    uint256 public constant MAX_FINALIZATION_DURATION = 30 days;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event ContributionLogged(
        string  indexed projectId,
        address indexed contributor,
        string          cid,
        string          creditRole,
        uint256         timestamp
    );
    event ProfileRegistered(
        address indexed wallet,
        string          name,
        string          orcid,
        uint256         timestamp
    );
    event ProjectInitialized(
        string  indexed projectId,
        address indexed admin,
        uint256         timestamp
    );
    event CollaboratorAuthorized(
        string  indexed projectId,
        address indexed collaborator
    );
    event CollaboratorRevoked(
        string  indexed projectId,
        address indexed collaborator
    );
    event ProjectAdminTransferred(
        string  indexed projectId,
        address indexed previousAdmin,
        address indexed newAdmin,
        uint256         timestamp
    );

    // NEW: Dispute and Finalization Events
    event ContributionDisputed(
        string  indexed projectId,
        bytes32 indexed contributionHash,
        string          reason
    );
    event FinalizationInitiated(
        string  indexed projectId,
        address indexed admin,
        uint256         deadline
    );
    event FinalizationHalted(
        string  indexed projectId,
        address indexed haltedBy,
        uint256         timestamp
    );
    event FinalizationExecuted(
        string  indexed projectId,
        uint256         timestamp
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "AcademicLedger: not contract owner");
        _;
    }

    modifier onlyProjectAdmin(string memory _projectId) {
        require(
            msg.sender == projectAdmins[_projectId],
            "AcademicLedger: not project admin"
        );
        _;
    }

    modifier onlyAuthorized(string calldata _projectId) {
        require(
            authorizedCollaborators[_projectId][msg.sender],
            "AcademicLedger: caller not authorized for this project"
        );
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Identity Registry
    // ─────────────────────────────────────────────────────────────────────────

    function registerProfile(
        string calldata _name,
        string calldata _orcid
    ) external {
        require(bytes(_name).length  > 0,    "AcademicLedger: name empty");
        require(bytes(_orcid).length > 0,    "AcademicLedger: orcid empty");
        require(bytes(_name).length  <= 128, "AcademicLedger: name too long");
        require(bytes(_orcid).length <= 24,  "AcademicLedger: orcid too long");

        ResearcherProfile storage p = researcherProfiles[msg.sender];
        uint256 regTime = p.exists ? p.registeredAt : block.timestamp;

        researcherProfiles[msg.sender] = ResearcherProfile({
            name:          _name,
            orcid:         _orcid,
            walletAddress: msg.sender,
            registeredAt:  regTime,
            exists:        true
        });

        emit ProfileRegistered(msg.sender, _name, _orcid, block.timestamp);
    }

    function getProfile(address _wallet)
        external view returns (ResearcherProfile memory)
    {
        return researcherProfiles[_wallet];
    }

    function hasProfile(address _wallet) external view returns (bool) {
        return researcherProfiles[_wallet].exists;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Project Management
    // ─────────────────────────────────────────────────────────────────────────

    function initializeProject(string calldata _projectId) external {
        require(bytes(_projectId).length > 0,   "AcademicLedger: projectId empty");
        require(bytes(_projectId).length <= 64,  "AcademicLedger: projectId too long");
        require(!projectExists[_projectId],       "AcademicLedger: project already exists");

        projectExists[_projectId]                       = true;
        projectAdmins[_projectId]                       = msg.sender;
        authorizedCollaborators[_projectId][msg.sender] = true;
        userProjects[msg.sender].push(_projectId);
        allProjects.push(_projectId);
        projectCollaborators[_projectId].push(msg.sender); // roster track creator

        emit ProjectInitialized(_projectId, msg.sender, block.timestamp);
        emit CollaboratorAuthorized(_projectId, msg.sender);
    }

    function getUserProjects(address _user)
        public view returns (string[] memory)
    {
        string[] memory owned = userProjects[_user];
        uint count = owned.length;
        for (uint i = 0; i < allProjects.length; i++) {
            if (authorizedCollaborators[allProjects[i]][_user]) {
                bool already = false;
                for (uint j = 0; j < owned.length; j++) {
                    if (keccak256(abi.encodePacked(owned[j])) == keccak256(abi.encodePacked(allProjects[i]))) {
                        already = true;
                        break;
                    }
                }
                if (!already) {
                    count++;
                }
            }
        }
        string[] memory result = new string[](count);
        uint idx = 0;
        for (uint i = 0; i < owned.length; i++) {
            result[idx++] = owned[i];
        }
        for (uint i = 0; i < allProjects.length; i++) {
            if (authorizedCollaborators[allProjects[i]][_user]) {
                bool already = false;
                for (uint j = 0; j < owned.length; j++) {
                    if (keccak256(abi.encodePacked(owned[j])) == keccak256(abi.encodePacked(allProjects[i]))) {
                        already = true;
                        break;
                    }
                }
                if (!already) {
                    result[idx++] = allProjects[i];
                }
            }
        }
        return result;
    }

    function syncUserProjects(address _user) external {
        for (uint i = 0; i < allProjects.length; i++) {
            string memory proj = allProjects[i];
            if (authorizedCollaborators[proj][_user]) {
                // Check if already in userProjects
                bool already = false;
                for (uint j = 0; j < userProjects[_user].length; j++) {
                    if (keccak256(abi.encodePacked(userProjects[_user][j])) == keccak256(abi.encodePacked(proj))) {
                        already = true;
                        break;
                    }
                }
                if (!already) {
                    userProjects[_user].push(proj);
                }
            }
        }
    }

    function doesProjectExist(string calldata _projectId)
        external view returns (bool)
    {
        return projectExists[_projectId];
    }

    function isProjectAdmin(string calldata _projectId, address _wallet)
        external view returns (bool)
    {
        return projectAdmins[_projectId] == _wallet;
    }

    function transferProjectAdmin(
        string  calldata _projectId,
        address          _newAdmin
    ) external onlyProjectAdmin(_projectId) {
        require(_newAdmin != address(0), "AcademicLedger: zero address");
        require(_newAdmin != msg.sender,  "AcademicLedger: already admin");

        address previousAdmin = projectAdmins[_projectId];
        projectAdmins[_projectId] = _newAdmin;

        // Roster-track new admin only if not already in array
        if (!authorizedCollaborators[_projectId][_newAdmin]) {
            projectCollaborators[_projectId].push(_newAdmin);
        }
        authorizedCollaborators[_projectId][_newAdmin] = true;
        userProjects[_newAdmin].push(_projectId);

        emit ProjectAdminTransferred(_projectId, previousAdmin, _newAdmin, block.timestamp);
        emit CollaboratorAuthorized(_projectId, _newAdmin);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Collaborator Management
    // ─────────────────────────────────────────────────────────────────────────

    function authorizeCollaborator(
        string  calldata _projectId,
        address          _collaborator
    ) external onlyProjectAdmin(_projectId) {
        require(_collaborator != address(0), "AcademicLedger: zero address");

        // Only push to roster array if not already tracked
        if (!authorizedCollaborators[_projectId][_collaborator]) {
            projectCollaborators[_projectId].push(_collaborator);
            // Add project to collaborator's userProjects if not already there
            bool alreadyInUserProjects = false;
            for (uint i = 0; i < userProjects[_collaborator].length; i++) {
                if (keccak256(abi.encodePacked(userProjects[_collaborator][i])) == keccak256(abi.encodePacked(_projectId))) {
                    alreadyInUserProjects = true;
                    break;
                }
            }
            if (!alreadyInUserProjects) {
                userProjects[_collaborator].push(_projectId);
            }
        }

        authorizedCollaborators[_projectId][_collaborator] = true;
        emit CollaboratorAuthorized(_projectId, _collaborator);
    }

    function revokeCollaborator(
        string  calldata _projectId,
        address          _collaborator
    ) external onlyProjectAdmin(_projectId) {
        // NOTE: address stays in projectCollaborators array but
        // authorizedCollaborators flag is set to false.
        // The frontend filters by the flag when rendering the roster.
        authorizedCollaborators[_projectId][_collaborator] = false;
        // Remove from userProjects if not the project admin
        if (_collaborator != projectAdmins[_projectId]) {
            for (uint i = 0; i < userProjects[_collaborator].length; i++) {
                if (keccak256(abi.encodePacked(userProjects[_collaborator][i])) == keccak256(abi.encodePacked(_projectId))) {
                    // Shift elements to remove
                    for (uint j = i; j < userProjects[_collaborator].length - 1; j++) {
                        userProjects[_collaborator][j] = userProjects[_collaborator][j + 1];
                    }
                    userProjects[_collaborator].pop();
                    break;
                }
            }
        }
        emit CollaboratorRevoked(_projectId, _collaborator);
    }

    // ── NEW: Roster getter ────────────────────────────────────────────────
    /**
     * @notice Returns all addresses ever authorized for a project.
     * @dev    Includes revoked addresses — the frontend must filter by
     *         calling authorizedCollaborators(projectId, address) for each.
     *         This is the standard Solidity pattern for iterable mappings.
     */
    function getProjectCollaborators(string memory _projectId)
        public view returns (address[] memory)
    {
        return projectCollaborators[_projectId];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Dispute Management (Zero-Storage)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Admin flags a contribution as disputed. No reason stored on-chain.
     * @dev    Reason logged via event, keeping storage lean and costs low.
     *         Hash computed as keccak256(projectId + contributor + timestamp)
     *         to uniquely identify each contribution.
     */
    function flagContributionAsDisputed(
        string  calldata _projectId,
        address          _contributor,
        uint256          _timestamp,
        string  calldata _reason
    ) external onlyProjectAdmin(_projectId) {
        require(projectExists[_projectId], "AcademicLedger: project not initialized");
        require(bytes(_reason).length > 0 && bytes(_reason).length <= 512,
            "AcademicLedger: reason must be non-empty and <= 512 chars");

        bytes32 hash = keccak256(abi.encodePacked(_projectId, _contributor, _timestamp));
        isDisputed[hash] = true;

        emit ContributionDisputed(_projectId, hash, _reason);
    }

    /**
     * @notice Check if a contribution is flagged as disputed.
     */
    function checkIfDisputed(
        string  calldata _projectId,
        address          _contributor,
        uint256          _timestamp
    ) external view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(_projectId, _contributor, _timestamp));
        return isDisputed[hash];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Project Finalization (Configurable Opt-Out State Machine)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Admin initiates finalization countdown.
     * @dev    Starts a bounded review window. Any authorized user can halt it.
     *         Once sealed, no new contributions allowed.
     */
    function initiateFinalization(
        string calldata _projectId,
        uint256 _durationSeconds
    )
        external onlyProjectAdmin(_projectId)
    {
        require(projectExists[_projectId], "AcademicLedger: project not initialized");
        require(
            _durationSeconds >= MIN_FINALIZATION_DURATION &&
            _durationSeconds <= MAX_FINALIZATION_DURATION,
            "AcademicLedger: finalization duration out of range"
        );
        require(
            !projectFinalization[_projectId].isFinalized,
            "AcademicLedger: project already finalized"
        );

        uint256 deadline = block.timestamp + _durationSeconds;
        projectFinalization[_projectId] = ProjectFinalization({
            isFinalizationActive: true,
            finalizationDeadline: deadline,
            isFinalized:          false
        });

        emit FinalizationInitiated(_projectId, msg.sender, deadline);
    }

    /**
     * @notice Authorized user halts active finalization (resets timer).
     * @dev    Anyone authorized to contribute can halt if they spot an error.
     *         Resets the countdown to zero.
     */
    function haltFinalization(string calldata _projectId)
        external onlyAuthorized(_projectId)
    {
        ProjectFinalization storage fin = projectFinalization[_projectId];
        require(fin.isFinalizationActive, "AcademicLedger: finalization not active");
        require(!fin.isFinalized, "AcademicLedger: project already finalized");

        fin.isFinalizationActive = false;
        fin.finalizationDeadline  = 0;

        emit FinalizationHalted(_projectId, msg.sender, block.timestamp);
    }

    /**
     * @notice Anyone can seal the project once 7 days have elapsed.
     * @dev    Checks deadline, prevents re-entry, and locks the project.
     */
    function executeFinalization(string calldata _projectId)
        external
    {
        ProjectFinalization storage fin = projectFinalization[_projectId];
        require(fin.isFinalizationActive, "AcademicLedger: finalization not active");
        require(!fin.isFinalized, "AcademicLedger: already finalized");
        require(
            block.timestamp >= fin.finalizationDeadline,
            "AcademicLedger: deadline not reached"
        );

        fin.isFinalized = true;
        fin.isFinalizationActive = false;

        emit FinalizationExecuted(_projectId, block.timestamp);
    }

    /**
     * @notice Get finalization status of a project.
     */
    function getFinalizationStatus(string memory _projectId)
        external view returns (ProjectFinalization memory)
    {
        return projectFinalization[_projectId];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Contribution Logging
    // ─────────────────────────────────────────────────────────────────────────

    function logContribution(
        string calldata _projectId,
        string calldata _cid,
        string calldata _creditRole
    ) external onlyAuthorized(_projectId) {
        require(bytes(_projectId).length  > 0, "AcademicLedger: projectId empty");
        require(bytes(_cid).length        > 0, "AcademicLedger: cid empty");
        require(bytes(_creditRole).length > 0, "AcademicLedger: creditRole empty");
        require(projectExists[_projectId],      "AcademicLedger: project not initialized");

        // NEW: Check if project is finalized
        require(
            !projectFinalization[_projectId].isFinalized,
            "AcademicLedger: project is finalized"
        );

        contributions[_projectId].push(Contribution({
            contributor: msg.sender,
            cid:         _cid,
            creditRole:  _creditRole,
            timestamp:   block.timestamp
        }));

        emit ContributionLogged(_projectId, msg.sender, _cid, _creditRole, block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read Functions
    // ─────────────────────────────────────────────────────────────────────────

    function getContributions(string calldata _projectId)
        external view returns (Contribution[] memory)
    {
        return contributions[_projectId];
    }

    function getContributionCount(string calldata _projectId)
        external view returns (uint256)
    {
        return contributions[_projectId].length;
    }

    function isAuthorized(string calldata _projectId, address _collaborator)
        external view returns (bool)
    {
        return authorizedCollaborators[_projectId][_collaborator];
    }
}
