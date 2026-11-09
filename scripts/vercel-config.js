// Vercel build step. Vercel can't run the game server (it needs a long-lived
// WebSocket process), so it only hosts the static page and points it at the
// real server, e.g. on Render, via the SLIDEIT_SERVER environment variable.
import { writeFileSync } from 'node:fs';

const raw = (process.env.SLIDEIT_SERVER || '').trim().replace(/\/+$/, '');
let url;
try {
  url = new URL(raw);
} catch {}
if (!url || !/^https?:$/.test(url.protocol)) {
  console.error(
    '\nSLIDEIT_SERVER is missing or invalid (got "' + raw + '").\n' +
      'In Vercel: Project → Settings → Environment Variables, add\n' +
      '  SLIDEIT_SERVER = https://<your-app>.onrender.com\n' +
      'then redeploy.\n',
  );
  process.exit(1);
}
const origin = url.origin;
writeFileSync(
  new URL('../public/config.js', import.meta.url),
  `// Written by scripts/vercel-config.js at build time.\nwindow.SLIDEIT_SERVER = ${JSON.stringify(origin)};\n`,
);
console.log(`Slide It: game server set to ${origin}`);
