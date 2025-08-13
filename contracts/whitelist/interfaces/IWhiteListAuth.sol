pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

interface IWhiteListAuth {
    struct KYCAttribute {
        uint256 attributeId;
        address supplier;
        address recipient;
        uint8 verifyType;
        bool activity;
        bool deadlock;
        bool isVerifiedToken;
        uint256 fromTime;
        uint256 expireTime;
    }

    struct erc20Attribute {
        string name;
        string symbol;
        uint8 decimals;
        uint8 tokenType;
        bool activity;
        address minter;
    }

    function getKYCAttributes(address _target) external view returns (KYCAttribute[] memory);
    function getSupplierStatus(address _target) external view returns (bool);
    function isERC20Active(address contractAddress) external view returns (bool);
    function getERC20Info(address contractAddress) external view returns (erc20Attribute memory);
    function getCTIStatus(address _target) external view returns (bool);
}