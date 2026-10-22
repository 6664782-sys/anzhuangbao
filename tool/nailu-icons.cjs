const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const logo = fs.readFileSync(path.join(root, 'assets/images/nailu.svg'), 'utf8');
const paths = [...logo.matchAll(/<path[^>]+d="([^"]+)"[^>]*\/>/g)].map(m => m[1]);
const glyph = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 360"><g fill="none" stroke="#b8eed7" stroke-width="12" stroke-linecap="round" stroke-linejoin="round">${paths.slice(0, 2).map(d => `<path d="${d}"/>`).join('')}</g></svg>`;
function write(file, bytes) { const target = path.join(root, file); fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, bytes); }
async function png(svg, size) { return sharp(Buffer.from(svg)).resize(size, size).png().toBuffer(); }
async function ico(svg, sizes) {
  const images = await Promise.all(sizes.map(n => png(svg, n)));
  const header = Buffer.alloc(6 + 16 * sizes.length); header.writeUInt16LE(1, 2); header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  sizes.forEach((n, i) => { const p = 6 + i * 16; header[p] = header[p+1] = n === 256 ? 0 : n; header.writeUInt16LE(1, p+4); header.writeUInt16LE(32, p+6); header.writeUInt32LE(images[i].length, p+8); header.writeUInt32LE(offset, p+12); offset += images[i].length; });
  return Buffer.concat([header, ...images]);
}
async function main() {
  write('assets/images/icon.png', await png(logo, 1024));
  write('windows/runner/resources/app_icon.ico', await ico(logo, [16,20,24,32,40,48,64,96,128,256]));
  const macDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
  const contents = JSON.parse(fs.readFileSync(path.join(root, macDir, 'Contents.json')));
  for (const image of contents.images) { const n = Number(image.size.split('x')[0]) * Number(image.scale.slice(0,-1)); write(`${macDir}/${image.filename}`, await png(logo, n)); }
  const densities = {mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192};
  for (const [density, n] of Object.entries(densities)) {
    const webp = await sharp(Buffer.from(logo)).resize(n,n).webp({lossless:true}).toBuffer();
    for (const filename of ['ic_launcher.webp','ic_launcher_round.webp']) {
      write(`android/app/src/main/res/mipmap-${density}/${filename}`, webp);
      const tv = `android/app/src/main/res/mipmap-television-${density}/${filename}`;
      if (fs.existsSync(path.join(root, tv))) write(tv, webp);
    }
  }
  const banner = `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="180"><rect width="320" height="180" fill="#112b31"/><g transform="translate(30 26) scale(.35)">${logo.replace(/<svg[^>]*>|<\/svg>/g,'')}</g><text x="173" y="103" fill="#b8eed7" font-size="36" font-family="sans-serif">NaiLu</text></svg>`;
  write('android/app/src/main/res/mipmap-xhdpi/ic_banner.png', await sharp(Buffer.from(banner)).png().toBuffer());
  const vector = `<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="540" android:viewportHeight="540"><group android:translateX="90" android:translateY="90">${paths.slice(0,2).map(d=>`<path android:fillColor="@android:color/transparent" android:strokeColor="#b8eed7" android:strokeWidth="10" android:strokeLineCap="round" android:strokeLineJoin="round" android:pathData="${d}"/>`).join('')}</group></vector>`;
  write('android/app/src/main/res/drawable/ic_launcher_foreground.xml', vector);
  const notification = vector.replaceAll('540', '360').replace('android:translateX="90" android:translateY="90"', '').replaceAll('#b8eed7', '#FFFFFF').replace('108dp', '24dp').replace('108dp', '24dp');
  write('android/service/src/main/res/drawable/ic.xml', notification);
  write('android/service/src/main/res/drawable/ic_service.xml', notification);
  write('assets_source/images/icon/glyph.svg', glyph);
  const colors = ['#b8eed7','#8aa09c','#e5b663','#e68080'];
  for (let i = 1; i <= 4; i++) {
    const source = glyph.replace('#b8eed7', colors[i-1]);
    write(`assets_source/images/icon/status_${i}.svg`, source);
    write(`assets/images/tray/windows/status_${i}.ico`, await ico(source, [16,20,24,32,40,48,64]));
    for (let scale = 1; scale <= 4; scale++) {
      const suffix = scale === 1 ? '' : `${scale}.0x/`;
      write(`assets/images/tray/unix/${suffix}status_${i}.png`, await png(source,18*scale));
      if (i === 1 || i === 4) write(`assets/images/tray/macos/${suffix}status_${i}.png`, await png(source.replace(/#[a-f0-9]{6}/gi, '#000000'),18*scale));
    }
  }
  console.log('NaiLu launcher, notification and tray assets generated.');
}
main().catch(e=>{ console.error(e); process.exitCode=1; });
