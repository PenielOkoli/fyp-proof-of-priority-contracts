// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AcademicLedger {

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

    address public owner;

    mapping(string => Contribution[]) private contributions;
    mapping(string => mapping(address => bool)) private authorizedCollaborators;
    mapping(address => ResearcherProfile) public researcherProfiles;

    event ContributionLogged(
        string  indexed projectId,
        address indexed contributor,
        string          cid,
        string          creditRole,
        uint256         timestamp
    );
    event CollaboratorAuthorized(string indexed projectId, address indexed collaborator);
    event CollaboratorRevoked(string indexed projectId, address indexed collaborator);
    event ProfileRegistered(
        address indexed wallet,
        string          name,
        string          orcid,
        uint256         timestamp
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "AcademicLedger: caller is not the owner");
        _;
    }

    modifier onlyAuthorized(string calldata projectId) {
        require(
            msg.sender == owner || authorizedCollaborators[projectId][msg.sender],
            "AcademicLedger: caller is not authorized for this project"
        );
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function registerProfile(
        string calldata _name,
        string calldata _orcid
    ) external {
        require(bytes(_name).length > 0,   "AcademicLedger: name cannot be empty");
        require(bytes(_orcid).length > 0,  "AcademicLedger: ORCID cannot be empty");
        require(bytes(_name).length <= 128, "AcademicLedger: name too long");
        require(bytes(_orcid).length <= 24,  "AcademicLedger: ORCID too long");

        ResearcherProfile storage profile = researcherProfiles[msg.sender];
        uint256 registrationTime = profile.exists ? profile.registeredAt : block.timestamp;

        researcherProfiles[msg.sender] = ResearcherProfile({
            name:          _name,
            orcid:         _orcid,
            walletAddress: msg.sender,
            registeredAt:  registrationTime,
            exists:        true
        });

        emit ProfileRegistered(msg.sender, _name, _orcid, block.timestamp);
    }

    function getProfile(address wallet)
        external view returns (ResearcherProfile memory)
    {
        return researcherProfiles[wallet];
    }

    function hasProfile(address wallet) external view returns (bool) {
        return researcherProfiles[wallet].exists;
    }

    function logContribution(
        string calldata projectId,
        string calldata cid,
        string calldata creditRole
    ) external onlyAuthorized(projectId) {
        require(bytes(projectId).length > 0,  "AcademicLedger: projectId empty");
        require(bytes(cid).length > 0,         "AcademicLedger: CID empty");
        require(bytes(creditRole).length > 0,  "AcademicLedger: creditRole empty");

        contributions[projectId].push(Contribution({
            contributor: msg.sender,
            cid:         cid,
            creditRole:  creditRole,
            timestamp:   block.timestamp
        }));

        emit ContributionLogged(projectId, msg.sender, cid, creditRole, block.timestamp);
    }

    function authorizeCollaborator(
        string calldata projectId,
        address collaborator
    ) external onlyOwner {
        require(collaborator != address(0), "AcademicLedger: zero address");
        authorizedCollaborators[projectId][collaborator] = true;
        emit CollaboratorAuthorized(projectId, collaborator);
    }

    function revokeCollaborator(
        string calldata projectId,
        address collaborator
    ) external onlyOwner {
        authorizedCollaborators[projectId][collaborator] = false;
        emit CollaboratorRevoked(projectId, collaborator);
    }

    function getContributions(string calldata projectId)
        external view returns (Contribution[] memory)
    {
        return contributions[projectId];
    }

    function getContributionCount(string calldata projectId)
        external view returns (uint256)
    {
        return contributions[projectId].length;
    }

    function isAuthorized(string calldata projectId, address collaborator)
        external view returns (bool)
    {
        return collaborator == owner || authorizedCollaborators[projectId][collaborator];
    }
}
