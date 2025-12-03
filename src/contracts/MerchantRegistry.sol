// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IMerchantRegistry} from "../interfaces/IMerchantRegistry.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

/**
 * @title MerchantRegistry
 * @notice Stores merchanant accounts
 * @dev Responsibilities: Registers a merchant, save merchant metadata,update merchant info and emit events
 */
contract MerchantRegistry is IMerchantRegistry, PausableUpgradeable, Ownable2StepUpgradeable {
    error MerchantRegistry__ThrowZeroAddress();
    error MerchantRegistry__MerchantAlreadyExists();
    error MerchantRegistry__MerchantNotFound();
    error MerchantRegistry__UnauthorizedMerchant();
    error MerchantRegistry__InvalidMetadataUri();
    error MerchantRegistry__MerchantNotVerified();
    error MerchantRegistry__InvalidVerificationStatus();

    mapping(bytes32 => Merchant) private merchant;
    mapping(address => uint256) private _nonce;
    uint256[50] private _gap;

    /**
     * @dev Disables initializers to prevent the implementation contract from being initialized.
     *      This is a security measure for upgradeable contracts to ensure that only proxy contracts
     *      can be initialized, preventing potential vulnerabilities.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize function
     */
    function initialize() external initializer {
        __Ownable2Step_init();
        __Pausable_init();
    }

    /* ##################################################################
                                OWNER FUNCTIONS
    ################################################################## */
    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpase the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /* ##################################################################
                                USER CALLS
    ################################################################## */
    /**
     * @dev See {registerMerchant - IMerchantRegistry}
     */
    function registerMerchant(address _payoutWallet, string calldata _metadataUri)
        external
        whenNotPaused
        returns (bytes32 merchantId)
    {
        if (_payoutWallet == address(0)) {
            revert MerchantRegistry__ThrowZeroAddress();
        }

        if (bytes(_metadataUri).length == 0) {
            revert MerchantRegistry__InvalidMetadataUri();
        }

        // increase merchant nonce to avoid replay attacks
        _nonce[msg.sender]++;

        // generate transaction id for the transaction with chain id
        merchantId = keccak256(abi.encode(msg.sender, _nonce[msg.sender], block.chainid));

        if (merchant[merchantId].exists) {
            revert MerchantRegistry__MerchantAlreadyExists();
        }

        merchant[merchantId] = Merchant({
            owner: msg.sender,
            payoutWallet: _payoutWallet,
            metadataURI: _metadataUri,
            exists: true,
            verificationStatus: IMerchantRegistry.VerificationStatus.PENDING,
            createdAt: block.timestamp
        });

        emit MerchantRegistered(merchantId, msg.sender, _payoutWallet);
    }

    /**
     * @dev See {updateMerchant - IMerchantRegistry}
     */
    function updateMerchant(bytes32 _merchantId, address _payoutWallet, string memory _metadataUri)
        external
        whenNotPaused
    {
        Merchant storage m = merchant[_merchantId];

        // Checks
        if (_payoutWallet == address(0)) {
            revert MerchantRegistry__ThrowZeroAddress();
        }

        if (!m.exists) {
            revert MerchantRegistry__MerchantNotFound();
        }

        if (msg.sender != m.owner) {
            revert MerchantRegistry__UnauthorizedMerchant();
        }

        if (bytes(_metadataUri).length == 0) {
            revert MerchantRegistry__InvalidMetadataUri();
        }
        // Effects
        m.payoutWallet = _payoutWallet;
        m.metadataURI = _metadataUri;

        emit MerchantUpdated(_merchantId);
    }

    /**
     * @dev Update merchant verification status (owner only)
     * @param _merchantId The merchant ID to update
     * @param _newStatus The new verification status
     */
    function updateMerchantVerificationStatus(bytes32 _merchantId, IMerchantRegistry.VerificationStatus _newStatus)
        external
        onlyOwner
        whenNotPaused
    {
        Merchant storage m = merchant[_merchantId];

        if (!m.exists) {
            revert MerchantRegistry__MerchantNotFound();
        }

        IMerchantRegistry.VerificationStatus oldStatus = m.verificationStatus;
        m.verificationStatus = _newStatus;

        emit MerchantVerificationStatusUpdated(_merchantId, oldStatus, _newStatus);
    }

    /**
     * @dev Batch update multiple merchants' verification status
     * @param _merchantIds Array of merchant IDs
     * @param _statuses Array of new verification statuses
     */
    function batchUpdateVerificationStatus(
        bytes32[] calldata _merchantIds,
        IMerchantRegistry.VerificationStatus[] calldata _statuses
    ) external onlyOwner whenNotPaused {
        if (_merchantIds.length != _statuses.length) {
            revert MerchantRegistry__InvalidVerificationStatus();
        }

        for (uint256 i = 0; i < _merchantIds.length; i++) {
            bytes32 merchantId = _merchantIds[i];
            Merchant storage m = merchant[merchantId];

            if (!m.exists) continue; // Skip non-existent merchants

            IMerchantRegistry.VerificationStatus oldStatus = m.verificationStatus;
            m.verificationStatus = _statuses[i];

            emit MerchantVerificationStatusUpdated(merchantId, oldStatus, _statuses[i]);
        }
    }

    /* ##################################################################
                                   VIEW CALLS
       ################################################################## */
    /**
     * @dev See {getMerchantInfo-IMerchantRegistry}
     */
    function getMerchantInfo(bytes32 _merchantId) external view returns (Merchant memory) {
        if (!merchant[_merchantId].exists) revert MerchantRegistry__MerchantNotFound();
        return merchant[_merchantId];
    }

    /**
     * @dev Check if merchant is verified
     * @param _merchantId The merchant ID to check
     * @return isVerified True if merchant is verified
     */
    function isMerchantVerified(bytes32 _merchantId) external view returns (bool isVerified) {
        if (!merchant[_merchantId].exists) return false;
        return merchant[_merchantId].verificationStatus == IMerchantRegistry.VerificationStatus.VERIFIED;
    }

    /**
     * @dev Get merchant verification status
     * @param _merchantId The merchant ID
     * @return status Current verification status
     */
    function getMerchantVerificationStatus(bytes32 _merchantId)
        external
        view
        returns (IMerchantRegistry.VerificationStatus status)
    {
        if (!merchant[_merchantId].exists) {
            revert MerchantRegistry__MerchantNotFound();
        }
        return merchant[_merchantId].verificationStatus;
    }

    /**
     * @dev Get merchant creation timestamp
     * @param _merchantId The merchant ID
     * @return createdAt When the merchant was registered
     */
    function getMerchantCreatedAt(bytes32 _merchantId) external view returns (uint256 createdAt) {
        if (!merchant[_merchantId].exists) {
            revert MerchantRegistry__MerchantNotFound();
        }
        return merchant[_merchantId].createdAt;
    }
}
