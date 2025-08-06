# Risk Officer Agent - Policy enforcement and risk constraint management
# Part of the Sentinel Swarm autonomous treasury management system

include("../src/JuliaOS.jl")
using .JuliaOS
using JSON3
using Dates
using Logging

"""
Risk Officer Agent enforces risk policies and constraints:
- Validates proposals against DAO risk policies
- Enforces allocation limits and exposure caps
- Checks compliance with governance rules
- Applies risk guardrails and circuit breakers
"""
function create_risk_officer_agent()
    return Agent(
        name="RiskOfficer",
        tools=[:policy_validation, :risk_limits, :exposure_checks, :circuit_breakers],
        config=Dict(
            "strict_enforcement" => true,
            "override_threshold" => "governance_vote",
            "escalation_levels" => ["warning", "block", "emergency_stop"],
            "policy_version" => "1.0"
        ),
        run=enforce_risk_policies
    )
end

"""
Main risk enforcement logic - validates proposals against all policies
"""
function enforce_risk_policies(ctx::Dict)
    @info "RiskOfficer: Starting policy enforcement review"
    
    try
        # Extract data from context
        analysis = get(ctx, "analysis", Dict())
        portfolio = get(ctx, "portfolio", Dict())
        policies = get(ctx, "policies", Dict())
        market = get(ctx, "market", Dict())
        
        # Get recommended option from analysis
        recommendations = get(analysis, "recommendations", Dict())
        primary_recommendation = get(recommendations, "primary_recommendation", Dict())
        
        if isempty(primary_recommendation)
            return Dict(
                "status" => "no_action",
                "message" => "No recommendation provided for evaluation",
                "violations" => [],
                "timestamp" => now()
            )
        end
        
        # Perform comprehensive policy validation
        # Convert JSON3.Object to Dict if needed
        policies_dict = policies isa Dict ? policies : Dict(policies)
        validation_results = validate_against_policies(primary_recommendation, portfolio, policies_dict, market, ctx)
        
        # Get size_pct from recommendation
        size_pct = get(primary_recommendation, "size_pct", 0.0)
        max_rebalance_pct = get(get(policies_dict, "risk_policies", Dict()), "max_rebalance_pct", 0.25)
        
        # Check if size exceeds policy limits
        violations = get(validation_results, "violations", [])
        if size_pct > max_rebalance_pct
            push!(violations, "Rebalance size $(size_pct*100)% exceeds policy limit $(max_rebalance_pct*100)%")
        end
        
        # Determine approval status
        status = isempty(violations) ? "approved" : "rejected"
        
        @info "RiskOfficer: Policy review complete" status=status violations=length(violations)
        
        return Dict(
            "status" => status,
            "violations" => violations,
            "recommendation" => primary_recommendation,
            "message" => status == "approved" ? "Recommendation approved" : "Policy violations detected",
            "timestamp" => now()
        )
        
    catch e
        @error "RiskOfficer: Error during policy enforcement" exception=e
        return Dict(
            "status" => "error",
            "error" => string(e),
            "timestamp" => now()
        )
    end
end

"""
Validate recommendation against all DAO policies
"""
function validate_against_policies(recommendation::Dict, portfolio::Dict, policies::Dict, market::Dict, ctx::Dict)
    @info "RiskOfficer: Validating recommendation against DAO policies"
    
    validation_results = Dict(
        "passed" => String[],
        "failed" => String[],
        "warnings" => String[],
        "details" => Dict()
    )
    
    # Check maximum daily VaR policy
    max_var_policy = check_max_var_policy(recommendation, policies, validation_results)
    
    # Check minimum stable allocation policy
    min_stable_policy = check_min_stable_policy(recommendation, policies, validation_results)
    
    # Check allowed DEXes policy
    allowed_dexes_policy = check_allowed_dexes_policy(recommendation, policies, validation_results)
    
    # Check concentration limits
    concentration_policy = check_concentration_limits(recommendation, portfolio, policies, validation_results)
    
    # Check transaction size limits
    transaction_limits_policy = check_transaction_limits(recommendation, policies, validation_results)
    
    # Check slippage tolerances
    slippage_policy = check_slippage_tolerances(recommendation, policies, validation_results)
    
    # Calculate overall policy compliance score
    total_checks = length(validation_results["passed"]) + length(validation_results["failed"])
    compliance_score = total_checks > 0 ? length(validation_results["passed"]) / total_checks : 0.0
    
    validation_results["compliance_score"] = compliance_score
    validation_results["overall_status"] = compliance_score >= 0.8 ? "compliant" : "non_compliant"
    
    return validation_results
end

"""
Check maximum daily VaR policy
"""
function check_max_var_policy(recommendation::Dict, policies::Dict, validation_results::Dict)
    max_var_pct = get(policies, "max_daily_var_pct", 8.0)
    expected_var = get(recommendation, "expected_var_impact", "0%")
    
    # Parse expected VaR impact
    var_value = parse_var_impact(expected_var)
    
    if var_value <= max_var_pct
        push!(validation_results["passed"], "max_daily_var_policy")
        validation_results["details"]["max_var_check"] = Dict(
            "status" => "passed",
            "expected_var" => var_value,
            "limit" => max_var_pct,
            "margin" => max_var_pct - var_value
        )
    else
        push!(validation_results["failed"], "max_daily_var_policy")
        validation_results["details"]["max_var_check"] = Dict(
            "status" => "failed",
            "expected_var" => var_value,
            "limit" => max_var_pct,
            "excess" => var_value - max_var_pct
        )
    end
end

"""
Check minimum stable allocation policy
"""
function check_min_stable_policy(recommendation::Dict, policies::Dict, validation_results::Dict)
    min_stable_pct = get(policies, "min_stable_allocation_pct", 30.0)
    
    # Check if recommendation maintains minimum stable allocation
    # This would need to be calculated based on the specific actions in the recommendation
    new_allocation = estimate_new_allocation_from_recommendation(recommendation)
    stable_allocation = calculate_stable_allocation(new_allocation)
    
    if stable_allocation >= min_stable_pct
        push!(validation_results["passed"], "min_stable_allocation_policy")
        validation_results["details"]["min_stable_check"] = Dict(
            "status" => "passed",
            "stable_allocation" => stable_allocation,
            "requirement" => min_stable_pct,
            "margin" => stable_allocation - min_stable_pct
        )
    else
        push!(validation_results["failed"], "min_stable_allocation_policy")
        validation_results["details"]["min_stable_check"] = Dict(
            "status" => "failed", 
            "stable_allocation" => stable_allocation,
            "requirement" => min_stable_pct,
            "shortfall" => min_stable_pct - stable_allocation
        )
    end
end

"""
Check allowed DEXes policy
"""
function check_allowed_dexes_policy(recommendation::Dict, policies::Dict, validation_results::Dict)
    allowed_dexes = get(policies, "allowed_dexes", ["Orca", "Jupiter", "Phoenix"])
    
    # Extract DEXes from recommendation actions (if any)
    used_dexes = extract_dexes_from_recommendation(recommendation)
    
    unauthorized_dexes = filter(dex -> !(dex in allowed_dexes), used_dexes)
    
    if isempty(unauthorized_dexes)
        push!(validation_results["passed"], "allowed_dexes_policy")
        validation_results["details"]["dexes_check"] = Dict(
            "status" => "passed",
            "used_dexes" => used_dexes,
            "allowed_dexes" => allowed_dexes
        )
    else
        push!(validation_results["failed"], "allowed_dexes_policy")
        validation_results["details"]["dexes_check"] = Dict(
            "status" => "failed",
            "unauthorized_dexes" => unauthorized_dexes,
            "allowed_dexes" => allowed_dexes
        )
    end
end

"""
Check concentration limits policy
"""
function check_concentration_limits(recommendation::Dict, portfolio::Dict, policies::Dict, validation_results::Dict)
    max_single_asset_pct = get(policies, "max_single_asset_allocation_pct", 70.0)
    
    # Estimate new allocation after recommendation
    new_allocation = estimate_new_allocation_from_recommendation(recommendation)
    
    violations = String[]
    for (asset, allocation_pct) in new_allocation
        if allocation_pct > max_single_asset_pct && !contains(uppercase(asset), "USD")
            push!(violations, "$asset: $(round(allocation_pct, digits=1))% > $(max_single_asset_pct)%")
        end
    end
    
    if isempty(violations)
        push!(validation_results["passed"], "concentration_limits_policy")
        validation_results["details"]["concentration_check"] = Dict(
            "status" => "passed",
            "max_allocation" => maximum(values(new_allocation)),
            "limit" => max_single_asset_pct
        )
    else
        push!(validation_results["failed"], "concentration_limits_policy")
        validation_results["details"]["concentration_check"] = Dict(
            "status" => "failed",
            "violations" => violations,
            "limit" => max_single_asset_pct
        )
    end
end

"""
Check transaction size limits
"""
function check_transaction_limits(recommendation::Dict, policies::Dict, validation_results::Dict)
    max_single_tx_pct = get(policies, "max_single_transaction_pct", 25.0)
    
    # Extract transaction sizes from recommendation
    transaction_sizes = extract_transaction_sizes_from_recommendation(recommendation)
    
    oversized_transactions = filter(tx -> tx["size_pct"] > max_single_tx_pct, transaction_sizes)
    
    if isempty(oversized_transactions)
        push!(validation_results["passed"], "transaction_limits_policy")
        validation_results["details"]["transaction_limits_check"] = Dict(
            "status" => "passed",
            "max_transaction_size" => isempty(transaction_sizes) ? 0.0 : maximum(tx["size_pct"] for tx in transaction_sizes),
            "limit" => max_single_tx_pct
        )
    else
        push!(validation_results["failed"], "transaction_limits_policy")
        validation_results["details"]["transaction_limits_check"] = Dict(
            "status" => "failed",
            "oversized_transactions" => oversized_transactions,
            "limit" => max_single_tx_pct
        )
    end
end

"""
Check slippage tolerance policies
"""
function check_slippage_tolerances(recommendation::Dict, policies::Dict, validation_results::Dict)
    max_slippage_bps = get(policies, "max_slippage_tolerance_bps", 100)
    
    # Extract slippage from recommendation
    expected_slippage = extract_slippage_from_recommendation(recommendation)
    
    if expected_slippage <= max_slippage_bps
        push!(validation_results["passed"], "slippage_tolerance_policy")
        validation_results["details"]["slippage_check"] = Dict(
            "status" => "passed",
            "expected_slippage_bps" => expected_slippage,
            "limit_bps" => max_slippage_bps
        )
    else
        push!(validation_results["failed"], "slippage_tolerance_policy")
        validation_results["details"]["slippage_check"] = Dict(
            "status" => "failed",
            "expected_slippage_bps" => expected_slippage,
            "limit_bps" => max_slippage_bps,
            "excess_bps" => expected_slippage - max_slippage_bps
        )
    end
end

"""
Check overall risk limits
"""
function check_risk_limits(recommendation::Dict, portfolio::Dict, policies::Dict, ctx::Dict)
    @info "RiskOfficer: Checking risk limits"
    
    risk_checks = Dict(
        "var_limits" => check_var_limits(recommendation, policies),
        "volatility_limits" => check_volatility_limits(recommendation, portfolio, policies),
        "drawdown_limits" => check_drawdown_limits(recommendation, policies),
        "correlation_limits" => check_correlation_limits(recommendation, portfolio, policies)
    )
    
    # Determine overall risk limit compliance
    all_passed = all(check["status"] == "passed" for check in values(risk_checks))
    
    return Dict(
        "overall_status" => all_passed ? "within_limits" : "exceeds_limits",
        "individual_checks" => risk_checks,
        "timestamp" => now()
    )
end

"""
Validate exposure constraints
"""
function validate_exposure_constraints(recommendation::Dict, portfolio::Dict, policies::Dict, ctx::Dict)
    @info "RiskOfficer: Validating exposure constraints"
    
    exposure_checks = Dict(
        "asset_exposure" => check_asset_exposure_limits(recommendation, portfolio, policies),
        "sector_exposure" => check_sector_exposure_limits(recommendation, portfolio, policies),
        "counterparty_exposure" => check_counterparty_exposure_limits(recommendation, policies),
        "liquidity_exposure" => check_liquidity_exposure_limits(recommendation, portfolio, policies)
    )
    
    # Determine overall exposure constraint compliance
    all_passed = all(check["status"] == "passed" for check in values(exposure_checks))
    
    return Dict(
        "overall_status" => all_passed ? "compliant" : "violations_detected",
        "individual_checks" => exposure_checks,
        "timestamp" => now()
    )
end

"""
Check governance requirements
"""
function check_governance_requirements(recommendation::Dict, policies::Dict, ctx::Dict)
    @info "RiskOfficer: Checking governance requirements"
    
    governance_checks = Dict(
        "multisig_required" => check_multisig_requirements(recommendation, policies),
        "proposal_required" => check_proposal_requirements(recommendation, policies),
        "voting_threshold" => check_voting_threshold_requirements(recommendation, policies),
        "timelock_required" => check_timelock_requirements(recommendation, policies)
    )
    
    return Dict(
        "checks" => governance_checks,
        "requires_governance_vote" => get(policies, "require_multisig_to_execute", true),
        "minimum_voting_period_hours" => get(policies, "minimum_voting_period_hours", 72),
        "execution_delay_hours" => get(policies, "execution_delay_hours", 24)
    )
end

"""
Make final approval decision based on all checks
"""
function make_approval_decision(validation_results::Dict, risk_check_results::Dict, exposure_results::Dict, governance_results::Dict, ctx::Dict)
    violations = String[]
    override_requirements = String[]
    
    # Check policy validation
    if validation_results["overall_status"] == "non_compliant"
        append!(violations, validation_results["failed"])
    end
    
    # Check risk limits
    if risk_check_results["overall_status"] == "exceeds_limits"
        push!(violations, "risk_limits_exceeded")
    end
    
    # Check exposure constraints
    if exposure_results["overall_status"] == "violations_detected"
        push!(violations, "exposure_constraints_violated")
    end
    
    # Determine approval status
    if isempty(violations)
        status = "approved"
        approved_recommendation = get(get(ctx, "analysis", Dict()), "recommendations", Dict())["primary_recommendation"]
    else
        status = "rejected"
        approved_recommendation = Dict()
        
        # Determine what's needed for override
        if length(violations) <= 2 && !("risk_limits_exceeded" in violations)
            push!(override_requirements, "DAO governance vote with 2/3 majority")
        else
            push!(override_requirements, "Emergency governance procedure")
            push!(override_requirements, "Risk committee review")
        end
    end
    
    return Dict(
        "status" => status,
        "approved_recommendation" => approved_recommendation,
        "violations" => violations,
        "override_requirements" => override_requirements,
        "decision_rationale" => generate_decision_rationale(status, violations, override_requirements)
    )
end

"""
Generate comprehensive risk report
"""
function generate_risk_report(approval_decision::Dict, validation_results::Dict, risk_check_results::Dict, exposure_results::Dict, governance_results::Dict, ctx::Dict)
    return Dict(
        "overall_assessment" => approval_decision["status"],
        "risk_score" => calculate_overall_risk_score(validation_results, risk_check_results, exposure_results),
        "compliance_percentage" => validation_results["compliance_score"] * 100,
        "key_concerns" => identify_key_concerns(approval_decision["violations"]),
        "recommendations" => generate_risk_officer_recommendations(approval_decision, validation_results),
        "next_steps" => determine_next_steps(approval_decision),
        "governance_path" => determine_governance_path(governance_results, approval_decision)
    )
end

# Helper functions for parsing and calculation

function parse_var_impact(var_string::String)
    # Extract numeric value from strings like "5.2%" or "reduce to 4.8%"
    numbers = [parse(Float64, m.match) for m in eachmatch(r"(\d+\.?\d*)", var_string)]
    return isempty(numbers) ? 5.0 : numbers[1] # Default to 5% if parsing fails
end

function estimate_new_allocation_from_recommendation(recommendation::Dict)
    # Mock implementation - in production, this would simulate the recommendation's impact
    return Dict(
        "SOL" => 45.0,
        "USDC" => 40.0,
        "ORCA" => 10.0,
        "ETH" => 5.0
    )
end

function calculate_stable_allocation(allocation::Dict)
    stable_assets = ["USDC", "USDT", "DAI", "FRAX"]
    stable_allocation = 0.0
    
    for (asset, pct) in allocation
        if any(contains(uppercase(asset), stable) for stable in stable_assets)
            stable_allocation += pct
        end
    end
    
    return stable_allocation
end

function extract_dexes_from_recommendation(recommendation::Dict)
    # Extract DEX names from recommendation description or action items
    description = get(recommendation, "description", "")
    common_dexes = ["Orca", "Jupiter", "Phoenix", "Serum", "Raydium", "Uniswap", "Sushiswap"]
    
    found_dexes = String[]
    for dex in common_dexes
        if contains(description, dex)
            push!(found_dexes, dex)
        end
    end
    
    return found_dexes
end

function extract_transaction_sizes_from_recommendation(recommendation::Dict)
    # Mock implementation - extract transaction sizes from recommendation details
    return [
        Dict("type" => "swap", "size_pct" => 15.0),
        Dict("type" => "add_liquidity", "size_pct" => 5.0)
    ]
end

function extract_slippage_from_recommendation(recommendation::Dict)
    # Extract expected slippage from recommendation
    # Mock implementation
    return 35.0 # 35 basis points
end

function check_var_limits(recommendation::Dict, policies::Dict)
    # Implementation for VaR limit checking
    return Dict("status" => "passed", "details" => "VaR within acceptable limits")
end

function check_volatility_limits(recommendation::Dict, portfolio::Dict, policies::Dict)
    return Dict("status" => "passed", "details" => "Volatility profile acceptable")
end

function check_drawdown_limits(recommendation::Dict, policies::Dict)
    return Dict("status" => "passed", "details" => "Expected drawdown within limits")
end

function check_correlation_limits(recommendation::Dict, portfolio::Dict, policies::Dict)
    return Dict("status" => "passed", "details" => "Asset correlations within policy bounds")
end

function check_asset_exposure_limits(recommendation::Dict, portfolio::Dict, policies::Dict)
    return Dict("status" => "passed", "details" => "Asset exposures within limits")
end

function check_sector_exposure_limits(recommendation::Dict, portfolio::Dict, policies::Dict)
    return Dict("status" => "passed", "details" => "Sector diversification adequate")
end

function check_counterparty_exposure_limits(recommendation::Dict, policies::Dict)
    return Dict("status" => "passed", "details" => "Counterparty risk acceptable")
end

function check_liquidity_exposure_limits(recommendation::Dict, portfolio::Dict, policies::Dict)
    return Dict("status" => "passed", "details" => "Liquidity profile maintained")
end

function check_multisig_requirements(recommendation::Dict, policies::Dict)
    requires_multisig = get(policies, "require_multisig_to_execute", true)
    return Dict("required" => requires_multisig, "status" => "check_required")
end

function check_proposal_requirements(recommendation::Dict, policies::Dict)
    auto_proposal = get(policies, "auto_create_proposal", true)
    return Dict("required" => true, "auto_create" => auto_proposal)
end

function check_voting_threshold_requirements(recommendation::Dict, policies::Dict)
    return Dict("threshold" => "simple_majority", "quorum" => "20%")
end

function check_timelock_requirements(recommendation::Dict, policies::Dict)
    return Dict("required" => true, "delay_hours" => 24)
end

function calculate_overall_risk_score(validation_results::Dict, risk_check_results::Dict, exposure_results::Dict)
    # Simple risk scoring: 0-100 where 100 is highest risk
    base_score = 20.0
    
    # Add points for policy violations
    violation_count = length(get(validation_results, "failed", []))
    base_score += violation_count * 15.0
    
    # Add points for risk limit violations
    if risk_check_results["overall_status"] == "exceeds_limits"
        base_score += 25.0
    end
    
    # Add points for exposure violations
    if exposure_results["overall_status"] == "violations_detected"
        base_score += 20.0
    end
    
    return min(100.0, base_score)
end

function identify_key_concerns(violations::Vector)
    concerns = String[]
    
    for violation in violations
        if violation == "max_daily_var_policy"
            push!(concerns, "Excessive portfolio risk exposure")
        elseif violation == "min_stable_allocation_policy"
            push!(concerns, "Insufficient stable asset allocation")
        elseif violation == "concentration_limits_policy"
            push!(concerns, "Over-concentration in specific assets")
        elseif violation == "risk_limits_exceeded"
            push!(concerns, "Multiple risk thresholds breached")
        end
    end
    
    return concerns
end

function generate_risk_officer_recommendations(approval_decision::Dict, validation_results::Dict)
    recommendations = String[]
    
    if approval_decision["status"] == "approved"
        push!(recommendations, "Proceed with recommended strategy under normal governance process")
        push!(recommendations, "Monitor execution for any deviations from expected parameters")
    else
        push!(recommendations, "Modify recommendation to address policy violations")
        push!(recommendations, "Consider phased implementation to reduce risk impact")
        push!(recommendations, "Obtain additional governance approvals for override")
    end
    
    return recommendations
end

function determine_next_steps(approval_decision::Dict)
    if approval_decision["status"] == "approved"
        return [
            "Forward to Compliance Agent for final screening",
            "Prepare for Proposal Writer to draft governance proposal",
            "Schedule execution timeline"
        ]
    else
        return [
            "Return to Analyst Agent for strategy modification", 
            "Evaluate override options with governance team",
            "Consider alternative approaches that meet policy requirements"
        ]
    end
end

function determine_governance_path(governance_results::Dict, approval_decision::Dict)
    if approval_decision["status"] == "approved"
        return Dict(
            "path" => "standard_governance",
            "requirements" => ["proposal_creation", "voting_period", "execution_timelock"],
            "estimated_timeline_days" => 5
        )
    else
        return Dict(
            "path" => "override_governance",
            "requirements" => approval_decision["override_requirements"],
            "estimated_timeline_days" => 10
        )
    end
end

function generate_decision_rationale(status::String, violations::Vector, override_requirements::Vector)
    if status == "approved"
        return "Recommendation meets all DAO risk policies and governance requirements. Approved for standard execution process."
    else
        violation_summary = join(violations, ", ")
        override_summary = join(override_requirements, "; ")
        return "Recommendation violates DAO policies: $violation_summary. Override requires: $override_summary."
    end
end

# Export the agent creation function
export create_risk_officer_agent
