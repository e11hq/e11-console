// node:fs for E11 Talk's own code on Cloudflare: its "relay" folder held files sent the old way (through the office's
// disk). Here every file goes through R2, so that folder is empty and nothing is written to disk.
const no = () => { throw new Error('Files go through R2 here'); };
const fs = {
  mkdirSync() {}, rmSync() {}, existsSync: () => false, readdirSync: () => [],
  writeFileSync: no, appendFileSync: no, readFileSync: no, openSync: no, writeSync: no, closeSync() {}, statSync: no,
};
export default fs;
export const { mkdirSync, rmSync, existsSync, readdirSync, writeFileSync, appendFileSync, readFileSync, openSync, writeSync, closeSync, statSync } = fs;
