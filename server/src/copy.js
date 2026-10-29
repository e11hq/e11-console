// A plain read-and-write file copy, used instead of fs.copyFileSync. Node's copyFileSync uses the kernel's
// copy_file_range, which on some older kernels (the office NAS's among them) never finishes when the two files are on
// different disks — e.g. the container's /tmp and the NAS data folder — and spins the server at 100% CPU, so it stops
// answering (the App Review copy froze that way on 1.9.12). Same arguments as fs.copyFileSync (COPYFILE_EXCL honoured).
import fs from 'node:fs';

const CHUNK = 1 << 20;

export function copyFileSync(src, dest, mode = 0) {
  const excl = (mode & fs.constants.COPYFILE_EXCL) !== 0;
  const tmp = excl ? dest : `${dest}.copy-${process.pid}-${Date.now()}`;
  const from = fs.openSync(src, 'r');
  let to = null, made = false;
  try {
    to = fs.openSync(tmp, excl ? 'wx' : 'w'); made = true;
    const buf = Buffer.allocUnsafe(CHUNK);
    for (;;) {
      const n = fs.readSync(from, buf, 0, CHUNK, null);
      if (n <= 0) break;
      let off = 0;
      while (off < n) off += fs.writeSync(to, buf, off, n - off);
    }
    fs.closeSync(to); to = null;
    if (!excl) fs.renameSync(tmp, dest);
  } catch (e) {
    if (to != null) try { fs.closeSync(to); } catch { /* ignore */ }
    if (made) try { fs.rmSync(tmp, { force: true }); } catch { /* ignore */ }
    throw e;
  } finally {
    fs.closeSync(from);
  }
}
