# StableBase Contracts

A decentralized stablecoin payment processing system built on EVM-compatible blockchains. StableBase enables merchants to accept stablecoin payments (USDC, USDT, cUSD) with automated fee collection and settlement.

## Features

- **Multi-chain Support** - Deploy on Ethereum, Base, Polygon, Arbitrum, Optimism, and Celo
- **Stablecoin Payments** - Accept USDC, USDT, and cUSD payments
- **Merchant Registry** - On-chain merchant verification system
- **Upgradeable Contracts** - Built with OpenZeppelin's upgradeable proxy pattern
- **Configurable Fees** - Platform fee management (default 2%)
- **Order Management** - Create, pay, settle, refund, and cancel orders

## Architecture

```
┌─────────────────┐     ┌───────────────────┐     ┌─────────────────┐
│    Customer     │────►│ PaymentProcessor  │────►│    Merchant     │
│   (Payer)       │     │                   │     │  (Recipient)    │
└─────────────────┘     └─────────┬─────────┘     └─────────────────┘
                                  │
                        ┌─────────▼─────────┐
                        │ MerchantRegistry  │
                        │   (Verification)  │
                        └───────────────────┘
```

### Core Contracts

| Contract           | Description                                              |
| ------------------ | -------------------------------------------------------- |
| `PaymentProcessor` | Handles order creation, payment, settlement, and refunds |
| `MerchantRegistry` | Manages merchant registration and verification           |
| `TokensManager`    | Manages supported tokens and platform fees               |

## Payment Flow

1. **Register Merchant** → Merchant registers with payout wallet
2. **Verify Merchant** → Platform owner verifies the merchant
3. **Create Order** → Customer creates an order for a merchant
4. **Pay Order** → Customer pays (requires token approval)
5. **Settle Order** → Funds distributed to merchant (minus platform fee)

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js >= 16

### Installation

```bash
git clone https://github.com/yourusername/StableBase-Contracts.git
cd StableBase-Contracts
make install
```

### Environment Setup

```bash
cp .env.example .env
# Edit .env with your configuration
```

Required environment variables:

```
DEPLOYER_PRIVATE_KEY=your_private_key
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=your_api_key
```

### Build & Test

```bash
make build    # Compile contracts
make test     # Run tests
```

### Deploy

```bash
# Deploy to Base Sepolia testnet
make deploy-base-sepolia

# Set supported tokens
make set-tokens-base-sepolia
```

## Usage

### Register a Merchant

```bash
make register-merchant PAYOUT=0x... METADATA="https://example.com/merchant.json"
```

### Verify Merchant (Owner Only)

```bash
make verify-merchant MERCHANT_ID=0x...
```

### Process a Payment

```bash
# 1. Approve tokens
make approve-usdc AMOUNT=1000000  # 1 USDC

# 2. Create order
make create-order MERCHANT_ID=0x... AMOUNT=500000 METADATA="https://..."

# 3. Pay order
make pay-order ORDER_ID=0x...

# 4. Settle order
make settle-order ORDER_ID=0x...
```

### View Commands

```bash
make help                  # Show all commands
make info                  # Show deployed addresses
make check-token-support   # Check if USDC is supported
```

## Deployed Contracts (Base Sepolia)

| Contract                 | Address                                      |
| ------------------------ | -------------------------------------------- |
| PaymentProcessor (Proxy) | `0x7c39408AC96a1b9a2722056eDE90b54D2B260380` |
| MerchantRegistry (Proxy) | `0x93e93Dfa36C87De32B9118CA5D9BAd1Db892002d` |

## Supported Networks

| Network      | Chain ID | Status      |
| ------------ | -------- | ----------- |
| Ethereum     | 1        | Ready       |
| Base         | 8453     | Ready       |
| Polygon      | 137      | Ready       |
| Arbitrum     | 42161    | Ready       |
| Optimism     | 10       | Ready       |
| Celo         | 42220    | Ready       |
| Base Sepolia | 84532    | ✅ Deployed |

## Contributing

We welcome contributions! Here's how to get started:

### Development Setup

1. **Fork the repository**

2. **Clone your fork**

   ```bash
   git clone https://github.com/YOUR_USERNAME/StableBase-Contracts.git
   cd StableBase-Contracts
   ```

3. **Install dependencies**

   ```bash
   make install
   ```

4. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

### Code Standards

- Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Write tests for new features
- Maintain >90% test coverage
- Use NatSpec comments for all public functions
- Run `make format` before committing

### Testing

```bash
make test                    # Run all tests
forge test -vvv              # Verbose output
forge coverage               # Check coverage
```

### Pull Request Process

1. Update documentation if needed
2. Add tests for new functionality
3. Ensure all tests pass
4. Update the CHANGELOG if applicable
5. Request review from maintainers

### Areas for Contribution

- [ ] Add support for more stablecoins
- [ ] Implement batch payments
- [ ] Add payment streaming
- [ ] Improve gas optimization
- [ ] Add more comprehensive tests
- [ ] Documentation improvements
- [ ] Frontend SDK development

### Report Issues

Found a bug? [Open an issue](https://github.com/yourusername/StableBase-Contracts/issues) with:

- Clear description
- Steps to reproduce
- Expected vs actual behavior
- Network/environment details

## Security

- Contracts use OpenZeppelin's battle-tested libraries
- Upgradeable proxy pattern for future improvements
- Reentrancy protection on all payment functions
- Emergency pause functionality

For security concerns, please email: security@yourdomain.com

## License

MIT License - see [LICENSE](LICENSE) for details

---

Built with ❤️ using [Foundry](https://book.getfoundry.sh/)
