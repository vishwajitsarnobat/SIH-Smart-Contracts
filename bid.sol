// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract Auction is ERC721URIStorage, ReentrancyGuard {

    uint256 public tokenCounter;
    uint256 public auctionCounter;

    uint8 public constant STATUS_OPEN = 1;
    uint8 public constant STATUS_DONE = 2;
    uint8 public constant STATUS_COMPLETED = 3;

    uint256 public minBidIncrement = 1 ether;
    uint256 public auctionTimeExtension = 300;
    uint256 public platformFeePercent = 2;
    uint256 public bidFee = 0.01 ether; // fee to charge for participation in auction

    struct AuctionDetails {
        address seller;
        uint256 tokenId;
        string commodity;
        uint256 rate;
        uint256 quantity;
        uint256 price;
        uint256 netPrice;
        uint256 startAt;
        uint256 endAt;
        uint256 deliveryDate;
        uint8 status;
        uint256 lockedFunds;
    }

    event Minted(address indexed minter, uint256 nftID, string uri);
    event AuctionCreated(uint256 auctionId, address indexed seller, string commodity, uint256 rate, uint256 quantity, uint256 price, uint256 deliveryDate, uint256 tokenId, uint256 startAt, uint256 endAt);
    event BidCreated(uint256 auctionId, address indexed bidder, uint256 bid, uint256 fee);
    event AuctionCompleted(uint256 auctionId, address indexed seller, address indexed bidder, uint256 bid);
    event WithdrawBid(uint256 auctionId, address indexed bidder, uint256 bid);
    event AuctionCancelled(uint256 auctionId);
    event DepositForfeited(uint256 auctionId, address indexed bidder, uint256 fee);
    event FundsLocked(uint256 auctionId, uint256 amount);
    event ContractFulfilled(uint256 auctionId, address indexed bidder, uint256 amount);

    mapping(uint256 => AuctionDetails) public auctions;
    mapping(uint256 => mapping(address => uint256)) public bids;
    mapping(uint256 => address) public lowestBidder;
    mapping(uint256 => mapping(address => uint256)) public bidFees;

    constructor() ERC721("KrishiNFT", "KNFT") {
        tokenCounter = 0;
        auctionCounter = 0;
    }

    function mint(string memory tokenURI, address minterAddress) public returns (uint256) {
        tokenCounter++;
        uint256 tokenId = tokenCounter;
        _safeMint(minterAddress, tokenId);
        _setTokenURI(tokenId, tokenURI);
        emit Minted(minterAddress, tokenId, tokenURI);
        return tokenId;
    }

    function createAuction(
        string memory commodity,
        uint256 rate,
        uint256 quantity,
        uint256 price,
        uint256 deliveryDate,
        uint256 tokenId,
        uint256 durationInSeconds
    ) public returns (uint256) {
        auctionCounter++;
        uint256 auctionId = auctionCounter;

        uint256 startAt = block.timestamp;
        uint256 endAt = startAt + durationInSeconds;

        auctions[auctionId] = AuctionDetails({
            seller: msg.sender,
            tokenId: tokenId,
            commodity: commodity,
            rate: rate,
            quantity: quantity,
            price: price,
            netPrice: price,
            status: STATUS_OPEN,
            startAt: startAt,
            endAt: endAt,
            deliveryDate: deliveryDate,
            lockedFunds: 0
        });

        _transfer(msg.sender, address(this), tokenId);
        emit AuctionCreated(auctionId, msg.sender, commodity, rate, quantity, price, deliveryDate, tokenId, startAt, endAt);
        return auctionId;
    }

    function bid(uint256 auctionId) public payable nonReentrant {
        require(isAuctionOpen(auctionId), 'Auction has ended');
        AuctionDetails storage auction = auctions[auctionId];
        require(msg.sender != auction.seller, "Cannot bid on your own auction");

        uint256 newBid = bids[auctionId][msg.sender] + msg.value;
        require(newBid < auction.price, "Cannot bid above or equal to the latest bidding price");
        require(auction.price - newBid >= minBidIncrement, "Bid increment too low");

        require(msg.value >= bidFee, "Insufficient bid fee");

        bids[auctionId][msg.sender] += msg.value;
        bidFees[auctionId][msg.sender] = bidFee;
        lowestBidder[auctionId] = msg.sender;

        if (auction.endAt - block.timestamp < auctionTimeExtension) {
            auction.endAt = block.timestamp + auctionTimeExtension;
        }

        emit BidCreated(auctionId, msg.sender, newBid, bidFee);
    }

    function completeAuction(uint256 auctionId) public payable nonReentrant {
        require(!isAuctionOpen(auctionId), 'Auction is still open');

        AuctionDetails storage auction = auctions[auctionId];
        address winner = lowestBidder[auctionId];
        require(
            msg.sender == auction.seller || msg.sender == winner,
            'Only seller or winner can complete auction'
        );

        if (winner != address(0)) {
            require(msg.value == auction.price, "Company must provide the exact auction price");
            auction.lockedFunds = msg.value;

            _transfer(address(this), winner, auction.tokenId);
            emit FundsLocked(auctionId, auction.lockedFunds);

        } else {
            _transfer(address(this), auction.seller, auction.tokenId);
        }

        auction.status = STATUS_DONE;
        emit AuctionCompleted(auctionId, auction.seller, winner, bids[auctionId][winner]);
    }

    function fulfillContract(uint256 auctionId) public nonReentrant {
        AuctionDetails storage auction = auctions[auctionId];
        require(auction.status == STATUS_DONE, "Auction must be completed before fulfilling contract");
        address winner = lowestBidder[auctionId];
        require(msg.sender == winner, "Only the winning farmer can fulfill the contract");

        uint256 amount = auction.lockedFunds;
        auction.lockedFunds = 0;
        auction.status = STATUS_COMPLETED;

        (bool sent, ) = winner.call{value: amount}("");
        require(sent, "Failed to release funds to farmer");

        uint256 fee = bidFees[auctionId][winner];
        bidFees[auctionId][winner] = 0;

        emit ContractFulfilled(auctionId, winner, amount);
    }

    function forfeitBid(uint256 auctionId) internal {
        address winner = lowestBidder[auctionId];
        uint256 fee = bidFees[auctionId][winner];

        if (fee > 0) {
            bidFees[auctionId][winner] = 0;
            (bool sent, ) = owner().call{value: fee}("");
            require(sent, "Failed to forfeit bid fee");

            emit DepositForfeited(auctionId, winner, fee);
        }
    }

    function isAuctionOpen(uint256 id) public view returns (bool) {
        return
            auctions[id].status == STATUS_OPEN &&
            auctions[id].endAt > block.timestamp;
    }

    function isAuctionExpired(uint256 id) public view returns (bool) {
        return auctions[id].endAt <= block.timestamp;
    }

    function _transferFund(address payable to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        require(to != address(0), 'Error, cannot transfer to address(0)');

        uint256 platformFee = (amount * platformFeePercent) / 100;
        uint256 finalAmount = amount - platformFee;

        (bool transferSent, ) = to.call{value: finalAmount}("");
        require(transferSent, "Error, failed to send Ether");

        (bool feeSent, ) = owner().call{value: platformFee}("");
        require(feeSent, "Error, failed to send platform fee");
    }

    fallback() external payable {
        revert("Fallback function called");
    }

    receive() external payable {
        revert("Direct Ether not accepted");
    }
}