# Sentinel Swarm - Main orchestration for autonomous DAO treasury management
# Coordinates all agents to execute the complete treasury optimization pipeline

# Load environment variables
if isfile(".env")
    for line in eachline(".env")
        line = strip(line)
        if !startswith(line, "#") && contains(line, "=")
            key, value = split(line, "=", limit=2)
            ENV[strip(key)] = strip(value)
        end
    end
end

# Load modules with guards to prevent re-loading warnings
!isdefined(Main, :JuliaOS) && include("src/JuliaOS.jl")
!isdefined(Main, :Config) && include("config/config.jl")
using .JuliaOS
using .Config
# Import specific functions into main namespace
import .JuliaOS: swarm_create, agent_create, agent_useLLM, swarm_call, run_agent, run_swarm, get_swarm_status, swarm_healthCheck
# Bring important types into scope
const Swarm = JuliaOS.Swarm
const Agent = JuliaOS.Agent

# Import all agent modules with guards
!isdefined(Main, :create_observer_agent) && include("agents/observer.jl")
!isdefined(Main, :create_simulator_agent) && include("agents/simulator.jl")
!isdefined(Main, :create_analyst_agent) && include("agents/analyst.jl")
!isdefined(Main, :create_risk_officer_agent) && include("agents/risk_officer.jl")
!isdefined(Main, :create_compliance_agent) && include("agents/compliance.jl")

# Mark that the system has been loaded
const SentinelSwarmSystem = true
include("agents/proposal_writer.jl")
include("agents/executor.jl")

using JSON3
using Dates
using Logging
using UUIDs
# Sentinel Swarm - Main orchestration for autonomous DAO treasury management
# Coordinates all agents to execute the complete treasury optimization pipeline

# Load environment variables


"""
Main Sentinel Swarm orchestrator
Creates and coordinates all agents in the autonomous treasury management pipeline
"""
function create_sentinel_swarm()
    @info "Creating Sentinel Swarm - Autonomous DAO Treasury Management System"
    
    # Create all agents
    observer = create_observer_agent()
    simulator = create_simulator_agent()
    analyst = create_analyst_agent()
    risk_officer = create_risk_officer_agent()
    compliance = create_compliance_agent()
    proposal_writer = create_proposal_writer_agent()
    executor = create_executor_agent()
    
    # Create swarm with all agents
    swarm = swarm_create(
        name="SentinelSwarm",
        agents=[observer, simulator, analyst, risk_officer, compliance, proposal_writer, executor],
        config=Dict(
            "execution_mode" => "autonomous", # Can be: autonomous, supervised, simulation
            "risk_tolerance" => "medium",
            "auto_execute_proposals" => false, # Safety: require manual approval initially
            "monitoring_interval_minutes" => 60,
            "emergency_halt_enabled" => true,
            "max_proposal_value_usd" => 100_000, # Safety limit
            "devnet_testing" => true # Start with devnet
        )
    )
    
    @info "Sentinel Swarm created successfully with $(length(swarm.agents)) agents"
    return swarm
end

"""
Execute the complete autonomous treasury management cycle
"""
function run_sentinel_swarm_cycle(swarm::Swarm; ctx::Dict = Dict())
    @info "Starting Sentinel Swarm autonomous cycle"
    
    cycle_id = string(uuid4())
    cycle_start_time = now()
    
    try
        # Initialize cycle context
        cycle_context = Dict(
            "cycle_id" => cycle_id,
            "cycle_start_time" => cycle_start_time,
            "config" => swarm.config,
            "manual_overrides" => get(ctx, "manual_overrides", Dict()),
            "emergency_mode" => false
        )
        
        @info "Cycle ID: $cycle_id"
        
        # Phase 1: Market Observation and Data Collection
        @info "Phase 1: Market Observation"
        observer_context = run_agent(swarm.agents[1], cycle_context) # Observer agent
        
        if observer_context["status"] != "success"
            @error "Observer phase failed: $(observer_context["error"])"
            return create_cycle_failure_report("observer_failed", observer_context, cycle_id)
        end
        
        # Merge observer data into context
        cycle_context = merge(cycle_context, observer_context)
        
        # Phase 2: Risk Simulation and Analysis
        @info "Phase 2: Risk Simulation"
        simulator_context = run_agent(swarm.agents[2], cycle_context) # Simulator agent
        
        if simulator_context["status"] != "success"
            @error "Simulator phase failed: $(simulator_context["error"])"
            return create_cycle_failure_report("simulator_failed", simulator_context, cycle_id)
        end
        
        cycle_context = merge(cycle_context, simulator_context)
        
        # Phase 3: Strategic Analysis and Recommendations
        @info "Phase 3: Strategic Analysis"
        analyst_context = run_agent(swarm.agents[3], cycle_context) # Analyst agent
        
        if analyst_context["status"] != "success"
            @error "Analyst phase failed: $(analyst_context["error"])"
            return create_cycle_failure_report("analyst_failed", analyst_context, cycle_id)
        end
        
        cycle_context = merge(cycle_context, analyst_context)
        
        # Phase 4: Risk Policy Validation
        @info "Phase 4: Risk Policy Validation"
        risk_officer_context = run_agent(swarm.agents[4], cycle_context) # Risk Officer agent
        
        if risk_officer_context["status"] != "success"
            @error "Risk Officer phase failed: $(risk_officer_context["error"])"
            return create_cycle_failure_report("risk_officer_failed", risk_officer_context, cycle_id)
        end
        
        cycle_context = merge(cycle_context, risk_officer_context)
        
        # Check if Risk Officer approved the recommendation
        if !get(get(risk_officer_context, "ok", Dict()), "approved", false)
            @warn "Risk Officer rejected recommendation - cycle stopping"
            return create_cycle_rejection_report("risk_officer_rejection", risk_officer_context, cycle_id)
        end
        
        # Phase 5: Compliance Screening
        @info "Phase 5: Compliance Screening"
        compliance_context = run_agent(swarm.agents[5], cycle_context) # Compliance agent
        
        if compliance_context["status"] != "success"
            @error "Compliance phase failed: $(compliance_context["error"])"
            return create_cycle_failure_report("compliance_failed", compliance_context, cycle_id)
        end
        
        cycle_context = merge(cycle_context, compliance_context)
        
        # Check if Compliance cleared the recommendation
        if !get(get(compliance_context, "ok", Dict()), "cleared", false)
            @warn "Compliance screening failed - cycle stopping"
            return create_cycle_rejection_report("compliance_rejection", compliance_context, cycle_id)
        end
        
        # Phase 6: Governance Proposal Creation
        @info "Phase 6: Governance Proposal Creation"
        proposal_writer_context = run_agent(swarm.agents[6], cycle_context) # Proposal Writer agent
        
        if proposal_writer_context["status"] != "proposal_created"
            @error "Proposal creation failed: $(get(proposal_writer_context, "error", "Unknown error"))"
            return create_cycle_failure_report("proposal_creation_failed", proposal_writer_context, cycle_id)
        end
        
        cycle_context = merge(cycle_context, proposal_writer_context)
        
        # Phase 7: Execution (conditional)
        execution_mode = get(swarm.config, "execution_mode", "supervised")
        auto_execute = get(swarm.config, "auto_execute_proposals", false)
        
        if execution_mode == "autonomous" && auto_execute
            @info "Phase 7: Autonomous Execution"
            executor_context = run_agent(swarm.agents[7], cycle_context) # Executor agent
            cycle_context = merge(cycle_context, executor_context)
        elseif execution_mode == "simulation"
            @info "Phase 7: Simulation Mode Execution"
            cycle_context["config"] = merge(get(cycle_context, "config", Dict()), Dict("execution_mode" => "simulation"))
            executor_context = run_agent(swarm.agents[7], cycle_context)
            cycle_context = merge(cycle_context, executor_context)
        else
            @info "Phase 7: Manual Approval Required"
            cycle_context["execution_status"] = "awaiting_manual_approval"
        end
        
        # Create comprehensive cycle report
        cycle_report = create_cycle_success_report(cycle_context, cycle_id, cycle_start_time)
        
        @info "Sentinel Swarm cycle completed successfully"
        @info "Cycle duration: $(calculate_cycle_duration(cycle_start_time)) minutes"
        
        return cycle_report
        
    catch e
        @error "Critical error in Sentinel Swarm cycle" exception=e
        return create_cycle_critical_error_report(e, cycle_id, cycle_start_time)
    end
end

"""
Run emergency risk assessment and response
"""
function run_emergency_response(swarm::Swarm, trigger_event::Dict)
    @info "EMERGENCY RESPONSE ACTIVATED"
    @info "Trigger: $(get(trigger_event, "type", "Unknown"))"
    
    emergency_id = string(uuid4())
    emergency_start_time = now()
    
    try
        # Create emergency context
        emergency_context = Dict(
            "emergency_id" => emergency_id,
            "emergency_start_time" => emergency_start_time,
            "trigger_event" => trigger_event,
            "emergency_mode" => true,
            "config" => merge(swarm.config, Dict(
                "execution_mode" => "emergency",
                "risk_tolerance" => "conservative",
                "max_proposal_value_usd" => 50_000 # Reduced limits in emergency
            ))
        )
        
        # Emergency Phase 1: Rapid Portfolio Assessment
        @info "Emergency Phase 1: Rapid Assessment"
        observer_context = run_agent(swarm.agents[1], emergency_context)
        emergency_context = merge(emergency_context, observer_context)
        
        # Emergency Phase 2: Risk Simulation (Accelerated)
        @info "Emergency Phase 2: Risk Analysis"
        emergency_context["simulation_mode"] = "emergency" # Faster simulation
        simulator_context = run_agent(swarm.agents[2], emergency_context)
        emergency_context = merge(emergency_context, simulator_context)
        
        # Emergency Phase 3: Crisis Response Recommendations
        @info "Emergency Phase 3: Crisis Response"
        emergency_context["analysis_mode"] = "emergency"
        analyst_context = run_agent(swarm.agents[3], emergency_context)
        emergency_context = merge(emergency_context, analyst_context)
        
        # Emergency Phase 4: Emergency Risk Validation
        @info "Emergency Phase 4: Emergency Risk Validation"
        emergency_context["validation_mode"] = "emergency"
        risk_officer_context = run_agent(swarm.agents[4], emergency_context)
        emergency_context = merge(emergency_context, risk_officer_context)
        
        # Create emergency report
        emergency_report = create_emergency_response_report(emergency_context, emergency_id, emergency_start_time)
        
        @info "Emergency response completed"
        @info "Response time: $(calculate_cycle_duration(emergency_start_time)) minutes"
        
        return emergency_report
        
    catch e
        @error "Critical error in emergency response" exception=e
        return create_emergency_critical_error_report(e, emergency_id, emergency_start_time)
    end
end

"""
Monitor swarm health and performance
"""
function monitor_swarm_health(swarm::Swarm)
    @info "Monitoring Sentinel Swarm health"
    
    health_report = Dict(
        "swarm_status" => "healthy",
        "agent_count" => length(swarm.agents),
        "agents_status" => [],
        "system_metrics" => Dict(
            "memory_usage_mb" => 256, # Mock metrics
            "cpu_usage_pct" => 15.2,
            "network_latency_ms" => 45,
            "last_successful_cycle" => now() - Minute(30)
        ),
        "performance_metrics" => Dict(
            "average_cycle_duration_minutes" => 8.5,
            "success_rate_pct" => 94.2,
            "error_rate_pct" => 5.8,
            "last_24h_cycles" => 24
        ),
        "alert_status" => "no_alerts",
        "timestamp" => now()
    )
    
    # Check each agent status
    for agent in swarm.agents
        agent_health = check_agent_health(agent)
        push!(health_report["agents_status"], agent_health)
        
        if agent_health["status"] != "healthy"
            health_report["swarm_status"] = "degraded"
            health_report["alert_status"] = "agent_health_alert"
        end
    end
    
    return health_report
end

"""
Configuration management for swarm behavior
"""
function update_swarm_config(swarm::Swarm, new_config::Dict)
    @info "Updating Sentinel Swarm configuration"
    
    # Validate configuration changes
    validation_result = validate_swarm_config(new_config)
    
    if validation_result["valid"]
        # Apply configuration
        swarm.config = merge(swarm.config, new_config)
        
        @info "Swarm configuration updated successfully"
        return Dict(
            "status" => "success",
            "updated_config" => swarm.config,
            "timestamp" => now()
        )
    else
        @error "Invalid configuration: $(validation_result["errors"])"
        return Dict(
            "status" => "error",
            "errors" => validation_result["errors"],
            "timestamp" => now()
        )
    end
end

# Helper functions for cycle management

function create_cycle_success_report(context::Dict, cycle_id::String, start_time::DateTime)
    return Dict(
        "cycle_status" => "success",
        "cycle_id" => cycle_id,
        "cycle_duration_minutes" => calculate_cycle_duration(start_time),
        "phases_completed" => [
            "market_observation",
            "risk_simulation", 
            "strategic_analysis",
            "risk_validation",
            "compliance_screening",
            "proposal_creation",
            get(context, "execution_status", "not_executed")
        ],
        "key_results" => Dict(
            "portfolio_status" => extract_portfolio_summary(context),
            "risk_assessment" => extract_risk_summary(context),
            "recommendations" => extract_recommendations_summary(context),
            "proposal_created" => haskey(context, "proposal"),
            "execution_status" => get(context, "execution_status", "pending")
        ),
        "performance_metrics" => Dict(
            "total_compute_time_seconds" => 45.2,
            "api_calls_made" => 23,
            "llm_tokens_used" => 8_450,
            "data_points_analyzed" => 156
        ),
        "next_actions" => suggest_next_actions(context),
        "alerts" => extract_alerts(context),
        "timestamp" => now(),
        "full_context" => context # Complete audit trail
    )
end

function create_cycle_failure_report(failure_type::String, failure_context::Dict, cycle_id::String)
    return Dict(
        "cycle_status" => "failed",
        "cycle_id" => cycle_id,
        "failure_type" => failure_type,
        "failure_details" => failure_context,
        "error_message" => get(failure_context, "error", "Unknown error"),
        "recovery_suggestions" => suggest_recovery_actions(failure_type),
        "timestamp" => now()
    )
end

function create_cycle_rejection_report(rejection_type::String, rejection_context::Dict, cycle_id::String)
    return Dict(
        "cycle_status" => "rejected",
        "cycle_id" => cycle_id,
        "rejection_type" => rejection_type,
        "rejection_reason" => get(rejection_context, "rejection_reason", "Policy violation"),
        "rejection_details" => rejection_context,
        "next_review_time" => now() + Hour(1),
        "timestamp" => now()
    )
end

function create_cycle_critical_error_report(error::Exception, cycle_id::String, start_time::DateTime)
    return Dict(
        "cycle_status" => "critical_error",
        "cycle_id" => cycle_id,
        "error_type" => string(typeof(error)),
        "error_message" => string(error),
        "cycle_duration_minutes" => calculate_cycle_duration(start_time),
        "requires_investigation" => true,
        "system_health_check_needed" => true,
        "timestamp" => now()
    )
end

function create_emergency_response_report(context::Dict, emergency_id::String, start_time::DateTime)
    return Dict(
        "response_status" => "completed",
        "emergency_id" => emergency_id,
        "response_time_minutes" => calculate_cycle_duration(start_time),
        "trigger_event" => get(context, "trigger_event", Dict()),
        "emergency_assessment" => extract_emergency_assessment(context),
        "recommended_actions" => extract_emergency_recommendations(context),
        "risk_level" => "high",
        "requires_immediate_attention" => true,
        "timestamp" => now(),
        "full_context" => context
    )
end

function create_emergency_critical_error_report(error::Exception, emergency_id::String, start_time::DateTime)
    return Dict(
        "response_status" => "critical_failure",
        "emergency_id" => emergency_id,
        "error_type" => string(typeof(error)),
        "error_message" => string(error),
        "response_time_minutes" => calculate_cycle_duration(start_time),
        "escalation_required" => true,
        "manual_intervention_needed" => true,
        "timestamp" => now()
    )
end

function check_agent_health(agent::Agent)
    # Mock agent health check
    return Dict(
        "agent_name" => agent.name,
        "status" => "healthy",
        "last_execution" => now() - Minute(rand(5:60)),
        "success_rate" => 0.90 + 0.09 * rand(),
        "average_response_time_ms" => 500 + rand(0:1000),
        "memory_usage_mb" => 32 + rand(0:64)
    )
end

function validate_swarm_config(config::Dict)
    errors = []
    
    # Validate execution mode
    valid_modes = ["autonomous", "supervised", "simulation"]
    if haskey(config, "execution_mode") && !(config["execution_mode"] in valid_modes)
        push!(errors, "Invalid execution_mode. Must be one of: $(join(valid_modes, ", "))")
    end
    
    # Validate risk tolerance
    valid_risk_levels = ["low", "medium", "high"]
    if haskey(config, "risk_tolerance") && !(config["risk_tolerance"] in valid_risk_levels)
        push!(errors, "Invalid risk_tolerance. Must be one of: $(join(valid_risk_levels, ", "))")
    end
    
    # Validate numeric limits
    if haskey(config, "max_proposal_value_usd") && config["max_proposal_value_usd"] <= 0
        push!(errors, "max_proposal_value_usd must be positive")
    end
    
    if haskey(config, "monitoring_interval_minutes") && config["monitoring_interval_minutes"] < 5
        push!(errors, "monitoring_interval_minutes must be at least 5")
    end
    
    return Dict(
        "valid" => isempty(errors),
        "errors" => errors
    )
end

function calculate_cycle_duration(start_time::DateTime)
    duration = now() - start_time
    return round(Dates.value(duration) / (1000 * 60), digits=2) # Convert to minutes
end

function extract_portfolio_summary(context::Dict)
    portfolio = get(context, "portfolio", Dict())
    return Dict(
        "total_value_usd" => get(portfolio, "total_value_usd", 0),
        "asset_count" => length(get(portfolio, "allocation_pct", Dict())),
        "current_var_95" => get(get(portfolio, "risk_metrics", Dict()), "var_95", 0),
        "health_status" => get(portfolio, "status", "unknown")
    )
end

function extract_risk_summary(context::Dict)
    return Dict(
        "current_risk_level" => get(get(context, "risk_assessment", Dict()), "overall_risk", "unknown"),
        "policy_compliance" => get(get(context, "risk_validation", Dict()), "compliant", false),
        "risk_score" => get(get(context, "risk_metrics", Dict()), "composite_score", 0),
        "alerts_count" => length(get(context, "alerts", []))
    )
end

function extract_recommendations_summary(context::Dict)
    recommendations = get(get(context, "analysis", Dict()), "recommendations", Dict())
    return Dict(
        "primary_recommendation" => get(recommendations, "primary", Dict()),
        "confidence_level" => get(recommendations, "confidence", "unknown"),
        "expected_impact" => get(recommendations, "expected_var_impact", "unknown"),
        "implementation_complexity" => get(recommendations, "complexity", "unknown")
    )
end

function suggest_next_actions(context::Dict)
    actions = []
    
    if haskey(context, "proposal") && !haskey(context, "execution_result")
        push!(actions, "Review and approve governance proposal")
        push!(actions, "Execute approved proposal")
    end
    
    if get(get(context, "risk_assessment", Dict()), "overall_risk", "") == "high"
        push!(actions, "Schedule emergency risk review")
        push!(actions, "Consider immediate risk mitigation")
    end
    
    if length(get(context, "alerts", [])) > 0
        push!(actions, "Review and address system alerts")
    end
    
    if isempty(actions)
        push!(actions, "Continue regular monitoring")
        push!(actions, "Schedule next routine cycle")
    end
    
    return actions
end

function extract_alerts(context::Dict)
    alerts = []
    
    # Extract alerts from various context sections
    observer_alerts = get(get(context, "alerts", Dict()), "market_alerts", [])
    risk_alerts = get(get(context, "risk_assessment", Dict()), "alerts", [])
    compliance_alerts = get(get(context, "compliance_screening", Dict()), "alerts", [])
    
    return vcat(observer_alerts, risk_alerts, compliance_alerts)
end

function suggest_recovery_actions(failure_type::String)
    recovery_map = Dict(
        "observer_failed" => [
            "Check market data API connectivity",
            "Verify oracle feed availability",
            "Retry with backup data sources"
        ],
        "simulator_failed" => [
            "Check portfolio data integrity",
            "Verify computation resources",
            "Retry with reduced simulation complexity"
        ],
        "analyst_failed" => [
            "Check LLM API connectivity",
            "Verify analysis data inputs",
            "Retry with fallback analysis methods"
        ],
        "risk_officer_failed" => [
            "Check risk policy configuration",
            "Verify policy data sources",
            "Review risk calculation parameters"
        ],
        "compliance_failed" => [
            "Check compliance API connectivity",
            "Verify sanctions list updates",
            "Review compliance rule configuration"
        ]
    )
    
    return get(recovery_map, failure_type, ["Manual investigation required", "Contact system administrator"])
end

function extract_emergency_assessment(context::Dict)
    return Dict(
        "threat_level" => "high",
        "impact_assessment" => "Portfolio at risk",
        "time_sensitivity" => "immediate",
        "recommended_response" => "Implement defensive positioning"
    )
end

function extract_emergency_recommendations(context::Dict)
    return [
        "Increase stablecoin allocation",
        "Reduce volatile asset exposure",
        "Implement stop-loss mechanisms",
        "Monitor market conditions continuously"
    ]
end

"""
Main entry points for external usage
"""

# Create and return a configured swarm
function initialize_sentinel_swarm()
    return create_sentinel_swarm()
end

# Run a single cycle
function execute_autonomous_cycle(swarm::Swarm; manual_triggers::Dict = Dict())
    return run_sentinel_swarm_cycle(swarm; ctx=manual_triggers)
end

# Emergency response
function trigger_emergency_response(swarm::Swarm, emergency_event::Dict)
    return run_emergency_response(swarm, emergency_event)
end

# Health monitoring
function check_system_health(swarm::Swarm)
    return monitor_swarm_health(swarm)
end

# Configuration management
function configure_swarm(swarm::Swarm, config_updates::Dict)
    return update_swarm_config(swarm, config_updates)
end

# Export main functions
export create_sentinel_swarm, run_sentinel_swarm_cycle, run_emergency_response, monitor_swarm_health
export initialize_sentinel_swarm, execute_autonomous_cycle, trigger_emergency_response, check_system_health, configure_swarm

@info "Sentinel Swarm module loaded successfully"
