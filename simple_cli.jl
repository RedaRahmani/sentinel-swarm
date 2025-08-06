#!/usr/bin/env julia

# SENTINEL SWARM CLI - Production Command Line Interface

using JSON3
using Dates
using HTTP

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
    end
end

function main()
    println("🚀 Sentinel Swarm CLI v1.0.0")
    println("🔗 Autonomous DAO Treasury Management")
    println()
    
    load_environment()
    
    if length(ARGS) == 0 || ARGS[1] == "help"
        println("USAGE: julia simple_cli.jl <command>")
        println("COMMANDS:")
        println("  status  - Check system status")
        println("  run     - Run complete workflow")
        println("  help    - Show this help")
        return
    end
    
    command = ARGS[1]
    
    if command == "status"
        println("📊 SYSTEM STATUS CHECK")
        println("=" ^ 30)
        
        # Check environment variables
        required_vars = ["OPENAI_API_KEY", "SOLANA_RPC_URL", "REALMS_REALM_PUBKEY"]
        for var in required_vars
            status = haskey(ENV, var) && !isempty(ENV[var]) ? "✅" : "❌"
            println("$status $var")
        end
        
        # Check files
        files = ["config/default-policies.json", "chains/ts-cli/dist/index.js"]
        for file in files
            status = isfile(file) ? "✅" : "❌"
            println("$status $file")
        end
        
        # Test network
        try
            response = HTTP.get(ENV["SOLANA_RPC_URL"]; timeout=5)
            println("✅ Solana RPC: Connected")
        catch
            println("❌ Solana RPC: Failed")
        end
        
        println("✅ Status check complete")
        
    elseif command == "run"
        println("🎯 RUNNING SENTINEL SWARM")
        println("=" ^ 30)
        
        try
            include("production_demo.jl")
            println("✅ Demo completed successfully!")
        catch e
            println("❌ Demo failed: $e")
        end
        
    else
        println("❌ Unknown command: $command")
    end
end

main()
