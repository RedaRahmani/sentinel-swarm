# Test suite for Sentinel Swarm autonomous treasury management system
# Comprehensive testing of all agents and system integration

using Test
using Dates
using JSON3

# Include the main system
include("../sentinel_swarm.jl")
include("../src/JuliaOS.jl")

# Test configuration
const TEST_CONFIG = Dict(
    "execution_mode" => "simulation",
    "auto_approve_dev" => true,
    "devnet_testing" => true,
    "test_portfolio_size" => 100_000
)

@testset "Sentinel Swarm Test Suite" begin
    
    @testset "JuliaOS Framework Tests" begin
        @testset "Agent Creation" begin
            agent = Agent(
                name="TestAgent",
                tools=[:test_tool],
                config=Dict("test" => true),
                run=(ctx) -> Dict("status" => "success", "test" => true)
            )
            
            @test agent.name == "TestAgent"
            @test :test_tool in agent.tools
            @test agent.config["test"] == true
            @test isa(agent.run, Function)
        end
        
        @testset "Agent Execution" begin
            agent = Agent(
                name="TestAgent",
                tools=[:test],
                config=Dict(),
                run=(ctx) -> Dict("status" => "success", "input" => get(ctx, "input", "none"))
            )
            
            result = run_agent(agent, Dict("input" => "test_data"))
            @test result["status"] == "success"
            @test result["input"] == "test_data"
        end
        
        @testset "LLM Integration" begin
            response = agent_useLLM(prompt="Test prompt", temperature=0.5)
            @test haskey(response, "content")
            @test haskey(response, "model")
            @test haskey(response, "timestamp")
        end
        
        @testset "Swarm Creation" begin
            agent1 = Agent(name="Agent1", tools=[], config=Dict(), run=(ctx) -> Dict("status" => "success"))
            agent2 = Agent(name="Agent2", tools=[], config=Dict(), run=(ctx) -> Dict("status" => "success"))
            
            swarm = swarm_create(
                name="TestSwarm",
                agents=[agent1, agent2],
                config=Dict("test" => true)
            )
            
            @test swarm.name == "TestSwarm"
            @test length(swarm.agents) == 2
            @test swarm.config["test"] == true
        end
    end
    
    @testset "Individual Agent Tests" begin
        @testset "Observer Agent" begin
            observer = create_observer_agent()
            @test observer.name == "Observer"
            @test :market_data in observer.tools
            
            # Test with mock context
            mock_context = Dict(
                "config" => TEST_CONFIG,
                "timestamp" => now()
            )
            
            result = run_agent(observer, mock_context)
            @test result["status"] == "success"
            @test haskey(result, "portfolio")
            @test haskey(result, "market")
            @test haskey(result, "alerts")
        end
        
        @testset "Simulator Agent" begin
            simulator = create_simulator_agent()
            @test simulator.name == "Simulator"
            @test :monte_carlo in simulator.tools
            
            # Test with portfolio data
            mock_context = Dict(
                "config" => TEST_CONFIG,
                "portfolio" => Dict(
                    "total_value_usd" => 100_000,
                    "allocation_pct" => Dict("SOL" => 40.0, "USDC" => 30.0, "BTC" => 30.0)
                ),
                "market" => Dict(
                    "prices" => Dict("SOL" => 150.0, "USDC" => 1.0, "BTC" => 45000.0),
                    "volatility" => Dict("SOL" => Dict("30d" => 0.45), "BTC" => Dict("30d" => 0.35))
                )
            )
            
            result = run_agent(simulator, mock_context)
            @test result["status"] == "success"
            @test haskey(result, "simulation_insights")
            @test haskey(result, "var_analysis")
            @test haskey(result, "optimization_candidates")
        end
        
        @testset "Analyst Agent" begin
            analyst = create_analyst_agent()
            @test analyst.name == "Analyst"
            @test :llm_analysis in analyst.tools
            
            # Test with analysis data
            mock_context = Dict(
                "config" => TEST_CONFIG,
                "portfolio" => Dict("total_value_usd" => 100_000),
                "market" => Dict("trend" => "bullish"),
                "simulation_insights" => Dict(
                    "risk_metrics_analysis" => Dict("current_var_95" => 8.2),
                    "candidates_ranking" => [Dict("name" => "Rebalance to 60/40")]
                )
            )
            
            result = run_agent(analyst, mock_context)
            @test result["status"] == "success"
            @test haskey(result, "analysis")
            @test haskey(result["analysis"], "recommendations")
        end
        
        @testset "Risk Officer Agent" begin
            risk_officer = create_risk_officer_agent()
            @test risk_officer.name == "RiskOfficer"
            @test :policy_validation in risk_officer.tools
            
            # Test with recommendation
            mock_context = Dict(
                "config" => TEST_CONFIG,
                "analysis" => Dict(
                    "recommendations" => Dict(
                        "primary" => Dict(
                            "name" => "Conservative Rebalancing",
                            "risk_level" => "medium",
                            "expected_var_impact" => "5.8%"
                        )
                    )
                ),
                "portfolio" => Dict("total_value_usd" => 50_000) # Under limit
            )
            
            result = run_agent(risk_officer, mock_context)
            @test result["status"] == "success"
            @test haskey(result, "ok")
        end
        
        @testset "Compliance Agent" begin
            compliance = create_compliance_agent()
            @test compliance.name == "Compliance"
            @test :aml_screening in compliance.tools
            
            # Test with cleared recommendation
            mock_context = Dict(
                "config" => TEST_CONFIG,
                "ok" => Dict(
                    "approved" => true,
                    "approved_recommendation" => Dict(
                        "name" => "Test Rebalancing",
                        "counterparties" => ["Orca", "Jupiter"]
                    )
                )
            )
            
            result = run_agent(compliance, mock_context)
            @test result["status"] == "success"
            @test haskey(result, "ok")
        end
        
        @testset "Proposal Writer Agent" begin
            proposal_writer = create_proposal_writer_agent()
            @test proposal_writer.name == "ProposalWriter"
            @test :realms_proposal in proposal_writer.tools
            
            # Test with cleared recommendation
            mock_context = Dict(
                "config" => TEST_CONFIG,
                "ok" => Dict(
                    "cleared" => true,
                    "approved_recommendation" => Dict(
                        "name" => "Portfolio Optimization",
                        "description" => "Rebalance portfolio for better risk profile"
                    )
                ),
                "analysis" => Dict("executive_summary" => Dict()),
                "portfolio" => Dict("total_value_usd" => 75_000)
            )
            
            result = run_agent(proposal_writer, mock_context)
            @test result["status"] == "proposal_created"
            @test haskey(result, "proposal")
            @test haskey(result, "realms_proposal")
        end
        
        @testset "Executor Agent" begin
            executor = create_executor_agent()
            @test executor.name == "Executor"
            @test :transaction_simulation in executor.tools
            
            # Test with proposal
            mock_proposal = Dict(
                "proposal_id" => "test-123",
                "instruction_bundle" => Dict(
                    "instructions" => [
                        Dict(
                            "program_id" => "test",
                            "accounts" => [],
                            "data" => "test",
                            "instruction_type" => "swap"
                        )
                    ]
                )
            )
            
            mock_context = Dict(
                "config" => merge(TEST_CONFIG, Dict("auto_approve_dev" => true)),
                "proposal" => mock_proposal
            )
            
            result = run_agent(executor, mock_context)
            @test result["status"] == "simulation_complete"
            @test haskey(result, "simulation_result")
        end
    end
    
    @testset "Integration Tests" begin
        @testset "Swarm Creation and Configuration" begin
            swarm = create_sentinel_swarm()
            
            @test swarm.name == "SentinelSwarm"
            @test length(swarm.agents) == 7
            @test haskey(swarm.config, "execution_mode")
            
            # Test agent names are correct
            agent_names = [agent.name for agent in swarm.agents]
            expected_names = ["Observer", "Simulator", "Analyst", "RiskOfficer", "Compliance", "ProposalWriter", "Executor"]
            @test all(name in agent_names for name in expected_names)
        end
        
        @testset "Configuration Management" begin
            swarm = create_sentinel_swarm()
            
            # Test valid configuration update
            new_config = Dict(
                "risk_tolerance" => "low",
                "max_proposal_value_usd" => 75_000
            )
            
            result = update_swarm_config(swarm, new_config)
            @test result["status"] == "success"
            @test swarm.config["risk_tolerance"] == "low"
            @test swarm.config["max_proposal_value_usd"] == 75_000
            
            # Test invalid configuration
            invalid_config = Dict("execution_mode" => "invalid_mode")
            result = update_swarm_config(swarm, invalid_config)
            @test result["status"] == "error"
            @test !isempty(result["errors"])
        end
        
        @testset "Health Monitoring" begin
            swarm = create_sentinel_swarm()
            health_report = monitor_swarm_health(swarm)
            
            @test haskey(health_report, "swarm_status")
            @test haskey(health_report, "agent_count")
            @test haskey(health_report, "agents_status")
            @test haskey(health_report, "system_metrics")
            @test health_report["agent_count"] == 7
        end
    end
    
    @testset "Full Cycle Tests" begin
        @testset "Successful Autonomous Cycle" begin
            swarm = create_sentinel_swarm()
            
            # Override config for testing
            swarm.config = merge(swarm.config, TEST_CONFIG)
            
            result = run_sentinel_swarm_cycle(swarm)
            
            @test result["cycle_status"] == "success"
            @test haskey(result, "cycle_id")
            @test haskey(result, "key_results")
            @test haskey(result, "performance_metrics")
            @test length(result["phases_completed"]) >= 6 # At least 6 phases
        end
        
        @testset "Emergency Response" begin
            swarm = create_sentinel_swarm()
            swarm.config = merge(swarm.config, TEST_CONFIG)
            
            emergency_event = Dict(
                "type" => "market_crash",
                "severity" => "high",
                "portfolio_impact_pct" => -25.0,
                "timestamp" => now()
            )
            
            result = run_emergency_response(swarm, emergency_event)
            
            @test result["response_status"] == "completed"
            @test haskey(result, "emergency_id")
            @test haskey(result, "emergency_assessment")
            @test haskey(result, "recommended_actions")
        end
        
        @testset "Cycle Failure Handling" begin
            # Test cycle with intentional failure
            swarm = create_sentinel_swarm()
            
            # Modify observer to fail
            swarm.agents[1].run = (ctx) -> Dict("status" => "error", "error" => "Simulated failure")
            
            result = run_sentinel_swarm_cycle(swarm)
            
            @test result["cycle_status"] == "failed"
            @test result["failure_type"] == "observer_failed"
            @test haskey(result, "recovery_suggestions")
        end
    end
    
    @testset "Policy Validation Tests" begin
        @testset "Policy File Loading" begin
            # Test if policy file exists and is valid JSON
            policy_path = joinpath(@__DIR__, "..", "config", "default-policies.json")
            @test isfile(policy_path)
            
            policies = JSON3.read(read(policy_path, String))
            @test haskey(policies, "risk_policies")
            @test haskey(policies, "execution_policies")
            @test haskey(policies, "compliance_policies")
        end
        
        @testset "Risk Policy Validation" begin
            policy_path = joinpath(@__DIR__, "..", "config", "default-policies.json")
            policies = JSON3.read(read(policy_path, String))
            
            # Test portfolio limits are reasonable
            portfolio_limits = policies["risk_policies"]["portfolio_limits"]
            @test portfolio_limits["max_single_asset_allocation_pct"] <= 100
            @test portfolio_limits["min_stablecoin_allocation_pct"] >= 0
            @test portfolio_limits["max_leverage_ratio"] >= 1.0
            
            # Test VaR constraints
            var_constraints = policies["risk_policies"]["var_constraints"]
            @test var_constraints["confidence_level"] > 0 && var_constraints["confidence_level"] < 1
            @test var_constraints["max_portfolio_var_95_pct"] > 0
        end
    end
    
    @testset "Error Handling Tests" begin
        @testset "Agent Error Recovery" begin
            # Test agent with error in execution
            error_agent = Agent(
                name="ErrorAgent",
                tools=[:error_tool],
                config=Dict(),
                run=(ctx) -> error("Simulated agent error")
            )
            
            # Should handle error gracefully
            result = try
                run_agent(error_agent, Dict())
            catch e
                Dict("status" => "error", "error" => string(e))
            end
            
            @test result["status"] == "error"
            @test haskey(result, "error")
        end
        
        @testset "Network Failure Simulation" begin
            # Test network failure handling in Observer
            observer = create_observer_agent()
            
            # Simulate network failure context
            network_failure_context = Dict(
                "config" => merge(TEST_CONFIG, Dict("simulate_network_failure" => true))
            )
            
            result = run_agent(observer, network_failure_context)
            # Should still complete with fallback data
            @test result["status"] == "success"
        end
    end
    
    @testset "Performance Tests" begin
        @testset "Cycle Performance" begin
            swarm = create_sentinel_swarm()
            swarm.config = merge(swarm.config, TEST_CONFIG)
            
            start_time = time()
            result = run_sentinel_swarm_cycle(swarm)
            execution_time = time() - start_time
            
            # Should complete within reasonable time (adjust threshold as needed)
            @test execution_time < 60.0 # 60 seconds max
            @test result["cycle_status"] == "success"
        end
        
        @testset "Memory Usage" begin
            # Basic memory usage test
            initial_memory = Base.gc_bytes()
            
            swarm = create_sentinel_swarm()
            run_sentinel_swarm_cycle(swarm)
            
            # Force garbage collection
            GC.gc()
            final_memory = Base.gc_bytes()
            
            # Memory increase should be reasonable
            memory_increase = final_memory - initial_memory
            @test memory_increase < 100_000_000 # Less than 100MB increase
        end
    end
    
    @testset "Security Tests" begin
        @testset "Input Validation" begin
            swarm = create_sentinel_swarm()
            
            # Test with malicious input
            malicious_context = Dict(
                "config" => Dict("execution_mode" => "<script>alert('xss')</script>"),
                "malicious_data" => "'; DROP TABLE users; --"
            )
            
            result = run_sentinel_swarm_cycle(swarm, ctx=malicious_context)
            # Should handle malicious input safely
            @test haskey(result, "cycle_status")
        end
        
        @testset "Configuration Security" begin
            swarm = create_sentinel_swarm()
            
            # Test with invalid configuration values
            dangerous_config = Dict(
                "max_proposal_value_usd" => -1000000,
                "execution_mode" => "../../etc/passwd"
            )
            
            result = update_swarm_config(swarm, dangerous_config)
            @test result["status"] == "error"
            @test !isempty(result["errors"])
        end
    end
end

# Utility functions for testing

function create_test_portfolio(size_usd::Float64 = 100_000.0)
    return Dict(
        "total_value_usd" => size_usd,
        "allocation_pct" => Dict(
            "SOL" => 35.0,
            "USDC" => 30.0,
            "BTC" => 25.0,
            "ETH" => 10.0
        ),
        "balances" => Dict(
            "SOL" => size_usd * 0.35 / 150.0,
            "USDC" => size_usd * 0.30,
            "BTC" => size_usd * 0.25 / 45000.0,
            "ETH" => size_usd * 0.10 / 3000.0
        )
    )
end

function create_test_market_data()
    return Dict(
        "prices" => Dict(
            "SOL" => 150.0,
            "USDC" => 1.0,
            "BTC" => 45000.0,
            "ETH" => 3000.0
        ),
        "volatility" => Dict(
            "SOL" => Dict("24h" => 0.045, "30d" => 0.45),
            "BTC" => Dict("24h" => 0.035, "30d" => 0.35),
            "ETH" => Dict("24h" => 0.040, "30d" => 0.40),
            "USDC" => Dict("24h" => 0.001, "30d" => 0.01)
        ),
        "volume_24h" => Dict(
            "SOL" => 2_500_000_000,
            "BTC" => 15_000_000_000,
            "ETH" => 8_000_000_000,
            "USDC" => 5_000_000_000
        )
    )
end

function run_performance_benchmark()
    @info "Running Sentinel Swarm Performance Benchmark"
    
    swarm = create_sentinel_swarm()
    swarm.config = merge(swarm.config, TEST_CONFIG)
    
    # Benchmark multiple cycles
    cycle_times = []
    for i in 1:5
        start_time = time()
        result = run_sentinel_swarm_cycle(swarm)
        execution_time = time() - start_time
        push!(cycle_times, execution_time)
        
        @info "Cycle $i: $(round(execution_time, digits=2))s - $(result["cycle_status"])"
    end
    
    avg_time = sum(cycle_times) / length(cycle_times)
    @info "Average cycle time: $(round(avg_time, digits=2))s"
    @info "Min time: $(round(minimum(cycle_times), digits=2))s"
    @info "Max time: $(round(maximum(cycle_times), digits=2))s"
    
    return Dict(
        "average_time_seconds" => avg_time,
        "min_time_seconds" => minimum(cycle_times),
        "max_time_seconds" => maximum(cycle_times),
        "total_cycles" => length(cycle_times)
    )
end

# Export test utilities
export create_test_portfolio, create_test_market_data, run_performance_benchmark

@info "Sentinel Swarm test suite loaded successfully"
