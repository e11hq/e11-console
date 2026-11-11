// The owner's standing code, as the hash the NAS keeps (OWNER_CODE_HASH) — run on your own computer:
//   node server/src/signin-hash.js
// It asks for the 4 digits (not shown as you type) and prints the line to paste into the NAS setting. The digits
// themselves are never kept anywhere.
import readline from 'node:readline';
import { hashSecret } from './signin.js';

const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
rl._writeToOutput = (s) => { if (s.includes('Owner code')) process.stdout.write(s); };
rl.question('Owner code (4 digits): ', (code) => {
  rl.close(); process.stdout.write('\n');
  if (!/^\d{4}$/.test(code.trim())) { console.error('It has to be 4 digits.'); process.exit(1); }
  console.log('OWNER_CODE_HASH=' + hashSecret(code.trim()));
});
