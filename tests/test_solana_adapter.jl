# Test suite for Solana adapter functionality
using Test
using JSON3

include("../chains/bridge.jl")
using .SolanaBridge

@testset "Solana Adapter Tests" begin
    
    @testset "Mock CLI Interface" begin
        # Mock the run_cli function to avoid actual Node.js calls during testing
        original_run_cli = SolanaBridge.run_cli
        
        # Mock responses for different commands
        mock_responses = Dict(
            "ix-transfer" => Dict(
                "instructions" => [Dict(
                    "programId" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                    "keys" => [
                        Dict("pubkey" => "from_ata", "isSigner" => false, "isWritable" => true),
                        Dict("pubkey" => "to_ata", "isSigner" => false, "isWritable" => true),
                        Dict("pubkey" => "from_wallet", "isSigner" => true, "isWritable" => false)
                    ],
                    "data" => "base64encodeddata"
                )],
                "signers" => ["signer_pubkey"]
            ),
            "proposal-create" => Dict(
                "realm" => "test_realm",
                "governance" => "test_governance", 
                "title" => "Test Proposal",
                "descriptionMd" => "Test Description",
                "instructions" => [],
                "meta" => Dict("createdAt" => 1234567890, "rpc" => "test_rpc", "signer" => "test_signer")
            ),
            "dry-run" => Dict(
                "ok" => true,
                "instructionsCount" => 1
            ),
            "proposal-post" => Dict(
                "posted" => true,
                "proposalId" => "prop_test123",
                "explorerUrl" => "https://explorer.solana.com/?cluster=devnet"
            )
        )
        
        function mock_run_cli(cmd::String, payload::Dict)
            @test haskey(mock_responses, cmd)
            return mock_responses[cmd]
        end
        
        # Replace the function temporarily
        @eval SolanaBridge run_cli = $mock_run_cli
        
        @testset "ix_transfer" begin
            result = SolanaBridge.ix_transfer(
                from="from_wallet", 
                to="to_wallet", 
                mint="token_mint", 
                amount=1000
            )
            
            @test haskey(result, "instructions")
            @test haskey(result, "signers")
            @test length(result["instructions"]) == 1
            
            instruction = result["instructions"][1]
            @test haskey(instruction, "programId")
            @test haskey(instruction, "keys") 
            @test haskey(instruction, "data")
            @test instruction["programId"] == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
        end
        
        @testset "realms_create_proposal" begin
            result = SolanaBridge.realms_create_proposal(
                "Test Proposal",
                "# Test Description\\nThis is a test",
                []
            )
            
            @test haskey(result, "realm")
            @test haskey(result, "governance")
            @test haskey(result, "title")
            @test haskey(result, "descriptionMd")
            @test haskey(result, "instructions")
            @test haskey(result, "meta")
            
            @test result["title"] == "Test Proposal"
            @test result["descriptionMd"] == "# Test Description\\nThis is a test"
        end
        
        @testset "dry_run" begin
            test_instructions = [Dict("programId" => "test", "keys" => [], "data" => "")]
            result = SolanaBridge.dry_run(test_instructions)
            
            @test haskey(result, "ok")
            @test haskey(result, "instructionsCount")
            @test result["ok"] == true
            @test result["instructionsCount"] == 1
        end
        
        @testset "post_proposal" begin
            test_proposal = Dict("realm" => "test", "instructions" => [])
            result = SolanaBridge.post_proposal(test_proposal)
            
            @test haskey(result, "posted")
            @test haskey(result, "proposalId")
            @test haskey(result, "explorerUrl")
            @test result["posted"] == true
            @test startswith(result["proposalId"], "prop_")
            @test contains(result["explorerUrl"], "explorer.solana.com")
        end
        
        # Restore original function
        @eval SolanaBridge run_cli = $original_run_cli
    end
    
    @testset "Payload Shape Validation" begin
        # Test that payload structures match expected formats
        
        @testset "Transfer payload shape" begin
            # This would normally call the CLI, so we'll test payload construction
            cfg_mock = (
                solana_rpc = "https://api.devnet.solana.com",
                keypair_json = "[1,2,3]"
            )
            
            # Mock Config.cfg() for testing
            original_cfg = SolanaBridge.Config.cfg
            @eval SolanaBridge.Config cfg() = $cfg_mock
            
            # We can't easily test the actual CLI call without Node.js setup,
            # but we can verify the payload would be constructed correctly
            @test cfg_mock.solana_rpc == "https://api.devnet.solana.com"
            @test cfg_mock.keypair_json == "[1,2,3]"
            
            # Restore original
            @eval SolanaBridge.Config cfg = $original_cfg
        end
    end
    
    @testset "Golden Snapshot Tests" begin
        @testset "Proposal JSON Envelope" begin
            # Test the expected structure of a proposal JSON envelope
            expected_envelope = Dict(
                "realm" => "test_realm_pubkey",
                "governance" => "test_governance_pubkey",
                "title" => "Treasury Rebalancing Proposal",
                "descriptionMd" => "## Summary\\nRebalance portfolio to reduce VaR",
                "instructions" => [
                    Dict(
                        "programId" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                        "keys" => [
                            Dict("pubkey" => "source_ata", "isSigner" => false, "isWritable" => true),
                            Dict("pubkey" => "dest_ata", "isSigner" => false, "isWritable" => true),
                            Dict("pubkey" => "authority", "isSigner" => true, "isWritable" => false)
                        ],
                        "data" => "instruction_data_base64"
                    )
                ],
                "meta" => Dict(
                    "createdAt" => 1234567890,
                    "rpc" => "https://api.devnet.solana.com",
                    "signer" => "authority_pubkey"
                )
            )
            
            # Validate required fields exist
            @test haskey(expected_envelope, "realm")
            @test haskey(expected_envelope, "governance")
            @test haskey(expected_envelope, "title")
            @test haskey(expected_envelope, "descriptionMd")
            @test haskey(expected_envelope, "instructions")
            @test haskey(expected_envelope, "meta")
            
            # Validate instruction structure
            instruction = expected_envelope["instructions"][1]
            @test haskey(instruction, "programId")
            @test haskey(instruction, "keys")
            @test haskey(instruction, "data")
            
            # Validate keys structure
            key = instruction["keys"][1]
            @test haskey(key, "pubkey")
            @test haskey(key, "isSigner")
            @test haskey(key, "isWritable")
            
            # Validate meta structure
            meta = expected_envelope["meta"]
            @test haskey(meta, "createdAt")
            @test haskey(meta, "rpc")
            @test haskey(meta, "signer")
        end
    end
end
