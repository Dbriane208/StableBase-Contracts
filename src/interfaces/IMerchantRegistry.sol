// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IMerchantRegistry
 * @notice Interface for the Merchant contract
 */
interface IMerchantRegistry {
    /* ##################################################################
                            MERCHANT    EVENTS
    ################################################################## */

    /**
     * @dev Emitted when a merchant is created
     * @param merchantId The ID of the merchant
     * @param owner The user who registered as merchant [msg.sender]
     * @param payoutWallet The address of the receving wallet
     */
    event MerchantRegistered(bytes32 indexed merchantId, address owner, address payoutWallet);

    /**
     * @dev Emitted when a merchant is updated
     * @param merchantId The ID of the merchant
     */
    event MerchantUpdated(bytes32 indexed merchantId);

    /**
     * @dev Emitted when merchant verification status changes
     * @param merchantId The ID of the merchant
     * @param oldStatus The previous verification status
     * @param newStatus The new verification status
     */
    event MerchantVerificationStatusUpdated(
        bytes32 indexed merchantId, VerificationStatus oldStatus, VerificationStatus newStatus
    );
    /* ##################################################################
                                STRUCTS
    ################################################################## */
    /**
     * @dev Enum for merchant verification status
     */
    enum VerificationStatus {
        PENDING,
        VERIFIED,
        REJECTED,
        SUSPENDED
    }

    /**
     * @dev Struct representing a merchant
     * @param owner The address of the merchant
     * @param payoutWallet The address to hold the payments
     * @param metadataURI The URI containing merchant metadata
     * @param exists Helper flag to check existence
     * @param verificationStatus Current verification status
     * @param createdAt Timestamp when merchant was registered
     */
    struct Merchant {
        address owner;
        address payoutWallet;
        string metadataURI;
        bool exists;
        VerificationStatus verificationStatus;
        uint256 createdAt;
    }

    /* ##################################################################
                                EXTERNAL CALLS
    ################################################################## */
    /**
     * @notice registers a merchant
     * @param _payoutWallet The address merchant will receive payments
     * @param _metadataUri URI for offchain metadata
     * @return _merchantId The ID of the merchant
     */
    function registerMerchant(address _payoutWallet, string calldata _metadataUri)
        external
        returns (bytes32 _merchantId);

    /**
     * @notice updates a merchant
     * @param _merchantId The ID of the merchant
     * @param _payoutWallet The address merchant will receive payments
     * @param _metadataUri URI for offchain metadata
     */
    function updateMerchant(bytes32 _merchantId, address _payoutWallet, string memory _metadataUri) external;

    /**
     * @notice Gets the details of the merchant
     * @param _merchantId The ID of the merchant
     * @return Merchant The merchant details
     */
    function getMerchantInfo(bytes32 _merchantId) external view returns (Merchant memory);
}

