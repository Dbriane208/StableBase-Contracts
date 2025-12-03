#!/bin/bash
# test_deployment.sh

echo "=== StableBase Deployment Testing ==="

# 1. Test compilation
echo "Testing contract compilation..."
forge build
if [ $? -ne 0 ]; then
    echo "❌ Compilation failed"
    exit 1
fi
echo "✅ Compilation successful"

# 2. Run unit tests
echo "Running unit tests..."
forge test
if [ $? -ne 0 ]; then
    echo "❌ Unit tests failed"
    exit 1
fi
echo "✅ Unit tests passed"

# 3. Test deployment scripts (dry run)
echo "Testing deployment scripts..."
forge script script/Deploy.s.sol --fork-url $FORK_URL
if [ $? -ne 0 ]; then
    echo "❌ Deployment script test failed"
    exit 1
fi
echo "✅ Deployment script test passed"

# 4. Validate network configuration
echo "Validating network configuration..."
forge script script/NetworkConfig.s.sol --fork-url $FORK_URL
if [ $? -ne 0 ]; then
    echo "❌ Network configuration validation failed"
    exit 1
fi
echo "✅ Network configuration validated"

echo "=== All tests passed! Ready for deployment ==="