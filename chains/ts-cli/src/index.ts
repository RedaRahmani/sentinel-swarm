#!/usr/bin/env node
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import {
  buildTransferIx,
  createProposalJson,
  dryRunBundle,
  postProposal
} from "./realms";

async function readStdinJSON<T = any>(): Promise<T> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  const jsonStr = Buffer.concat(chunks).toString("utf-8");
  
  // Only show debug if --verbose flag is present, --quiet is not default
  const verbose = process.argv.includes('--verbose');
  const quiet = process.argv.includes('--quiet') || !verbose; // quiet by default unless verbose
  
  if (verbose && !quiet) {
    console.error(`STDIN LENGTH: ${jsonStr.length}`);
    console.error(`STDIN FIRST 100: ${jsonStr.substring(0, 100)}`);
  }
  
  return JSON.parse(jsonStr);
}

function handleError(command: string, error: any, quiet: boolean = true) {
  if (!quiet) {
    console.error(`${command} error:`, error);
  }
  
  // Return structured error for certain error types
  if (error && typeof error === 'object' && error.code) {
    process.stdout.write(JSON.stringify({
      ok: false,
      err: error
    }));
  } else {
    // For backwards compatibility, exit with error code
    process.exit(1);
  }
}

yargs(hideBin(process.argv))
  .command("ix-transfer", "Build SPL transfer ix", (y) => y
    .option('verbose', { type: 'boolean', default: false })
    .option('quiet', { type: 'boolean', default: true }), 
    async (argv) => {
    try {
      const input = await readStdinJSON();
      const out = await buildTransferIx(input);
      process.stdout.write(JSON.stringify(out));
    } catch (e) {
      handleError("ix-transfer", e, argv.quiet);
    }
  })
  .command("proposal-create", "Create Realms proposal JSON", (y) => y
    .option('verbose', { type: 'boolean', default: false })
    .option('quiet', { type: 'boolean', default: true }), 
    async (argv) => {
    try {
      const input = await readStdinJSON();
      const out = await createProposalJson(input);
      process.stdout.write(JSON.stringify(out));
    } catch (e) {
      // For proposal-create, handle wallet parsing errors specially
      if (e instanceof Error && e.message.includes('WALLET_PARSE_ERROR')) {
        process.stdout.write(JSON.stringify({
          ok: false,
          err: {
            code: "WALLET_PARSE_ERROR",
            reason: e.message
          }
        }));
      } else {
        handleError("proposal-create", e, argv.quiet);
      }
    }
  })
  .command("dry-run", "Simulate a tx bundle", (y) => y
    .option('verbose', { type: 'boolean', default: false })
    .option('quiet', { type: 'boolean', default: true }), 
    async (argv) => {
    try {
      const input = await readStdinJSON();
      const out = await dryRunBundle(input);
      process.stdout.write(JSON.stringify(out));
    } catch (e) {
      // dry-run should always return structured output, never exit
      process.stdout.write(JSON.stringify({
        ok: false,
        logs: null,
        err: {
          code: "UNEXPECTED_ERROR",
          reason: e instanceof Error ? e.message : String(e)
        },
        unitsConsumed: null
      }));
    }
  })
  .command("proposal-post", "Post proposal to devnet", (y) => y
    .option('verbose', { type: 'boolean', default: false })
    .option('quiet', { type: 'boolean', default: true }), 
    async (argv) => {
    try {
      const input = await readStdinJSON();
      const out = await postProposal(input);
      process.stdout.write(JSON.stringify(out));
    } catch (e) {
      handleError("proposal-post", e, argv.quiet);
    }
  })
  .strictCommands()
  .demandCommand()
  .parse();
