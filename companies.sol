// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AgriculturalContracts is ReentrancyGuard, Ownable {
    uint256 public contractCounter;
    uint256 public applicationCounter;

    struct Contract {
        uint256 id;
        address company;
        string details;
        uint256 price;
        uint256 quantity;
        uint256 deliveryDate;
        bool isOpen;
        bool isFulfilled;
    }

    struct Application {
        uint256 id;
        uint256 contractId;
        address farmer;
        string additionalNotes;
        bool isApproved;
    }

    mapping(uint256 => Contract) public contracts;
    mapping(uint256 => Application) public applications;
    mapping(uint256 => uint256[]) public contractApplications;
    mapping(uint256 => uint256) public contractFunds;

    event ContractCreated(uint256 indexed contractId, address indexed company, uint256 price, uint256 quantity, uint256 deliveryDate);
    event ApplicationSubmitted(uint256 indexed applicationId, uint256 indexed contractId, address indexed farmer);
    event ApplicationApproved(uint256 indexed applicationId, uint256 indexed contractId, address indexed farmer);
    event ContractFulfilled(uint256 indexed contractId, address indexed farmer, uint256 amount);
    event FundsLocked(uint256 indexed contractId, uint256 amount);
    event FundsReleased(uint256 indexed contractId, address indexed farmer, uint256 amount);

    modifier onlyCompany(uint256 _contractId) {
        require(msg.sender == contracts[_contractId].company, "Only the contract creator can perform this action");
        _;
    }

    modifier onlyFarmer(uint256 _applicationId) {
        require(msg.sender == applications[_applicationId].farmer, "Only the application creator can perform this action");
        _;
    }

    function createContract(string memory _details, uint256 _price, uint256 _quantity, uint256 _deliveryDate) external {
        contractCounter++;
        contracts[contractCounter] = Contract({
            id: contractCounter,
            company: msg.sender,
            details: _details,
            price: _price,
            quantity: _quantity,
            deliveryDate: _deliveryDate,
            isOpen: true,
            isFulfilled: false
        });

        emit ContractCreated(contractCounter, msg.sender, _price, _quantity, _deliveryDate);
    }

    function applyForContract(uint256 _contractId, string memory _additionalNotes) external {
        require(contracts[_contractId].isOpen, "Contract is not open for applications");
        
        applicationCounter++;
        applications[applicationCounter] = Application({
            id: applicationCounter,
            contractId: _contractId,
            farmer: msg.sender,
            additionalNotes: _additionalNotes,
            isApproved: false
        });

        contractApplications[_contractId].push(applicationCounter);

        emit ApplicationSubmitted(applicationCounter, _contractId, msg.sender);
    }

    function approveApplication(uint256 _applicationId) external onlyCompany(applications[_applicationId].contractId) {
        Application storage application = applications[_applicationId];
        Contract storage contract = contracts[application.contractId];

        require(!application.isApproved, "Application already approved");
        require(contract.isOpen, "Contract is not open");

        application.isApproved = true;
        contract.isOpen = false;

        emit ApplicationApproved(_applicationId, application.contractId, application.farmer);
    }

    function lockFunds(uint256 _contractId) external payable onlyCompany(_contractId) {
        Contract storage contract = contracts[_contractId];
        require(!contract.isOpen, "Contract must be closed before locking funds");
        require(msg.value == contract.price * contract.quantity, "Incorrect fund amount");

        contractFunds[_contractId] = msg.value;

        emit FundsLocked(_contractId, msg.value);
    }

    function confirmDelivery(uint256 _contractId) external onlyCompany(_contractId) {
        Contract storage contract = contracts[_contractId];
        require(!contract.isOpen, "Contract must be closed");
        require(!contract.isFulfilled, "Contract already fulfilled");
        require(contractFunds[_contractId] > 0, "No funds locked for this contract");

        contract.isFulfilled = true;

        uint256 amount = contractFunds[_contractId];
        contractFunds[_contractId] = 0;

        // Find the approved farmer
        address payable farmer;
        for (uint256 i = 0; i < contractApplications[_contractId].length; i++) {
            Application storage app = applications[contractApplications[_contractId][i]];
            if (app.isApproved) {
                farmer = payable(app.farmer);
                break;
            }
        }

        require(farmer != address(0), "Approved farmer not found");

        (bool success, ) = farmer.call{value: amount}("");
        require(success, "Failed to send funds to farmer");

        emit FundsReleased(_contractId, farmer, amount);
        emit ContractFulfilled(_contractId, farmer, amount);
    }

    function getContractApplications(uint256 _contractId) external view returns (uint256[] memory) {
        return contractApplications[_contractId];
    }

    // Add any additional functions or modifications as needed
}