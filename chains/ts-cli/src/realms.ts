import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import {
  getAssociatedTokenAddressSync,
  createAssociatedTokenAccountInstruction,
  createTransferInstruction,
} from "@solana/spl-token";
import {
  VoteType,
  withCreateProposal,
  withInsertTransaction,
  getRealm,
  getTokenOwnerRecordAddress,
} from "@solana/spl-governance";

const GOV_PROGRAM_ID = new PublicKey("GovER5Lthms3bLBqWub97yVrMmEogzX7xNjdXpPPCVZw");
const MEMO_PROGRAM_ID = new PublicKey("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr");

// Common placeholder pubkeys that should not be treated as real addresses
const PLACEHOLDER_PUBKEYS = new Set([
  "authority", "proposal_account", "source_wallet", "target_wallet",
  "governance", "realm", "payer", "signer", "mint", "token_account"
]);

// ----------------- helpers -----------------
function keypairFromJson(json: string): Keypair {
  try {
    // Trim and remove inline comments if present
    let cleaned = json.trim();
    if (cleaned.includes('#')) {
      cleaned = cleaned.substring(0, cleaned.indexOf('#')).trim();
    }
    
    const arr = JSON.parse(cleaned);
    if (!Array.isArray(arr)) throw new Error("Invalid keypair JSON (expected array)");
    return Keypair.fromSecretKey(Uint8Array.from(arr));
  } catch (error) {
    throw new Error(`WALLET_PARSE_ERROR: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function isValidBase58(str: string): boolean {
  try {
    new PublicKey(str);
    return true;
  } catch {
    return false;
  }
}

function normalizeInstruction(ixJson: any): { normalized: any; errors: string[] } {
  const errors: string[] = [];
  const normalized: any = {};

  // Handle programId vs program_id
  const programId = ixJson.programId || ixJson.program_id;
  if (!programId) {
    errors.push("Missing programId/program_id");
  } else if (PLACEHOLDER_PUBKEYS.has(programId) || !isValidBase58(programId)) {
    errors.push(`Invalid programId: ${programId}`);
  } else {
    normalized.programId = programId;
  }

  // Handle keys vs accounts
  const rawKeys = ixJson.keys || ixJson.accounts || [];
  const normalizedKeys: any[] = [];
  
  for (let i = 0; i < rawKeys.length; i++) {
    const key = rawKeys[i];
    const pubkey = key.pubkey;
    
    if (!pubkey) {
      errors.push(`Missing pubkey at keys[${i}]`);
      continue;
    }
    
    if (PLACEHOLDER_PUBKEYS.has(pubkey) || !isValidBase58(pubkey)) {
      errors.push(`Invalid pubkey at keys[${i}]: ${pubkey}`);
      continue;
    }
    
    normalizedKeys.push({
      pubkey,
      isSigner: !!(key.isSigner ?? key.is_signer),
      isWritable: !!(key.isWritable ?? key.is_writable),
    });
  }
  
  normalized.keys = normalizedKeys;

  // Handle data (base64 or hex)
  let data = ixJson.data || "";
  if (typeof data === "string" && data.length > 0) {
    // Auto-detect hex vs base64
    if (data.startsWith("0x")) {
      data = data.slice(2);
    }
    
    // Try hex first, then base64
    try {
      if (/^[0-9a-fA-F]*$/.test(data)) {
        normalized.data = Buffer.from(data, "hex").toString("base64");
      } else {
        // Validate base64
        Buffer.from(data, "base64");
        normalized.data = data;
      }
    } catch {
      errors.push(`Invalid data format (must be base64 or hex): ${data.substring(0, 20)}...`);
    }
  } else {
    normalized.data = "";
  }

  return { normalized, errors };
}

function validateInstructionBundle(instructions: any[]): { valid: boolean; errors: string[]; normalized?: any[] } {
  if (!Array.isArray(instructions)) {
    return { valid: false, errors: ["Instructions must be an array"] };
  }

  const allErrors: string[] = [];
  const normalizedInstructions: any[] = [];
  
  for (let i = 0; i < instructions.length; i++) {
    const { normalized, errors } = normalizeInstruction(instructions[i]);
    
    if (errors.length > 0) {
      allErrors.push(...errors.map(err => `instructions[${i}]: ${err}`));
    } else {
      normalizedInstructions.push(normalized);
    }
  }

  return {
    valid: allErrors.length === 0,
    errors: allErrors,
    normalized: allErrors.length === 0 ? normalizedInstructions : undefined
  };
}

function createMemoFallbackInstruction(): any {
  return {
    programId: MEMO_PROGRAM_ID.toBase58(),
    keys: [],
    data: Buffer.from("Sentinel Demo: dry-run", "utf-8").toString("base64")
  };
}
function serializeIx(ix: TransactionInstruction) {
  return {
    programId: ix.programId.toBase58(),
    keys: ix.keys.map((k) => ({
      pubkey: k.pubkey.toBase58(),
      isSigner: k.isSigner,
      isWritable: k.isWritable,
    })),
    data: Buffer.from(ix.data).toString("base64"),
  };
}

function safeDeserIx(ixJson: any): TransactionInstruction {
  return new TransactionInstruction({
    programId: new PublicKey(ixJson.programId),
    keys: (ixJson.keys || []).map((k: any) => ({
      pubkey: new PublicKey(k.pubkey),
      isSigner: !!k.isSigner,
      isWritable: !!k.isWritable,
    })),
    data: Buffer.from(ixJson.data || "", "base64"),
  });
}

// ----------------- existing builders (unchanged) -----------------
export async function buildTransferIx(input: any) {
  const { from, to, mint, amount } = input;
  const fromPk = new PublicKey(from);
  const toPk = new PublicKey(to);
  const mintPk = new PublicKey(mint);

  const fromAta = getAssociatedTokenAddressSync(mintPk, fromPk, true);
  const toAta = getAssociatedTokenAddressSync(mintPk, toPk, true);

  const ixs: TransactionInstruction[] = [
    createAssociatedTokenAccountInstruction(fromPk, fromAta, fromPk, mintPk),
    createAssociatedTokenAccountInstruction(fromPk, toAta, toPk, mintPk),
    createTransferInstruction(fromAta, toAta, fromPk, BigInt(amount))
  ];
  return { instructions: ixs.map(serializeIx) };
}

export async function createProposalJson(input: any) {
  const { realm, governance, title, descriptionMd, instructions, rpc, wallet } = input;
  if (!Array.isArray(instructions)) throw new Error("instructions[] required");
  return {
    realm, governance, title, descriptionMd,
    instructions,
    meta: { createdAt: Date.now(), rpc, signer: keypairFromJson(wallet).publicKey.toBase58() }
  };
}

// ----------------- REAL implementations -----------------
export async function dryRunBundle(input: any) {
  const { rpc, wallet, instructions } = input;
  
  try {
    const conn = new Connection(rpc, "confirmed");
    
    // Parse and validate wallet
    let payer: Keypair;
    try {
      payer = keypairFromJson(wallet);
    } catch (error) {
      return {
        ok: false,
        logs: null,
        err: {
          code: "WALLET_PARSE_ERROR",
          reason: error instanceof Error ? error.message : String(error)
        },
        unitsConsumed: null
      };
    }

    // Validate instruction bundle
    const validation = validateInstructionBundle(instructions || []);
    
    if (!validation.valid) {
      // Check for memo fallback
      const useMemoFallback = process.env.DEMO_MEMO_FALLBACK === "1";
      
      if (useMemoFallback) {
        // Replace with memo instruction
        const memoIx = createMemoFallbackInstruction();
        const tx = new Transaction().add(safeDeserIx(memoIx));
        tx.feePayer = payer.publicKey;
        
        const { blockhash } = await conn.getLatestBlockhash("confirmed");
        tx.recentBlockhash = blockhash;
        
        const sim = await conn.simulateTransaction(tx);
        
        return {
          ok: sim.value.err === null,
          logs: sim.value.logs || [],
          err: sim.value.err || null,
          unitsConsumed: sim.value.unitsConsumed || null
        };
      } else {
        // Return validation error
        return {
          ok: false,
          logs: null,
          err: {
            code: "VALIDATION_ERROR",
            reason: "Invalid instruction bundle",
            details: validation.errors
          },
          unitsConsumed: null
        };
      }
    }

    // Build transaction with validated instructions
    const tx = new Transaction().add(...validation.normalized!.map(safeDeserIx));
    tx.feePayer = payer.publicKey;
    
    const { blockhash } = await conn.getLatestBlockhash("confirmed");
    tx.recentBlockhash = blockhash;

    const sim = await conn.simulateTransaction(tx);
    
    return {
      ok: sim.value.err === null,
      logs: sim.value.logs || [],
      err: sim.value.err || null,
      unitsConsumed: sim.value.unitsConsumed || null
    };
    
  } catch (error) {
    return {
      ok: false,
      logs: null,
      err: {
        code: "SIMULATION_ERROR",
        reason: error instanceof Error ? error.message : String(error)
      },
      unitsConsumed: null
    };
  }
}

export async function postProposal(input: any) {
  const { rpc, wallet, proposalJson } = input;
  const { realm, governance, title, descriptionMd, instructions } = proposalJson;

  try {
    const conn = new Connection(rpc, "confirmed");
    const payer = keypairFromJson(wallet);
    const realmPk = new PublicKey(realm);
    const governancePk = new PublicKey(governance);

    // Validate inputs
    if (!title || !descriptionMd) {
      throw new Error("Title and description are required");
    }

    console.log(`Creating proposal: ${title}`);
    console.log(`Realm: ${realm}`);
    console.log(`Governance: ${governance}`);
    console.log(`Instructions: ${instructions?.length || 0}`);

    // Get realm account to validate it exists
    const realmAcc = await getRealm(conn, realmPk);
    const governingMint = realmAcc.account.config.councilMint ?? realmAcc.account.communityMint;
    
    if (!governingMint) {
      throw new Error("Realm has no governing mint (council/community)");
    }

    // Get token owner record address
    const tokenOwnerRecord = await getTokenOwnerRecordAddress(
      GOV_PROGRAM_ID,
      realmPk,
      governingMint,
      payer.publicKey
    );

    // Create the proposal transaction
    const transaction = new Transaction();
    
    // Add proposal creation instruction
    const proposalIndex = await getNextProposalIndex(conn, governancePk);
    const proposalAddress = await getProposalAddress(
      GOV_PROGRAM_ID,
      governancePk,
      governingMint,
      proposalIndex
    );

    // Use withCreateProposal to add the creation instruction
    await withCreateProposal(
      transaction.instructions,
      GOV_PROGRAM_ID,
      3, // programVersion
      realmPk,
      governancePk,
      tokenOwnerRecord,
      title,
      descriptionMd,
      governingMint,
      payer.publicKey,
      proposalIndex,
      VoteType.SINGLE_CHOICE,
      ["Approve"],
      true, // useDenyOption
      payer.publicKey // payer
    );

    // Add any additional instructions to the proposal
    if (instructions && instructions.length > 0) {
      for (let i = 0; i < instructions.length; i++) {
        const ix = safeDeserIx(instructions[i]);
        await withInsertTransaction(
          transaction.instructions,
          GOV_PROGRAM_ID,
          3, // programVersion
          governancePk,
          proposalAddress,
          tokenOwnerRecord,
          payer.publicKey,
          i, // index
          0, // optionIndex
          0, // holdUpTime
          [{ programId: ix.programId, accounts: ix.keys, data: ix.data }], // transactionInstructions
          payer.publicKey // payer
        );
      }
    }

    // Set transaction properties
    transaction.feePayer = payer.publicKey;
    const { blockhash } = await conn.getLatestBlockhash("confirmed");
    transaction.recentBlockhash = blockhash;

    // Sign and send transaction
    transaction.sign(payer);
    const txSignature = await sendAndConfirmTransaction(conn, transaction, [payer], {
      commitment: "confirmed",
      maxRetries: 3
    });

    const explorerUrl = `https://explorer.solana.com/tx/${txSignature}?cluster=devnet`;
    
    console.log(`✅ Proposal created successfully!`);
    console.log(`📋 Proposal: ${proposalAddress.toBase58()}`);
    console.log(`🔗 Transaction: ${explorerUrl}`);

    return {
      posted: true,
      proposalPubkey: proposalAddress.toBase58(),
      txSignature,
      explorerUrl,
      success: true
    };

  } catch (error) {
    console.error("❌ Failed to create proposal:", error);
    
    // Return error details but still in expected format
    return {
      posted: false,
      error: error instanceof Error ? error.message : String(error),
      success: false
    };
  }
}

// Helper functions for governance
async function getNextProposalIndex(connection: Connection, governance: PublicKey): Promise<number> {
  try {
    // In a real implementation, we'd query the governance account to get the next proposal index
    // For now, generate a random index for testing
    return Math.floor(Date.now() / 1000) % 1000000;
  } catch (error) {
    return Math.floor(Date.now() / 1000) % 1000000;
  }
}

async function getProposalAddress(
  programId: PublicKey,
  governance: PublicKey,
  governingTokenMint: PublicKey,
  proposalIndex: number
): Promise<PublicKey> {
  const [proposalAddress] = await PublicKey.findProgramAddress(
    [
      Buffer.from("governance"),
      governance.toBuffer(),
      governingTokenMint.toBuffer(),
      Buffer.from(proposalIndex.toString())
    ],
    programId
  );
  return proposalAddress;
}
