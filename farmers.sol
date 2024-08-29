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
    uint8 public constant STATUS_CANCELLED = 4;

    uint256 public minBidIncrement = 1 ether; // need to modify
    uint256 public auctionTimeExtension = 300;
    uint256 public platformFeePercent = 2; // need to modify
    uint256 public bidFee = 0.01 ether; // need to modify

    struct AuctionDetails {
        address seller;
        uint256 tokenId;
        string commodity;
        uint256 rate;
        uint256 quantity;
        uint256 start_price;
        uint256 startAt;
        uint256 endAt;
        uint256 deliveryDate;
        uint8 status;
        uint256 highestBid;
        address highestBidder;
        bool sellerAgreement;
        bool bidderAgreement;
        uint256 lockedFunds;
    }

    event Minted(address indexed minter, uint256 nftID, string uri);
    event AuctionCreated(uint256 auctionId, address indexed seller, string commodity, uint256 rate, uint256 quantity, uint256 start_price, uint256 deliveryDate, uint256 tokenId, uint256 startAt, uint256 endAt);
    event BidCreated(uint256 auctionId, address indexed bidder, uint256 bid, uint256 fee);
    event AuctionCompleted(uint256 auctionId, address indexed seller, address indexed bidder, uint256 bid);
    event WithdrawBid(uint256 auctionId, address indexed bidder, uint256 bid);
    event AuctionCancelled(uint256 auctionId);
    event DepositForfeited(uint256 auctionId, address indexed bidder, uint256 fee);
    event FundsLocked(uint256 auctionId, uint256 amount);
    event ContractFulfilled(uint256 auctionId, address indexed bidder, uint256 amount);

    mapping(uint256 => AuctionDetails) public auctions;
    mapping(uint256 => mapping(address => uint256)) public bids;
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
        uint256 start_price,
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
            start_price: start_price,
            status: STATUS_OPEN,
            startAt: startAt,
            endAt: endAt,
            deliveryDate: deliveryDate,
            highestBid: 0,
            highestBidder: address(0),
            sellerAgreement: false,
            bidderAgreement: false,
            lockedFunds: 0
        });

        _transfer(msg.sender, address(this), tokenId);
        emit AuctionCreated(auctionId, msg.sender, commodity, rate, quantity, start_price, deliveryDate, tokenId, startAt, endAt);
        return auctionId;
    }

    function bid(uint256 auctionId) public payable nonReentrant {
        require(isAuctionOpen(auctionId), 'Auction has ended');
        AuctionDetails storage auction = auctions[auctionId];
        require(msg.sender != auction.seller, "Cannot bid on your own auction");

        uint256 newBid = bids[auctionId][msg.sender] + msg.value;
        require(newBid > auction.highestBid + minBidIncrement, "Bid increment too low");

        require(msg.value >= bidFee, "Insufficient bid fee");

        bids[auctionId][msg.sender] += msg.value;
        bidFees[auctionId][msg.sender] = bidFee;
        auction.highestBid = newBid;
        auction.highestBidder = msg.sender;

        if (auction.endAt - block.timestamp < auctionTimeExtension) {
            auction.endAt = block.timestamp + auctionTimeExtension;
        }

        emit BidCreated(auctionId, msg.sender, newBid, bidFee);
    }

    function completeAuction(uint256 auctionId) public nonReentrant {
        require(!isAuctionOpen(auctionId), 'Auction is still open');

        AuctionDetails storage auction = auctions[auctionId];
        require(msg.sender == auction.seller, 'Only seller can complete auction');

        if (auction.highestBidder != address(0)) {
            auction.status = STATUS_DONE;
            auction.lockedFunds = auction.highestBid;
            emit AuctionCompleted(auctionId, auction.seller, auction.highestBidder, auction.highestBid);

            _transfer(address(this), auction.highestBidder, auction.tokenId);
            emit FundsLocked(auctionId, auction.highestBid);
        } else {
            _transfer(address(this), auction.seller, auction.tokenId);
        }
    }

    function agreeFulfillment(uint256 auctionId) public {
        AuctionDetails storage auction = auctions[auctionId];
        require(auction.status == STATUS_DONE, "Auction must be completed before fulfilling contract");

        if (msg.sender == auction.seller) {
            auction.sellerAgreement = true;
        } else if (msg.sender == auction.highestBidder) {
            auction.bidderAgreement = true;
        }

        if (auction.sellerAgreement && auction.bidderAgreement) {
            fulfillContract(auctionId);
        }
    }

    function fulfillContract(uint256 auctionId) internal nonReentrant {
        AuctionDetails storage auction = auctions[auctionId];
        address winner = auction.highestBidder;

        uint256 amount = auction.lockedFunds;
        auction.status = STATUS_COMPLETED;
        auction.lockedFunds = 0;

        uint256 platformFee = (amount * platformFeePercent) / 100;
        uint256 finalAmount = amount - platformFee;

        (bool sent, ) = auction.seller.call{value: finalAmount}("");
        require(sent, "Failed to release funds to seller");

        (bool feeSent, ) = address(this).call{value: platformFee}("");
        require(feeSent, "Failed to transfer platform fee");

        uint256 fee = bidFees[auctionId][winner];
        bidFees[auctionId][winner] = 0;

        emit ContractFulfilled(auctionId, winner, amount);
    }

    function cancelAuction(uint256 auctionId) public {
        AuctionDetails storage auction = auctions[auctionId];
        require(msg.sender == auction.seller, "Only the seller can cancel the auction");
        require(auction.status == STATUS_OPEN, "Can only cancel open auctions");

        auction.status = STATUS_CANCELLED;
        _transfer(address(this), auction.seller, auction.tokenId);

        emit AuctionCancelled(auctionId);
    }

    function withdrawBid(uint256 auctionId) public nonReentrant {
        require(isAuctionExpired(auctionId) || auctions[auctionId].status == STATUS_CANCELLED, "Auction is still active");
        require(msg.sender != auctions[auctionId].highestBidder, "Highest bidder cannot withdraw");

        uint256 bidAmount = bids[auctionId][msg.sender];
        require(bidAmount > 0, "No bid to withdraw");

        bids[auctionId][msg.sender] = 0;
        (bool sent, ) = msg.sender.call{value: bidAmount}("");
        require(sent, "Failed to send Ether");

        emit WithdrawBid(auctionId, msg.sender, bidAmount);
    }

    function isAuctionOpen(uint256 id) public view returns (bool) {
        return auctions[id].status == STATUS_OPEN && auctions[id].endAt > block.timestamp;
    }

    function isAuctionExpired(uint256 id) public view returns (bool) {
        return auctions[id].endAt <= block.timestamp;
    }

    fallback() external payable {
        revert("Fallback function called");
    }

    receive() external payable {
        revert("Direct Ether not accepted");
    }
}