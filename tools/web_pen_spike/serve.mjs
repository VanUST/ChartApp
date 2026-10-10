// PURPOSE: Serve the web pen spike over HTTP so a tablet and a phone on this network can open it,
//          because a real Safari or Chrome on real hardware is the only thing that can answer what
//          a browser delivers for a stylus. `file://` would not do: some pointer behaviour differs
//          by context, and a phone cannot open a file on this machine at all.
//
//          Read-only, one directory, no directory traversal, no writes, no user data. It exists to
//          answer a measurement question and is not a server the product will ever use.
// INPUTS: A port (default 8777), optionally a bind address (default 0.0.0.0 so both the LAN and an
//         `adb reverse` forward reach it), and optionally a directory to serve (default: this
//         script's own directory). The directory argument exists so the same server can serve the
//         built application without a second copy of this file.
// OUTPUTS: One HTTP response per request, and one line per request on stdout so a connection from
//          the tablet or the phone is visible rather than assumed.
// KEYWORDS: spike, static-server, read-only, measurement, web-pen
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const port = Number(process.argv[2] ?? 8777);
const host = process.argv[3] ?? '0.0.0.0';
const root = process.argv[4]
  ? resolve(process.argv[4])
  : resolve(fileURLToPath(new URL('.', import.meta.url)));

const types = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
]);

createServer(async (request, response) => {
  // A path that escapes the directory is refused rather than normalised into something servable.
  const requested = decodeURIComponent(new URL(request.url, 'http://x').pathname);
  const relative = normalize(requested === '/' ? 'index.html' : requested.slice(1));
  const target = join(root, relative);
  if (!target.startsWith(root)) {
    response.writeHead(403).end('forbidden');
    console.log(`403 ${requested}`);
    return;
  }
  try {
    const body = await readFile(target);
    response.writeHead(200, {
      'content-type': types.get(extname(target)) ?? 'application/octet-stream',
      // The spike is edited while a device has it open, so nothing may be cached.
      'cache-control': 'no-store',
    });
    response.end(body);
    console.log(`200 ${requested} ${body.length} bytes  from ${request.socket.remoteAddress}`);
  } catch {
    response.writeHead(404).end('not found');
    console.log(`404 ${requested}`);
  }
}).listen(port, host, () => {
  console.log(`serving ${root} on http://${host}:${port}`);
  console.log(`tablet over USB:  adb reverse tcp:${port} tcp:${port}  then open http://localhost:${port}`);
});
