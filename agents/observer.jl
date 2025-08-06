# Observer Agent - Monitors portfolio balances, oracle prices, and market conditions
# Part of the Sentinel Swarm autonomous treasury management system

include("../src/JuliaOS.jl")
using .JuliaOS
using HTTP
using JSON3
using Dates
using Logging

"""
Observer Agent monitors on-chain and off-chain data sources for:
- Portfolio balances across multiple wallets
- Oracle prices and staleness
- DEX pool liquidity and health
- Governance queue updates
"""
function create_observer_agent()
    return Agent(
        name="Observer",
        tools=[:fetch_balances, :fetch_prices, :fetch_pools, :check_governance],
        config=Dict(
            "rpc_endpoints" => Dict(
                "solana" => "https://api.devnet.solana.com",
                "ethereum" => "https://eth-mainnet.alchemyapi.io/v2/demo"
            ),
            "oracle_sources" => ["pyth", "chainlink", "switchboard"],
            "monitoring_interval" => 30, # seconds
            "alert_thresholds" => Dict(
                "depeg_bps" => 50,
                "oracle_staleness_minutes" => 15,
                "liquidity_drop_pct" => 25
            )
        ),
        run=observe_market_conditions
    )
end

"""
Main observation logic - fetches current market state and portfolio data
"""
function observe_market_conditions(ctx::Dict)
    @info "Observer: Starting market observation cycle"
    
    try
        # Fetch portfolio state
        portfolio = fetch_portfolio_balances(ctx)
        
        # Fetch market data
        market = fetch_market_snapshot(ctx)
        
        # Check for alert conditions
        alerts = check_alert_conditions(portfolio, market, ctx)
        
        # Compile observation report
        observation = Dict(
            "timestamp" => now(),
            "portfolio" => portfolio,
            "market" => market,
            "alerts" => alerts,
            "status" => "healthy"
        )
        
        # Log key metrics
        @info "Observer: Portfolio value: $(portfolio["total_value_usd"]) USD"
        @info "Observer: Active alerts: $(length(alerts))"
        
        # Trigger alerts if necessary
        if !isempty(alerts)
            @warn "Observer: Threshold breaches detected!" alerts
            # Emit threshold_breach event to trigger swarm response
            return Dict(
                "type" => "threshold_breach",
                "observation" => observation,
                "priority" => determine_priority(alerts)
            )
        end
        
        return Dict(
            "type" => "heartbeat", 
            "observation" => observation
        )
        
    catch e
        @error "Observer: Error during observation cycle" exception=e
        return Dict(
            "type" => "error",
            "error" => string(e),
            "timestamp" => now()
        )
    end
end

"""
Fetch portfolio balances across configured wallets and chains
"""
function fetch_portfolio_balances(ctx::Dict)
    @info "Observer: Fetching portfolio balances"
    
    # Get wallet addresses from context or config
    wallets = get(ctx, "portfolio_wallets", [
        "CWE8jPTUYhdCTZYWPTe1o5DFqfdjzWKc9WKz6rSjQUdG", # Example Solana wallet
    ])
    
    portfolio = Dict(
        "total_value_usd" => 0.0,
        "assets" => Dict{String, Float64}(),
        "allocation_pct" => Dict{String, Float64}(),
        "wallets" => Dict{String, Any}(),
        "last_updated" => now()
    )
    
    total_value = 0.0
    
    for wallet_address in wallets
        try
            if length(wallet_address) > 40  # Likely Solana address
                wallet_data = fetch_solana_balances_real(wallet_address, ctx)
                portfolio["wallets"][wallet_address] = wallet_data
                
                # Aggregate assets
                wallet_assets = get(wallet_data, "assets", Dict())
                for (asset, amount) in wallet_assets
                    if haskey(portfolio["assets"], asset)
                        portfolio["assets"][asset] += amount
                    else
                        portfolio["assets"][asset] = amount
                    end
                end
                
                total_value += get(wallet_data, "value_usd", 0.0)
            else
                # Assume Ethereum for shorter addresses  
                wallet_data = fetch_ethereum_balances(wallet_address, ctx)
                portfolio["wallets"][wallet_address] = wallet_data
                total_value += get(wallet_data, "value_usd", 0.0)
            end
        catch e
            @error "Failed to fetch wallet balance" wallet=wallet_address exception=e
        end
    end
    
    portfolio["total_value_usd"] = total_value
    
    # Calculate allocation percentages
    for (asset, amount) in portfolio["assets"]
        asset_value = amount * get_asset_price_usd(asset, ctx)
        portfolio["allocation_pct"][asset] = total_value > 0 ? (asset_value / total_value) * 100 : 0.0
    end
    
    @info "Observer: Portfolio fetched" total_value_usd=total_value asset_count=length(portfolio["assets"])
    return portfolio
end

"""
Fetch real Solana wallet balances using RPC
"""
function fetch_solana_balances_real(wallet_address::String, ctx::Dict)
    try
        rpc_url = get(ENV, "SOLANA_RPC_URL", "https://api.devnet.solana.com")
        
        # Get native SOL balance
        sol_balance_payload = Dict(
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "getBalance",
            "params" => [wallet_address]
        )
        
        sol_response = HTTP.post(
            rpc_url,
            ["Content-Type" => "application/json"],
            JSON3.write(sol_balance_payload);
            timeout=10
        )
        
        sol_balance = 0.0
        if sol_response.status == 200
            sol_data = JSON3.read(String(sol_response.body))
            if haskey(sol_data, "result") && sol_data.result !== nothing
                sol_balance = sol_data.result.value / 1e9  # Convert lamports to SOL
            end
        end
        
        # Get SPL token balances
        token_accounts_payload = Dict(
            "jsonrpc" => "2.0",
            "id" => 2,
            "method" => "getTokenAccountsByOwner",
            "params" => [
                wallet_address,
                Dict("programId" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
                Dict("encoding" => "jsonParsed")
            ]
        )
        
        token_response = HTTP.post(
            rpc_url,
            ["Content-Type" => "application/json"],
            JSON3.write(token_accounts_payload);
            timeout=10
        )
        
        assets = Dict("SOL" => sol_balance)
        
        if token_response.status == 200
            token_data = JSON3.read(String(token_response.body))
            if haskey(token_data, "result") && haskey(token_data.result, "value")
                for account in token_data.result.value
                    try
                        parsed = account.account.data.parsed
                        if haskey(parsed, "info")
                            info = parsed.info
                            mint = info.mint
                            amount = parse(Float64, info.tokenAmount.amount)
                            decimals = info.tokenAmount.decimals
                            
                            # Convert to human readable amount
                            balance = amount / (10^decimals)
                            
                            # Map common mints to symbols
                            symbol = get_token_symbol_from_mint(mint)
                            if balance > 0
                                assets[symbol] = balance
                            end
                        end
                    catch e
                        @warn "Error parsing token account" exception=e
                    end
                end
            end
        end
        
        # Calculate total USD value
        total_value = 0.0
        for (asset, amount) in assets
            price = get_asset_price_usd(asset, ctx)
            total_value += amount * price
        end
        
        wallet_data = Dict(
            "address" => wallet_address,
            "chain" => "solana",
            "assets" => assets,
            "value_usd" => total_value,
            "last_updated" => now()
        )
        
        @info "Observer: Solana wallet fetched" address=wallet_address[1:8]*"..." assets=length(assets) value_usd=total_value
        return wallet_data
        
    catch e
        @error "Failed to fetch Solana balances" wallet=wallet_address exception=e
        return Dict(
            "address" => wallet_address,
            "chain" => "solana", 
            "assets" => Dict("SOL" => 0.0),
            "value_usd" => 0.0,
            "error" => string(e)
        )
    end
end

"""
Map Solana token mints to common symbols
"""
function get_token_symbol_from_mint(mint::String)
    mint_to_symbol = Dict(
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" => "USDC",
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB" => "USDT", 
        "So11111111111111111111111111111111111111112" => "SOL",
        "orcaEKTdK7LKz57vaAYr9QeNsVEPfiu6QeMU1kektZE" => "ORCA",
        "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263" => "BONK"
    )
    
    return get(mint_to_symbol, mint, "UNKNOWN_$(mint[1:8])")
end

"""
Fetch Ethereum wallet balances using RPC
"""
function fetch_ethereum_balances(wallet_address::String, ctx::Dict)
    # Mock data for demo
    mock_balances = Dict(
        "ETH" => 5.2,
        "USDC" => 8500.0,
        "WBTC" => 0.15
    )
    
    wallet_data = Dict(
        "address" => wallet_address,
        "chain" => "ethereum", 
        "assets" => mock_balances,
        "value_usd" => 0.0
    )
    
    # Calculate USD value
    total_value = 0.0
    for (asset, amount) in mock_balances
        price = get_asset_price_usd(asset, ctx)
        total_value += amount * price
    end
    
    wallet_data["value_usd"] = total_value
    return wallet_data
end

"""
Fetch current market snapshot including prices and liquidity
"""
function fetch_market_snapshot(ctx::Dict)
    @info "Observer: Fetching market snapshot from multiple sources"
    
    try
        # Fetch Solana/USDC price from multiple sources
        sol_price = fetch_sol_price()
        
        # Fetch pool liquidity data
        pool_data = fetch_dex_pools()
        
        # Fetch oracle data staleness
        oracle_health = check_oracle_health_data()
        
        # Compile market snapshot
        market_snapshot = Dict(
            "timestamp" => now(),
            "prices" => Dict(
                "SOL/USD" => sol_price,
                "USDC/USD" => 1.0001,
                "USDT/USD" => 0.9998,
                "last_updated" => now()
            ),
            "pools" => pool_data,
            "oracles" => oracle_health,
            "network_health" => check_network_health(),
            "volatility" => calculate_recent_volatility(ctx)
        )
        
        @info "Observer: Market snapshot complete" sol_price=sol_price pool_count=length(pool_data)
        return market_snapshot
        
    catch e
        @error "Observer: Failed to fetch market data" exception=e
        # Return fallback data to keep system operational
        return Dict(
            "timestamp" => now(),
            "prices" => Dict("SOL/USD" => 100.0, "USDC/USD" => 1.0, "USDT/USD" => 1.0),
            "pools" => [],
            "oracles" => Dict("health" => "unknown"),
            "network_health" => "degraded",
            "volatility" => Dict("SOL" => 0.5),
            "error" => string(e)
        )
    end
end

"""
Fetch SOL price from external APIs
"""
function fetch_sol_price()
    try
        # Use CoinGecko as reliable price source
        response = HTTP.get("https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd")
        
        if response.status == 200
            data = JSON3.read(String(response.body))
            return Float64(data.solana.usd)
        else
            @warn "Failed to fetch SOL price from CoinGecko"
            return 100.0 # Fallback price
        end
        
    catch e
        @error "Error fetching SOL price" exception=e
        return 100.0 # Fallback price
    end
end

"""
Fetch DEX pool liquidity data
"""
function fetch_dex_pools()
    try
        # For production, integrate with Jupiter/Orca APIs
        # Mock data for now with realistic structure
        pools = [
            Dict(
                "name" => "SOL/USDC",
                "dex" => "Orca",
                "liquidity_usd" => 15_000_000.0,
                "volume_24h" => 5_000_000.0,
                "fee_tier" => 0.0025,
                "health" => "healthy"
            ),
            Dict(
                "name" => "SOL/USDT", 
                "dex" => "Raydium",
                "liquidity_usd" => 8_000_000.0,
                "volume_24h" => 2_000_000.0,
                "fee_tier" => 0.0025,
                "health" => "healthy"
            )
        ]
        
        return pools
        
    catch e
        @error "Error fetching pool data" exception=e
        return []
    end
end

"""
Check oracle health and data staleness
"""
function check_oracle_health_data()
    try
        return Dict(
            "pyth" => Dict(
                "status" => "healthy",
                "last_update" => now(),
                "staleness_seconds" => 5
            ),
            "switchboard" => Dict(
                "status" => "healthy", 
                "last_update" => now(),
                "staleness_seconds" => 8
            )
        )
        
    catch e
        @error "Error checking oracle health" exception=e
        return Dict("status" => "unknown")
    end
end

"""
Check Solana network health
"""
function check_network_health()
    try
        rpc_url = get(ENV, "SOLANA_RPC_URL", "https://api.devnet.solana.com")
        
        # Make a simple RPC call to check network status
        payload = Dict(
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "getHealth"
        )
        
        response = HTTP.post(
            rpc_url,
            ["Content-Type" => "application/json"],
            JSON3.write(payload);
            timeout=10
        )
        
        if response.status == 200
            return "healthy"
        else
            return "degraded"
        end
        
    catch e
        @error "Error checking network health" exception=e
        return "unknown"
    end
end

"""
Fetch Solana wallet balances using RPC
"""
function fetch_solana_balances(wallet_address::String, ctx::Dict)
    # Simulate Solana RPC call
    # In production, this would use actual Solana RPC endpoints
    
    # Mock data for demo
    mock_balances = Dict(
        "SOL" => 45.7,
        "USDC" => 12500.0,
        "ORCA" => 850.0
    )
    
    wallet_data = Dict(
        "address" => wallet_address,
        "chain" => "solana",
        "assets" => mock_balances,
        "value_usd" => 0.0
    )
    
    # Calculate USD value
    total_value = 0.0
    for (asset, amount) in mock_balances
        price = get_asset_price_usd(asset, ctx)
        total_value += amount * price
    end
    
    wallet_data["value_usd"] = total_value
    return wallet_data
end

"""
Fetch Ethereum wallet balances using RPC
"""
function fetch_ethereum_balances(wallet_address::String, ctx::Dict)
    # Mock data for demo
    mock_balances = Dict(
        "ETH" => 5.2,
        "USDC" => 8500.0,
        "WBTC" => 0.15
    )
    
    wallet_data = Dict(
        "address" => wallet_address,
        "chain" => "ethereum", 
        "assets" => mock_balances,
        "value_usd" => 0.0
    )
    
    # Calculate USD value
    total_value = 0.0
    for (asset, amount) in mock_balances
        price = get_asset_price_usd(asset, ctx)
        total_value += amount * price
    end
    
    wallet_data["value_usd"] = total_value
    return wallet_data
end

"""
Fetch current asset prices from various sources
"""
function fetch_asset_prices(ctx::Dict)
    # Mock price data - in production would fetch from Pyth, Chainlink, etc.
    return Dict(
        "SOL" => 23.45,
        "ETH" => 2340.67,
        "USDC" => 1.002,
        "WBTC" => 43250.0,
        "ORCA" => 2.34,
        "BTC" => 43180.0
    )
end

"""
Get asset price in USD
"""
function get_asset_price_usd(asset::String, ctx::Dict)
    prices = get(ctx, "prices", fetch_asset_prices(ctx))
    return get(prices, asset, 0.0)
end

"""
Fetch DEX pool states and liquidity information
"""
function fetch_pool_states(ctx::Dict)
    # Mock pool data
    return Dict(
        "SOL-USDC-Orca" => Dict(
            "dex" => "Orca",
            "token_a" => "SOL",
            "token_b" => "USDC", 
            "liquidity_usd" => 2_450_000.0,
            "volume_24h" => 890_000.0,
            "fees_24h" => 2_670.0,
            "price_impact_1k" => 0.012,
            "last_update" => now()
        ),
        "ETH-USDC-Uniswap" => Dict(
            "dex" => "Uniswap",
            "token_a" => "ETH",
            "token_b" => "USDC",
            "liquidity_usd" => 45_600_000.0,
            "volume_24h" => 12_300_000.0, 
            "fees_24h" => 36_900.0,
            "price_impact_1k" => 0.003,
            "last_update" => now()
        )
    )
end

"""
Check oracle health and staleness
"""
function check_oracle_health(ctx::Dict)
    return Dict(
        "pyth_sol_usd" => Dict(
            "price" => 23.45,
            "confidence" => 0.02,
            "last_update" => now() - Minute(2),
            "status" => "healthy"
        ),
        "chainlink_eth_usd" => Dict(
            "price" => 2340.67,
            "confidence" => 0.01,
            "last_update" => now() - Minute(1),
            "status" => "healthy"
        )
    )
end

"""
Calculate recent volatility for risk assessment
"""
function calculate_recent_volatility(ctx::Dict)
    # Mock volatility data
    return Dict(
        "SOL" => Dict(
            "24h_volatility" => 0.08,
            "7d_volatility" => 0.12,
            "trend" => "increasing"
        ),
        "ETH" => Dict(
            "24h_volatility" => 0.06,
            "7d_volatility" => 0.09,
            "trend" => "stable"
        )
    )
end

"""
Check for alert conditions based on current market state
"""
function check_alert_conditions(portfolio::Dict, market::Dict, ctx::Dict)
    alerts = []
    thresholds = get(ctx, "alert_thresholds", Dict())
    
    # Check for depeg alerts (only for stablecoins)
    market_prices = get(market, "prices", Dict())
    stablecoins = ["USDC/USD", "USDT/USD", "DAI/USD", "PYUSD/USD"]
    
    for (asset, price) in market_prices
        if isa(price, Number) && asset in stablecoins
            deviation_bps = abs((price - 1.0) / 1.0) * 10000
            if deviation_bps > get(thresholds, "depeg_bps", 50)
                push!(alerts, Dict(
                    "type" => "depeg",
                    "asset" => asset,
                    "current_price" => price,
                    "deviation_bps" => deviation_bps,
                    "severity" => deviation_bps > 100 ? "high" : "medium"
                ))
            end
        end
    end
    
    # Check oracle staleness
    market_oracles = get(market, "oracles", Dict())
    for (oracle, data) in market_oracles
        staleness_minutes = (now() - data["last_update"]).value / (1000 * 60)
        if staleness_minutes > get(thresholds, "oracle_staleness_minutes", 15)
            push!(alerts, Dict(
                "type" => "oracle_stale",
                "oracle" => oracle,
                "staleness_minutes" => staleness_minutes,
                "severity" => staleness_minutes > 30 ? "high" : "medium"
            ))
        end
    end
    
    # Check concentration risk
    for (asset, allocation_pct) in portfolio["allocation_pct"]
        if allocation_pct > 60 && asset != "USDC" # High concentration threshold
            push!(alerts, Dict(
                "type" => "concentration_risk",
                "asset" => asset,
                "allocation_pct" => allocation_pct,
                "severity" => allocation_pct > 80 ? "high" : "medium"
            ))
        end
    end
    
    # Check liquidity drops
    market_pools = get(market, "pools", Dict())
    for (pool_name, pool_data) in market_pools
        # This would compare against historical liquidity
        # For demo, we'll trigger if liquidity is below a threshold
        if isa(pool_data, Dict) && haskey(pool_data, "liquidity_usd")
            if pool_data["liquidity_usd"] < 1_000_000 # $1M threshold
                push!(alerts, Dict(
                    "type" => "low_liquidity",
                    "pool" => pool_name,
                    "liquidity_usd" => pool_data["liquidity_usd"],
                    "severity" => "medium"
                ))
            end
        end
    end
    
    return alerts
end

"""
Determine priority level based on alert types and severity
"""
function determine_priority(alerts::Vector)
    high_severity_count = count(alert -> get(alert, "severity", "low") == "high", alerts)
    
    if high_severity_count > 0
        return "high"
    elseif length(alerts) > 2
        return "medium"
    else
        return "low"
    end
end

"""
Get asset price in USD
"""
function get_asset_price_usd(asset::String, ctx::Dict)
    # Simple price mapping for demo
    prices = Dict(
        "SOL" => 140.0,
        "USDC" => 1.0,
        "USDT" => 1.0,
        "ETH" => 2340.0,
        "WBTC" => 43000.0,
        "ORCA" => 2.5,
        "BONK" => 0.000015
    )
    return get(prices, asset, 0.0)
end

"""
Calculate recent volatility for risk assessment
"""
function calculate_recent_volatility(ctx::Dict)
    # Mock volatility data
    return Dict(
        "SOL" => Dict(
            "24h_volatility" => 0.08,
            "7d_volatility" => 0.12,
            "trend" => "increasing"
        ),
        "ETH" => Dict(
            "24h_volatility" => 0.06,
            "7d_volatility" => 0.09,
            "trend" => "stable"
        )
    )
end

# Export the agent creation function
export create_observer_agent
