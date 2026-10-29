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
  // The app and Dock plugin use these appearance images while running.
  const light = (await fs.readFile(source, 'utf8'))
    .replace(/  <g id="development-banner">[\s\S]*?<\/g>\n/, '');
  for (const [name, svg] of [
    ['AppIconLight', light],
    ['AppIconDark', light.replace('rx="44" fill="#fff"', 'rx="44" fill="#1c1c1e"')]
  ]) {
    await sharp(Buffer.from(svg), { density: 288 }).resize(1024, 1024).png()
      .toFile(path.join(root, 'Assets.xcassets', `${name}.imageset`, `${name}.png`));
  }
  console.log(`Rendered ${catalog.images.length} development sizes and two running-app appearance icons.`);
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
