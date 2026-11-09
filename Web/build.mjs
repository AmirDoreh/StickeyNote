import { mkdir, cp, rm, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.dirname(fileURLToPath(import.meta.url));
const destination = path.join(root, 'dist');
const runtime = ['index.html','styles.css','app.js','links.js','core.js','cloud.js','cloud-archive.js','config.js','icon.svg','icon-192.png','icon-512.png','apple-touch-icon.png','manifest.json','service-worker.js','vendor'];
// Validate all inputs before replacing the generated output.
await Promise.all(runtime.map(file => stat(path.join(root,file))));
await rm(destination, {recursive:true,force:true});
await mkdir(destination, {recursive:true});
await Promise.all(runtime.map(file => cp(path.join(root,file),path.join(destination,file),{recursive:true})));
console.log(`Built ${runtime.length} runtime entries in ${destination}`);
