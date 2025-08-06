# Test suite for Proposal Writer agent functionality
using Test
using JSON3
using Dates

include("../agents/proposal_writer.jl")
include("../src/JuliaOS.jl")
using .JuliaOS

@testset "Proposal Writer Tests" begin
    
    @testset "Agent Creation" begin
        proposal_writer = create_proposal_writer_agent()
        
        @test proposal_writer.name == "ProposalWriter"
        @test :realms_proposal in proposal_writer.tools
        @test :instruction_builder in proposal_writer.tools
        @test :markdown_generation in proposal_writer.tools
        @test haskey(proposal_writer.config, "proposal_templates")
    end
    
    @testset "Proposal Creation with Fixture" begin
        # Create fixture data
        fixture_recommendation = Dict(
            "name" => "Reduce SOL exposure to 25%",
            "type" => "rebalance",
            "actions" => [
                Dict(
                    "type" => "transfer",
                    "from_wallet" => "treasury_wallet_123",
                    "to_wallet" => "stable_wallet_456", 
                    "token_mint" => "So11111111111111111111111111111111111111112", # SOL mint
                    "amount" => 50000000000, # 50 SOL in lamports
                    "description" => "Transfer 50 SOL to stable allocation"
                )
            ],
            "expected_var_impact" => -1.2,
            "risk_level" => "medium",
            "priority" => "high"
        )
        
        fixture_analysis = Dict(
            "situation_analysis" => Dict(
                "llm_analysis" => "Current portfolio shows elevated VaR due to SOL concentration. Market volatility suggests defensive positioning.",
                "portfolio_health" => "moderate_risk",
                "risk_factors" => ["high_sol_concentration", "market_volatility"]
            ),
            "recommendations" => Dict(
                "primary_recommendation" => fixture_recommendation,
                "alternative_options" => []
            )
        )
        
        fixture_ctx = Dict(
            "ok" => Dict("approved_recommendation" => fixture_recommendation),
            "analysis" => fixture_analysis,
            "portfolio" => Dict(
                "total_value_usd" => 1000000,
                "assets" => Dict("SOL" => 0.45, "USDC" => 0.35, "USDT" => 0.20)
            ),
            "policies" => Dict(
                "max_daily_var_pct" => 6.0,
                "min_stable_allocation_pct" => 35.0
            )
        )
        
        # Mock the LLM calls to avoid requiring API keys during tests
        original_agent_useLLM = JuliaOS.agent_useLLM
        function mock_agent_useLLM(;prompt::String, temperature::Float64=0.7, max_tokens::Int=1000)
            if contains(prompt, "governance proposal description")
                return Dict("content" => "## Treasury Rebalancing Proposal\\n\\nThis proposal reduces SOL exposure to improve risk metrics.")
            elseif contains(prompt, "voting rationale") 
                return Dict("content" => "Vote YES to reduce portfolio volatility and maintain stable allocations.")
            else
                return Dict("content" => "Mock LLM response for testing")
            end
        end
        @eval JuliaOS agent_useLLM = $mock_agent_useLLM
        
        # Mock the SolanaBridge calls
        include("../chains/bridge.jl")
        original_realms_create = SolanaBridge.realms_create_proposal
        function mock_realms_create(title::String, description_md::String, instructions)
            return Dict(
                "realm" => "test_realm",
                "governance" => "test_governance",
                "title" => title,
                "descriptionMd" => description_md,
                "instructions" => instructions,
                "meta" => Dict("createdAt" => time(), "signer" => "test_signer")
            )
        end
        @eval SolanaBridge realms_create_proposal = $mock_realms_create
        
        # Mock Config to avoid environment dependency
        include("../config/config.jl")
        original_cfg = Config.cfg
        mock_config = Config.AppConfig("openai", "test_key", "gpt-4", "test_rpc", "[1,2,3]", "realm", "gov")
        @eval Config cfg() = $mock_config
        
        try
            # Test proposal creation
            proposal_writer = create_proposal_writer_agent()
            result = create_governance_proposal(fixture_ctx)
            
            @testset "Result Structure" begin
                @test haskey(result, "status")
                @test haskey(result, "proposal")
                @test haskey(result, "realms_proposal")
                @test haskey(result, "instruction_bundle")
                @test result["status"] == "proposal_created"
            end
            
            @testset "Instruction Bundle Shape" begin
                instruction_bundle = result["instruction_bundle"]
                @test haskey(instruction_bundle, "instructions")
                @test haskey(instruction_bundle, "instruction_count") 
                @test haskey(instruction_bundle, "bundle_hash")
                @test instruction_bundle["instruction_count"] >= 1
                @test isa(instruction_bundle["instructions"], Array)
            end
            
            @testset "Proposal Fields" begin
                proposal = result["proposal"]
                @test haskey(proposal, "proposal_id")
                @test haskey(proposal, "summary")
                @test haskey(proposal, "metadata")
                
                realms_proposal = result["realms_proposal"]
                @test haskey(realms_proposal, "title")
                @test haskey(realms_proposal, "descriptionMd")
                @test contains(realms_proposal["title"], "Treasury") || contains(realms_proposal["title"], "Rebalancing")
            end
            
        finally
            # Restore original functions
            @eval JuliaOS agent_useLLM = $original_agent_useLLM
            @eval SolanaBridge realms_create_proposal = $original_realms_create
            @eval Config cfg = $original_cfg
        end
    end
    
    @testset "Instruction Building" begin
        @testset "Transfer Instruction" begin
            test_recommendation = Dict(
                "actions" => [
                    Dict(
                        "type" => "transfer",
                        "from_wallet" => "from123",
                        "to_wallet" => "to456", 
                        "token_mint" => "mint789",
                        "amount" => 1000000
                    )
                ]
            )
            
            # Mock SolanaBridge.ix_transfer
            original_ix_transfer = SolanaBridge.ix_transfer
            function mock_ix_transfer(;from, to, mint, amount)
                return Dict(
                    "instructions" => [Dict(
                        "programId" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                        "keys" => [],
                        "data" => "mock_transfer_data"
                    )]
                )
            end
            @eval SolanaBridge ix_transfer = $mock_ix_transfer
            
            try
                result = build_instruction_bundle(test_recommendation, Dict(), Dict(), Dict())
                
                @test haskey(result, "instructions")
                @test haskey(result, "instruction_count")
                @test result["instruction_count"] >= 1
                @test length(result["instructions"]) >= 1
                
            finally
                @eval SolanaBridge ix_transfer = $original_ix_transfer
            end
        end
    end
    
    @testset "Action Extraction" begin
        test_recommendation = Dict(
            "actions" => [
                Dict("type" => "transfer", "amount" => 1000),
                Dict("type" => "swap", "from_token" => "SOL", "to_token" => "USDC")
            ]
        )
        
        actions = extract_actions_from_recommendation(test_recommendation)
        @test length(actions) == 2
        @test actions[1]["type"] == "transfer"
        @test actions[2]["type"] == "swap"
    end
    
    @testset "Title Generation" begin
        test_recommendation = Dict(
            "name" => "Reduce SOL exposure",
            "type" => "rebalance",
            "priority" => "high"
        )
        
        title = generate_proposal_title(test_recommendation, Dict())
        @test isa(title, String)
        @test length(title) > 0
        @test length(title) <= 100 # Reasonable title length
    end
    
    @testset "Bundle Hash Calculation" begin
        test_instructions = [
            Dict("programId" => "prog1", "data" => "data1"),
            Dict("programId" => "prog2", "data" => "data2")
        ]
        
        hash1 = calculate_bundle_hash(test_instructions)
        hash2 = calculate_bundle_hash(test_instructions)
        
        @test isa(hash1, String)
        @test hash1 == hash2 # Same input should produce same hash
        @test length(hash1) > 10 # Should be a reasonable hash length
        
        # Different input should produce different hash
        different_instructions = [Dict("programId" => "prog3", "data" => "data3")]
        hash3 = calculate_bundle_hash(different_instructions)
        @test hash1 != hash3
    end
end
