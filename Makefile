-include .env
export

# Public fallback RPCs - one `?=` per chain, kept in the same order as
# [rpc_endpoints] in foundry.toml. `?=` only applies when the variable is not
# already set, so values in .env (included above) always win.
ETH_MAINNET_RPC_URL ?= https://eth.llamarpc.com
ETH_SEPOLIA_RPC_URL ?= https://ethereum-sepolia-rpc.publicnode.com # Sepolia
BNB_MAINNET_RPC_URL ?= https://bsc-dataseed.binance.org
BNB_TESTNET_RPC_URL ?= https://data-seed-prebsc-1-s1.binance.org:8545
ARBITRUM_MAINNET_RPC_URL ?= https://arb1.arbitrum.io/rpc # Arbitrum One
ARBITRUM_SEPOLIA_RPC_URL ?= https://sepolia-rollup.arbitrum.io/rpc # Arbitrum Sepolia
BASE_MAINNET_RPC_URL ?= https://mainnet.base.org
BASE_TESTNET_RPC_URL ?= https://sepolia.base.org # Base Sepolia
OP_MAINNET_RPC_URL ?= https://mainnet.optimism.io
OP_TESTNET_RPC_URL ?= https://sepolia.optimism.io # OP Sepolia
MONAD_MAINNET_RPC_URL ?= https://rpc.monad.xyz
MONAD_TESTNET_RPC_URL ?= https://testnet-rpc.monad.xyz # primary test target
HYPERLIQUID_MAINNET_RPC_URL ?= https://rpc.hyperliquid.xyz/evm # HyperEVM
HYPERLIQUID_TESTNET_RPC_URL ?= https://rpc.hyperliquid-testnet.xyz/evm
ROBINHOOD_MAINNET_RPC_URL ?= https://rpc.chain.robinhood.com # Orbit L2, ETH gas
ROBINHOOD_TESTNET_RPC_URL ?= https://rpc.testnet.chain.robinhood.com
XLAYER_MAINNET_RPC_URL ?= https://rpc.xlayer.tech
XLAYER_TESTNET_RPC_URL ?= https://testnet.rpc.xlayer.tech
BOTCHAIN_MAINNET_RPC_URL ?= https://rpc.botchain.ai # BOT, chainId 677
BOTCHAIN_TESTNET_RPC_URL ?= https://rpc.bohr.life # tBOT, chainId 968

# Terminal styling for `make help` (degrades gracefully when unsupported)
bold := $(shell tput bold 2>/dev/null)
cyan := $(shell tput setaf 6 2>/dev/null)
dim := $(shell tput setaf 8 2>/dev/null)
italic := $(shell tput sitm 2>/dev/null)
reset := $(shell tput sgr0 2>/dev/null)

# payment-kit.evm - multi-chain runner
#
# Chains (in order, matching foundry.toml [rpc_endpoints]):
#   ethereum | bnb | arbitrum | base | op | monad | hyperliquid |
#   robinhood | xlayer | botchain        (each with -mainnet and -testnet)
#
# Commands per network:
#   simulate-forwarder-{chain}-{network}  dry run - no transaction broadcast
#   simulate-factory-{chain}-{network}    dry run - no transaction broadcast
#   deploy-forwarder-{chain}-{network}    REAL deploy of shared ERC2771 forwarder
#   deploy-factory-{chain}-{network}      REAL deploy of factory (+ implementation)
#
# Every successful deploy writes deployments/{chain}-{network}.json
# e.g. deployments/monad-testnet.json, deployments/base-mainnet.json
#
# Always simulate first. Set TRUSTED_FORWARDER in .env before deploying a
# factory if you want gasless payments on its registries (see README).

.PHONY: build test clean fmt snapshot ci-local help

build:
	forge build

test:
	forge test -vvv

fmt:
	forge fmt

snapshot:
	forge snapshot

# Mirrors the GitHub Actions CI exactly (fmt check, build, tests, via_ir
# profile). Run this before every push - if it passes here, CI will pass.
ci-local:
	forge fmt --check
	forge build
	forge test
	FOUNDRY_PROFILE=via_ir forge build
	FOUNDRY_PROFILE=via_ir forge test -vv

clean:
	forge clean

help:
	@echo ""
	@echo "$(bold)payment-kit.evm$(reset) - multi-chain payment registry toolkit"
	@echo ""
	@echo "$(dim)Usage:$(reset) make [target]   ($(italic)see targets below$(reset))"
	@echo ""
	@echo "$(cyan)DEVELOPMENT$(reset)"
	@printf "  $(cyan)%-44s$(reset) %s\n" "make ci-local" "Everything CI runs: fmt check, build, tests, via_ir"
	@printf "  $(cyan)%-44s$(reset) %s\n" "make build" "Compile contracts (Solc 0.8.36, pinned)"
	@printf "  $(cyan)%-44s$(reset) %s\n" "make test" "Full test suite incl. invariants (-vvv)"
	@printf "  $(cyan)%-44s$(reset) %s\n" "make fmt" "Auto-format all Solidity sources"
	@printf "  $(cyan)%-44s$(reset) %s\n" "make snapshot" "Gas report per test (.gas-snapshot)"
	@printf "  $(cyan)%-44s$(reset) %s\n" "make clean" "Remove build artifacts"
	@echo ""
	@echo "$(cyan)DEPLOYMENT$(reset) $(dim)- four targets per chain/network$(reset)"
	@printf "  $(cyan)%-44s$(reset) %s\n" \
	  "make simulate-forwarder-\$$CHAIN-\$$NETWORK" "Dry run - deploy ERC2771 forwarder (no broadcast)"
	@printf "  $(cyan)%-44s$(reset) %s\n" \
	  "make simulate-factory-\$$CHAIN-\$$NETWORK" "Dry run - deploy factory + implementation (no broadcast)"
	@printf "  $(cyan)%-44s$(reset) %s\n" \
	  "make deploy-forwarder-\$$CHAIN-\$$NETWORK" "REAL deploy of shared ERC2771 forwarder"
	@printf "  $(cyan)%-44s$(reset) %s\n" \
	  "make deploy-factory-\$$CHAIN-\$$NETWORK" "REAL deploy of factory (+ implementation)"
	@echo ""
	@printf "  $(dim)%-46s$(reset)" "chains :"
	@echo "ethereum bnb arbitrum base op monad hyperliquid"
	@printf "  $(dim)%-46s$(reset)" ""
	@echo "robinhood xlayer botchain"
	@printf "  $(dim)%-46s$(reset)" "network:"
	@echo "mainnet | testnet"
	@echo ""
	@echo "$(cyan)EXAMPLES$(reset)"
	@printf "  $(dim)%-46s$(reset)" "# try before you buy (Monad testnet):"
	@echo '  make simulate-factory-monad-testnet'
	@printf "  $(dim)%-46s$(reset)" "# real deploy:"
	@echo '  make deploy-factory-monad-testnet'
	@echo ""
	@echo "$(dim)Notes:$(reset)"
	@printf "  %-46s\n" "* Real deploys need PRIVATE_KEY (+ RPC URLs) in .env."
	@printf "  %-46s\n" "* Simulate first. Every successful deploy writes"
	@printf "  %-46s\n" "  deployments/{chain}-{network}.json"
	@printf "  %-46s\n" "* Set TRUSTED_FORWARDER in .env before deploying a"
	@printf "  %-46s\n" "  factory if you want gasless payments on its registries."
	@echo ""

# Ethereum
simulate-forwarder-ethereum-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url ethereum_mainnet -vvvv

simulate-factory-ethereum-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url ethereum_mainnet -vvvv

deploy-forwarder-ethereum-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url ethereum_mainnet --broadcast --verify -vvvv

deploy-factory-ethereum-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url ethereum_mainnet --broadcast --verify -vvvv

simulate-forwarder-ethereum-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url ethereum_testnet -vvvv

simulate-factory-ethereum-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url ethereum_testnet -vvvv

deploy-forwarder-ethereum-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url ethereum_testnet --broadcast --verify -vvvv

deploy-factory-ethereum-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url ethereum_testnet --broadcast --verify -vvvv

# BNB Smart Chain
simulate-forwarder-bnb-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url bnb_mainnet -vvvv

simulate-factory-bnb-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url bnb_mainnet -vvvv

deploy-forwarder-bnb-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url bnb_mainnet --broadcast --verify -vvvv

deploy-factory-bnb-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url bnb_mainnet --broadcast --verify -vvvv

simulate-forwarder-bnb-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url bnb_testnet -vvvv

simulate-factory-bnb-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url bnb_testnet -vvvv

deploy-forwarder-bnb-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url bnb_testnet --broadcast --verify -vvvv

deploy-factory-bnb-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url bnb_testnet --broadcast --verify -vvvv

# Arbitrum One / Arbitrum Sepolia
simulate-forwarder-arbitrum-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url arbitrum_mainnet -vvvv

simulate-factory-arbitrum-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url arbitrum_mainnet -vvvv

deploy-forwarder-arbitrum-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url arbitrum_mainnet --broadcast --verify -vvvv

deploy-factory-arbitrum-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url arbitrum_mainnet --broadcast --verify -vvvv

simulate-forwarder-arbitrum-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url arbitrum_testnet -vvvv

simulate-factory-arbitrum-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url arbitrum_testnet -vvvv

deploy-forwarder-arbitrum-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url arbitrum_testnet --broadcast --verify -vvvv

deploy-factory-arbitrum-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url arbitrum_testnet --broadcast --verify -vvvv

# Base / Base Sepolia
simulate-forwarder-base-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url base_mainnet -vvvv

simulate-factory-base-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url base_mainnet -vvvv

deploy-forwarder-base-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url base_mainnet --broadcast --verify -vvvv

deploy-factory-base-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url base_mainnet --broadcast --verify -vvvv

simulate-forwarder-base-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url base_testnet -vvvv

simulate-factory-base-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url base_testnet -vvvv

deploy-forwarder-base-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url base_testnet --broadcast --verify -vvvv

deploy-factory-base-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url base_testnet --broadcast --verify -vvvv

# OP Mainnet / OP Sepolia
simulate-forwarder-op-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url op_mainnet -vvvv

simulate-factory-op-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url op_mainnet -vvvv

deploy-forwarder-op-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url op_mainnet --broadcast --verify -vvvv

deploy-factory-op-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url op_mainnet --broadcast --verify -vvvv

simulate-forwarder-op-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url op_testnet -vvvv

simulate-factory-op-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url op_testnet -vvvv

deploy-forwarder-op-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url op_testnet --broadcast --verify -vvvv

deploy-factory-op-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url op_testnet --broadcast --verify -vvvv

# Monad (primary target)
simulate-forwarder-monad-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url monad_mainnet -vvvv

simulate-factory-monad-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url monad_mainnet -vvvv

deploy-forwarder-monad-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url monad_mainnet --broadcast -vvvv

deploy-factory-monad-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url monad_mainnet --broadcast -vvvv

simulate-forwarder-monad-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url monad_testnet -vvvv

simulate-factory-monad-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url monad_testnet -vvvv

deploy-forwarder-monad-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url monad_testnet --broadcast -vvvv

deploy-factory-monad-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url monad_testnet --broadcast -vvvv

# Hyperliquid HyperEVM
simulate-forwarder-hyperliquid-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url hyperliquid_mainnet -vvvv

simulate-factory-hyperliquid-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url hyperliquid_mainnet -vvvv

deploy-forwarder-hyperliquid-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url hyperliquid_mainnet --broadcast -vvvv

deploy-factory-hyperliquid-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url hyperliquid_mainnet --broadcast -vvvv

simulate-forwarder-hyperliquid-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url hyperliquid_testnet -vvvv

simulate-factory-hyperliquid-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url hyperliquid_testnet -vvvv

deploy-forwarder-hyperliquid-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url hyperliquid_testnet --broadcast -vvvv

deploy-factory-hyperliquid-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url hyperliquid_testnet --broadcast -vvvv

# Robinhood Chain (Arbitrum Orbit)
simulate-forwarder-robinhood-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url robinhood_mainnet -vvvv

simulate-factory-robinhood-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url robinhood_mainnet -vvvv

deploy-forwarder-robinhood-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url robinhood_mainnet --broadcast -vvvv

deploy-factory-robinhood-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url robinhood_mainnet --broadcast -vvvv

simulate-forwarder-robinhood-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url robinhood_testnet -vvvv

simulate-factory-robinhood-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url robinhood_testnet -vvvv

deploy-forwarder-robinhood-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url robinhood_testnet --broadcast -vvvv

deploy-factory-robinhood-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url robinhood_testnet --broadcast -vvvv

# X Layer
simulate-forwarder-xlayer-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url xlayer_mainnet -vvvv

simulate-factory-xlayer-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url xlayer_mainnet -vvvv

deploy-forwarder-xlayer-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url xlayer_mainnet --broadcast -vvvv

deploy-factory-xlayer-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url xlayer_mainnet --broadcast -vvvv

simulate-forwarder-xlayer-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url xlayer_testnet -vvvv

simulate-factory-xlayer-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url xlayer_testnet -vvvv

deploy-forwarder-xlayer-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url xlayer_testnet --broadcast -vvvv

deploy-factory-xlayer-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url xlayer_testnet --broadcast -vvvv

# BOT Chain
simulate-forwarder-botchain-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url botchain_mainnet -vvvv

simulate-factory-botchain-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url botchain_mainnet -vvvv

deploy-forwarder-botchain-mainnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url botchain_mainnet --broadcast -vvvv

deploy-factory-botchain-mainnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url botchain_mainnet --broadcast -vvvv

simulate-forwarder-botchain-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url botchain_testnet -vvvv

simulate-factory-botchain-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url botchain_testnet -vvvv

deploy-forwarder-botchain-testnet:
	forge script script/DeployForwarder.s.sol:DeployForwarder --rpc-url botchain_testnet --broadcast -vvvv

deploy-factory-botchain-testnet:
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url botchain_testnet --broadcast -vvvv
	