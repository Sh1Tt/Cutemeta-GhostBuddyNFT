// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract GhostBuddyNFT is Ownable, ERC721, ERC2981 {
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private _tokenIds;
    
    uint256 public constant ORIGINAL_SUPPLY = 5555;
    uint256 public constant MAX_SUPPLY = 10000;
    uint96 public constant MAX_WL_MINT_PER_WALLET = 3;
    uint96 public constant MAX_MINT_PER_TX = 5;
    uint256 public mintPrice = 3000000000000000; // 0.003 -- remove before flight
    uint256 public expeditionFee = 2000000000000000; // 0.02 -- remove before flight
    uint96 private _royaltyPercentage = 500; // 5% -- remove before flight
    uint256 private _minimumExpeditionTime = 86400; // 1 day -- remove before flight
    
    bool public isWhitelistActive = false;
    bool public isPublicMintActive = false;
    bool public isRevealed = false;

    string private constant _ogBaseURI = "ipfs://QmZFxhGiLp5Jo6GiLQeypJbwTRSbMLeDBTDLHiw2jCrqh4/";
    string private constant _ogImageURI = "ipfs://QmYThkCs5vihZZxZxRtYgf9ttZZd6ESqjn8uxcQxnsCrcd/";
    string private constant _unrevealedURI = "https://brooklyn.hsd.services/uploads/cutemeta/gb/unrevealed.json"; // centralised url for testing only
    // Ghost Buddy V2: A collection of playful, interdimensional companions. When the portals between realms closed, 5555 Buddies got stranded. 
    // Now, with magic portals restored, these spirits can roam freely once more. In the Metaverse, they have built a vibrant realm to socialize, play games, and evolve. 
    // These spirits can embark on expeditions to earn rewards, customize with magical gear, and save their progress on-chain, unlocking endless customization and adventure.  -- remove before flight
    string private _description;
    string private _imageURI;
    string private _defaultVRMFile; // "https://brooklyn.hsd.services/uploads/models/gb-basic.vrm";
    mapping(uint256 => string) private _tokenTraits;
    mapping(uint256 => string) private _vrmFiles;
    mapping(uint256 => string) private _metaverseTraits;
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public whitelistMintCount;
    mapping(uint256 => bool) private _originalTokensMinted;
    
    mapping(uint256 => uint256) private _expeditions;
    mapping(address => bool) public gamemasters;

    event Revealed();
    event RoyaltyUpdated(address indexed receiver, uint96 indexed feeNumerator);
    event MetadataUpdate(uint256 indexed tokenId);

    constructor() 
        ERC721("GhostBuddyNFT", "GBN")
        Ownable(msg.sender)
    {
        _setDefaultRoyalty(owner(), _royaltyPercentage);
    }

    modifier onlyGamemasterOrOwner() {
        require(gamemasters[msg.sender] || owner() == msg.sender, "Not authorized");
        _;
    }

    function addGamemaster(address _gamemaster) external onlyOwner {
        require(_gamemaster != address(0), "Zero address");
        gamemasters[_gamemaster] = true;
    }

    function removeGamemaster(address _gamemaster) external onlyOwner {
        gamemasters[_gamemaster] = false;
    }

    function mintOriginalTokens(address[] memory originalHolders, uint256 startIndex, uint256 endIndex) external onlyOwner {
        require(startIndex < ORIGINAL_SUPPLY, "Index out of bounds");
        require(endIndex <= ORIGINAL_SUPPLY, "Index out of bounds");
        require(startIndex < endIndex, "Invalid index range");
        require(endIndex - startIndex == originalHolders.length, "Array length mismatch");
        
        for (uint256 i = 0; i < originalHolders.length; i++) {
            uint256 tokenId = startIndex + i;
            require(!_originalTokensMinted[tokenId], "Token already minted");
            _safeMint(originalHolders[i], tokenId);
            _originalTokensMinted[tokenId] = true;
            _tokenIds.increment();
        }
    }

    function whitelistMint(uint256 quantity) external payable {
        require(isWhitelistActive, "WL mint not active");
        require(whitelist[msg.sender], "Not whitelisted");
        require(whitelistMintCount[msg.sender] + quantity <= MAX_WL_MINT_PER_WALLET, "Exceeds max per wallet");
        require(msg.value >= mintPrice * quantity, "Insufficient payment");
        require(_tokenIds.current() + quantity <= MAX_SUPPLY, "Exceeds max supply");

        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(msg.sender, _tokenIds.current());
            _tokenIds.increment();
        }
        whitelistMintCount[msg.sender] += quantity;
    }

    function publicMint(uint256 quantity) external payable {
        require(isPublicMintActive, "Public mint not active");
        require(quantity <= MAX_MINT_PER_TX, "Max 3 per TX");
        require(msg.value >= mintPrice * quantity, "Insufficient payment");
        require(_tokenIds.current() + quantity <= MAX_SUPPLY, "Exceeds max supply");

        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(msg.sender, _tokenIds.current());
            _tokenIds.increment();
        }
    }

    function generateTokenURI(uint256 tokenId) internal view returns (string memory) {
        string memory attributes = string(abi.encodePacked(
            bytes(_tokenTraits[tokenId]).length > 0 ? _tokenTraits[tokenId] : "",
            bytes(_metaverseTraits[tokenId]).length > 0 ? string(abi.encodePacked(', ', _metaverseTraits[tokenId])) : ""
        ));

        string memory imageUri = string(
            abi.encodePacked(
                tokenId < ORIGINAL_SUPPLY ? _ogImageURI : _imageURI,
                tokenId.toString(), ".png"
            )
        );

        string memory vrmFile = bytes(_vrmFiles[tokenId]).length > 0 ? _vrmFiles[tokenId] : _defaultVRMFile;

        bytes memory dataURI = abi.encodePacked(
            '{',
                '"name": "Ghost Buddy #', tokenId.toString(), '",',
                '"description": "', _description, '",'
                '"image": "', imageUri, '",',
                '"attributes": [', attributes, '],',
                '"vrm_url": "', vrmFile, '"',
            '}'
        );
        
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(dataURI)
            )
        );
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(tokenId >= 0 && tokenId <= _tokenIds.current(), "False Id");

        if (isRevealed) {
            return generateTokenURI(tokenId);
        }
        else {
            if (tokenId < ORIGINAL_SUPPLY) {
                return string(abi.encodePacked(_ogBaseURI, tokenId.toString()));
            }
            else {
                return _unrevealedURI;
            }
        }
    }

    function setDescription(string memory newDescription) external onlyOwner {
        require(bytes(_description).length == 0, "Already set");
        _description = newDescription;
    }

    function setImageURI(string memory uri) external onlyOwner {
        require(bytes(_imageURI).length == 0, "Already set");
        _imageURI = uri;
    }

    function setDefaultVRMFile(string memory vrmFile) external onlyOwner {
        _defaultVRMFile = vrmFile;
    }

    function setTokenTraits(uint256 tokenId, string memory traits) external onlyOwner {
        require(tokenId >= 0 && tokenId <= _tokenIds.current(), "False Id");
        require(bytes(_tokenTraits[tokenId]).length == 0, "Already set");
        _tokenTraits[tokenId] = traits;
    }

    function setVRMFile(uint256 tokenId, string memory vrmFile) external onlyGamemasterOrOwner {
        require(tokenId >= 0 && tokenId <= _tokenIds.current(), "False Id");
        _vrmFiles[tokenId] = vrmFile;
        emit MetadataUpdate(tokenId);
    }

    function getVRMFile(uint256 tokenId) external view returns (string memory) {
        require(tokenId >= 0 && tokenId <= _tokenIds.current(), "False Id");
        return _vrmFiles[tokenId];
    }

    function setMetaverseTraits(uint256 tokenId, string memory traits) external onlyGamemasterOrOwner {
        require(tokenId >= 0 && tokenId <= _tokenIds.current(), "False Id");
        _metaverseTraits[tokenId] = traits;
        emit MetadataUpdate(tokenId);
    }

    function getMetaverseTraits(uint256 tokenId) external view returns (string memory) {
        require(tokenId >= 0 && tokenId <= _tokenIds.current(), "False Id");
        return _metaverseTraits[tokenId];
    }

    function addToWhitelist(address[] memory addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = true;
        }
    }

    function removeFromWhitelist(address[] memory addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            delete whitelist[addresses[i]];
        }
    }

    function setWhitelistStatus(bool status) external onlyOwner {
        isWhitelistActive = status;
    }

    function setPublicMintStatus(bool status) external onlyOwner {
        isPublicMintActive = status;
    }

    function reveal() external onlyOwner {
        isRevealed = true;
        emit Revealed();
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
    }
    
    function setExpeditionFee(uint256 newFee) external onlyOwner {
        expeditionFee = newFee;
    }

    function startExpedition(uint256 tokenId) external payable {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(_expeditions[tokenId] == 0, "On expedition");
        require(msg.value >= expeditionFee, "Insufficient payment");
        
        _expeditions[tokenId] = block.timestamp;
    }

    function endExpedition(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(_expeditions[tokenId] > 0, "Not on expedition");
        require(block.timestamp >= _expeditions[tokenId] + _minimumExpeditionTime, "Still on expedition");
        delete _expeditions[tokenId];
    }

    function getExpedition(uint256 tokenId) external view returns (uint256) {
        require(tokenId >= 0 && tokenId <= _tokenIds.current(), "False Id");
        return _expeditions[tokenId];
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        require(_expeditions[tokenId] == 0, "On expedition");
        return super._update(to, tokenId, auth);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        require(receiver != address(0), "Zero address");
        _setDefaultRoyalty(receiver, feeNumerator);
        emit RoyaltyUpdated(receiver, feeNumerator);
    }

    // Override required by Solidity
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}