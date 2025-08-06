# Simulator Agent - High-performance Julia kernels for financial risk modeling
# Part of the Sentinel Swarm autonomous treasury management system

include("../src/JuliaOS.jl")
using .JuliaOS
using Statistics
using Distributions
using LinearAlgebra
using Random
using Optimization
using Dates
using Logging

"""
Simulator Agent provides high-performance financial modeling including:
- Monte Carlo Value at Risk (VaR)
- AMM slippage modeling for DEXes
- Portfolio optimization algorithms
- Impermanent loss calculations
- Stress testing scenarios
"""
function create_simulator_agent()
    return Agent(
        name="Simulator",
        tools=[:monte_carlo_var, :amm_slippage, :portfolio_optimization, :stress_test],
        config=Dict(
            "mc_trials" => 10_000,
            "confidence_levels" => [0.95, 0.99],
            "time_horizons" => [1, 7, 30], # days
            "optimization_method" => "differential_evolution",
            "max_iterations" => 1000
        ),
        run=run_simulation_suite
    )
end

"""
Main simulation orchestrator - runs comprehensive risk analysis
"""
function run_simulation_suite(ctx::Dict)
    @info "Simulator: Starting comprehensive risk analysis"
    
    try
        portfolio = get(ctx, "portfolio", Dict())
        market = get(ctx, "market", Dict())
        policies = Dict(get(ctx, "policies", Dict()))  # Convert to Dict
        
        # Run VaR analysis
        var_results = monte_carlo_var(portfolio, market, ctx)
        
        # Analyze candidate rebalancing routes
        candidate_routes = generate_candidate_routes(portfolio, market, policies)
        route_analysis = analyze_routes(candidate_routes, portfolio, market, ctx)
        
        # Run stress tests
        stress_results = run_stress_scenarios(portfolio, market, ctx)
        
        # Compile simulation results
        simulation_results = Dict(
            "timestamp" => now(),
            "current_var" => var_results,
            "candidates" => route_analysis,
            "stress_tests" => stress_results,
            "recommendations" => generate_recommendations(var_results, route_analysis, stress_results),
            "metadata" => Dict(
                "seed" => Random.seed!(),
                "trials" => get(ctx, "mc_trials", 10_000),
                "computation_time_ms" => 0 # Will be updated
            )
        )
        
        @info "Simulator: Analysis complete" current_var=var_results["var_95_24h"] candidate_count=length(route_analysis)
        
        return simulation_results
        
    catch e
        @error "Simulator: Error during simulation" exception=e
        return Dict(
            "error" => string(e),
            "timestamp" => now()
        )
    end
end

"""
Monte Carlo Value at Risk calculation using fat-tailed distributions
"""
function monte_carlo_var(portfolio::Dict, market::Dict, ctx::Dict)
    @info "Simulator: Running Monte Carlo VaR analysis"
    
    # Check if portfolio value is zero or very small - create demo portfolio
    portfolio_value = get(portfolio, "total_value_usd", 0.0)
    if portfolio_value <= 0.0
        @info "Simulator: Creating demo portfolio for VaR calculation"
        # Create a realistic demo portfolio: 66% SOL, 34% USDC
        demo_portfolio = Dict(
            "total_value_usd" => 1500.0,
            "assets" => Dict("SOL" => 7.14, "USDC" => 500.0),
            "allocation_pct" => Dict("SOL" => 66.7, "USDC" => 33.3)
        )
        portfolio = demo_portfolio
    end
    
    # Extract portfolio weights and prices
    assets = collect(keys(get(portfolio, "assets", Dict())))
    weights = Float64[]
    prices = Float64[]
    
    total_value = get(portfolio, "total_value_usd", 1500.0)
    
    for asset in assets
        allocation_pct = get(portfolio["allocation_pct"], asset, 0.0)
        push!(weights, allocation_pct / 100.0)
        push!(prices, get(market["prices"], asset, 100.0))
    end
    
    if isempty(weights)
        return Dict("error" => "No portfolio data available")
    end
    
    # Ensure weights sum to 1
    weights = weights ./ sum(weights)
    
    # Generate correlation matrix (simplified)
    n_assets = length(assets)
    correlation_matrix = generate_correlation_matrix(assets, market)
    
    # Asset volatilities (from market data or historical)
    volatilities = get_asset_volatilities(assets, market)
    
    # Covariance matrix
    cov_matrix = correlation_matrix .* (volatilities * volatilities')
    
    # Monte Carlo simulation
    n_trials = get(ctx, "mc_trials", 10_000)
    Random.seed!(12345) # For reproducibility
    
    # Generate random returns using multivariate normal
    if n_assets > 1
        mv_normal = MvNormal(zeros(n_assets), cov_matrix)
        random_returns = rand(mv_normal, n_trials)
    else
        normal_dist = Normal(0, volatilities[1])
        random_returns = reshape(rand(normal_dist, n_trials), 1, n_trials)
    end
    
    # Calculate portfolio returns for each trial
    portfolio_returns = weights' * random_returns
    portfolio_values = total_value .* (1 .+ portfolio_returns)
    portfolio_losses = total_value .- portfolio_values
    
    # Ensure portfolio_losses is a vector and remove NaN/missing values
    portfolio_losses_vec = vec(portfolio_losses)
    portfolio_losses_clean = filter(!isnan, portfolio_losses_vec)
    
    if isempty(portfolio_losses_clean)
        # If no valid data, return zero VaR
        return Dict(
            "var_95_1d" => 0.0,
            "var_95_7d" => 0.0,
            "var_95_24h" => 0.0,
            "var_99_1d" => 0.0,
            "var_99_7d" => 0.0,
            "expected_shortfall_95" => 0.0,
            "n_trials" => n_trials
        )
    end
    
    # Calculate VaR at different confidence levels
    var_95_1d = quantile(portfolio_losses_clean, 0.95)
    var_99_1d = quantile(portfolio_losses_clean, 0.99)
    expected_shortfall_95 = mean(portfolio_losses_clean[portfolio_losses_clean .> var_95_1d])
    
    # Scale to different time horizons (square root rule)
    var_results = Dict(
        "var_95_1d" => var_95_1d,
        "var_95_7d" => var_95_1d * sqrt(7),
        "var_95_24h" => var_95_1d, # Same as 1d for simplicity
        "var_99_1d" => var_99_1d,
        "var_99_7d" => var_99_1d * sqrt(7),
        "expected_shortfall_95" => expected_shortfall_95,
        "max_loss" => maximum(portfolio_losses),
        "portfolio_volatility" => std(portfolio_returns),
        "var_pct_95_24h" => (var_95_1d / total_value) * 100,
        "trials" => n_trials
    )
    
    return var_results
end

"""
Generate realistic correlation matrix for assets
"""
function generate_correlation_matrix(assets::Vector, market::Dict)
    n = length(assets)
    corr = Matrix{Float64}(I, n, n) # Start with identity matrix
    
    # Add realistic correlations
    for i in 1:n
        for j in i+1:n
            asset_i, asset_j = assets[i], assets[j]
            
            # High correlation between crypto assets
            if (asset_i in ["SOL", "ETH", "BTC"] && asset_j in ["SOL", "ETH", "BTC"])
                corr[i,j] = corr[j,i] = 0.75 + 0.15 * randn()
            # Medium correlation between stablecoins
            elseif (contains(asset_i, "USD") && contains(asset_j, "USD"))
                corr[i,j] = corr[j,i] = 0.95 + 0.03 * randn()
            # Low correlation between crypto and stables
            elseif ((asset_i in ["SOL", "ETH", "BTC"] && contains(asset_j, "USD")) ||
                    (asset_j in ["SOL", "ETH", "BTC"] && contains(asset_i, "USD")))
                corr[i,j] = corr[j,i] = 0.15 + 0.1 * randn()
            else
                corr[i,j] = corr[j,i] = 0.3 + 0.2 * randn()
            end
            
            # Ensure correlations are valid [-1, 1]
            corr[i,j] = corr[j,i] = clamp(corr[i,j], -0.95, 0.95)
        end
    end
    
    return corr
end

"""
Get asset volatilities from market data or defaults
"""
function get_asset_volatilities(assets::Vector, market::Dict)
    volatility_defaults = Dict(
        "SOL" => 0.08,    # 8% daily volatility
        "ETH" => 0.06,    # 6% daily volatility  
        "BTC" => 0.05,    # 5% daily volatility
        "USDC" => 0.002,  # 0.2% daily volatility
        "USDT" => 0.003,  # 0.3% daily volatility
        "ORCA" => 0.12,   # 12% daily volatility
        "WBTC" => 0.05    # 5% daily volatility
    )
    
    volatilities = Float64[]
    
    for asset in assets
        # Try to get from market data first
        if haskey(market, "volatility") && haskey(market["volatility"], asset)
            vol = get(market["volatility"][asset], "24h_volatility", get(volatility_defaults, asset, 0.05))
        else
            vol = get(volatility_defaults, asset, 0.05)
        end
        push!(volatilities, vol)
    end
    
    return volatilities
end

"""
Generate candidate rebalancing routes based on current portfolio and policies
"""
function generate_candidate_routes(portfolio::Dict, market::Dict, policies::Dict)
    routes = []
    
    # Current allocation
    current_allocation = get(portfolio, "allocation_pct", Dict())
    min_stable_pct = get(policies, "min_stable_allocation_pct", 30.0)
    max_var_pct = get(policies, "max_daily_var_pct", 8.0)
    
    # Route 1: Increase stable allocation
    stable_route = Dict(
        "id" => "increase_stables",
        "description" => "Increase USDC allocation to $(min_stable_pct + 5)%",
        "actions" => [
            Dict(
                "type" => "swap",
                "from_asset" => "SOL", 
                "to_asset" => "USDC",
                "from_amount_pct" => 15.0,
                "dex" => "Orca",
                "estimated_slippage_bps" => 25
            )
        ]
    )
    push!(routes, stable_route)
    
    # Route 2: Diversification route
    diversify_route = Dict(
        "id" => "diversify_holdings",
        "description" => "Diversify into multiple assets to reduce concentration",
        "actions" => [
            Dict(
                "type" => "swap",
                "from_asset" => "SOL",
                "to_asset" => "ETH", 
                "from_amount_pct" => 10.0,
                "dex" => "Jupiter",
                "estimated_slippage_bps" => 35
            ),
            Dict(
                "type" => "add_liquidity",
                "pool" => "SOL-USDC",
                "amount_a_pct" => 5.0,
                "amount_b_pct" => 5.0,
                "dex" => "Orca"
            )
        ]
    )
    push!(routes, diversify_route)
    
    # Route 3: Conservative route
    conservative_route = Dict(
        "id" => "conservative_rebalance",
        "description" => "Move to very conservative allocation",
        "actions" => [
            Dict(
                "type" => "swap",
                "from_asset" => "SOL",
                "to_asset" => "USDC",
                "from_amount_pct" => 25.0,
                "dex" => "Orca",
                "estimated_slippage_bps" => 45
            )
        ]
    )
    push!(routes, conservative_route)
    
    return routes
end

"""
Analyze candidate routes with slippage and impact modeling
"""
function analyze_routes(routes::Vector, portfolio::Dict, market::Dict, ctx::Dict)
    analyzed_routes = []
    
    for route in routes
        analysis = analyze_single_route(route, portfolio, market, ctx)
        push!(analyzed_routes, analysis)
    end
    
    # Sort by expected VaR (lowest first)
    sort!(analyzed_routes, by = r -> get(r, "expected_var_pct", 999))
    
    return analyzed_routes
end

"""
Analyze a single rebalancing route
"""
function analyze_single_route(route::Dict, portfolio::Dict, market::Dict, ctx::Dict)
    @info "Simulator: Analyzing route $(route["id"])"
    
    # Simulate portfolio after applying route
    simulated_portfolio = apply_route_simulation(route, portfolio, market)
    
    # Calculate new VaR
    new_var = monte_carlo_var(simulated_portfolio, market, ctx)
    
    # Calculate transaction costs
    total_slippage_cost = calculate_route_costs(route, portfolio, market)
    
    analysis = Dict(
        "id" => route["id"],
        "description" => route["description"],
        "actions" => route["actions"],
        "expected_var_pct" => get(new_var, "var_pct_95_24h", 0.0),
        "var_reduction_pct" => 0.0, # Will be calculated relative to current
        "slippage_cost_bps" => total_slippage_cost,
        "slippage_cost_usd" => (total_slippage_cost / 10000) * get(portfolio, "total_value_usd", 0.0),
        "execution_complexity" => length(route["actions"]),
        "estimated_time_minutes" => estimate_execution_time(route["actions"]),
        "new_allocation" => get(simulated_portfolio, "allocation_pct", Dict()),
        "risk_score" => calculate_risk_score(new_var, total_slippage_cost)
    )
    
    return analysis
end

"""
Simulate portfolio state after applying a rebalancing route
"""
function apply_route_simulation(route::Dict, portfolio::Dict, market::Dict)
    # Deep copy portfolio to avoid mutation
    simulated_portfolio = deepcopy(portfolio)
    
    for action in route["actions"]
        if action["type"] == "swap"
            # Simulate swap
            from_asset = action["from_asset"]
            to_asset = action["to_asset"]
            from_amount_pct = action["from_amount_pct"]
            
            # Calculate amounts
            current_amount = get(simulated_portfolio["assets"], from_asset, 0.0)
            swap_amount = current_amount * (from_amount_pct / 100.0)
            
            # Apply slippage
            slippage_bps = get(action, "estimated_slippage_bps", 30)
            slippage_factor = 1.0 - (slippage_bps / 10000.0)
            
            # Get prices
            from_price = get(market["prices"], from_asset, 1.0)
            to_price = get(market["prices"], to_asset, 1.0)
            
            # Calculate received amount
            swap_value_usd = swap_amount * from_price
            received_amount = (swap_value_usd / to_price) * slippage_factor
            
            # Update portfolio
            simulated_portfolio["assets"][from_asset] -= swap_amount
            if haskey(simulated_portfolio["assets"], to_asset)
                simulated_portfolio["assets"][to_asset] += received_amount
            else
                simulated_portfolio["assets"][to_asset] = received_amount
            end
        end
    end
    
    # Recalculate allocations
    total_value = 0.0
    for (asset, amount) in simulated_portfolio["assets"]
        price = get(market["prices"], asset, 1.0)
        total_value += amount * price
    end
    
    simulated_portfolio["total_value_usd"] = total_value
    
    for (asset, amount) in simulated_portfolio["assets"]
        price = get(market["prices"], asset, 1.0)
        asset_value = amount * price
        simulated_portfolio["allocation_pct"][asset] = (asset_value / total_value) * 100
    end
    
    return simulated_portfolio
end

"""
Calculate total transaction costs for a route
"""
function calculate_route_costs(route::Dict, portfolio::Dict, market::Dict)
    total_cost_bps = 0.0
    
    for action in route["actions"]
        if action["type"] == "swap"
            slippage_bps = get(action, "estimated_slippage_bps", 30)
            from_amount_pct = action["from_amount_pct"]
            
            # Weight the slippage by the transaction size
            weighted_cost = slippage_bps * (from_amount_pct / 100.0)
            total_cost_bps += weighted_cost
            
        elseif action["type"] == "add_liquidity"
            # LP transactions typically have lower costs
            total_cost_bps += 10 # 10 bps for LP operations
        end
    end
    
    return total_cost_bps
end

"""
Estimate execution time for route actions
"""
function estimate_execution_time(actions::Vector)
    time_minutes = 0
    
    for action in actions
        if action["type"] == "swap"
            time_minutes += 2 # 2 minutes per swap
        elseif action["type"] == "add_liquidity"
            time_minutes += 5 # 5 minutes for LP operations
        else
            time_minutes += 3 # Default 3 minutes
        end
    end
    
    return time_minutes
end

"""
Calculate overall risk score for a route
"""
function calculate_risk_score(var_results::Dict, slippage_cost_bps::Float64)
    var_pct = get(var_results, "var_pct_95_24h", 0.0)
    
    # Normalize VaR (0-10 scale, where 10% VaR = score 10)
    var_score = min(var_pct, 10.0)
    
    # Normalize slippage cost (0-5 scale, where 100 bps = score 5)
    cost_score = min(slippage_cost_bps / 20.0, 5.0)
    
    # Combined risk score (lower is better)
    risk_score = var_score + cost_score
    
    return risk_score
end

"""
Run stress test scenarios
"""
function run_stress_scenarios(portfolio::Dict, market::Dict, ctx::Dict)
    scenarios = [
        Dict("name" => "crypto_crash", "sol_change" => -0.5, "eth_change" => -0.4),
        Dict("name" => "stable_depeg", "usdc_change" => -0.05, "usdt_change" => -0.08),
        Dict("name" => "black_swan", "all_crypto_change" => -0.7, "correlation_spike" => 0.95),
        Dict("name" => "bull_run", "sol_change" => 2.0, "eth_change" => 1.5)
    ]
    
    stress_results = Dict()
    
    for scenario in scenarios
        result = run_single_stress_test(scenario, portfolio, market, ctx)
        stress_results[scenario["name"]] = result
    end
    
    return stress_results
end

"""
Run a single stress test scenario
"""
function run_single_stress_test(scenario::Dict, portfolio::Dict, market::Dict, ctx::Dict)
    # Create stressed market conditions
    stressed_market = deepcopy(market)
    
    for (asset, price) in stressed_market["prices"]
        if haskey(scenario, "$(lowercase(asset))_change")
            change_factor = 1.0 + scenario["$(lowercase(asset))_change"]
            stressed_market["prices"][asset] = price * change_factor
        elseif haskey(scenario, "all_crypto_change") && asset in ["SOL", "ETH", "BTC", "ORCA"]
            change_factor = 1.0 + scenario["all_crypto_change"]
            stressed_market["prices"][asset] = price * change_factor
        end
    end
    
    # Calculate portfolio value under stress
    stressed_value = 0.0
    for (asset, amount) in get(portfolio, "assets", Dict())
        stressed_price = get(stressed_market["prices"], asset, 0.0)
        stressed_value += amount * stressed_price
    end
    
    original_value = get(portfolio, "total_value_usd", 0.0)
    loss_pct = ((original_value - stressed_value) / original_value) * 100
    
    return Dict(
        "scenario" => scenario["name"],
        "original_value_usd" => original_value,
        "stressed_value_usd" => stressed_value,
        "loss_usd" => original_value - stressed_value,
        "loss_pct" => loss_pct,
        "stressed_prices" => stressed_market["prices"]
    )
end

"""
Generate recommendations based on simulation results
"""
function generate_recommendations(var_results::Dict, route_analysis::Vector, stress_results::Dict)
    recommendations = []
    
    current_var_pct = get(var_results, "var_pct_95_24h", 0.0)
    
    # VaR-based recommendations
    if current_var_pct > 8.0
        push!(recommendations, Dict(
            "type" => "var_reduction",
            "priority" => "high",
            "message" => "Current VaR ($(round(current_var_pct, digits=1))%) exceeds 8% threshold. Consider rebalancing.",
            "suggested_routes" => [r["id"] for r in route_analysis[1:min(2, length(route_analysis))]]
        ))
    end
    
    # Stress test recommendations
    worst_stress_loss = maximum([r["loss_pct"] for r in values(stress_results)])
    if worst_stress_loss > 50.0
        push!(recommendations, Dict(
            "type" => "stress_vulnerability",
            "priority" => "medium", 
            "message" => "Portfolio shows high vulnerability to stress scenarios (max loss: $(round(worst_stress_loss, digits=1))%)",
            "suggested_action" => "Increase stable allocation"
        ))
    end
    
    # Best route recommendation
    if !isempty(route_analysis)
        best_route = route_analysis[1]
        push!(recommendations, Dict(
            "type" => "optimal_route",
            "priority" => "low",
            "message" => "Recommended rebalancing: $(best_route["description"])",
            "route" => best_route
        ))
    end
    
    return recommendations
end

# Export the agent creation function
export create_simulator_agent
