#!/usr/bin/env node

async function readStdinJSON() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const str = Buffer.concat(chunks).toString("utf-8");
  console.error("STDIN LENGTH:", str.length);
  console.error("STDIN FIRST 100:", str.substring(0, 100));
  return JSON.parse(str);
}

async function main() {
  try {
    const input = await readStdinJSON();
    console.error("INPUT:", input);
    const output = {success: true, input};
    process.stdout.write(JSON.stringify(output));
  } catch (e) {
    console.error("ERROR:", e);
    process.exit(1);
  }
}

main();
