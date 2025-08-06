module SolanaBridge
using JSON3
include("../config/config.jl")
using .Config

function clean_wallet_json(s::AbstractString)::String
    # Strip whitespace
    cleaned = strip(s)
    
    # Remove inline comment starting with # to end of line
    if contains(cleaned, "#")
        cleaned = strip(split(cleaned, "#")[1])
    end
    
    # Validate it's a JSON array
    if !startswith(cleaned, "[") || !endswith(cleaned, "]")
        error("Wallet JSON must be a valid array: $cleaned")
    end
    
    return cleaned
end

function run_cli(cmd::String, payload::Dict)
    # Create the command with --quiet flag by default unless verbose is requested
    verbose_mode = get(ENV, "CLI_VERBOSE", "0") == "1"
    cmd_args = verbose_mode ? "--verbose" : "--quiet"
    c = Cmd(`node dist/index.js $cmd $cmd_args`; dir="chains/ts-cli")
    
    # Convert payload to JSON string
    json_input = JSON3.write(payload)
    
    # Only log in non-demo mode and if not quiet
    demo_mode = get(ENV, "DEMO_MODE", "0") == "1"
    if !demo_mode && verbose_mode
        @info "Sending JSON to CLI" length=length(json_input) first_100=json_input[1:min(100, end)]
    end
    
    # Use pipeline to send JSON via stdin
    try
        # Write JSON to buffer and pipe to command
        buf = IOBuffer(json_input)
        output = read(pipeline(c, stdin=buf), String)
        
        if !demo_mode && verbose_mode
            @info "CLI output received" length=length(output) output=output
        end
        
        # Parse and return JSON response
        if isempty(strip(output))
            return Dict("error" => "No output from CLI")
        end
        return JSON3.read(output)
    catch e
        if !demo_mode
            @warn "CLI command failed" cmd=cmd exception=e
        end
        return Dict("error" => "CLI execution failed: $(string(e))")
    end
end

function ix_transfer(; from::String, to::String, mint::String, amount::Int)
    c = Config.cfg()
    
    # Ensure the wallet is properly formatted as a JSON array
    wallet_key = c.keypair_json
    if !startswith(wallet_key, "[")
        wallet_key = "[" * wallet_key * "]"
    end
    
    payload = Dict(
        "from"=>from, "to"=>to, "mint"=>mint, "amount"=>amount,
        "rpc"=>c.solana_rpc, "wallet"=>wallet_key,
    )
    return run_cli("ix-transfer", payload)
end

function realms_create_proposal(title::String, description_md::String, instructions)
    c = Config.cfg()
    
    # Clean the wallet JSON to remove any inline comments
    wallet_key = clean_wallet_json(c.keypair_json)
    
    payload = Dict(
        "realm"=>c.realms_realm, "governance"=>c.realms_gov,
        "title"=>title, "descriptionMd"=>description_md,
        "instructions"=>instructions,
        "rpc"=>c.solana_rpc, "wallet"=>wallet_key
    )
    return run_cli("proposal-create", payload)
end

function dry_run(instructions)
    c = Config.cfg()
    
    # Clean the wallet JSON to remove any inline comments
    wallet_key = clean_wallet_json(c.keypair_json)
    
    payload = Dict("rpc"=>c.solana_rpc, "wallet"=>wallet_key, "instructions"=>instructions)
    return run_cli("dry-run", payload)
end

function post_proposal(proposal_json)
    c = Config.cfg()
    
    # Ensure the wallet is properly formatted as a JSON array
    wallet_key = c.keypair_json
    if !startswith(wallet_key, "[")
        wallet_key = "[" * wallet_key * "]"
    end
    
    payload = Dict("rpc"=>c.solana_rpc, "wallet"=>wallet_key, "proposalJson"=>proposal_json)
    return run_cli("proposal-post", payload)
end

end # module
