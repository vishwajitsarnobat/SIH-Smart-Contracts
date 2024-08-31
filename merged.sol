// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract ContractPlatform is ERC721URIStorage, ReentrancyGuard {

    uint256 public tokenCounter;
    uint256 public contractCounter;

    uint8 public constant STATUS_OPEN = 1;
    uint8 public constant STATUS_DONE = 2;
    uint8 public constant STATUS_COMPLETED = 3;
    uint8 public constant STATUS_CANCELLED = 4;

    uint256 public platformFeePercent = 2; // Platform fee percentage
    uint256 public applicationFee; // Fee for applying to a contract
    uint256 public companyCancellationFee; // Fee for companies cancelling a contract
    uint256 public farmerCancellationFee; // Fee for farmers cancelling a contract

    struct ContractDetails {
        address creator;
        uint256 tokenId;
        string commodity;
        uint256 rate;
        uint256 quantity;
        uint256 startAt;
        uint256 endAt;
        uint256 deliveryDate;
        uint8 status;
        address selectedApplicant;
        bool creatorAgreement;
        bool applicantAgreement;
        uint256 lockedFunds;
        bool isFarmerInitiated;
        uint256 requiredLandArea;
        bool isInspected;
        bool isInsured;
        address responsibleForLogistics;
        bool isFractional;
    }

    struct Application {
        address applicant;
        uint256 proposedAmount;
        string note;
    }

    event Minted(address indexed minter, uint256 nftID, string uri);
    event ContractCreated(uint256 contractId, address indexed creator, string commodity, uint256 rate, uint256 quantity, uint256 deliveryDate, uint256 tokenId, uint256 startAt, uint256 endAt, bool isFarmerInitiated, uint256 requiredLandArea, bool isFractional);
    event ApplicationSubmitted(uint256 contractId, address indexed applicant, uint256 proposedAmount, string note);
    event ApplicantSelected(uint256 contractId, address indexed creator, address indexed applicant);
    event ContractCompleted(uint256 contractId, address indexed creator, address indexed applicant);
    event ContractCancelled(uint256 contractId, address canceller, string reason);
    event ContractFulfilled(uint256 contractId, address indexed applicant, uint256 amount);
    event ContractInspected(uint256 contractId, bool inspectionStatus);
    event InsuranceStatusUpdated(uint256 contractId, bool isInsured);

    mapping(uint256 => ContractDetails) public contracts;
    mapping(uint256 => Application[]) public applications;
    mapping(address => uint256) public farmerLandArea;

    constructor() ERC721("KrishiNFT", "KNFT") {
        tokenCounter = 0;
        contractCounter = 0;
        applicationFee = 0.1 ether; // Set initial application fee
        companyCancellationFee = 1 ether; // Set initial company cancellation fee
        farmerCancellationFee = 0.5 ether; // Set initial farmer cancellation fee
    }

    function mint(string memory tokenURI, address minterAddress) public returns (uint256) {
        tokenCounter++;
        uint256 tokenId = tokenCounter;
        _safeMint(minterAddress, tokenId);
        _setTokenURI(tokenId, tokenURI);
        emit Minted(minterAddress, tokenId, tokenURI);
        return tokenId;
    }

    function createContract(
        string memory commodity,
        uint256 rate,
        uint256 quantity,
        uint256 deliveryDate,
        uint256 tokenId,
        uint256 durationInSeconds,
        bool isFarmerInitiated,
        uint256 requiredLandArea,
        address responsibleForLogistics,
        bool isFractional
    ) public returns (uint256) {
        contractCounter++;
        uint256 contractId = contractCounter;

        uint256 startAt = block.timestamp;
        uint256 endAt = startAt + durationInSeconds;

        contracts[contractId] = ContractDetails({
            creator: msg.sender,
            tokenId: tokenId,
            commodity: commodity,
            rate: rate,
            quantity: quantity,
            status: STATUS_OPEN,
            startAt: startAt,
            endAt: endAt,
            deliveryDate: deliveryDate,
            selectedApplicant: address(0),
            creatorAgreement: false,
            applicantAgreement: false,
            lockedFunds: 0,
            isFarmerInitiated: isFarmerInitiated,
            requiredLandArea: requiredLandArea,
            isInspected: false,
            isInsured: false,
            responsibleForLogistics: responsibleForLogistics,
            isFractional: isFractional
        });

        _transfer(msg.sender, address(this), tokenId);
        emit ContractCreated(contractId, msg.sender, commodity, rate, quantity, deliveryDate, tokenId, startAt, endAt, isFarmerInitiated, requiredLandArea, isFractional);
        return contractId;
    }

    function applyForContract(uint256 contractId, uint256 proposedAmount, string memory note) public payable nonReentrant {
        require(isContractOpen(contractId), 'Contract is no longer open for applications');
        ContractDetails storage contractDetails = contracts[contractId];
        require(msg.sender != contractDetails.creator, "Contract creator cannot apply");
        require(msg.value >= proposedAmount + applicationFee, "Insufficient funds sent");

        Application memory application = Application({
            applicant: msg.sender,
            proposedAmount: proposedAmount,
            note: note
        });

        applications[contractId].push(application);

        emit ApplicationSubmitted(contractId, msg.sender, proposedAmount, note);
    }

    function selectApplicant(uint256 contractId, address applicant) public nonReentrant {
        ContractDetails storage contractDetails = contracts[contractId];
        require(msg.sender == contractDetails.creator, "Only contract creator can select applicant");
        require(isContractOpen(contractId), 'Contract is no longer open');

        bool applicantFound = false;
        uint256 proposedAmount = 0;
        string memory note;
        for (uint i = 0; i < applications[contractId].length; i++) {
            if (applications[contractId][i].applicant == applicant) {
                applicantFound = true;
                proposedAmount = applications[contractId][i].proposedAmount;
                note = applications[contractId][i].note;
                break;
            }
        }
        require(applicantFound, "Selected applicant did not apply for this contract");

        // Check if the farmer has enough land area
        if (!contractDetails.isFarmerInitiated) {
            require(farmerLandArea[applicant] >= contractDetails.requiredLandArea, "Farmer does not have enough land area");
        }

        contractDetails.selectedApplicant = applicant;
        contractDetails.status = STATUS_DONE;

        // Lock funds from the company
        if (contractDetails.isFarmerInitiated) {
            require(msg.value >= proposedAmount, "Insufficient funds sent by company");
            contractDetails.lockedFunds = proposedAmount;
        }

        _transfer(address(this), applicant, contractDetails.tokenId);

        // Update contract details based on negotiation
        // This part would typically involve more complex logic to parse and apply changes from the note
        // For simplicity, we're just emitting an event with the note
        emit ApplicantSelected(contractId, msg.sender, applicant);
    }

    function agreeFulfillment(uint256 contractId) public {
        ContractDetails storage contractDetails = contracts[contractId];
        require(contractDetails.status == STATUS_DONE, "Contract must be completed before fulfilling it");
        require(msg.sender == contractDetails.creator || msg.sender == contractDetails.selectedApplicant, "Only creator or selected applicant can agree to fulfillment");

        if (msg.sender == contractDetails.creator) {
            contractDetails.creatorAgreement = true;
        } else if (msg.sender == contractDetails.selectedApplicant) {
            contractDetails.applicantAgreement = true;
        }

        if (contractDetails.creatorAgreement && contractDetails.applicantAgreement) {
            fulfillContract(contractId);
        }
    }

    function fulfillContract(uint256 contractId) internal nonReentrant {
        ContractDetails storage contractDetails = contracts[contractId];
        address payable recipient = payable(contractDetails.isFarmerInitiated ? contractDetails.creator : contractDetails.selectedApplicant);

        uint256 amount = contractDetails.lockedFunds;
        contractDetails.status = STATUS_COMPLETED;
        contractDetails.lockedFunds = 0;

        uint256 platformFee = (amount * platformFeePercent) / 100;
        uint256 finalAmount = amount - platformFee;

        (bool sent, ) = recipient.call{value: finalAmount}("");
        require(sent, "Failed to release funds to recipient");

        (bool feeSent, ) = address(this).call{value: platformFee}("");
        require(feeSent, "Failed to transfer platform fee");

        // Refund application fee to the selected applicant
        (bool refundSent, ) = payable(contractDetails.selectedApplicant).call{value: applicationFee}("");
        require(refundSent, "Failed to refund application fee");

        emit ContractFulfilled(contractId, contractDetails.selectedApplicant, amount);
    }

    function cancelContract(uint256 contractId, string memory reason) public payable {
        ContractDetails storage contractDetails = contracts[contractId];
        require(msg.sender == contractDetails.creator || msg.sender == contractDetails.selectedApplicant, "Only the creator or selected applicant can cancel the contract");
        require(contractDetails.status == STATUS_OPEN || contractDetails.status == STATUS_DONE, "Can only cancel open or in-progress contracts");

        uint256 cancellationFee = msg.sender == contractDetails.creator && !contractDetails.isFarmerInitiated ? 
            companyCancellationFee : farmerCancellationFee;

        require(msg.value >= cancellationFee, "Insufficient cancellation fee");

        contractDetails.status = STATUS_CANCELLED;

        if (contractDetails.status == STATUS_DONE) {
            // Refund locked funds
            if (contractDetails.isFarmerInitiated) {
                (bool sent, ) = payable(contractDetails.creator).call{value: contractDetails.lockedFunds}("");
                require(sent, "Failed to refund locked funds");
            }
            _transfer(contractDetails.selectedApplicant, contractDetails.creator, contractDetails.tokenId);
        } else {
            _transfer(address(this), contractDetails.creator, contractDetails.tokenId);
        }

        emit ContractCancelled(contractId, msg.sender, reason);
    }

    function setInspectionStatus(uint256 contractId, bool status) public {
        ContractDetails storage contractDetails = contracts[contractId];
        require(msg.sender == contractDetails.creator, "Only the creator can update inspection status");
        contractDetails.isInspected = status;
        emit ContractInspected(contractId, status);
    }

    function setInsuranceStatus(uint256 contractId, bool status) public {
        // In a real-world scenario, this function would be restricted to authorized insurance providers or government entities
        ContractDetails storage contractDetails = contracts[contractId];
        contractDetails.isInsured = status;
        emit InsuranceStatusUpdated(contractId, status);
    }

    function updateFarmerLandArea(address farmer, uint256 landArea) public {
        // In a real-world scenario, this function would be restricted to authorized entities
        farmerLandArea[farmer] = landArea;
    }

    function isContractOpen(uint256 id) public view returns (bool) {
        return contracts[id].status == STATUS_OPEN && contracts[id].endAt > block.timestamp;
    }

    function getApplications(uint256 contractId) public view returns (Application[] memory) {
        return applications[contractId];
    }

    function setApplicationFee(uint256 newFee) public {
        // In a real-world scenario, this function would be restricted to contract owner or governance mechanism
        applicationFee = newFee;
    }

    function setCancellationFees(uint256 newCompanyFee, uint256 newFarmerFee) public {
        // In a real-world scenario, this function would be restricted to contract owner or governance mechanism
        companyCancellationFee = newCompanyFee;
        farmerCancellationFee = newFarmerFee;
    }

    fallback() external payable {
        revert("Fallback function called");
    }

    receive() external payable {
        revert("Direct Ether not accepted");
    }
}