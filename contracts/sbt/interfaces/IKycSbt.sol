pragma solidity =0.6.6;

interface IKycSbt {
    function balanceOf(address owner) external view returns (uint256);
    function getHoldTokens(address holder) external view returns (uint256[] memory);
    function getKYCAttribute(uint256 tokenId) external view returns (address, uint8, bool, bool, bool, uint256, uint256);
    function locked(uint256 tokenId) external view returns (bool);
}