// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

//to fix debugger in vscode
// import "./vscode_/a.sol";
// import "./vscode_/ReentrancyGuard.sol";

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract ContractPlatform is ERC721URIStorage, ReentrancyGuard {
    uint256 public tokenCounter;
    uint256 public contractCounter;

    enum Status {
        OPEN,
        ALLOTED,
        AGREED,
        COMPLETED,
        CANCELLED
    }

    uint256 immutable public platformFeePercent; 
    uint256 immutable applicationFee; 
    uint256 immutable cancellationFee; 
    address immutable platform_; 

    struct ContractDetails {
        /*contract goods details */
        address creator;
        bool isCreatorFarmer;
        uint256 tokenId;
        string commodity;
        uint256 rate;
        uint32 quantity;
        uint256 lockInAmount;
        string[] clauses;
        uint256 deliveryDate;
        Status status; 
        
        //-90 to 90 for latitude and -180 to 180 for longitude. multiply by 10^6.
        //max: 10^9
        //int 32 max 10^10
        int32 deliveryLatitude;
        int32 deliveryLongitude;
        
        /*contract delivery related */
        //start and end of application acceptance
        uint256 startAt;
        uint256 endAt;
        address selectedApplicant;
        string cancellationReason;
        bool creatorAgreement;
        bool applicantAgreement;
        

        //used for fetching
        bool creatorResponsibleForLogistics; 
        string quality; 
    }

    struct Application {
        address applicant;
        uint256 proposedRate;
        string note;
    }
    //number of contracts and applications are linked
    mapping(uint256 => ContractDetails) public contracts;
    mapping(uint256 => Application[]) public applications;


    event Minted(address indexed minter, uint256 nftID, string uri);
    event ContractCreated(
        address creator,
        bool isCreatorFarmer,
        uint256 contractId,
        uint256 tokenId,
        string commodity,
        uint256 rate,
        uint32 quantity,
        string[]  clauses,
        int32 deliveryLatitude,
        int32 deliveryLongitude,
        uint256 startAt,
        uint256 endAt,
        uint256 deliveryDate,
        uint256 lockInAmount,
        bool creatorResponsibleForLogistics,
        string  quality
        
    );
    event ApplicationSubmitted(uint256 contractId,address indexed applicant,uint256 proposedRate,string note);
    event ApplicantSelected(uint256 contractId,address indexed creator,address indexed applicant,uint256 rate,string note);
    event ContractAgreed(uint256 contractId,address indexed creator,address indexed applicant);
    event ContractCompleted(uint256 contractId,address indexed creator,address indexed applicant,uint256 rate,uint32 quantity);
    event ContractCancelled(uint256 contractId,address canceller,string reason);
    


    modifier notCreator(uint256 contractId) {
        require(msg.sender != contracts[contractId].creator,"Creator cannot apply for their own contract");
        _;
    }
    modifier onlyCreator(uint256 contractId) {
        require(msg.sender == contracts[contractId].creator,"Only creator can perform this action");
        _;
    }
    modifier onlyApplicant(uint256 contractId) {
        require(msg.sender == contracts[contractId].selectedApplicant,"Only selected applicant can perform this action");
        _;
    }
    modifier onlyCreatorOrApplicant(uint256 contractId) {
        require(msg.sender == contracts[contractId].creator || msg.sender == contracts[contractId].selectedApplicant,"Only creator or selected applicant can perform this action");
        _;
    }
    modifier onlyBuyer(uint256 contractId) {
        bool CallerIsCreator = (msg.sender == contracts[contractId].creator);
        bool CreatorisFarmer = contracts[contractId].isCreatorFarmer;
        require(CallerIsCreator || msg.sender == contracts[contractId].selectedApplicant,"Only creator or selected applicant can perform this action");
        require((CallerIsCreator && !CreatorisFarmer) || (!CallerIsCreator && CreatorisFarmer) ,"Only selected applicant can perform this action");
        _;
    }
    constructor() ERC721("KrishiNFT", "KNFT") {
        tokenCounter = 0;
        contractCounter = 0;
        platformFeePercent = 5; 
        applicationFee = 0.1 ether; 
        cancellationFee = 0.5 ether; 

        platform_ = msg.sender;
    }
    //contractopenfor is from current time
    //nonReentrant: use for any payable function or one that tranfers money
    //charging cancellation fees to take it in case of cancellation and to prevent bogus contracts
    function createContract(
        address creator,
        bool isCreatorFarmer,
        uint256 tokenId,
        string memory commodity,
        uint256 rate,
        uint32 quantity,
        string[] memory clauses,
        int32 deliveryLatitude,
        int32 deliveryLongitude,
        uint256 contractOpenFor,
        uint256 deliveryDate,
        bool creatorResponsibleForLogistics,
        string memory quality
    ) external payable nonReentrant returns (uint256) {
        require(msg.value == cancellationFee, "Incorrect creation fee sent");
        require(contractOpenFor< deliveryDate, "Contract cannot open after delivery date");
        contractCounter++;
        //counter is id currently
        contracts[contractCounter] = ContractDetails({
            creator: creator,
            isCreatorFarmer: isCreatorFarmer,
            tokenId: tokenId,
            commodity: commodity,
            rate: rate,
            quantity: quantity,
            clauses: clauses,
            deliveryLatitude: deliveryLatitude,
            deliveryLongitude: deliveryLongitude,
            startAt: block.timestamp,
            endAt: block.timestamp + contractOpenFor,
            deliveryDate: deliveryDate,
            status: Status.OPEN,
            selectedApplicant: address(0),
            cancellationReason: "",
            creatorAgreement: false,
            applicantAgreement: false,
            creatorResponsibleForLogistics: creatorResponsibleForLogistics,
            quality: quality
            });
        //number should be greater than 100 and last 2 decimal places should be 0, or leads to error
        //so better to use getContractRate to get the rate in front end
        //charging 5% of the total amount as lock in.
        contracts[contractCounter].lockInAmount = (rate * quantity * 5) / 100;

        _transfer(msg.sender, address(this), tokenId);
        emit ContractCreated(
            creator,
            isCreatorFarmer,
            contractCounter,
            tokenId,
            commodity,
            rate,
            quantity,
            clauses,
            deliveryLatitude,
            deliveryLongitude,
            contracts[contractCounter].startAt,
            contracts[contractCounter].endAt,
            deliveryDate,
            creatorResponsibleForLogistics,
            quality
        );
        return contractId;
    }

    function mint(
        string memory tokenURI,
        address minterAddress
    ) external returns (uint256) {
        tokenCounter++;
        uint256 tokenId = tokenCounter;
        _safeMint(minterAddress, tokenId);
        _setTokenURI(tokenId, tokenURI);
        emit Minted(minterAddress, tokenId, tokenURI);
        return tokenId;
    }

    //not charging farmers anything for bidding
    function applyForContract(uint256 contractId,uint256 proposedRate,string memory note) external payable nonReentrant notCreator(contractId) 
    {
        require(isContractOpen(contractId),"Contract is no longer open for applications");
        ContractDetails storage contractDetails = contracts[contractId];
        uint256 amount;
        if(!contractDetails.isCreatorFarmer){
            amount = 0;
            require(msg.value == amount,"No funds should be sent for this contract");
        }
        else{
            
            require(msg.value == contractDetails.lockInAmount,"Insufficient funds sent");
        }

        Application memory application = Application({
            applicant: msg.sender,
            proposedRate: proposedRate,
            note: note
        });

        applications[contractId].push(application);

        emit ApplicationSubmitted(contractId, msg.sender, proposedRate, note);
        //if someone bids at very end, add time to contract
        if (contractDetails.endAt < block.timestamp+10 minutes) {
            contractDetails.endAt = block.timestamp + 1 hours;
        }
    }


    function selectApplicant(uint256 contractId,address applicant) external nonReentrant onlyCreator(contractId) {
        ContractDetails storage contractDetails = contracts[contractId];

        require(isContractOpen(contractId), "Contract is no longer open");

        bool applicantFound = false;
        uint256 index;
        for (uint256 i = 0; i < applications[contractId].length; i++) {
            
            if (applications[contractId][i].applicant == applicant) {
                applicantFound = true;
                break;
            }
        }
        require(applicantFound,"Selected applicant did not apply for this contract");

        //changing contract to reflect the selected applicant
        //doesnt allow advnaved changes to contract
        contractDetails.rate = applications[contractId][index].proposedRate;
        contractDetails.selectedApplicant = applicant;
        contractDetails.status = Status.ALLOTED;
        freeFunds(contractId);
        emit ApplicantSelected(contractId, msg.sender, applicant,contractDetails.rate,applications[contractId][index].note);
        //should be deleted or not?
        delete applications[contractId];
        
        //this line was here before modification. i dont understand what it does, so im leaving it for now
        _transfer(address(this), applicant, contractDetails.tokenId);
    }
    

    function freeFunds(uint256 contractId,address exclude) internal {
        ContractDetails storage contractDetails = contracts[contractId];
        if (!contractDetails.isCreatorFarmer) {
            return ;
        }
        //send back money to all applicants except the selected one
        for (uint i = 0; i < applications[contractId].length; i++) {
            if (applications[contractId][i].applicant != exclude ) {
                (bool sent, ) = payable(applications[contractId][i].applicant).call{value: contractDetails.lockInAmount }("");
                require(sent, "Failed to refund application fee");
            }
        }
    }
    function agreeFulfillment(uint256 contractId) external payable nonReentrant onlyCreatorOrApplicant {
        ContractDetails storage contractDetails = contracts[contractId];
        require( contractDetails.status == Status.ALLOTED,"Contract must be alloted before agreeing to fulfilling it");

        bool CallerIsCreator = (msg.sender == contractDetails.creator);
        bool CreatorisFarmer = contractDetails.isCreatorFarmer;
        uint256 amount;
        //no funds should be sent if farmer
        if ((CallerIsCreator && CreatorisFarmer) || (!CallerIsCreator && !CreatorisFarmer)) {
            amount = 0;
            require(msg.value == amount, "No funds should be sent for this contract");
        } else {
            //externally,  getTotalAmount- getLockInAmount should be used
            amount = contractDetails.rate * contractDetails.quantity - contractDetails.lockInAmount;
            require(msg.value == amount, "Insufficient funds sent");
        }
        if (CallerIsCreator) {
            contractDetails.creatorAgreement = true;
        } else {
            contractDetails.applicantAgreement = true;
        }
        
        if (contractDetails.creatorAgreement && contractDetails.applicantAgreement) {
            emit ContractAgreed(contractId, contractDetails.creator, contractDetails.selectedApplicant);
            contractDetails.status = Status.AGREED;
        }
    }

    function fulfillContract(uint256 contractId) external nonReentrant nonReentrant onlyBuyer(contractId) {
        ContractDetails storage contractDetails = contracts[contractId];
        require( contractDetails.status == Status.AGREED,"Contract must be accepted by both parties before funds can be released");
        address payable recipient = payable(msg.sender==contractDetails.creator?contractDetails.selectedApplicant:contractDetails.creator);
        uint256 platformFee = (amount * platformFeePercent) / 100;

        //send money to platform owner or government
        (bool feeSent, ) = payable(platform_).call{value: platformFee}("");
        require(feeSent, "Failed to transfer platform fee");

        // Refund application fee to the creator
        (bool refundSent, ) = payable(contractDetails.creator).call{value: cancellationFee}("");
        require(refundSent, "Failed to refund contract creation fee");

        //send rest to farmer
        (bool sent, ) = recipient.call{value: address(this).balance}("");
        require(sent, "Failed to release funds to recipient");
        contractDetails.status = Status.COMPLETED;
        emit ContractCompleted(contractId, contractDetails.creator, contractDetails.selectedApplicant, contractDetails.rate, contractDetails.quantity);
    }

    function cancelContract(uint256 contractId,string reason) external payable onlyCreatorOrApplicant(contractId) nonReentrant {
        ContractDetails storage contractDetails = contracts[contractId];
        require(contractDetails.status == Status.OPEN || contractDetails.status == Status.ALLOTED,"Contract must be open or alloted to be cancelled");

        if(isCreator){
            contractDetails.cancellationReason = string(abi.encodePacked("Creator cancelled the contract.\nReason mentioned: ", reason));
        } else{
            require(msg.value == cancellationFee, "Incorrect cancellation fee sent");
            contractDetails.cancellationReason = string(abi.encodePacked("Applicant cancelled the contract.\nReason mentioned: ", reason));
        }
        contractDetails.status = Status.CANCELLED;
        (bool sent, ) = payable(creator).call{value: cancellationFee}("");
        require(sent, "Failed to transfer cancellation fee to creator");
        
        //handles case where lock in money needs to be given back to buyer or farmer
        if(contractDetails.status == Status.ALLOTED){
            address payable recipient;
            if(contractDetails.creator == msg.sender && !contractDetails.isCreatorFarmer){
                (bool sent, ) =payable(contractDetails.selectedApplicant).call{value: contractDetails.lockInAmount}("");
            }
            else if( contractDetails.selectedApplicant == msg.sender && contractDetails.isCreatorFarmer){
                (bool sent, ) =payable(contractDetails.creator).call{value: contractDetails.lockInAmount}("");
            } 

        }
        

        //not touching this part as i dont understnad nft. change it to current logic
        if (contractDetails.isCreatorFarmer) {
            _transfer(contractDetails.selectedApplicant,contractDetails.creator,contractDetails.tokenId);
        } else {
            _transfer(address(this), contractDetails.creator,contractDetails.tokenId);
        }

        emit ContractCancelled(contractId, msg.sender, reason);
    }

    function isContractOpen(uint256 id) public view returns (bool) {
        return contracts[id].status == Status.OPEN && contracts[id].endAt > block.timestamp;
    }



    /*for frontend*/

    //gpt says to implement pagination or one element at a time, as its cheaper
    function getApplicant(uint256 contractId,uint256 index) external view returns (Application memory) {
        require(index < applications[contractId].length,"Invalid index");
        return applications[contractId][index];
    }
    //externally: call for all index till error
    function getContract(uint256 contractId) external view returns (ContractDetails memory) {
        return contracts[contractId];
    }
    //alternate: maintain 2 arrays, one for open and one for closed contracts. 
    //and return those array to external, so they can call one by one
    //or some other solution
    function getContractCount() external view returns (uint256) {
        return contractCounter;
    }
    

    /*contract details fetch*/
    function getApplicationCount(uint256 contractId) external view returns (uint256) {
        return applications[contractId].length;
    }
    
    function getIsCreatorFarmer(uint256 contractId) external view returns (bool) {
        return contracts[contractId].isCreatorFarmer;
    }

    function getTokenId(uint256 contractId) external view returns (uint256) {
        return contracts[contractId].tokenId;
    }

    function getCommodity(uint256 contractId) external view returns (string memory) {
        return contracts[contractId].commodity;
    }
    function getContractRate(uint256 contractId) external view returns (uint256) {
        return contracts[contractId].rate;
    }
    function getContractQuantity(uint256 contractId) external view returns (uint32) {
        return contracts[contractId].quantity;
    }
    function getTotalAmount(uint256 contractId) external view returns (uint256) {
        return contracts[contractId].rate * contracts[contractId].quantity;
    }
    function getClauses(uint256 contractId) external view returns (string[] memory) {
        return contracts[contractId].clauses;
    }

    function getDeliveryCoordinates(uint256 contractId) external view returns (int32[2] memory) {
        return [contracts[contractId].deliveryLatitude, contracts[contractId].deliveryLongitude];
    }

    function getApplicationStartDate(uint256 contractId) external view returns (uint256) {
        return contracts[contractId].startAt;
    }

    function getApplicationEndDate(uint256 contractId) external view returns (uint256) {
        return contracts[contractId].endAt;
    }

    function getDeliveryDate(uint256 contractId) external view returns (uint256) {
        return contracts[contractId].deliveryDate;
    }

    function getSelectedApplicant(uint256 contractId) external view returns (address) {
        return contracts[contractId].selectedApplicant;
    }
    function getContractStatus(uint256 contractId) external view returns (Status) {
        return contracts[contractId].status;
    }
    
    function getCancellationReason(uint256 contractId) external view returns (string memory) {
        return contracts[contractId].cancellationReason;
    }

    function getCreatorAgreement(uint256 contractId) external view returns (bool) {
        return contracts[contractId].creatorAgreement;
    }

    function getApplicantAgreement(uint256 contractId) external view returns (bool) {
        return contracts[contractId].applicantAgreement;
    }
   
    function isCreatorResponsibleForLogistics(uint256 contractId) external view returns (bool) {
        return contracts[contractId].creatorResponsibleForLogistics;
    }

    function getQualityOfProduce(uint256 contractId) external view returns (string memory) {
        return contracts[contractId].quality;
    }
    function getLockInAmount(uint256 contractId) external view returns (uint256) {
        return contracts[contractId].lockInAmount;
    }


    /* fees fetch*/
    function getApplicationFee() external view returns (uint256) {
        return applicationFee;
    }
    function getCancellationFee() external view returns (uint256) {
        return cancellationFee;
    }

    function getPlatformFeePercent() external view returns (uint256) {
        return platformFeePercent;
    }


    //what these do?
    fallback() external payable {
        revert("Fallback function called");
    }

    receive() external payable {
        revert("Direct Ether not accepted");
    }
}
