# Sentinel Swarm — 90s Demo Script

1) **Intro (10s)**  
   - "This dApp uses JuliaOS agents + swarms to monitor risk and propose governance actions."

2) **Policy UI (15s)**  
   - Show `ui/default-policies.json` editing or UI screen (if running).  
   - "Policies guide the swarm; changes are versioned and enforced."

3) **Trigger + Run (20s)**  
   - Run the swarm or smoke test to generate a proposal.  
   - `./scripts/smoke_devnet.sh`  
   - Explain: "We produce a Realms proposal with executable instructions."

4) **Explorer (25s)**  
   - Copy `explorerUrl` → open in browser (devnet).  
   - "This is a real on-chain proposal with a tx signature."

5) **Close (20s)**  
   - "JuliaOS = LLM cognition + Julia simulations + on-chain execution.  
     Sentinel Swarm is reusable: risk models, adapters, and policies others can fork."
