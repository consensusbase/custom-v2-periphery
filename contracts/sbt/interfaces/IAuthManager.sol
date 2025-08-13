pragma solidity =0.6.6;

interface IAuthManager {
    function getMinterActivity(address target) external view returns (bool);
    function isERC20Active(address contractAddress) external view returns (bool);
    function getSBTContract() external view returns (address);
    function getERC20Info(address tokenAddress) external view returns (string memory, string memory, uint8, uint8, address);
}