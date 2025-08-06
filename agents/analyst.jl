# Analyst Agent - LLM-powered analysis and recommendation generation
# Part of the Sentinel Swarm autonomous treasury management system

include("../src/JuliaOS.jl")
include("../config/config.jl")
using .JuliaOS
using .Config
using JSON3
using Dates
using Logging

"""
Analyst Agent uses LLM capabilities to:
- Analyze simulation results and market conditions
- Generate human-readable explanations
- Provide strategic recommendations with pros/cons
- Create narrative summaries for governance proposals
"""
function create_analyst_agent()
    return Agent(
        name="Analyst",
        tools=[:llm_analysis, :risk_explanation, :strategic_planning, :narrative_generation],
        config=Dict(
            "llm_model" => "gpt-3.5-turbo",
            "temperature" => 0.7,
            "max_tokens" => 2000,
            "analysis_depth" => "comprehensive",
            "risk_tolerance" => "moderate"
        ),
        run=analyze_portfolio_situation
    )
end

"""
Main analysis orchestrator - processes simulation data and generates insights
"""
function analyze_portfolio_situation(ctx::Dict)
    @info "Analyst: Starting comprehensive portfolio analysis"
    
    try
        # Extract context data
        portfolio = get(ctx, "portfolio", Dict())
        market = get(ctx, "market", Dict())
        sims = get(ctx, "simulation_results", Dict())
        policies = Dict(get(ctx, "policies", Dict()))  # Convert to Dict
        alerts = get(ctx, "alerts", [])
        
        # Check for demo force action
        force_demo = get(ctx, "force_demo_action", false)
        
        # Generate situation analysis
        situation_analysis = analyze_current_situation(portfolio, market, alerts, ctx)
        
        # Analyze simulation results
        simulation_insights = analyze_simulation_results(sims, ctx)
        
        # Generate strategic options
        strategic_options = generate_strategic_options(simulation_insights, policies, ctx)
        
        # Override with demo action if forced
        if force_demo
            strategic_options = Dict(
                "options" => [Dict(
                    "id" => "demo_action",
                    "name" => "increase_stables", 
                    "action" => "increase_stables",
                    "size_pct" => 0.20,
                    "rationale" => "Demo action: Increase stablecoin allocation",
                    "status" => "draft"
                )],
                "recommended_option" => "demo_action"
            )
        end
        
        # Create comprehensive recommendation
        @info "Analyst: Starting recommendations synthesis"
        recommendations = synthesize_recommendations(situation_analysis, simulation_insights, strategic_options, ctx)
        
        # Generate executive summary
        @info "Analyst: Generating executive summary"
        executive_summary = try
            generate_executive_summary(recommendations, ctx)
        catch e
            @warn "Executive summary generation failed, using fallback" exception=e
            Dict(
                "executive_summary" => "Strategic treasury management recommendation requiring review.",
                "key_points" => ["Strategic optimization", "Risk management", "Governance approval required"],
                "call_to_action" => "Review and vote on treasury proposal",
                "governance_impact" => "Standard governance review recommended"
            )
        end
        
        @info "Analyst: Creating analysis result"
        analysis_result = Dict(
            "status" => "success",
            "timestamp" => now(),
            "situation_analysis" => situation_analysis,
            "simulation_insights" => simulation_insights,
            "options" => strategic_options,
            "recommendations" => recommendations,
            "executive_summary" => executive_summary,
            "confidence_score" => calculate_confidence_score(sims, alerts),
            "urgency_level" => determine_urgency_level(alerts, sims)
        )
        
        @info "Analyst: Analysis complete" 
        @info "Recommendations generated: $(length(strategic_options)) options"
        @info "Urgency level: $(analysis_result["urgency_level"])"
        
        return analysis_result
        
    catch e
        @error "Analyst: Error during analysis" exception=e
        return Dict(
            "status" => "error",
            "error" => string(e),
            "timestamp" => now()
        )
    end
end

"""
Analyze current portfolio situation using LLM
"""
function analyze_current_situation(portfolio::Dict, market::Dict, alerts::Vector, ctx::Dict)
    # Prepare context for LLM
    portfolio_summary = summarize_portfolio(portfolio)
    market_summary = summarize_market_conditions(market)
    alerts_summary = summarize_alerts(alerts)
    
    prompt = """
    You are an expert DeFi portfolio analyst for a DAO treasury. Analyze the current situation and provide insights.

    PORTFOLIO OVERVIEW:
    $portfolio_summary

    MARKET CONDITIONS:
    $market_summary

    ACTIVE ALERTS:
    $alerts_summary

    Please provide a comprehensive situation analysis covering:
    1. Current portfolio health and risk profile
    2. Key market factors affecting the portfolio
    3. Critical issues that require attention
    4. Overall portfolio stability assessment

    Format your response as a structured analysis with clear sections.
    """
    
    # Check for API key
    cfg = Config.cfg()
    if cfg.openai_key === nothing || isempty(cfg.openai_key)
        error("OPENAI_API_KEY not found in environment. Please set it in .env file")
    end
    
    llm_response = agent_useLLM(prompt=prompt, temperature=0.7, max_tokens=1500)
    
    return Dict(
        "llm_analysis" => get(llm_response, "content", "Analysis unavailable"),
        "portfolio_health" => assess_portfolio_health(portfolio, alerts),
        "market_assessment" => assess_market_conditions(market),
        "risk_factors" => identify_risk_factors(portfolio, market, alerts),
        "opportunities" => identify_opportunities(market, portfolio)
    )
end

"""
Analyze simulation results using LLM
"""
function analyze_simulation_results(sims::Dict, ctx::Dict)
    if isempty(sims)
        return Dict("error" => "No simulation data available")
    end
    
    # Extract key metrics from simulations
    current_var = get(sims, "current_var", Dict())
    candidates = get(sims, "candidates", [])
    stress_tests = get(sims, "stress_tests", Dict())
    
    # Format simulation data for LLM
    var_summary = format_var_results(current_var)
    candidates_summary = format_candidates_summary(candidates)
    stress_summary = format_stress_results(stress_tests)
    
    prompt = """
    You are a quantitative risk analyst. Analyze these portfolio simulation results and provide insights.

    CURRENT RISK METRICS:
    $var_summary

    REBALANCING CANDIDATES:
    $candidates_summary

    STRESS TEST RESULTS:
    $stress_summary

    Please analyze these results and provide:
    1. Risk assessment of current portfolio
    2. Evaluation of rebalancing options
    3. Stress test vulnerability analysis
    4. Key quantitative insights and recommendations

    Focus on actionable insights backed by the numerical analysis.
    """
    
    llm_response = agent_useLLM(prompt=prompt, temperature=0.6, max_tokens=1500)
    
    return Dict(
        "llm_insights" => get(llm_response, "content", "Analysis unavailable"),
        "risk_metrics_analysis" => analyze_risk_metrics(current_var),
        "candidates_ranking" => rank_candidates(candidates),
        "stress_vulnerability" => analyze_stress_vulnerability(stress_tests),
        "quantitative_summary" => generate_quantitative_summary(sims)
    )
end

"""
Generate strategic options using LLM
"""
function generate_strategic_options(simulation_insights::Dict, policies::Dict, ctx::Dict)
    # Extract key information
    risk_assessment = get(simulation_insights, "risk_metrics_analysis", Dict())
    top_candidates = get(simulation_insights, "candidates_ranking", [])
    
    # Format policy constraints
    policy_summary = format_policy_constraints(policies)
    
    prompt = """
    You are a strategic advisor for DAO treasury management. Based on the risk analysis, generate strategic options.

    RISK ANALYSIS SUMMARY:
    $(get(simulation_insights, "llm_insights", "No analysis available"))

    TOP REBALANCING CANDIDATES:
    $(format_top_candidates(top_candidates))

    POLICY CONSTRAINTS:
    $policy_summary

    Generate 3 strategic options with the following for each:
    1. Option name and description
    2. Rationale and strategic reasoning
    3. Pros and cons
    4. Risk-reward assessment
    5. Implementation complexity
    6. Timeline and prerequisites

    Options should range from conservative to moderate approaches. Ensure all options comply with policy constraints.

    Format as JSON with this structure:
    {
        "options": [
            {
                "id": "option_1",
                "name": "Option Name",
                "description": "Brief description",
                "rationale": "Why this option makes sense",
                "pros": ["Pro 1", "Pro 2", "Pro 3"],
                "cons": ["Con 1", "Con 2", "Con 3"],
                "risk_level": "low/medium/high",
                "expected_var_impact": "percentage change",
                "implementation_complexity": "low/medium/high",
                "timeline_days": number,
                "compliance_status": "compliant/needs_review"
            }
        ],
        "recommended_option": "option_id"
    }
    """
    
    llm_response = agent_useLLM(prompt=prompt, temperature=0.8, max_tokens=2000)
    
    # Parse LLM response and add technical analysis
    try
        # Convert JSON3.Object to Dict if needed
        llm_response_dict = isa(llm_response, Dict) ? llm_response : Dict(pairs(llm_response))
        options_data = parse_options_response(llm_response_dict)
        
        # Enhance each option with technical details
        if haskey(options_data, "options") && isa(options_data["options"], Vector)
            for option in options_data["options"]
                enhance_option_with_technical_data(option, top_candidates, ctx)
            end
        end
        
        return options_data
    catch e
        @warn "Failed to parse LLM options response, using fallback" exception=e
        return generate_fallback_options(top_candidates, policies)
    end
end

"""
Enhance option with technical data
"""
function enhance_option_with_technical_data(option::Dict, candidates::Vector, ctx::Dict)
    # Add technical metrics if available
    option_name = get(option, "name", "")
    
    # Find matching candidate
    for candidate in candidates
        if contains(lowercase(get(candidate, "name", "")), lowercase(option_name))
            option["expected_var_pct"] = get(candidate, "expected_var_pct", 0.0)
            option["implementation_cost_bps"] = get(candidate, "implementation_cost_bps", 0.0)
            break
        end
    end
    
    return option
end

"""
Synthesize comprehensive recommendations
"""
function synthesize_recommendations(situation_analysis::Dict, simulation_insights::Dict, strategic_options::Dict, ctx::Dict)
    # Get the recommended option
    recommended_option_id = get(strategic_options, "recommended_option", "")
    recommended_option = nothing
    
    options_list = get(strategic_options, "options", [])
    for option in options_list
        if get(option, "id", "") == recommended_option_id
            recommended_option = option
            break
        end
    end
    
    if recommended_option === nothing && !isempty(options_list)
        recommended_option = options_list[1]
    end
    
    # Provide fallback if still nothing
    if recommended_option === nothing
        recommended_option = Dict(
            "id" => "fallback",
            "name" => "increase_stables",
            "description" => "Maintain Current Allocation",
            "action" => "increase_stables",
            "size_pct" => 0.20,
            "rationale" => "No specific action recommended at this time",
            "status" => "draft"
        )
    end
    
    # Ensure required fields are present
    if !haskey(recommended_option, "action")
        recommended_option["action"] = "increase_stables"
    end
    if !haskey(recommended_option, "size_pct") 
        recommended_option["size_pct"] = 0.20
    end
    if !haskey(recommended_option, "status")
        recommended_option["status"] = "draft"
    end
    
    # Generate final recommendation narrative
    recommendation_prompt = """
    Synthesize a final recommendation for DAO treasury management based on this analysis:

    SITUATION: $(get(situation_analysis, "llm_analysis", ""))
    
    RECOMMENDED STRATEGY: $(get(recommended_option, "name", "No option selected"))
    RATIONALE: $(get(recommended_option, "rationale", ""))

    Provide a concise executive recommendation that includes:
    1. Clear action items
    2. Expected outcomes
    3. Risk mitigation measures
    4. Success metrics
    5. Timeline for implementation

    Keep it focused and actionable for DAO governance.
    """
    
    llm_recommendation = agent_useLLM(prompt=recommendation_prompt, temperature=0.6, max_tokens=1000)
    
    return Dict(
        "primary_recommendation" => recommended_option,
        "alternative_options" => filter(opt -> haskey(opt, "id") && opt["id"] != recommended_option_id, get(strategic_options, "options", [])),
        "executive_recommendation" => get(llm_recommendation, "content", ""),
        "action_items" => extract_action_items(recommended_option),
        "success_metrics" => define_success_metrics(recommended_option),
        "risk_mitigation" => identify_risk_mitigation_measures(recommended_option),
        "implementation_plan" => create_implementation_plan(recommended_option)
    )
end

"""
Generate executive summary
"""
function generate_executive_summary(recommendations::Dict, ctx::Dict)
    primary_rec = get(recommendations, "primary_recommendation", Dict())
    
    summary_prompt = """
    Create a concise executive summary for DAO members about this treasury management recommendation:

    RECOMMENDED ACTION: $(get(primary_rec, "name", "No action"))
    RATIONALE: $(get(primary_rec, "rationale", ""))
    EXPECTED OUTCOME: $(get(primary_rec, "expected_var_impact", "Unknown"))

    The summary should be:
    - 2-3 paragraphs maximum
    - Non-technical language
    - Clear value proposition
    - Specific next steps

    This will be included in the governance proposal description.
    """
    
    # Wrap LLM call in try-catch to handle potential issues
    llm_summary = try
        agent_useLLM(prompt=summary_prompt, temperature=0.5, max_tokens=500)
    catch e
        @warn "Executive summary LLM call failed, using fallback" exception=e
        Dict("content" => "Strategic treasury optimization recommendation requiring DAO approval.")
    end
    
    return Dict(
        "executive_summary" => get(llm_summary, "content", ""),
        "key_points" => extract_key_points(primary_rec),
        "call_to_action" => generate_call_to_action(primary_rec),
        "governance_impact" => assess_governance_impact(primary_rec)
    )
end

# Helper functions for data formatting and analysis

function summarize_portfolio(portfolio::Dict)
    total_value = get(portfolio, "total_value_usd", 0)
    allocation = get(portfolio, "allocation_pct", Dict())
    
    # Ensure total_value is numeric
    total_value_num = isa(total_value, Number) ? total_value : 0.0
    
    summary = "Total Value: \$$(round(total_value_num, digits=0))\n"
    summary *= "Asset Allocation:\n"
    
    for (asset, pct) in sort(collect(allocation), by=x->x[2], rev=true)
        # Ensure pct is numeric
        pct_num = isa(pct, Number) ? pct : 0.0
        summary *= "- $asset: $(round(pct_num, digits=1))%\n"
    end
    
    return summary
end

function summarize_market_conditions(market::Dict)
    prices = get(market, "prices", Dict())
    volatility = get(market, "volatility", Dict())
    
    summary = "Current Prices:\n"
    for (asset, price) in prices
        # Skip non-numeric values (like timestamps)
        if !isa(price, Number)
            continue
        end
        
        vol_data = get(volatility, asset, Dict("24h_volatility" => 0.0))
        vol_pct = get(vol_data, "24h_volatility", 0.0) * 100
        summary *= "- $asset: \$$(round(price, digits=2)) (24h vol: $(round(vol_pct, digits=1))%)\n"
    end
    
    return summary
end

function summarize_alerts(alerts::Vector)
    if isempty(alerts)
        return "No active alerts"
    end
    
    summary = "Active Alerts ($(length(alerts))):\n"
    for alert in alerts
        alert_type = get(alert, "type", "unknown")
        severity = get(alert, "severity", "unknown")
        summary *= "- $(uppercase(alert_type)) ($(severity) severity)\n"
    end
    
    return summary
end

function format_var_results(var_results::Dict)
    var_24h = get(var_results, "var_pct_95_24h", 0.0)
    portfolio_vol = get(var_results, "portfolio_volatility", 0.0) * 100
    
    return """
    24-hour VaR (95%): $(round(var_24h, digits=2))%
    Portfolio Volatility: $(round(portfolio_vol, digits=2))%
    Monte Carlo Trials: $(get(var_results, "trials", 0))
    """
end

function format_candidates_summary(candidates::Vector)
    if isempty(candidates)
        return "No rebalancing candidates available"
    end
    
    summary = "Top Rebalancing Options:\n"
    for (i, candidate) in enumerate(candidates[1:min(3, length(candidates))])
        expected_var = get(candidate, "expected_var_pct", 0.0)
        slippage_bps = get(candidate, "slippage_cost_bps", 0.0)
        summary *= "$(i). $(candidate["description"]) - VaR: $(round(expected_var, digits=2))%, Cost: $(round(slippage_bps, digits=0)) bps\n"
    end
    
    return summary
end

function format_stress_results(stress_results::Dict)
    if isempty(stress_results)
        return "No stress test data available"
    end
    
    summary = "Stress Test Results:\n"
    for (scenario, result) in stress_results
        loss_pct = get(result, "loss_pct", 0.0)
        summary *= "- $(scenario): $(round(loss_pct, digits=1))% loss\n"
    end
    
    return summary
end

function assess_portfolio_health(portfolio::Dict, alerts::Vector)
    high_severity_alerts = count(alert -> get(alert, "severity", "") == "high", alerts)
    
    if high_severity_alerts > 0
        return "Poor - High severity alerts present"
    elseif length(alerts) > 2
        return "Fair - Multiple alerts require attention"
    elseif length(alerts) > 0
        return "Good - Minor issues to monitor"
    else
        return "Excellent - No active concerns"
    end
end

function assess_market_conditions(market::Dict)
    # Simplified market assessment based on volatility
    volatility = get(market, "volatility", Dict())
    avg_vol = 0.0
    count = 0
    
    for (asset, vol_data) in volatility
        if haskey(vol_data, "24h_volatility")
            avg_vol += vol_data["24h_volatility"]
            count += 1
        end
    end
    
    if count > 0
        avg_vol /= count
        if avg_vol > 0.1
            return "High volatility environment"
        elseif avg_vol > 0.06
            return "Moderate volatility environment"
        else
            return "Low volatility environment"
        end
    else
        return "Market conditions unclear"
    end
end

function identify_risk_factors(portfolio::Dict, market::Dict, alerts::Vector)
    risk_factors = String[]
    
    # Check concentration risk
    allocation = get(portfolio, "allocation_pct", Dict())
    for (asset, pct) in allocation
        if pct > 60 && !contains(asset, "USD")
            push!(risk_factors, "High concentration in $asset ($(round(pct, digits=1))%)")
        end
    end
    
    # Check alert-based risks
    for alert in alerts
        if alert["type"] == "depeg"
            push!(risk_factors, "Stablecoin depeg risk: $(alert["asset"])")
        elseif alert["type"] == "oracle_stale"
            push!(risk_factors, "Oracle reliability issues")
        end
    end
    
    return risk_factors
end

function identify_opportunities(market::Dict, portfolio::Dict)
    opportunities = String[]
    
    # Check for diversification opportunities
    allocation = get(portfolio, "allocation_pct", Dict())
    if length(allocation) < 3
        push!(opportunities, "Portfolio diversification across more assets")
    end
    
    # Check for yield opportunities
    push!(opportunities, "Liquidity provision for fee generation")
    push!(opportunities, "Staking rewards for non-productive assets")
    
    return opportunities
end

function parse_options_response(llm_response::Dict)
    content = get(llm_response, "content", "")
    
    # Try to extract JSON from the response
    try
        # Look for JSON content between markers or as complete response
        json_start = findfirst('{', content)
        json_end = findlast('}', content)
        
        if json_start !== nothing && json_end !== nothing
            json_content = content[json_start:json_end]
            parsed_response = JSON3.read(json_content, Dict)
            
            # Ensure all options have required fields
            if haskey(parsed_response, "options") && isa(parsed_response["options"], Vector)
                for option in parsed_response["options"]
                    if !haskey(option, "status")
                        option["status"] = "draft"
                    end
                    if !haskey(option, "id")
                        option["id"] = "llm_option_$(hash(get(option, "name", "")))"
                    end
                    if !haskey(option, "action")
                        option["action"] = "increase_stables"
                    end
                    if !haskey(option, "size_pct")
                        option["size_pct"] = 0.20
                    end
                end
            end
            
            return parsed_response
        end
    catch e
        @warn "Failed to parse JSON from LLM response" exception=e
    end
    
    # Fallback: parse the structured response manually
    return parse_structured_response(content)
end

function parse_structured_response(content::String)
    # Fallback parser for when JSON parsing fails
    options = []
    
    # This is a simplified parser - in production, you'd want more robust parsing
    lines = split(content, '\n')
    current_option = Dict()
    
    for line in lines
        line = strip(line)
        if contains(lowercase(line), "option") && contains(line, ":")
            if !isempty(current_option)
                push!(options, current_option)
            end
            current_option = Dict(
                "id" => "parsed_option_$(length(options) + 1)",
                "name" => line,
                "description" => "Parsed from LLM response",
                "risk_level" => "medium",
                "implementation_complexity" => "medium",
                "status" => "draft"
            )
        end
    end
    
    if !isempty(current_option)
        push!(options, current_option)
    end
    
    return Dict(
        "options" => options,
        "recommended_option" => isempty(options) ? "" : options[1]["id"]
    )
end

function generate_fallback_options(candidates::Vector, policies::Dict)
    options = []
    
    for (i, candidate) in enumerate(candidates[1:min(3, length(candidates))])
        option = Dict(
            "id" => "fallback_option_$i",
            "name" => get(candidate, "description", "Rebalancing Option $i"),
            "description" => get(candidate, "description", ""),
            "rationale" => "Based on simulation analysis",
            "risk_level" => determine_risk_level(candidate),
            "expected_var_impact" => "$(round(get(candidate, "expected_var_pct", 0.0), digits=1))%",
            "implementation_complexity" => determine_complexity(candidate),
            "pros" => ["Reduces portfolio risk", "Data-driven approach"],
            "cons" => ["Transaction costs", "Market timing risk"],
            "status" => "draft"
        )
        push!(options, option)
    end
    
    return Dict(
        "options" => options,
        "recommended_option" => isempty(options) ? "" : options[1]["id"]
    )
end

function determine_risk_level(candidate::Dict)
    var_pct = get(candidate, "expected_var_pct", 5.0)
    if var_pct < 4.0
        return "low"
    elseif var_pct < 7.0
        return "medium"
    else
        return "high"
    end
end

function determine_complexity(candidate::Dict)
    execution_complexity = get(candidate, "execution_complexity", 1)
    if execution_complexity == 1
        return "low"
    elseif execution_complexity <= 3
        return "medium"
    else
        return "high"
    end
end

function calculate_confidence_score(sims::Dict, alerts::Vector)
    # Simple confidence scoring based on data quality
    base_score = 0.8
    
    # Reduce confidence for high-severity alerts
    high_severity_count = count(alert -> get(alert, "severity", "") == "high", alerts)
    confidence = base_score - (high_severity_count * 0.1)
    
    # Adjust for simulation quality
    trials = get(get(sims, "current_var", Dict()), "trials", 0)
    if trials < 1000
        confidence -= 0.2
    end
    
    return max(0.1, min(1.0, confidence))
end

function determine_urgency_level(alerts::Vector, sims::Dict)
    high_severity_alerts = count(alert -> get(alert, "severity", "") == "high", alerts)
    current_var = get(get(sims, "current_var", Dict()), "var_pct_95_24h", 0.0)
    
    if high_severity_alerts > 0 || current_var > 10.0
        return "high"
    elseif length(alerts) > 1 || current_var > 7.0
        return "medium"
    else
        return "low"
    end
end

# Additional helper functions for recommendations processing
function extract_action_items(option::Dict)
    return [
        "Review and approve $(get(option, "name", "recommended strategy"))",
        "Execute rebalancing transactions as outlined",
        "Monitor portfolio performance post-implementation",
        "Report results to DAO governance"
    ]
end

function define_success_metrics(option::Dict)
    return [
        "VaR reduction to target levels",
        "Successful transaction execution within slippage tolerance", 
        "Improved portfolio risk profile",
        "Compliance with DAO risk policies"
    ]
end

function identify_risk_mitigation_measures(option::Dict)
    return [
        "Phased implementation to reduce market impact",
        "Monitoring of market conditions during execution",
        "Backup plans for adverse market movements",
        "Regular review and adjustment capabilities"
    ]
end

function create_implementation_plan(option::Dict)
    timeline = get(option, "timeline_days", 3)
    return Dict(
        "phase_1" => "Governance approval and preparation (Day 1)",
        "phase_2" => "Execute core transactions (Day 2)",
        "phase_3" => "Monitor and adjust as needed (Day $timeline)",
        "total_timeline_days" => timeline
    )
end

function extract_key_points(option::Dict)
    return [
        get(option, "name", "Strategic rebalancing"),
        "Expected VaR impact: $(get(option, "expected_var_impact", "Unknown"))",
        "Risk level: $(get(option, "risk_level", "Unknown"))",
        "Implementation: $(get(option, "implementation_complexity", "Unknown")) complexity"
    ]
end

function generate_call_to_action(option::Dict)
    return "Vote to approve $(get(option, "name", "this proposal")) to optimize treasury risk management and ensure sustainable operations."
end

function assess_governance_impact(option::Dict)
    complexity = get(option, "implementation_complexity", "medium")
    if complexity == "high"
        return "Requires detailed review and extended discussion period"
    elseif complexity == "medium"
        return "Standard governance review process recommended"
    else
        return "Can proceed with expedited review if needed"
    end
end

"""
Format policy constraints for LLM consumption
"""
function format_policy_constraints(policies::Dict)
    try
        risk_policies = get(policies, "risk_policies", Dict())
        var_constraints = get(risk_policies, "var_constraints", Dict())
        
        summary = "Key Policy Constraints:\n"
        summary *= "- Max Portfolio VaR (95%): $(get(var_constraints, "max_portfolio_var_95_pct", "N/A"))%\n"
        summary *= "- Max Asset Concentration: $(get(var_constraints, "max_asset_concentration_pct", "N/A"))%\n"
        summary *= "- Min Stablecoin Allocation: $(get(var_constraints, "min_stablecoin_pct", "N/A"))%\n"
        
        return summary
    catch e
        return "Policy constraints unavailable"
    end
end

"""
Format top candidates for LLM consumption
"""
function format_top_candidates(candidates::Vector)
    if isempty(candidates)
        return "No rebalancing candidates analyzed"
    end
    
    summary = ""
    for (i, candidate) in enumerate(candidates[1:min(3, length(candidates))])
        name = get(candidate, "name", "Unknown")
        expected_var = get(candidate, "expected_var_pct", 0.0)
        cost = get(candidate, "implementation_cost_bps", 0.0)
        summary *= "$(i). $name - Expected VaR: $(round(expected_var, digits=2))%, Cost: $(round(cost, digits=0)) bps\n"
    end
    
    return summary
end

# Export the agent creation function
export create_analyst_agent


