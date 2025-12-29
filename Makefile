# Load environment variables
-include .env

# ============================================
# Contract Addresses (Base Sepolia)
# ============================================
PAYMENT_PROCESSOR := 0x7c39408AC96a1b9a2722056eDE90b54D2B260380
MERCHANT_REGISTRY := 0x93e93Dfa36C87De32B9118CA5D9BAd1Db892002d
BASE_SEPOLIA_USDC := 0x036CbD53842c5426634e7929541eC2318f3dCF7e

# ============================================
# Basic Commands
# ============================================
.PHONY: clean install update build test snapshot format

clean:
	@forge clean

install:
	@forge install cyfrin/foundry-devops && \
	forge install foundry-rs/forge-std && \
	forge install openzeppelin/openzeppelin-contracts && \
	forge install openzeppelin/openzeppelin-contracts-upgradeable && \
	forge install OpenZeppelin/openzeppelin-foundry-upgrades

update:
	@forge update

build:
	@forge build

test:
	@forge test

snapshot:
	@forge snapshot

format:
	@forge fmt

# ============================================
# Base Sepolia Testnet Commands
# ============================================
.PHONY: deploy-base-sepolia postdeploy-base-sepolia set-tokens-base-sepolia

deploy-base-sepolia:
	@forge script script/Deploy.s.sol:Deploy --rpc-url base_sepolia --broadcast --verify

postdeploy-base-sepolia:
	@forge script script/PostDeployment.s.sol:PostDeployment --rpc-url base_sepolia --broadcast

set-tokens-base-sepolia:
	@forge script script/interactions/SetSupportedTokens.s.sol:SetSupportedTokens --rpc-url base_sepolia --broadcast

# ============================================
# Merchant Management (Base Sepolia)
# ============================================
.PHONY: register-merchant verify-merchant get-merchant-info

# Usage: make register-merchant PAYOUT=0x... METADATA="https://example.com/metadata.json"
register-merchant:
	@cast send $(MERCHANT_REGISTRY) \
		"registerMerchant(address,string)" \
		$(PAYOUT) "$(METADATA)" \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# Usage: make verify-merchant MERCHANT_ID=0x...
# Status: 0=PENDING, 1=VERIFIED, 2=REJECTED
verify-merchant:
	@cast send $(MERCHANT_REGISTRY) \
		"updateMerchantVerificationStatus(bytes32,uint8)" \
		$(MERCHANT_ID) 1 \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# Usage: make get-merchant-info MERCHANT_ID=0x...
get-merchant-info:
	@cast call $(MERCHANT_REGISTRY) \
		"getMerchantInfo(bytes32)" \
		$(MERCHANT_ID) \
		--rpc-url $(BASE_SEPOLIA_RPC_URL)

# ============================================
# Token Operations (Base Sepolia)
# ============================================
.PHONY: approve-usdc check-usdc-balance check-usdc-allowance

# Usage: make approve-usdc AMOUNT=10 000000 (1000 USDC)
approve-usdc:
	@cast send $(BASE_SEPOLIA_USDC) \
		"approve(address,uint256)" \
		$(PAYMENT_PROCESSOR) $(AMOUNT) \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# Usage: make check-usdc-balance WALLET=0x...
check-usdc-balance:
	@cast call $(BASE_SEPOLIA_USDC) \
		"balanceOf(address)(uint256)" \
		$(WALLET) \
		--rpc-url $(BASE_SEPOLIA_RPC_URL)

# Usage: make check-usdc-allowance OWNER=0x...
check-usdc-allowance:
	@cast call $(BASE_SEPOLIA_USDC) \
		"allowance(address,address)(uint256)" \
		$(OWNER) $(PAYMENT_PROCESSOR) \
		--rpc-url $(BASE_SEPOLIA_RPC_URL)

# ============================================
# Payment Operations (Base Sepolia)
# ============================================
.PHONY: create-order pay-order settle-order get-order check-token-support

# Step 1: Create an order
# Usage: make create-order MERCHANT_ID=0x... AMOUNT=100000 METADATA="https://example.com/order.json"
create-order:
	@cast send $(PAYMENT_PROCESSOR) \
		"createOrder(bytes32,address,uint256,string)" \
		$(MERCHANT_ID) $(BASE_SEPOLIA_USDC) $(AMOUNT) "$(METADATA)" \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# Step 2: Pay an order (payer must have approved USDC)
# Usage: make pay-order ORDER_ID=0x...
pay-order:
	@cast send $(PAYMENT_PROCESSOR) \
		"payOrder(bytes32)" \
		$(ORDER_ID) \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# Step 3: Settle an order (transfer funds to merchant)
# Usage: make settle-order ORDER_ID=0x...
settle-order:
	@cast send $(PAYMENT_PROCESSOR) \
		"settleOrder(bytes32)" \
		$(ORDER_ID) \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# Get order info
# Usage: make get-order ORDER_ID=0x...
get-order:
	@cast call $(PAYMENT_PROCESSOR) \
		"getOrderInfo(bytes32)" \
		$(ORDER_ID) \
		--rpc-url $(BASE_SEPOLIA_RPC_URL)

check-token-support:
	@cast call $(PAYMENT_PROCESSOR) \
		"isTokenSupported(address)(bool)" \
		$(BASE_SEPOLIA_USDC) \
		--rpc-url $(BASE_SEPOLIA_RPC_URL)

# ============================================
# Contract Info (Base Sepolia)
# ============================================
.PHONY: info owner

info:
	@echo "========================================"
	@echo "StableBase Contracts (Base Sepolia)"
	@echo "========================================"
	@echo "PaymentProcessor: $(PAYMENT_PROCESSOR)"
	@echo "MerchantRegistry: $(MERCHANT_REGISTRY)"
	@echo "USDC Token:       $(BASE_SEPOLIA_USDC)"
	@echo "========================================"
	@echo "Explorer: https://sepolia.basescan.org"
	@echo "========================================"

owner:
	@echo "PaymentProcessor Owner:"
	@cast call $(PAYMENT_PROCESSOR) "owner()(address)" --rpc-url $(BASE_SEPOLIA_RPC_URL)
	@echo "MerchantRegistry Owner:"
	@cast call $(MERCHANT_REGISTRY) "owner()(address)" --rpc-url $(BASE_SEPOLIA_RPC_URL)

# ============================================
# Upgrade Commands
# ============================================
.PHONY: upgrade-base-sepolia emergency-base-sepolia

upgrade-base-sepolia:
	@forge script script/Upgrade.s.sol:Upgrade --rpc-url base_sepolia --broadcast

emergency-base-sepolia:
	@forge script script/emergency/EmergencyPause.s.sol:EmergencyPause --rpc-url base_sepolia --broadcast

# ============================================
# Mainnet Deployment Commands
# ============================================
.PHONY: deploy-ethereum deploy-polygon deploy-arbitrum deploy-base deploy-celo deploy-optimism

deploy-ethereum:
	@forge script script/Deploy.s.sol:Deploy --rpc-url ethereum --broadcast --verify --slow

deploy-polygon:
	@forge script script/Deploy.s.sol:Deploy --rpc-url polygon --broadcast --verify

deploy-arbitrum:
	@forge script script/Deploy.s.sol:Deploy --rpc-url arbitrum --broadcast --verify

deploy-base:
	@forge script script/Deploy.s.sol:Deploy --rpc-url base --broadcast --verify

deploy-celo:
	@forge script script/Deploy.s.sol:Deploy --rpc-url celo --broadcast --verify

deploy-optimism:
	@forge script script/Deploy.s.sol:Deploy --rpc-url optimism --broadcast --verify

# ============================================
# Other Testnet Commands
# ============================================
.PHONY: deploy-sepolia deploy-amoy deploy-arbitrum-sepolia

deploy-sepolia:
	@forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --verify

deploy-amoy:
	@forge script script/Deploy.s.sol:Deploy --rpc-url amoy --broadcast --verify

deploy-arbitrum-sepolia:
	@forge script script/Deploy.s.sol:Deploy --rpc-url arbitrum_sepolia --broadcast --verify

# ============================================
# Help
# ============================================
.PHONY: help

help:
	@echo "StableBase Contracts - Available Commands"
	@echo ""
	@echo "Basic:"
	@echo "  make build                 - Build contracts"
	@echo "  make test                  - Run tests"
	@echo "  make clean                 - Clean build artifacts"
	@echo "  make info                  - Show deployed contract addresses"
	@echo ""
	@echo "Base Sepolia Deployment:"
	@echo "  make deploy-base-sepolia   - Deploy contracts"
	@echo "  make set-tokens-base-sepolia - Set supported tokens"
	@echo ""
	@echo "Merchant Management:"
	@echo "  make register-merchant PAYOUT=0x... METADATA=\"https://...\""
	@echo "  make verify-merchant MERCHANT_ID=0x..."
	@echo "  make get-merchant-info MERCHANT_ID=0x..."
	@echo ""
	@echo "Token Operations:"
	@echo "  make approve-usdc AMOUNT=1000000"
	@echo "  make check-usdc-balance WALLET=0x..."
	@echo "  make check-usdc-allowance OWNER=0x..."
	@echo "  make check-token-support"
	@echo ""
	@echo "Payment Flow (3 steps):"
	@echo "  1. make create-order MERCHANT_ID=0x... AMOUNT=100000 METADATA=\"https://...\""
	@echo "  2. make pay-order ORDER_ID=0x..."
	@echo "  3. make settle-order ORDER_ID=0x..."
	@echo "  make get-order ORDER_ID=0x..."
	@echo ""
	@echo "Contract Info:"
	@echo "  make owner                 - Show contract owners"
