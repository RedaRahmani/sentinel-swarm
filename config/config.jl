module Config

struct AppConfig
    llm_provider::String
    openai_key::Union{Nothing,String}
    openai_model::String
    solana_rpc::String
    keypair_json::String
    realms_realm::String
    realms_gov::String
end

function load_env()
    AppConfig(
        get(ENV,"LLM_PROVIDER","openai"),
        haskey(ENV,"OPENAI_API_KEY") ? ENV["OPENAI_API_KEY"] : nothing,
        get(ENV,"OPENAI_MODEL","gpt-4o-mini"),
        get(ENV,"SOLANA_RPC_URL","https://api.devnet.solana.com"),
        get(ENV,"SOLANA_WALLET_PRIVATE_KEY",""),
        get(ENV,"REALMS_REALM_PUBKEY",""),
        get(ENV,"REALMS_GOVERNANCE_PUBKEY","")
    )
end

const _CFG = load_env()
cfg() = _CFG

end # module
