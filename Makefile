# clean the repo
clean :; forge clean

# Install dependencies
install :; forge install cyfrin/foundry-devops && forge install foundry-rs/forge-std && forge install openzeppelin/openzeppelin-contracts && forge install openzeppelin/openzeppelin-contracts-upgradeable && forge install OpenZeppelin/openzeppelin-foundry-upgrades


# Update Dependencies
update :; forge update

build:; forge build

test:; forge test

snapshot :; forge snapshot

format :; forge fmt

# Deployment commands and usage

# 1. Initial deployment on a network
deploy: @forge script script/Deploy.s.sol --rpc-url $NETWORK_RPC --broadcast --verify

# 2. Post-deployment configuration
postdeploy: @forge script script/PostDeployment.s.sol --rpc-url $NETWORK_RPC --broadcast

# 3. Set supported tokens (if needed separately)
settokens: @forge script script/interactions/SetSupportedTokens.s.sol --rpc-url $NETWORK_RPC --broadcast

# 4. Set token fee settings (if needed separately)
tokensfeesettings: @forge script script/interactions/SetTokenFeeSettings.s.sol --rpc-url $NETWORK_RPC --broadcast

# 5. Upgrade contracts
upgrade: @forge script script/Upgrade.s.sol --rpc-url $NETWORK_RPC --broadcast

# 6. Emergency pause (if needed)
emergency: @forge script script/emergency/EmergencyPause.s.sol --rpc-url $NETWORK_RPC --broadcast

# Network Specific Deployment
# Deploy to Ethereum Mainnet
deployToEthereum: @forge script script/Deploy.s.sol --rpc-url ethereum --broadcast --verify --slow

# Deploy to Polygon
deployToPolygon: @forge script script/Deploy.s.sol --rpc-url polygon --broadcast --verify

# Deploy to Arbitrum
deployToArbitrum: @forge script script/Deploy.s.sol --rpc-url arbitrum --broadcast --verify

# Deploy to Base
deployToBase: @forge script script/Deploy.s.sol --rpc-url base --broadcast --verify

# Deploy to Celo (for cUSD support)
deployToCelo: @forge script script/Deploy.s.sol --rpc-url celo --broadcast --verify

# Deploy to Optimism
deployToOptimism: @forge script script/Deploy.s.sol --rpc-url optimism --broadcast --

# Testnet Deployment Commands
# Deploy to Sepolia testnet
testSepolia: @forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify

# Deploy to Polygon Amoy testnet
testPolygon: @forge script script/Deploy.s.sol --rpc-url amoy --broadcast --verify

# Deploy to Base Sepolia testnet
testBase: @forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
