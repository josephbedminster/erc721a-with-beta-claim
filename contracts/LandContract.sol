// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "erc721a/contracts/ERC721A.sol";

//ERC721A optimization for Otherside.xyz

// Inspired by cygaar and twitter users / erc721a chiru-labs

contract Land is ERC721A, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // attributes
    string private baseURI;
    address public operator;

    bool public publicSaleActive;
    uint256 public publicSaleStartTime;
    uint256 public publicSalePriceLoweringDuration;
    uint256 public publicSaleStartPrice;
    uint256 public publicSaleEndingPrice;
    uint256 public currentNumLandsMintedPublicSale;
    uint256 public mintIndexPublicSaleAndContributors;
    address public tokenContract;
    bool private isKycCheckRequired;
    bytes32 public kycMerkleRoot;

    uint256 public maxMintPerTx;
    uint256 public maxMintPerAddress;
    mapping(address => uint256) public mintedPerAddress;

    bool public claimableActive; 
    bool public adminClaimStarted;
    
    address public alphaContract; 
    mapping(uint256 => bool) public alphaClaimed;
    uint256 public alphaClaimedAmount;

    address public betaContract; 
    mapping(uint256 => bool) public betaClaimed;
    uint256 public betaClaimedAmount;
    uint256 public betaNftIdCurrent;

    Metadata[] public metadataHashes;
    bytes32 public keyHash;
    uint256 public fee;
    uint256 public publicSaleAndContributorsOffset;
    uint256 public alphaOffset;
    uint256 public betaOffset;
    mapping(bytes32 => bool) public isRandomRequestForPublicSaleAndContributors;
    bool public publicSaleAndContributorsRandomnessRequested;
    bool public ownerClaimRandomnessRequested;
    
    // constants
    uint256 immutable public MAX_LANDS;
    uint256 immutable public MAX_LANDS_WITH_FUTURE;
    uint256 immutable public MAX_ALPHA_NFT_AMOUNT;
    uint256 immutable public MAX_BETA_NFT_AMOUNT;
    uint256 immutable public MAX_PUBLIC_SALE_AMOUNT;
    uint256 immutable public RESERVED_CONTRIBUTORS_AMOUNT;
    uint256 immutable public MAX_FUTURE_LANDS;
    uint256 constant public MAX_MINT_PER_BLOCK = 150;

    // structs
    struct LandAmount {
        uint256 alpha;
        uint256 beta;
        uint256 publicSale;
        uint256 future;
    }
    struct ContributorAmount {
        address contributor;
        uint256 amount;
    }

    struct Metadata {
        bytes32 metadataHash;
        bytes32 shuffledArrayHash;
        uint256 startIndex;
        uint256 endIndex;
    }

    struct ContractAddresses {
        address alphaContract;
        address betaContract;
        address tokenContract;
    }

    // modifiers
    modifier whenPublicSaleActive() {
        require(publicSaleActive, "Public sale is not active");
        _;
    }
    modifier whenClaimableActive() {
        require(claimableActive && !adminClaimStarted, "Claimable state is not active");
        _;
    }
    modifier checkMetadataRange(Metadata memory _landMetadata){
        require(_landMetadata.endIndex < MAX_LANDS_WITH_FUTURE, "Range upper bound cannot exceed MAX_LANDS_WITH_FUTURE - 1");
        _;
    }

    modifier onlyOperator() {
        require(operator == msg.sender , "Only operator can call this method");
        _;
    }

    // events
    event LandPublicSaleStart(
        uint256 indexed _saleDuration,
        uint256 indexed _saleStartTime
    );
    event LandPublicSaleStop(
        uint256 indexed _currentPrice,
        uint256 indexed _timeElapsed
    );
    event ClaimableStateChanged(bool indexed claimableActive);

    event ContributorsClaimStart(uint256 _timestamp);
    event ContributorsClaimStop(uint256 _timestamp);

    event StartingIndexSetPublicSale(uint256 indexed _startingIndex);
    event StartingIndexSetAlphaBeta(uint256 indexed _alphaOffset, uint256 indexed _betaOffset);

    event PublicSaleMint(address indexed sender, uint256 indexed numLands, uint256 indexed mintPrice);

    constructor(string memory name, string memory symbol,
        ContractAddresses memory addresses,
        LandAmount memory amount,
        address _operator
    ) ERC721A(name, symbol) {
        alphaContract = addresses.alphaContract;
        betaContract = addresses.betaContract;
        tokenContract = addresses.tokenContract;

        MAX_ALPHA_NFT_AMOUNT = amount.alpha;
        MAX_BETA_NFT_AMOUNT = amount.beta;
        MAX_PUBLIC_SALE_AMOUNT = amount.publicSale;
        MAX_FUTURE_LANDS = amount.future;

        betaNftIdCurrent = amount.alpha; //beta starts after alpha
        mintIndexPublicSaleAndContributors = amount.alpha + amount.beta; //public sale starts after beta

        RESERVED_CONTRIBUTORS_AMOUNT = 1000;
        MAX_LANDS = amount.alpha + amount.beta + amount.publicSale + RESERVED_CONTRIBUTORS_AMOUNT;
        MAX_LANDS_WITH_FUTURE = MAX_LANDS + amount.future;

        operator = _operator;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
    function setBaseURI(string memory uri) external onlyOperator {
        baseURI = uri;
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    function setMaxMintPerTx(uint256 _maxMintPerTx) external onlyOperator {
        maxMintPerTx = _maxMintPerTx;
    }

    function setMaxMintPerAddress(uint256 _maxMintPerAddress) external onlyOperator {
        maxMintPerAddress = _maxMintPerAddress;
    }

    function setKycCheckRequired(bool _isKycCheckRequired) external onlyOperator {
        isKycCheckRequired = _isKycCheckRequired;
    }

    function setKycMerkleRoot(bytes32 _kycMerkleRoot) external onlyOperator {
        kycMerkleRoot = _kycMerkleRoot;
    }

    // Public Sale Methods
    function startPublicSale(
        uint256 _publicSalePriceLoweringDuration, 
        uint256 _publicSaleStartPrice, 
        uint256 _publicSaleEndingPrice,
        uint256 _maxMintPerTx,
        uint256 _maxMintPerAddress,
        bool _isKycCheckRequired
    ) external onlyOperator {
        require(!publicSaleActive, "Public sale has already begun");
        
        publicSalePriceLoweringDuration = _publicSalePriceLoweringDuration;
        publicSaleStartPrice = _publicSaleStartPrice;
        publicSaleEndingPrice = _publicSaleEndingPrice;
        publicSaleStartTime = block.timestamp;
        publicSaleActive = true;

        maxMintPerTx = _maxMintPerTx;
        maxMintPerAddress = _maxMintPerAddress;

        isKycCheckRequired = _isKycCheckRequired;

        emit LandPublicSaleStart(publicSalePriceLoweringDuration, publicSaleStartTime);
    }

    function stopPublicSale() external onlyOperator whenPublicSaleActive {
        emit LandPublicSaleStop(getMintPrice(), getElapsedSaleTime());
        publicSaleActive = false;
    }

    function getElapsedSaleTime() private view returns (uint256) {
        return publicSaleStartTime > 0 ? block.timestamp - publicSaleStartTime : 0;
    }

    function getMintPrice() public view whenPublicSaleActive returns (uint256) {
        uint256 elapsed = getElapsedSaleTime();
        uint256 price;

        if(elapsed < publicSalePriceLoweringDuration) {
            // Linear decreasing function
            price =
                publicSaleStartPrice -
                    ( ( publicSaleStartPrice - publicSaleEndingPrice ) * elapsed ) / publicSalePriceLoweringDuration ;
        } else {
            price = publicSaleEndingPrice;
        }

        return price;
    }

    function mintLands(uint256 numLands, bytes32[] calldata merkleProof) external whenPublicSaleActive nonReentrant {
        require(numLands > 0, "Must mint at least one beta");
        require(currentNumLandsMintedPublicSale + numLands <= MAX_PUBLIC_SALE_AMOUNT, "Minting would exceed max supply");
        require(numLands <= maxMintPerTx, "numLands should not exceed maxMintPerTx");
        require(numLands + mintedPerAddress[msg.sender] <= maxMintPerAddress, "sender address cannot mint more than maxMintPerAddress lands");
        if(isKycCheckRequired) {
            require(MerkleProof.verify(merkleProof, kycMerkleRoot, keccak256(abi.encodePacked(msg.sender))), "Sender address is not in KYC allowlist");
        } else {
            require(msg.sender == tx.origin, "Minting from smart contracts is disallowed");
        }
     
        uint256 mintPrice = 305;
        IERC20(tokenContract).safeTransferFrom(msg.sender, address(this), mintPrice * numLands);
        currentNumLandsMintedPublicSale += numLands;
        mintedPerAddress[msg.sender] += numLands;
        emit PublicSaleMint(msg.sender, numLands, mintPrice);
        mintLandsCommon(numLands, msg.sender);
    }

    function mintLandsCommon(uint256 numLands, address recipient) private {
        _mint(recipient, numLands, '', false);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if(balance > 0){
            Address.sendValue(payable(owner()), balance);
        }

        balance = IERC20(tokenContract).balanceOf(address(this));
        if(balance > 0){
            IERC20(tokenContract).safeTransfer(owner(), balance);
        }
    }

    // Alpha/Beta Claim Methods
    function flipClaimableState() external onlyOperator {
        claimableActive = !claimableActive;
        emit ClaimableStateChanged(claimableActive);
    }

    function nftOwnerClaimLand(uint256[] calldata alphaTokenIds, uint256[] calldata betaTokenIds) external whenClaimableActive {
        require(alphaTokenIds.length > 0 || betaTokenIds.length > 0, "Should claim at least one land");
        require(alphaTokenIds.length + betaTokenIds.length <= MAX_MINT_PER_BLOCK, "Input length should be <= MAX_MINT_PER_BLOCK");

        alphaClaimLand(alphaTokenIds);
        betaClaimLand(betaTokenIds);
    }

    function alphaClaimLand(uint256[] calldata alphaTokenIds) private {
        for(uint256 i; i < alphaTokenIds.length; ++i){
            uint256 alphaTokenId = alphaTokenIds[i];
            require(!alphaClaimed[alphaTokenId], "ALPHA NFT already claimed");
            require(ERC721(alphaContract).ownerOf(alphaTokenId) == msg.sender, "Must own all of the alpha defined by alphaTokenIds");
            
            alphaClaimLandByTokenId(alphaTokenId);    
        }
    }

    function alphaClaimLandByTokenId(uint256 alphaTokenId) private {
        alphaClaimed[alphaTokenId] = true;
        ++alphaClaimedAmount;        
        _safeMint(msg.sender, alphaTokenId);
    }

    function betaClaimLand(uint256[] calldata betaTokenIds) private {
        for(uint256 i; i < betaTokenIds.length; ++i){
            uint256 betaTokenId = betaTokenIds[i];
            require(!betaClaimed[betaTokenId], "BETA NFT already claimed");
            require(ERC721(betaContract).ownerOf(betaTokenId) == msg.sender, "Must own all of the beta defined by betaTokenIds");
            
            betaClaimLandByTokenId(betaTokenId);    
        }
    }

    function betaClaimLandByTokenId(uint256 betaTokenId) private {
        betaClaimed[betaTokenId] = true;
        ++betaClaimedAmount;
        _safeMint(msg.sender, betaNftIdCurrent++);
    }
      
}