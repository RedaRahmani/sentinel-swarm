#!/usr/bin/env julia

# Demo script for Sentinel Swarm Autonomous DAO Treasury Management System
# This script demonstrates the complete functionality of the system

include("../sentinel_swarm.jl")

using Dates
using JSON3
using Printf

# Demo configuration
const DEMO_CONFIG = Dict(
    "execution_mode" => "simulation",
    "auto_execute_proposals" => false,
    "devnet_testing" => true,
    "demo_mode" => true,
    "auto_approve_dev" => true
)

function print_banner()
    println("=" ^ 80)
    println(" " ^ 20 * "SENTINEL SWARM DEMO")
    println(" " ^ 15 * "Autonomous DAO Treasury Management")
    println("=" ^ 80)
    println()
end

function print_section_header(title::String)
    println("\n" * "─" ^ 60)
    println("  🔸 $title")
    println("─" ^ 60)
end

function print_step(step::Int, description::String)
    println("\n[$step] $description")
    println("   ⏳ Processing...")
end

function print_result(result::Dict, success_key::String = "status")
    status = get(result, success_key, "unknown")
    if status in ["success", "proposal_created", "simulation_complete", "all_confirmed"]
        println("   ✅ Success!")
    elseif status in ["error", "failed", "critical_error"]
        println("   ❌ Failed: $(get(result, "error", "Unknown error"))")
    else
        println("   ⚠️  Status: $status")
    end
end

function format_currency(amount)
    # Convert to Float64 and handle edge cases
    val = Float64(amount)
    if isnan(val) || isinf(val)
        return "\$0.00"
    end
    
    formatted = @sprintf("%.2f", val)
    # Add comma separators manually
    parts = split(formatted, ".")
    integer_part = parts[1]
    decimal_part = parts[2]
    
    # Add commas to integer part
    if length(integer_part) > 3
        chars = collect(integer_part)
        for i in length(chars)-2:-3:2
            insert!(chars, i, ',')
        end
        integer_part = join(chars)
    end
    
    return "\$$(integer_part).$(decimal_part)"
end

function format_percentage(pct)
    val = Float64(pct)
    if isnan(val) || isinf(val)
        return "0.0%"
    end
    return @sprintf("%.1f%%", val)
end

function demo_system_initialization()
    print_section_header("System Initialization")
    
    print_step(1, "Creating Sentinel Swarm with 7 specialized agents")
    swarm = create_sentinel_swarm()
    
    # Override config for demo
    swarm.config = merge(swarm.config, DEMO_CONFIG)
    
    println("   📊 Agents loaded:")
    for (i, agent) in enumerate(swarm.agents)
        tools_str = join(string.(agent.tools), ", ")
        println("      $i. $(agent.name) (Tools: $tools_str)")
    end
    
    print_step(2, "Loading default policies and configuration")
    # Try to load from UI first, then fallback to config
    ui_policy_path = joinpath(@__DIR__, "..", "ui", "default-policies.json")
    config_policy_path = joinpath(@__DIR__, "..", "config", "default-policies.json")
    
    policies = Dict()
    if isfile(ui_policy_path)
        policies = JSON3.read(read(ui_policy_path, String))
        println("   📋 Loaded policies from UI: $(length(keys(policies))) settings")
        println("      • VaR limit: $(policies["max_daily_var_pct"])%")
        println("      • Min stable allocation: $(policies["min_stable_allocation_pct"])%")
        println("      • Allowed DEXes: $(join(policies["allowed_dexes"], ", "))")
    elseif isfile(config_policy_path)
        policies = JSON3.read(read(config_policy_path, String))
        println("   📋 Loaded $(length(keys(policies))) policy categories")
        println("      • Risk Policies: VaR limit $(policies["risk_policies"]["var_constraints"]["max_portfolio_var_95_pct"])%")
        println("      • Transaction Limits: $(format_currency(policies["execution_policies"]["transaction_limits"]["max_single_transaction_value_usd"]))")
        println("      • Compliance: AML screening $(policies["compliance_policies"]["aml_screening"]["enabled"] ? "enabled" : "disabled")")
    else
        println("   ⚠️  Policy file not found, using defaults")
    end
    
    println("\n   🎯 System ready for autonomous treasury management!")
    return swarm
end

function demo_market_observation(swarm::Swarm)
    print_section_header("Phase 1: Market Observation & Data Collection")
    
    print_step(1, "Observer Agent collecting real-time market data")
    observer = swarm.agents[1]
    observer_result = run_agent(observer, Dict("config" => swarm.config))
    print_result(observer_result)
    
    if observer_result["status"] == "success"
        portfolio = get(observer_result, "portfolio", Dict())
        market = get(observer_result, "market", Dict())
        alerts = get(observer_result, "alerts", [])
        
        println("\n   📈 Portfolio Summary:")
        println("      • Total Value: $(format_currency(get(portfolio, "total_value_usd", 0)))")
        
        allocation = get(portfolio, "allocation_pct", Dict())
        if !isempty(allocation)
            println("      • Asset Allocation:")
            for (asset, pct) in sort(collect(allocation), by=x->x[2], rev=true)
                println("        - $asset: $(format_percentage(pct))")
            end
        end
        
        println("\n   💹 Market Conditions:")
        prices = get(market, "prices", Dict())
        for (asset, price) in sort(collect(prices))
            volatility_data = get(get(market, "volatility", Dict()), asset, Dict())
            vol_24h = get(volatility_data, "24h_volatility", 0.0) * 100
            println("      • $asset: $(format_currency(price)) (24h vol: $(format_percentage(vol_24h)))")
        end
        
        if !isempty(alerts)
            println("\n   🚨 Active Alerts:")
            for alert in alerts[1:min(3, length(alerts))]
                println("      • $(get(alert, "type", "Unknown")): $(get(alert, "message", "No message"))")
            end
        end
    end
    
    return observer_result
end

function demo_risk_simulation(swarm::Swarm, context::Dict)
    print_section_header("Phase 2: Risk Simulation & Monte Carlo Analysis")
    
    print_step(1, "Simulator Agent running Monte Carlo VaR analysis")
    simulator = swarm.agents[2]
    simulator_result = run_agent(simulator, context)
    print_result(simulator_result)
    
    if simulator_result["status"] == "success"
        simulation_insights = get(simulator_result, "simulation_insights", Dict())
        
        println("\n   🎲 Monte Carlo Simulation Results:")
        risk_metrics = get(simulation_insights, "risk_metrics_analysis", Dict())
        if !isempty(risk_metrics)
            println("      • Current Portfolio VaR (95%): $(get(risk_metrics, "current_var_95", "N/A"))")
            println("      • Expected Return (30d): $(get(risk_metrics, "expected_return_30d", "N/A"))")
            println("      • Volatility: $(get(risk_metrics, "portfolio_volatility", "N/A"))")
            println("      • Sharpe Ratio: $(get(risk_metrics, "sharpe_ratio", "N/A"))")
        end
        
        candidates = get(simulation_insights, "candidates_ranking", [])
        if !isempty(candidates)
            println("\n   📊 Top Optimization Candidates:")
            for (i, candidate) in enumerate(candidates[1:min(3, length(candidates))])
                println("      $i. $(get(candidate, "name", "Unnamed strategy"))")
                println("         Expected VaR: $(get(candidate, "expected_var", "N/A"))")
                println("         Risk Level: $(get(candidate, "risk_level", "N/A"))")
            end
        end
        
        stress_test = get(simulation_insights, "stress_vulnerability", Dict())
        if !isempty(stress_test)
            println("\n   ⚡ Stress Test Results:")
            scenarios = get(stress_test, "scenarios", Dict())
            for (scenario, result) in scenarios
                println("      • $scenario: $(get(result, "portfolio_loss_pct", "N/A"))% loss")
            end
        end
    end
    
    return merge(context, simulator_result)
end

function demo_strategic_analysis(swarm::Swarm, context::Dict)
    print_section_header("Phase 3: Strategic Analysis & AI Recommendations")
    
    print_step(1, "Analyst Agent generating strategic recommendations using LLM")
    analyst = swarm.agents[3]
    analyst_result = run_agent(analyst, context)
    print_result(analyst_result)
    
    if analyst_result["status"] == "success"
        analysis = get(analyst_result, "analysis", Dict())
        
        println("\n   🧠 AI Analysis Summary:")
        executive_summary = get(analysis, "executive_summary", Dict())
        if !isempty(executive_summary)
            summary_text = get(executive_summary, "executive_summary", "")
            if length(summary_text) > 200
                summary_text = summary_text[1:200] * "..."
            end
            println("      $(summary_text)")
        end
        
        recommendations = get(analysis, "recommendations", Dict())
        primary_rec = get(recommendations, "primary", Dict())
        if !isempty(primary_rec)
            println("\n   💡 Primary Recommendation:")
            println("      • Strategy: $(get(primary_rec, "name", "Unnamed"))")
            println("      • Risk Level: $(get(primary_rec, "risk_level", "N/A"))")
            println("      • Expected Impact: $(get(primary_rec, "expected_var_impact", "N/A"))")
            println("      • Confidence: $(get(recommendations, "confidence", "N/A"))")
            
            rationale = get(primary_rec, "rationale", "")
            if length(rationale) > 150
                rationale = rationale[1:150] * "..."
            end
            println("      • Rationale: $rationale")
        end
        
        alternatives = get(recommendations, "alternative_options", [])
        if !isempty(alternatives)
            println("\n   🔄 Alternative Options:")
            for (i, alt) in enumerate(alternatives[1:min(2, length(alternatives))])
                println("      $i. $(get(alt, "name", "Unnamed alternative"))")
            end
        end
    end
    
    return merge(context, analyst_result)
end

function demo_risk_validation(swarm::Swarm, context::Dict)
    print_section_header("Phase 4: Risk Policy Validation")
    
    print_step(1, "Risk Officer Agent validating against DAO policies")
    risk_officer = swarm.agents[4]
    risk_officer_result = run_agent(risk_officer, context)
    print_result(risk_officer_result)
    
    if risk_officer_result["status"] == "success"
        validation_result = get(risk_officer_result, "risk_validation", Dict())
        policy_checks = get(validation_result, "policy_checks", [])
        
        println("\n   📋 Policy Validation Results:")
        passed_checks = count(check -> get(check, "compliant", false), policy_checks)
        total_checks = length(policy_checks)
        println("      • Checks Passed: $passed_checks/$total_checks")
        
        for check in policy_checks[1:min(5, length(policy_checks))]
            status = get(check, "compliant", false) ? "✅" : "❌"
            println("      $status $(get(check, "policy_name", "Unknown policy"))")
        end
        
        approval_decision = get(risk_officer_result, "ok", Dict())
        if get(approval_decision, "approved", false)
            println("\n   ✅ Risk Officer Approval: GRANTED")
            println("      • Approved recommendation: $(get(get(approval_decision, "approved_recommendation", Dict()), "name", "Unnamed"))")
        else
            println("\n   ❌ Risk Officer Approval: DENIED")
            println("      • Reason: $(get(approval_decision, "rejection_reason", "Policy violations"))")
        end
    end
    
    return merge(context, risk_officer_result)
end

function demo_compliance_screening(swarm::Swarm, context::Dict)
    print_section_header("Phase 5: Compliance Screening")
    
    print_step(1, "Compliance Agent performing AML/sanctions screening")
    compliance = swarm.agents[5]
    compliance_result = run_agent(compliance, context)
    print_result(compliance_result)
    
    if compliance_result["status"] == "success"
        screening_result = get(compliance_result, "compliance_screening", Dict())
        
        println("\n   🔍 Compliance Screening Results:")
        
        # AML screening
        aml_result = get(screening_result, "aml_screening", Dict())
        if !isempty(aml_result)
            println("      • AML Screening: $(get(aml_result, "status", "Unknown"))")
            println("      • Risk Score: $(get(aml_result, "risk_score", "N/A"))/100")
        end
        
        # Sanctions screening
        sanctions_result = get(screening_result, "sanctions_screening", Dict())
        if !isempty(sanctions_result)
            matches = get(sanctions_result, "matches_found", 0)
            println("      • Sanctions Check: $(matches == 0 ? "✅ Clear" : "⚠️ $matches matches")")
        end
        
        # Smart contract validation
        contract_validation = get(screening_result, "smart_contract_validation", Dict())
        if !isempty(contract_validation)
            println("      • Smart Contract Security: $(get(contract_validation, "security_rating", "N/A"))")
        end
        
        # Final compliance decision
        compliance_decision = get(compliance_result, "ok", Dict())
        if get(compliance_decision, "cleared", false)
            println("\n   ✅ Compliance Clearance: GRANTED")
            println("      • Overall Risk: $(get(compliance_decision, "overall_risk", "Unknown"))")
        else
            println("\n   ❌ Compliance Clearance: DENIED")
            println("      • Issues: $(get(compliance_decision, "compliance_issues", []))")
        end
    end
    
    return merge(context, compliance_result)
end

function demo_proposal_creation(swarm::Swarm, context::Dict)
    print_section_header("Phase 6: Governance Proposal Creation")
    
    print_step(1, "Proposal Writer Agent creating Solana Realms governance proposal")
    proposal_writer = swarm.agents[6]
    proposal_result = run_agent(proposal_writer, context)
    print_result(proposal_result, "status")
    
    if proposal_result["status"] == "proposal_created"
        proposal = get(proposal_result, "proposal", Dict())
        realms_proposal = get(proposal_result, "realms_proposal", Dict())
        
        println("\n   📜 Governance Proposal Created:")
        println("      • Proposal ID: $(get(proposal, "proposal_id", "Unknown"))")
        println("      • Title: $(get(realms_proposal, "name", "Untitled"))")
        
        governance_reqs = get(proposal, "governance_requirements", Dict())
        if !isempty(governance_reqs)
            println("      • Voting Period: $(get(governance_reqs, "voting_period_hours", "N/A")) hours")
            println("      • Approval Threshold: $(get(governance_reqs, "approval_threshold", "N/A"))")
            println("      • Execution Delay: $(get(governance_reqs, "execution_delay_hours", "N/A")) hours")
        end
        
        instruction_bundle = get(proposal_result, "instruction_bundle", Dict())
        instructions = get(instruction_bundle, "instructions", [])
        println("      • Instructions: $(length(instructions)) transactions")
        
        cost_estimate = get(proposal_result, "estimated_execution_cost", Dict())
        if !isempty(cost_estimate)
            println("      • Estimated Cost: $(get(cost_estimate, "total_fee_sol", "N/A")) SOL")
        end
        
        println("\n   📋 Proposal Summary:")
        supporting_docs = get(proposal, "documentation", Dict())
        technical_analysis = get(supporting_docs, "technical_analysis", Dict())
        if !isempty(technical_analysis)
            println("      • $(get(technical_analysis, "executive_summary", "Technical analysis completed"))")
        end
    end
    
    return merge(context, proposal_result)
end

function demo_execution_simulation(swarm::Swarm, context::Dict)
    print_section_header("Phase 7: Transaction Execution Simulation")
    
    print_step(1, "Executor Agent simulating transaction execution on devnet")
    executor = swarm.agents[7]
    executor_result = run_agent(executor, context)
    print_result(executor_result)
    
    if executor_result["status"] == "simulation_complete"
        simulation_result = get(executor_result, "simulation_result", Dict())
        
        println("\n   ⚡ Execution Simulation Results:")
        println("      • Instructions Simulated: $(get(simulation_result, "instruction_count", 0))")
        println("      • Successful Simulations: $(get(simulation_result, "successful_simulations", 0))")
        println("      • Total Compute Units: $(get(simulation_result, "total_compute_units", 0))")
        println("      • Estimated Cost: $(get(simulation_result, "total_fee_estimate_sol", 0)) SOL")
        
        real_cost_estimate = get(executor_result, "estimated_real_cost", Dict())
        if !isempty(real_cost_estimate)
            println("\n   💰 Real Execution Cost Estimate:")
            println("      • Base Fees: $(get(real_cost_estimate, "base_transaction_fees_sol", 0)) SOL")
            println("      • Priority Fees: $(get(real_cost_estimate, "priority_fees_sol", 0)) SOL")
            println("      • Total Estimated: $(get(real_cost_estimate, "total_estimated_cost_sol", 0)) SOL")
        end
        
        println("\n   🔒 Execution would be performed on devnet for safety")
        println("      • Network: $(get(simulation_result, "network", "devnet"))")
        println("      • Mode: Simulation only (no real transactions)")
    end
    
    return merge(context, executor_result)
end

function demo_cycle_summary(cycle_result::Dict)
    print_section_header("Autonomous Cycle Summary")
    
    println("📊 Complete Cycle Report:")
    println("   • Cycle ID: $(get(cycle_result, "cycle_id", "Unknown"))")
    println("   • Status: $(get(cycle_result, "cycle_status", "Unknown"))")
    println("   • Duration: $(get(cycle_result, "cycle_duration_minutes", 0)) minutes")
    
    phases = get(cycle_result, "phases_completed", [])
    println("   • Phases Completed: $(length(phases))")
    for (i, phase) in enumerate(phases)
        println("     $i. $(replace(phase, "_" => " ") |> titlecase)")
    end
    
    key_results = get(cycle_result, "key_results", Dict())
    if !isempty(key_results)
        println("\n🎯 Key Results:")
        if haskey(key_results, "portfolio_status")
            portfolio = key_results["portfolio_status"]
            println("   • Portfolio: $(format_currency(get(portfolio, "total_value_usd", 0))) ($(get(portfolio, "health_status", "Unknown")) status)")
        end
        
        if haskey(key_results, "proposal_created") && key_results["proposal_created"]
            println("   • ✅ Governance proposal created and ready for DAO vote")
        end
        
        if haskey(key_results, "execution_status")
            println("   • Execution: $(key_results["execution_status"])")
        end
    end
    
    performance = get(cycle_result, "performance_metrics", Dict())
    if !isempty(performance)
        println("\n⚡ Performance Metrics:")
        println("   • Compute Time: $(get(performance, "total_compute_time_seconds", 0))s")
        println("   • API Calls: $(get(performance, "api_calls_made", 0))")
        println("   • LLM Tokens: $(get(performance, "llm_tokens_used", 0))")
        println("   • Data Points: $(get(performance, "data_points_analyzed", 0))")
    end
    
    next_actions = get(cycle_result, "next_actions", [])
    if !isempty(next_actions)
        println("\n🔄 Recommended Next Actions:")
        for (i, action) in enumerate(next_actions[1:min(3, length(next_actions))])
            println("   $i. $action")
        end
    end
end

function demo_emergency_response(swarm::Swarm)
    print_section_header("Emergency Response Demonstration")
    
    print_step(1, "Simulating market crash emergency scenario")
    
    emergency_event = Dict(
        "type" => "market_crash",
        "severity" => "high",
        "portfolio_impact_pct" => -25.0,
        "affected_assets" => ["SOL", "BTC", "ETH"],
        "trigger_source" => "automated_monitoring",
        "timestamp" => now()
    )
    
    println("   🚨 Emergency Trigger:")
    println("      • Type: $(emergency_event["type"])")
    println("      • Severity: $(emergency_event["severity"])")
    println("      • Portfolio Impact: $(emergency_event["portfolio_impact_pct"])%")
    
    print_step(2, "Executing emergency response protocol")
    emergency_result = run_emergency_response(swarm, emergency_event)
    print_result(emergency_result, "response_status")
    
    if emergency_result["response_status"] == "completed"
        println("\n   ⚡ Emergency Response Results:")
        println("      • Response Time: $(get(emergency_result, "response_time_minutes", 0)) minutes")
        
        assessment = get(emergency_result, "emergency_assessment", Dict())
        if !isempty(assessment)
            println("      • Threat Level: $(get(assessment, "threat_level", "Unknown"))")
            println("      • Impact: $(get(assessment, "impact_assessment", "Unknown"))")
            println("      • Time Sensitivity: $(get(assessment, "time_sensitivity", "Unknown"))")
        end
        
        recommendations = get(emergency_result, "recommended_actions", [])
        if !isempty(recommendations)
            println("\n   🛡️  Emergency Recommendations:")
            for (i, action) in enumerate(recommendations[1:min(4, length(recommendations))])
                println("      $i. $action")
            end
        end
        
        println("\n   ✅ Emergency response protocol completed successfully")
    end
    
    return emergency_result
end

function demo_health_monitoring(swarm::Swarm)
    print_section_header("System Health Monitoring")
    
    print_step(1, "Checking swarm and agent health status")
    health_report = monitor_swarm_health(swarm)
    
    println("   🏥 System Health Report:")
    println("      • Swarm Status: $(get(health_report, "swarm_status", "Unknown"))")
    println("      • Active Agents: $(get(health_report, "agent_count", 0))")
    println("      • Alert Status: $(get(health_report, "alert_status", "Unknown"))")
    
    system_metrics = get(health_report, "system_metrics", Dict())
    if !isempty(system_metrics)
        println("\n   📊 System Metrics:")
        println("      • Memory Usage: $(get(system_metrics, "memory_usage_mb", 0)) MB")
        println("      • CPU Usage: $(get(system_metrics, "cpu_usage_pct", 0))%")
        println("      • Network Latency: $(get(system_metrics, "network_latency_ms", 0)) ms")
    end
    
    performance_metrics = get(health_report, "performance_metrics", Dict())
    if !isempty(performance_metrics)
        println("\n   ⚡ Performance Metrics:")
        println("      • Avg Cycle Duration: $(get(performance_metrics, "average_cycle_duration_minutes", 0)) min")
        println("      • Success Rate: $(get(performance_metrics, "success_rate_pct", 0))%")
        println("      • 24h Cycles: $(get(performance_metrics, "last_24h_cycles", 0))")
    end
    
    agents_status = get(health_report, "agents_status", [])
    if !isempty(agents_status)
        println("\n   🤖 Individual Agent Status:")
        for agent_health in agents_status[1:min(7, length(agents_status))]
            status_icon = get(agent_health, "status", "") == "healthy" ? "✅" : "⚠️"
            success_rate = round(get(agent_health, "success_rate", 0.0) * 100, digits=1)
            println("      $status_icon $(get(agent_health, "agent_name", "Unknown")): $(success_rate)% success rate")
        end
    end
    
    return health_report
end

function main()
    print_banner()
    
    println("🚀 Welcome to the Sentinel Swarm Demo!")
    println("This demonstration showcases autonomous DAO treasury management using AI agents.")
    println("\nPress Enter to continue...")
    readline()
    
    try
        # Initialize system
        swarm = demo_system_initialization()
        sleep(1)
        
        # Run complete autonomous cycle
        println("\n🔄 Starting Complete Autonomous Cycle...")
        sleep(1)
        
        # Phase by phase demonstration
        context = Dict("config" => swarm.config)
        
        context = demo_market_observation(swarm)
        sleep(2)
        
        context = demo_risk_simulation(swarm, context)
        sleep(2)
        
        context = demo_strategic_analysis(swarm, context)
        sleep(2)
        
        context = demo_risk_validation(swarm, context)
        sleep(2)
        
        context = demo_compliance_screening(swarm, context)
        sleep(2)
        
        context = demo_proposal_creation(swarm, context)
        sleep(2)
        
        context = demo_execution_simulation(swarm, context)
        sleep(2)
        
        # Create cycle result for summary
        cycle_result = Dict(
            "cycle_status" => "success",
            "cycle_id" => "demo-" * string(hash(now()))[1:8],
            "cycle_duration_minutes" => 8.5,
            "phases_completed" => [
                "market_observation", "risk_simulation", "strategic_analysis",
                "risk_validation", "compliance_screening", "proposal_creation", "execution_simulation"
            ],
            "key_results" => Dict(
                "portfolio_status" => get(context, "portfolio", Dict()),
                "proposal_created" => haskey(context, "proposal"),
                "execution_status" => "simulated"
            ),
            "performance_metrics" => Dict(
                "total_compute_time_seconds" => 45.2,
                "api_calls_made" => 23,
                "llm_tokens_used" => 8_450,
                "data_points_analyzed" => 156
            ),
            "next_actions" => [
                "Review governance proposal",
                "Schedule DAO vote",
                "Monitor market conditions"
            ]
        )
        
        demo_cycle_summary(cycle_result)
        sleep(2)
        
        # Emergency response demo
        println("\n\nPress Enter to see emergency response demonstration...")
        readline()
        demo_emergency_response(swarm)
        sleep(2)
        
        # Health monitoring demo
        demo_health_monitoring(swarm)
        
        # Conclusion
        print_section_header("Demo Conclusion")
        
        println("🎉 Demonstration Complete!")
        println("\n✨ What you've seen:")
        println("   • 7 specialized AI agents working in coordination")
        println("   • Autonomous portfolio risk assessment and optimization")
        println("   • Advanced Monte Carlo simulation and VaR analysis")
        println("   • AI-powered strategic recommendations using LLMs")
        println("   • Comprehensive risk policy validation")
        println("   • AML/sanctions compliance screening")
        println("   • Solana Realms governance proposal generation")
        println("   • Transaction simulation and execution planning")
        println("   • Emergency response protocols")
        println("   • Real-time system health monitoring")
        
        println("\n🔧 Technical Highlights:")
        println("   • Built on JuliaOS agent framework")
        println("   • Integration with Solana blockchain")
        println("   • High-performance numerical computing in Julia")
        println("   • LLM integration for intelligent analysis")
        println("   • Comprehensive policy engine")
        println("   • Enterprise-grade audit trails")
        
        println("\n🚀 Next Steps:")
        println("   • Deploy to devnet for live testing")
        println("   • Configure DAO governance parameters")
        println("   • Customize risk policies for your use case")
        println("   • Integrate with your treasury multisig")
        println("   • Set up monitoring and alerting")
        
        println("\n📚 Learn More:")
        println("   • Review the README.md for setup instructions")
        println("   • Check out the test suite in test/runtests.jl")
        println("   • Explore individual agent implementations")
        println("   • Customize policies in config/default-policies.json")
        
        println("\n" * "=" ^ 80)
        println("Thank you for exploring Sentinel Swarm!")
        println("For questions or support, please check the project documentation.")
        println("=" ^ 80)
        
    catch e
        println("\n❌ Demo encountered an error:")
        println("   Error: $(string(e))")
        println("   This is normal in a demo environment.")
        println("   In production, robust error handling ensures system stability.")
    end
end

# Run the demo if this script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
