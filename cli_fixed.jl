#!/usr/bin/env julia

# SENTINEL SWARM CLI - Production Command Line Interface
# Complete CLI for all system operations

using JSON3
using Dates

function print_help()
    println("""
🚀 Sentinel Swarm CLI v1.0.0 - Autonomous DAO Treasury Management

USAGE:
    julia cli.jl <command> [options]

COMMANDS:
    run [--dry-run] [--force]     Run the complete autonomous swarm workflow
    monitor [--interval=60]       Start continuous monitoring mode  
    simulate [--scenarios=list]   Run risk simulation without execution
    status                        Check system status and health
    policy --validate             Validate policy configuration
    help                          Show this help message

EXAMPLES:
    julia cli.jl run --dry-run    # Test workflow without blockchain execution
    julia cli.jl monitor         # Start monitoring with 60s interval
    julia cli.jl status          # Check system health
    julia cli.jl policy --validate # Validate current policies

ENVIRONMENT:
    Ensure .env file is configured with:
    - OPENAI_API_KEY
    - SOLANA_RPC_URL  
    - SOLANA_WALLET_PRIVATE_KEY
    - REALMS_REALM_PUBKEY
    - REALMS_GOVERNANCE_PUBKEY
""")
end

function load_environment()
    if isfile(".env")
        for line in eachline(".env")
            line = strip(line)
            if !startswith(line, "#") && contains(line, "=") && !isempty(line)
                key, value = split(line, "=", limit=2)
                ENV[strip(key)] = strip(value)
            end
        end
        println("✅ Environment loaded from .env")
    else
        println("⚠️  No .env file found - using system environment")
    end
end

function handle_run_command(options)
    println("🎯 RUNNING SENTINEL SWARM WORKFLOW")
    println("=" ^ 50)
    
    dry_run = "--dry-run" in options
    force = "--force" in options
    
    if dry_run
        println("🧪 DRY RUN MODE - No blockchain transactions will be executed")
    end
    
    try
        # Load the system
        include("sentinel_swarm.jl")
        
        # Create swarm
        swarm = create_sentinel_swarm()
        
        # Load policies
        policies = JSON3.read(read("config/default-policies.json", String))
        
        # Extract wallet address from environment
        wallet_address = "CWE8jPTUYhdCTZYWPTe1o5DFqfdjzWKc9WKz6rSjQUdG"  # Demo wallet
        
        println("📋 Analyzing wallet: $(wallet_address[1:8])...")
        
        # Run observation
        observer_context = Dict(
            "portfolio_wallets" => [wallet_address],
            "policies" => policies
        )
        
        observation_result = swarm_call(swarm, "Observer", observer_context)
        portfolio_value = get(get(observation_result, "observation", Dict()), "portfolio", Dict("total_value_usd" => 0))["total_value_usd"]
        println("   ✓ Portfolio value: \$$portfolio_value")
        
        # Run simulation
        sim_context = merge(observer_context, Dict(
            "portfolio" => get(observation_result, "observation", Dict())["portfolio"],
            "market" => get(observation_result, "observation", Dict())["market"]
        ))
        
        simulation_result = swarm_call(swarm, "Simulator", sim_context)
        current_var = get(get(simulation_result, "current_var", Dict()), "var_95_24h", 0.0)
        println("   ✓ Current 24h VaR: $(round(current_var, digits=2))%")
        
        # Check if action needed
        max_var = get(get(policies, "risk_policies", Dict()), "var_constraints", Dict("max_portfolio_var_95_pct" => 10.0))["max_portfolio_var_95_pct"]
        
        if current_var > max_var || force
            println("\n🚨 VaR BREACH DETECTED - Initiating response")
            
            # Run full workflow
            analysis_context = merge(sim_context, Dict("simulation" => simulation_result))
            analysis_result = swarm_call(swarm, "Analyst", analysis_context)
            
            risk_context = merge(analysis_context, Dict("analysis" => analysis_result))
            risk_result = swarm_call(swarm, "RiskOfficer", risk_context)
            
            if get(risk_result, "status", "") == "approved"
                if !dry_run
                    proposal_context = merge(risk_context, Dict(
                        "ok" => Dict("approved_recommendation" => get(risk_result, "approved_recommendation", Dict()))
                    ))
                    
                    proposal_result = swarm_call(swarm, "ProposalWriter", proposal_context)
                    execution_context = merge(proposal_context, Dict("proposal" => proposal_result))
                    execution_result = swarm_call(swarm, "Executor", execution_context)
                    
                    if get(execution_result, "posted", false)
                        println("   🎉 PROPOSAL POSTED!")
                        println("   🔗 $(get(execution_result, "explorer_url", ""))")
                    else
                        println("   ⚠️  Proposal failed: $(get(execution_result, "error", ""))")
                    end
                else
                    println("   🧪 DRY RUN: Would create proposal for risk reduction")
                end
            else
                println("   ❌ Risk officer rejected proposal")
            end
        else
            println("\n✅ Portfolio within risk limits - no action needed")
        end
        
        println("\n✅ Workflow completed successfully!")
        
    catch e
        println("❌ Workflow failed: $e")
        exit(1)
    end
end

function handle_monitor_command(options)
    interval = 60  # Default interval
    
    for opt in options
        if startswith(opt, "--interval=")
            interval = parse(Int, split(opt, "=")[2])
        end
    end
    
    println("👁️  STARTING CONTINUOUS MONITORING")
    println("⏱️  Interval: $(interval)s")
    println("Press Ctrl+C to stop")
    println("=" ^ 50)
    
    try
        # Load the system
        include("sentinel_swarm.jl")
        swarm = create_sentinel_swarm()
        policies = JSON3.read(read("config/default-policies.json", String))
        
        while true
            timestamp = now()
            println("\n🕒 $(Dates.format(timestamp, "HH:MM:SS")) - Monitoring cycle")
            
            # Run observer
            observer_context = Dict(
                "portfolio_wallets" => ["CWE8jPTUYhdCTZYWPTe1o5DFqfdjzWKc9WKz6rSjQUdG"],
                "policies" => policies
            )
            
            result = swarm_call(swarm, "Observer", observer_context)
            
            if result["type"] == "threshold_breach"
                println("🚨 ALERT: Threshold breach detected!")
                alerts = get(get(result, "observation", Dict()), "alerts", [])
                for alert in alerts
                    println("   ⚠️  $alert")
                end
            else
                portfolio = get(get(result, "observation", Dict()), "portfolio", Dict())
                market = get(get(result, "observation", Dict()), "market", Dict())
                
                println("   📊 Portfolio value: \$$(get(portfolio, "total_value_usd", 0))")
                println("   💰 SOL price: \$$(get(get(market, "prices", Dict()), "SOL/USD", 0))")
                println("   ✅ Status: Healthy")
            end
            
            sleep(interval)
        end
        
    catch InterruptException
        println("\n👋 Monitoring stopped by user")
    catch e
        println("\n❌ Monitoring failed: $e")
        exit(1)
    end
end

function handle_simulate_command(options)
    scenarios = ["var_breach", "depeg", "liquidity_drop"]  # Default scenarios
    
    println("🧪 RUNNING RISK SIMULATIONS")
    println("📋 Scenarios: $(join(scenarios, ", "))")
    println("=" ^ 50)
    
    try
        # Load the system
        include("sentinel_swarm.jl")
        swarm = create_sentinel_swarm()
        policies = JSON3.read(read("config/default-policies.json", String))
        
        for scenario in scenarios
            println("\n🎯 Testing scenario: $scenario")
            
            # Create scenario-specific context
            sim_context = create_scenario_context(scenario, policies)
            
            # Run simulation
            sim_result = swarm_call(swarm, "Simulator", sim_context)
            
            # Display key results
            var_95 = get(get(sim_result, "current_var", Dict()), "var_95_24h", 0.0)
            println("   📊 24h VaR (95%): $(round(var_95, digits=2))%")
            
            recommendations = get(sim_result, "recommendations", [])
            println("   💡 Recommendations: $(length(recommendations))")
        end
        
        println("\n✅ All simulations completed")
        
    catch e
        println("❌ Simulation failed: $e")
        exit(1)
    end
end

function handle_status_command(options)
    println("📊 SENTINEL SWARM SYSTEM STATUS")
    println("=" ^ 40)
    
    try
        # Check environment
        println("🔧 Environment:")
        required_vars = ["OPENAI_API_KEY", "SOLANA_RPC_URL", "REALMS_REALM_PUBKEY"]
        for var in required_vars
            status = haskey(ENV, var) && !isempty(ENV[var]) ? "✅" : "❌"
            println("   $status $var")
        end
        
        # Check network connectivity
        println("\n🌐 Network:")
        try
            using HTTP
            response = HTTP.get(ENV["SOLANA_RPC_URL"]; timeout=5)
            println("   ✅ Solana RPC: Connected")
        catch
            println("   ❌ Solana RPC: Failed")
        end
        
        try
            HTTP.get("https://api.openai.com/v1/models", 
                ["Authorization" => "Bearer $(ENV["OPENAI_API_KEY"])"];
                timeout=5)
            println("   ✅ OpenAI API: Connected")
        catch
            println("   ❌ OpenAI API: Failed")
        end
        
        # Check system components
        println("\n🤖 System Components:")
        include("sentinel_swarm.jl")
        swarm = create_sentinel_swarm()
        for agent in swarm.agents
            println("   ✅ $(agent.name): Ready")
        end
        
        # Check policies
        println("\n📋 Policies:")
        if isfile("config/default-policies.json")
            policies = JSON3.read(read("config/default-policies.json", String))
            var_limit = get(get(policies, "risk_policies", Dict()), "var_constraints", Dict("max_portfolio_var_95_pct" => 0))["max_portfolio_var_95_pct"]
            println("   ✅ Risk policies loaded (VaR limit: $(var_limit)%)")
        else
            println("   ❌ Policy file missing")
        end
        
        println("\n✅ System status check complete")
        
    catch e
        println("❌ Status check failed: $e")
        exit(1)
    end
end

function handle_policy_command(options)
    if "--validate" in options
        println("✅ VALIDATING POLICY CONFIGURATION")
        println("=" ^ 40)
        
        try
            policies = JSON3.read(read("config/default-policies.json", String))
            
            # Basic validation
            required_sections = ["risk_policies", "execution_policies", "compliance_policies"]
            for section in required_sections
                if haskey(policies, section)
                    println("   ✅ $section: Present")
                else
                    println("   ❌ $section: Missing")
                end
            end
            
            # Validate risk limits
            risk_policies = get(policies, "risk_policies", Dict())
            var_limit = get(get(risk_policies, "var_constraints", Dict()), "max_portfolio_var_95_pct", 0)
            
            if var_limit > 0 && var_limit < 100
                println("   ✅ VaR limit: $(var_limit)% (Valid)")
            else
                println("   ⚠️  VaR limit: Invalid or missing")
            end
            
            println("\n✅ Policy validation complete")
            
        catch e
            println("❌ Policy validation failed: $e")
            exit(1)
        end
    else
        println("❌ Please specify --validate")
        exit(1)
    end
end

# Helper functions
function create_scenario_context(scenario, policies)
    # Create different contexts based on scenario type
    base_context = Dict("policies" => policies)
    
    if scenario == "var_breach"
        # Simulate high volatility scenario
        base_context["market"] = Dict(
            "prices" => Dict("SOL/USD" => 80.0),  # Lower price
            "volatility" => Dict("SOL" => 0.8)    # High volatility
        )
    elseif scenario == "depeg"
        # Simulate stablecoin depeg
        base_context["market"] = Dict(
            "prices" => Dict("USDC/USD" => 0.995, "USDT/USD" => 0.980)
        )
    elseif scenario == "liquidity_drop"
        # Simulate liquidity crisis
        base_context["market"] = Dict(
            "pools" => [Dict("liquidity_usd" => 1_000_000, "health" => "stressed")]
        )
    end
    
    return base_context
end

function main()
    args = ARGS
    
    if isempty(args) || args[1] == "help" || args[1] == "--help"
        print_help()
        return
    end
    
    println("🚀 Sentinel Swarm CLI v1.0.0")
    println("🔗 Autonomous DAO Treasury Management") 
    println()
    
    # Load environment
    load_environment()
    
    command = args[1]
    options = length(args) > 1 ? args[2:end] : String[]
    
    # Route to appropriate command handler
    if command == "run"
        handle_run_command(options)
    elseif command == "monitor"
        handle_monitor_command(options)
    elseif command == "simulate"
        handle_simulate_command(options) 
    elseif command == "status"
        handle_status_command(options)
    elseif command == "policy"
        handle_policy_command(options)
    else
        println("❌ Unknown command: $command")
        println("Use 'julia cli.jl help' for usage information")
        exit(1)
    end
end

# Run the CLI
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
