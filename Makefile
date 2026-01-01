# Load environment variables
-include .env

# ============================================
# Network Configuration
# ============================================
# Usage: make <command> NETWORK=base-sepolia
# Available networks: base-sepolia, polygon-amoy, arbitrum-sepolia, base, polygon, ethereum

NETWORK ?= base-sepolia

# Network-specific RPC URLs (from .env)
ifeq ($(NETWORK),base-sepolia)
    RPC_URL := $(BASE_SEPOLIA_RPC_URL)
    RPC_NAME := base_sepolia
    EXPLORER := https://sepolia.basescan.org
endif
ifeq ($(NETWORK),polygon-amoy)
    RPC_URL := $(POLYGON_AMOY_RPC_URL)
    RPC_NAME := amoy
    EXPLORER := https://amoy.polygonscan.com
endif
ifeq ($(NETWORK),arbitrum-sepolia)
    RPC_URL := $(ARBITRUM_SEPOLIA_RPC_URL)
    RPC_NAME := arbitrum_sepolia
    EXPLORER := https://sepolia.arbiscan.io
endif
ifeq ($(NETWORK),base)
    RPC_URL := $(BASE_RPC_URL)
    RPC_NAME := base
    EXPLORER := https://basescan.org
endif
ifeq ($(NETWORK),polygon)
    RPC_URL := $(POLYGON_RPC_URL)
    RPC_NAME := polygon
    EXPLORER := https://polygonscan.com
endif
ifeq ($(NETWORK),ethereum)
    RPC_URL := $(ETHEREUM_RPC_URL)
    RPC_NAME := ethereum
    EXPLORER := https://etherscan.io
endif

# ============================================
# Dynamic Contract Addresses (loaded from deployments)
# ============================================
# These are read from deployments/<network>/deployment.json after deployment
DEPLOYMENT_FILE := deployments/$(NETWORK)/deployment.json

# Default addresses (Base Sepolia - update after each deployment)
PAYMENT_PROCESSOR ?= $(shell [ -f "$(DEPLOYMENT_FILE)" ] && cat $(DEPLOYMENT_FILE) | grep -o '"paymentProcessor"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '0x[^"]*' || echo "0x7c39408AC96a1b9a2722056eDE90b54D2B260380")
MERCHANT_REGISTRY ?= $(shell [ -f "$(DEPLOYMENT_FILE)" ] && cat $(DEPLOYMENT_FILE) | grep -o '"merchantRegistry"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '0x[^"]*' || echo "0x93e93Dfa36C87De32B9118CA5D9BAd1Db892002d")

# USDC addresses per network
ifeq ($(NETWORK),base-sepolia)
    USDC := 0x036CbD53842c5426634e7929541eC2318f3dCF7e
endif
ifeq ($(NETWORK),polygon-amoy)
    USDC := 0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582
endif
ifeq ($(NETWORK),arbitrum-sepolia)
    USDC := 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
endif
ifeq ($(NETWORK),base)
    USDC := 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
endif
ifeq ($(NETWORK),polygon)
    USDC := 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
endif
ifeq ($(NETWORK),ethereum)
    USDC := 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
endif

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
# Deployment Commands (Network Agnostic)
# ============================================
# Usage: make deploy NETWORK=polygon-amoy
.PHONY: deploy set-tokens postdeploy upgrade emergency

deploy:
	@echo "Deploying to $(NETWORK)..."
	@forge script script/Deploy.s.sol:Deploy --rpc-url $(RPC_NAME) --broadcast --verify --ffi -vvvv

set-tokens:
	@echo "Setting tokens on $(NETWORK)..."
	@forge script script/interactions/SetSupportedTokens.s.sol:SetSupportedTokens --rpc-url $(RPC_NAME) --broadcast

postdeploy:
	@echo "Running post-deployment on $(NETWORK)..."
	@forge script script/PostDeployment.s.sol:PostDeployment --rpc-url $(RPC_NAME) --broadcast

upgrade:
	@echo "Upgrading contracts on $(NETWORK)..."
	@forge script script/Upgrade.s.sol:Upgrade --rpc-url $(RPC_NAME) --broadcast

emergency:
	@echo "Emergency pause on $(NETWORK)..."
	@forge script script/emergency/EmergencyPause.s.sol:EmergencyPause --rpc-url $(RPC_NAME) --broadcast

# ============================================
# Merchant Management (Network Agnostic)
# ============================================
.PHONY: register-merchant verify-merchant get-merchant-info

# Usage: make register-merchant PAYOUT=0x... METADATA="https://..." NETWORK=base-sepolia
register-merchant:
	@cast send $(MERCHANT_REGISTRY) \
		"registerMerchant(address,string)" \
		$(PAYOUT) "$(METADATA)" \
		--rpc-url $(RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# Usage: make verify-merchant MERCHANT_ID=0x... NETWORK=base-sepolia
verify-merchant:
	@cast send $(MERCHANT_REGISTRY) \
		"updateMerchantVerificationStatus(bytes32,uint8)" \
		$(MERCHANT_ID) 1 \
		--rpc-url $(RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# Usage: make get-merchant-info MERCHANT_ID=0x... NETWORK=base-sepolia
get-merchant-info:
	@cast call $(MERCHANT_REGISTRY) \
		"getMerchantInfo(bytes32)" \
		$(MERCHANT_ID) \
		--rpc-url $(RPC_URL)

# ============================================
# Token Operations (Network Agnostic)
# ============================================
.PHONY: approve-usdc check-usdc-balance check-usdc-allowance check-token-support

# Usage: make approve-usdc AMOUNT=1000000 NETWORK=base-sepolia
approve-usdc:
	@cast send $(USDC) \
		"approve(address,uint256)" \
		$(PAYMENT_PROCESSOR) $(AMOUNT) \
		--rpc-url $(RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# Usage: make check-usdc-balance WALLET=0x... NETWORK=base-sepolia
check-usdc-balance:
	@cast call $(USDC) \
		"balanceOf(address)(uint256)" \
		$(WALLET) \
		--rpc-url $(RPC_URL)

# Usage: make check-usdc-allowance OWNER=0x... NETWORK=base-sepolia
check-usdc-allowance:
	@cast call $(USDC) \
		"allowance(address,address)(uint256)" \
		$(OWNER) $(PAYMENT_PROCESSOR) \
		--rpc-url $(RPC_URL)

check-token-support:
	@cast call $(PAYMENT_PROCESSOR) \
		"isTokenSupported(address)(bool)" \
		$(USDC) \
		--rpc-url $(RPC_URL)

# Usage: make check-balances WALLET=0x... MERCHANT=0x... PLATFORM=0x... NETWORK=base-sepolia
check-balances:
	@echo "=== USDC Balances on $(NETWORK) ==="
	@echo "USDC Token: $(USDC)"
	@echo ""
	@echo "Your wallet ($(WALLET)):"
	@cast call $(USDC) "balanceOf(address)(uint256)" $(WALLET) --rpc-url $(RPC_URL)
	@echo ""
	@echo "Merchant wallet ($(MERCHANT)):"
	@cast call $(USDC) "balanceOf(address)(uint256)" $(MERCHANT) --rpc-url $(RPC_URL)
	@echo ""
	@echo "Platform wallet ($(PLATFORM)):"
	@cast call $(USDC) "balanceOf(address)(uint256)" $(PLATFORM) --rpc-url $(RPC_URL)

# Usage: make check-native-balance WALLET=0x... NETWORK=base-sepolia
check-native-balance:
	@echo "Native token balance for $(WALLET) on $(NETWORK):"
	@cast balance $(WALLET) --rpc-url $(RPC_URL)

# ============================================
# Payment Operations (Network Agnostic)
# ============================================
# MVP Flow: Customer creates, pays. Platform settles.
.PHONY: create-order pay-order settle-order get-order

# CUSTOMER creates an order (customer scans merchant QR, enters amount, creates order)
# Usage: make create-order MERCHANT_ID=0x... AMOUNT=5000000 PAYER_KEY=$CUSTOMER_KEY NETWORK=base-sepolia
create-order:
	@echo "Customer creating order for merchant $(MERCHANT_ID)..."
	@cast send $(PAYMENT_PROCESSOR) \
		"createOrder(bytes32,address,uint256,string)" \
		$(MERCHANT_ID) $(USDC) $(AMOUNT) "$(METADATA)" \
		--rpc-url $(RPC_URL) \
		--private-key $(or $(PAYER_KEY),$(DEPLOYER_PRIVATE_KEY))

# CUSTOMER pays the order they created
# Usage: make pay-order ORDER_ID=0x... PAYER_KEY=$CUSTOMER_KEY NETWORK=base-sepolia
pay-order:
	@echo "Customer paying order $(ORDER_ID)..."
	@cast send $(PAYMENT_PROCESSOR) \
		"payOrder(bytes32)" \
		$(ORDER_ID) \
		--rpc-url $(RPC_URL) \
		--private-key $(or $(PAYER_KEY),$(DEPLOYER_PRIVATE_KEY))

# CUSTOMER approves USDC before creating/paying (must be done first)
# Usage: make payer-approve AMOUNT=5000000 PAYER_KEY=$CUSTOMER_KEY NETWORK=base-sepolia
payer-approve:
	@echo "Customer approving $(AMOUNT) USDC..."
	@cast send $(USDC) \
		"approve(address,uint256)" \
		$(PAYMENT_PROCESSOR) $(AMOUNT) \
		--rpc-url $(RPC_URL) \
		--private-key $(or $(PAYER_KEY),$(DEPLOYER_PRIVATE_KEY))

# PLATFORM settles an order after payment (distributes 98% to merchant, 2% to platform)
# Usage: make settle-order ORDER_ID=0x... NETWORK=base-sepolia
settle-order:
	@echo "Platform settling order $(ORDER_ID)..."
	@cast send $(PAYMENT_PROCESSOR) \
		"settleOrder(bytes32)" \
		$(ORDER_ID) \
		--rpc-url $(RPC_URL) \
		--private-key $(DEPLOYER_PRIVATE_KEY)

# View order details
# Usage: make get-order ORDER_ID=0x... NETWORK=base-sepolia
get-order:
	@cast call $(PAYMENT_PROCESSOR) \
		"getOrder(bytes32)" \
		$(ORDER_ID) \
		--rpc-url $(RPC_URL)

# ============================================
# Contract Info (Network Agnostic)
# ============================================
.PHONY: info owner

info:
	@echo "========================================"
	@echo "StableBase Contracts ($(NETWORK))"
	@echo "========================================"
	@echo "PaymentProcessor: $(PAYMENT_PROCESSOR)"
	@echo "MerchantRegistry: $(MERCHANT_REGISTRY)"
	@echo "USDC Token:       $(USDC)"
	@echo "========================================"
	@echo "Explorer: $(EXPLORER)"
	@echo "========================================"

owner:
	@echo "PaymentProcessor Owner:"
	@cast call $(PAYMENT_PROCESSOR) "owner()(address)" --rpc-url $(RPC_URL)
	@echo "MerchantRegistry Owner:"
	@cast call $(MERCHANT_REGISTRY) "owner()(address)" --rpc-url $(RPC_URL)

# ============================================
# Help
# ============================================
.PHONY: help

help:
	@echo "StableBase Contracts - Available Commands"
	@echo ""
	@echo "Usage: make <command> NETWORK=<network>"
	@echo "Networks: base-sepolia, polygon-amoy, arbitrum-sepolia, base, polygon, ethereum"
	@echo "Default: NETWORK=base-sepolia"
	@echo ""
	@echo "Basic:"
	@echo "  make build                          - Build contracts"
	@echo "  make test                           - Run tests"
	@echo "  make clean                          - Clean build artifacts"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy NETWORK=polygon-amoy    - Deploy to network"
	@echo "  make set-tokens NETWORK=...         - Set supported tokens"
	@echo "  make info NETWORK=...               - Show contract addresses"
	@echo ""
	@echo "Merchant Management:"
	@echo "  make register-merchant PAYOUT=0x... METADATA=\"https://...\""
	@echo "  make verify-merchant MERCHANT_ID=0x..."
	@echo "  make get-merchant-info MERCHANT_ID=0x..."
	@echo ""
	@echo "Token Operations:"
	@echo "  make approve-usdc AMOUNT=1000000"
	@echo "  make check-usdc-balance WALLET=0x..."
	@echo "  make check-token-support"
	@echo ""
	@echo "Payment Flow:"
	@echo "  1. make create-order MERCHANT_ID=0x... AMOUNT=100000 METADATA=\"...\""
	@echo "  2. make pay-order ORDER_ID=0x..."
	@echo "  3. make settle-order ORDER_ID=0x..."
	@echo ""
	@echo "Examples:"
	@echo "  make deploy NETWORK=polygon-amoy"
	@echo "  make info NETWORK=base-sepolia"
	@echo "  make register-merchant PAYOUT=0x123... METADATA=\"https://...\" NETWORK=polygon-amoy"
