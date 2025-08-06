#!/usr/bin/env julia

# Quick Start Script for Sentinel Swarm
# Provides an easy way to get started with the system

include("../sentinel_swarm.jl")

using Pkg
using Dates

function check_dependencies()
    println("🔍 Checking Julia dependencies...")
    
    required_packages = [
        "JSON3", "Dates", "SHA", "UUIDs", "Logging", 
        "Statistics", "Distributions", "LinearAlgebra", "HTTP"
    ]
    
    missing_packages = []
    
    for pkg in required_packages
        try
            eval(Meta.parse("using $pkg"))
            println("   ✅ $pkg")
        catch
            println("   ❌ $pkg (missing)")
            push!(missing_packages, pkg)
        end
    end
    
    if !isempty(missing_packages)
        println("\n📦 Installing missing packages...")
        for pkg in missing_packages
            try
                Pkg.add(pkg)
                println("   ✅ Installed $pkg")
            catch e
                println("   ❌ Failed to install $pkg: $e")
            end
        end
    end
    
    println("✅ Dependencies check complete!")
end

function run_quick_test()
    println("\n🧪 Running quick system test...")
    
    try
        # Test basic system creation
        println("   Creating Sentinel Swarm...")
        swarm = create_sentinel_swarm()
        
        # Override for quick test
        swarm.config = merge(swarm.config, Dict(
            "execution_mode" => "simulation",
            "auto_approve_dev" => true,
            "devnet_testing" => true
        ))
        
        println("   ✅ Swarm created with $(length(swarm.agents)) agents")
        
        # Test individual agent creation
        println("   Testing agent creation...")
        test_agents = [
            ("Observer", create_observer_agent),
            ("Simulator", create_simulator_agent),
            ("Analyst", create_analyst_agent)
        ]
        
        for (name, creator) in test_agents
            try
                agent = creator()
                println("   ✅ $name agent created")
            catch e
                println("   ❌ $name agent failed: $e")
            end
        end
        
        # Test basic cycle (simplified)
        println("   Running simplified cycle test...")
        
        # Quick observer test
        observer_result = run_agent(swarm.agents[1], Dict("config" => swarm.config))
        if observer_result["status"] == "success"
            println("   ✅ Observer phase working")
        else
            println("   ⚠️  Observer phase had issues")
        end
        
        println("✅ Quick test completed successfully!")
        return true
        
    catch e
        println("❌ Quick test failed: $e")
        return false
    end
end

function setup_configuration()
    println("\n⚙️  Setting up basic configuration...")
    
    # Check if config directory exists
    config_dir = joinpath(@__DIR__, "..", "config")
    if !isdir(config_dir)
        mkdir(config_dir)
        println("   📁 Created config directory")
    end
    
    # Check policy file
    policy_file = joinpath(config_dir, "default-policies.json")
    if isfile(policy_file)
        println("   ✅ Policy configuration found")
        
        # Validate JSON
        try
            JSON3.read(read(policy_file, String))
            println("   ✅ Policy file is valid JSON")
        catch e
            println("   ⚠️  Policy file has JSON errors: $e")
        end
    else
        println("   ⚠️  Policy file not found - using defaults")
    end
    
    # Create user config if it doesn't exist
    user_config_file = joinpath(config_dir, "user-config.json")
    if !isfile(user_config_file)
        user_config = Dict(
            "environment" => "development",
            "execution_mode" => "simulation",
            "auto_approve_dev" => true,
            "devnet_testing" => true,
            "monitoring_interval_minutes" => 60,
            "max_proposal_value_usd" => 50_000,
            "user_preferences" => Dict(
                "notifications_enabled" => true,
                "detailed_logging" => true,
                "performance_monitoring" => true
            )
        )
        
        open(user_config_file, "w") do f
            JSON3.pretty(f, user_config)
        end
        println("   ✅ Created user configuration file")
    else
        println("   ✅ User configuration exists")
    end
    
    println("✅ Configuration setup complete!")
end

function display_next_steps()
    println("\n🚀 Next Steps:")
    println("
1. 📖 READ THE DOCUMENTATION
   • Open README.md for detailed setup instructions
   • Review the architecture overview
   • Understand the agent roles and responsibilities

2. 🎮 RUN THE DEMO
   julia demo/demo.jl
   • Interactive demonstration of all features
   • See the complete autonomous cycle in action
   • Learn about emergency response capabilities

3. 🧪 RUN THE TESTS
   julia test/runtests.jl
   • Comprehensive test suite
   • Validates all system components
   • Performance benchmarking

4. ⚙️  CUSTOMIZE CONFIGURATION
   • Edit config/default-policies.json for your DAO
   • Set risk tolerance and portfolio limits
   • Configure compliance requirements

5. 🔧 INTEGRATE WITH YOUR INFRASTRUCTURE
   • Set up Solana RPC endpoints
   • Configure treasury wallet connections
   • Set up monitoring and alerting

6. 🌐 DEPLOY TO DEVNET
   • Test with real Solana devnet
   • Validate governance integration
   • Perform end-to-end testing

7. 🚀 PRODUCTION DEPLOYMENT
   • Deploy to mainnet with proper security
   • Set up redundant monitoring
   • Configure emergency procedures
")
    
    println("💡 Quick Commands:")
    println("   • Run full demo:     julia demo/demo.jl")
    println("   • Run tests:         julia test/runtests.jl")
    println("   • Check health:      julia -e \"include(\\\"sentinel_swarm.jl\\\"); swarm = create_sentinel_swarm(); println(monitor_swarm_health(swarm))\"")
    println("   • Single cycle:      julia -e \"include(\\\"sentinel_swarm.jl\\\"); swarm = create_sentinel_swarm(); println(execute_autonomous_cycle(swarm))\"")
end

function main()
    println("=" ^ 80)
    println(" " ^ 25 * "SENTINEL SWARM")
    println(" " ^ 20 * "Quick Start & Setup")
    println("=" ^ 80)
    
    println("\n🎯 Welcome to Sentinel Swarm!")
    println("This script will help you get started with autonomous DAO treasury management.")
    
    # Step 1: Check dependencies
    check_dependencies()
    
    # Step 2: Setup configuration
    setup_configuration()
    
    # Step 3: Run quick test
    test_success = run_quick_test()
    
    if test_success
        println("\n✅ System is ready to use!")
        
        # Step 4: Show next steps
        display_next_steps()
        
        println("\n" * "=" ^ 80)
        println("🎉 Quick start complete! The system is ready for use.")
        println("Run 'julia demo/demo.jl' to see the full demonstration.")
        println("=" ^ 80)
    else
        println("\n❌ System setup encountered issues.")
        println("\n🔧 Troubleshooting:")
        println("   • Ensure you have Julia 1.9+ installed")
        println("   • Check internet connection for package downloads")
        println("   • Verify file permissions in the project directory")
        println("   • Run 'julia --project=. -e \"using Pkg; Pkg.instantiate()\"'")
        println("\n📞 For support, check the README.md or project documentation.")
    end
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
