# 🚀 Sentinel Swarm — Autonomous DAO Treasury & Risk Manager

**Built with JuliaOS** • AI-native agents + swarms + multi-chain intelligence

## 🎥 Project Explanation and Demo

- [Project Explanation Video](https://www.loom.com/share/980410415c3f4c51936dd3ff779df8ac?sid=d8fb8923-f589-4861-a470-5f35d5ec8d5c): A detailed walkthrough of the Sentinel Swarm project.
- [Demo Video](https://www.loom.com/share/2c4367d67db0445b91a3c45709372191?sid=5287bd8f-a795-4f66-beb3-addce41917e4): A live demonstration of the Sentinel Swarm in action.



## 🎯 Executive Summary

**Problem**: DAOs manage volatile, multi-chain treasuries worth billions. Risk changes hourly due to market shocks, depegs, liquidity drains, and governance attacks. Manual monitoring and reactive proposals are too slow.

**Solution**: Sentinel Swarm is an autonomous risk management system powered by JuliaOS. A swarm of specialized AI agents continuously monitors, simulates, and proposes risk-aware treasury actions with executable governance proposals.

**Why JuliaOS**: We combine LLM cognition (`agent.useLLM()`) with high-performance numerical computing (Julia kernels) and seamless on/off-chain orchestration—delivering explainable autonomy at speed.

## ✨ Key Features

- 🤖 **7 Specialized AI Agents**: Observer, Simulator, Analyst, Risk Officer, Compliance, Proposal Writer, Executor
- 🧠 **Advanced Swarm Intelligence**: Pipeline topology with debate/consensus mechanisms
- ⚡ **High-Performance Risk Models**: Monte Carlo VaR, AMM slippage modeling, portfolio optimization
- 🌐 **Multi-Chain Support**: Solana-native with EVM compatibility
- 📋 **Autonomous Governance**: Generate executable Realms proposals automatically
- 🎛️ **No-Code Policy Builder**: Set risk parameters without coding
- 🔍 **Full Auditability**: Reproducible simulations with seed tracking

## 🚀 Quick Start

### Prerequisites
- Julia 1.9+
- Node.js 18+
- Git
- Solana CLI (for devnet testing)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/sentinel-swarm.git
cd sentinel-swarm

# Install Julia dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Install Node.js dependencies (for UI)
cd ui/web && npm install && cd ../..

# Set up environment
cp .env.example .env
# Edit .env with your RPC endpoints and keys

# Run tests
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Demo Run

```bash
# Start the Sentinel Swarm (devnet mode)
julia --project=. scripts/run_demo.jl

# In another terminal, trigger a risk scenario
julia --project=. scripts/trigger_alert.jl

# Watch the swarm generate an autonomous proposal!
```

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Observer      │───▶│   Simulator     │───▶│   Analyst       │
│   Agent         │    │   Agent         │    │   Agent (LLM)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Executor      │◀───│ Proposal Writer │◀───│  Risk Officer   │
│   Agent         │    │   Agent (LLM)   │    │   Agent         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                               ┌─────────────────┐
                                               │  Compliance     │
                                               │  Agent          │
                                               └─────────────────┘
```

### Detailed Agent Responsibilities

1. **Config Agent**: Loads global variables like wallet keys, realm IDs, and RPC endpoints. This ensures all agents share the same context.

2. **Observation Agent**: Connects to Solana Devnet to fetch live market data and DAO treasury balances.

3. **Risk Simulator**: Computes 24-hour Value at Risk (VaR) to flag volatility and unstable assets.

4. **Analyst Agent**: Uses GPT-4o to strategize treasury actions, such as:
   - “Increase stablecoin reserves”
   - “Hold position”
   - “Reduce exposure to volatile assets”

5. **Risk Officer Agent**: Validates the Analyst’s suggestions against DAO policies. For example, if VaR exceeds 50%, it raises a flag and can reject risky strategies.

6. **Compliance Agent**: Reviews policy conformance and assigns a compliance risk score.

7. **Proposal Writer**: Converts actions into Solana governance instructions. In demo mode, it uses a fallback memo for placeholder addresses.

8. **Bridge Agent**: Interfaces with a TypeScript CLI to translate Julia proposals into JSON for dry-run simulation or on-chain posting.

9. **Executor Agent**: Simulates transactions, confirms compute usage, and saves artifacts — completing the full governance pipeline.


## 📊 Risk Models

### Value at Risk (VaR)
- Monte Carlo simulation with 10,000 trials
- Configurable distributions (Normal, t-distribution, skewed)
- 95% and 99% confidence intervals
- Expected shortfall and drawdown analysis

### AMM Slippage Modeling
- Constant product (x*y=k) and concentrated liquidity
- Multi-hop routing optimization
- Real-time liquidity depth analysis

### Portfolio Optimization
- Minimize VaR subject to policy constraints
- Efficient frontier analysis
- Rebalancing cost optimization

## 🧪 Testing

```bash
# Run all tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Run specific test suites
julia --project=. tests/test_simulator.jl
julia --project=. tests/test_proposal_writer.jl
julia --project=. tests/test_solana_adapter.jl

# Integration tests with devnet
julia --project=. tests/integration/test_end_to_end.jl
```

## 🚀 Devnet Demo

### Setup

```bash
# 1. Copy and configure environment
cp .env.sample .env  # Fill in your values (see below)

# 2. Install Node.js dependencies for Solana CLI
cd chains/ts-cli && npm install && npm run build && cd ../..

# 3. Install Julia dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Environment Configuration (.env)

```bash
# Required: OpenAI API for LLM agents
OPENAI_API_KEY=sk-your-openai-key-here
OPENAI_MODEL=gpt-4o-mini

# Required: Solana devnet configuration
SOLANA_RPC_URL=https://api.devnet.solana.com
SOLANA_WALLET_PRIVATE_KEY=[1,2,3,...]  # Your devnet keypair as JSON array
REALMS_REALM_PUBKEY=YourRealmPubkey
REALMS_GOVERNANCE_PUBKEY=YourGovernancePubkey

# Optional
PYTH_CLUSTER=pyth-devnet
```

### Run Demo

```bash
# Option 1: Interactive demo with all phases
julia demo/demo.jl

# Option 2: Policy editor (no-code UI)
# Open ui/web/index.html in your browser

# Option 3: Trigger scripted threshold breach
julia -e '
include("sentinel_swarm.jl")
swarm = create_sentinel_swarm()
# Simulate market stress to trigger autonomous proposal
ctx = Dict("emergency_mode" => true, "var_breach" => 8.5)
result = run_sentinel_swarm_cycle(swarm; ctx=ctx)
println("Result: ", result["status"])
if haskey(result, "proposalId")
    println("Proposal ID: ", result["proposalId"])
    println("Explorer: ", result["explorerUrl"])
    println("Artifacts: ", result["artifacts_path"])
end
'
```

### Expected Output

```bash
🚀 Sentinel Swarm Demo Output:
✅ Observer: Portfolio monitored (7 assets, $1.2M total)
✅ Simulator: VaR calculated (6.8% vs 6.0% limit)
✅ Analyst: Recommendation generated via LLM
✅ Risk Officer: Policy constraints applied
✅ Compliance: AML screening passed
✅ Proposal Writer: Realms proposal created
✅ Executor: Transaction dry-run successful

🎯 Expected Final Result:
{
  "posted": true,
  "proposalId": "prop_abc123def",
  "explorerUrl": "https://explorer.solana.com/?cluster=devnet",
  "artifacts_path": "data/artifacts/prop_abc123def/"
}

📁 Artifacts saved:
  • data/artifacts/prop_abc123def/policies.json
  • data/artifacts/prop_abc123def/simulation.json  
  • data/artifacts/prop_abc123def/metrics.json
  • data/artifacts/prop_abc123def/proposal.json
```

## 🏆 Acknowledgments

Built for the JuliaOS AI DApp Development Bounty. Special thanks to the JuliaOS team for creating an incredible platform for AI-native applications.

**Follow JuliaOS**: [X/Twitter](https://x.com/BuildOnJulia) • [Discord](https://discord.gg/JuliaOS) • [Docs](https://docs.juliaos.com)

## 📄 License

MIT License - see [LICENSE](./LICENSE) for details.

---

**🚀 Ready to revolutionize DAO treasury management? Let's build the future of autonomous governance together!**
