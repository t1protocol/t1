const fs = require('fs');
const path = require('path');
const glob = require('glob');

const newVersion = process.argv[2];
if (!newVersion) {
  console.error('Usage: node bump-version.js <new-version>');
  process.exit(1);
}

function updateJSONVersion(filePath) {
  const pkg = JSON.parse(fs.readFileSync(filePath));
  pkg.version = newVersion;
  fs.writeFileSync(filePath, JSON.stringify(pkg, null, 2) + '\n');
  console.log(`Updated ${filePath}`);
}

function updateCargoVersion(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const updated = content.replace(/version\s*=\s*"[^"]+"/, `version = "${newVersion}"`);
  fs.writeFileSync(filePath, updated);
  console.log(`Updated ${filePath}`);
}

// Bump all package.json
glob.sync('**/package.json', { ignore: ['**/node_modules/**'], cwd: path.resolve(__dirname, '..') })
  .map(f => path.resolve(__dirname, '..', f))
  .forEach(updateJSONVersion);

// Bump all Cargo.toml
glob.sync('**/Cargo.toml', { ignore: ['**/target/**'], cwd: path.resolve(__dirname, '..') })
  .map(f => path.resolve(__dirname, '..', f))
  .forEach(updateCargoVersion);