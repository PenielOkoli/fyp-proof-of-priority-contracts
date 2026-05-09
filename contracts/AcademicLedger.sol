// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  AcademicLedger v4
 * @notice DLT Proof-of-Priority — adds iterable collaborator roster per project.
 *
 * NEW IN v4:
 *   - mapping(string => address[]) public projectCollaborators
 *   - getProjectCollaborators() getter
 *   - initializeProject() pushes creator to roster
 *   - authorizeCollaborator() pushes new address (deduplication guard)
 *   - transferProjectAdmin() also roster-tracks the new admin
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

    // NEW: iterable roster of all addresses ever authorized per project
    mapping(string  => address[])                  public  projectCollaborators;

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
        projectCollaborators[_projectId].push(msg.sender); // roster track creator

        emit ProjectInitialized(_projectId, msg.sender, block.timestamp);
        emit CollaboratorAuthorized(_projectId, msg.sender);
    }

    function getUserProjects(address _user)
        public view returns (string[] memory)
    {
        return userProjects[_user];
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