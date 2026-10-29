#!/usr/bin/env node
// Rasterize the editable fork icon into the sizes declared by the Xcode catalog.
// Requires sharp; NODE_PATH may point to an existing installation.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

async function main() {
  const root = path.resolve(__dirname, '..');
  const source = path.join(root, 'design', 'jmin-dev-icon.svg');
  const directory = path.join(root, 'Assets.xcassets', 'AppIcon-Debug.appiconset');
  const catalog = JSON.parse(await fs.readFile(path.join(directory, 'Contents.json'), 'utf8'));
  for (const entry of catalog.images) {
    const pixels = Number(entry.size.split('x')[0]) * Number(entry.scale.replace('x', ''));
    await sharp(source, { density: 288 }).resize(pixels, pixels).png()
      .toFile(path.join(directory, entry.filename));
  }
  console.log(`Rendered ${catalog.images.length} development icon sizes.`);
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
