// Usage: node shotviz.js <png> <cols> <rows> [startY_frac] [endY_frac]
// Renders a region of the screenshot as ASCII: brightness -> chars, hue -> letter class.
const fs = require('fs');
const zlib = require('zlib');

function decodePNG(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not png');
  let pos = 8, width = 0, height = 0, colorType = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('ascii', pos + 4, pos + 8);
    if (type === 'IHDR') { width = buf.readUInt32BE(pos + 8); height = buf.readUInt32BE(pos + 12); colorType = buf[pos + 17]; }
    if (type === 'IDAT') idat.push(buf.subarray(pos + 8, pos + 8 + len));
    if (type === 'IEND') break;
    pos += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const bpp = colorType === 6 ? 4 : 3;
  const stride = width * bpp;
  const out = Buffer.alloc(height * stride);
  let rpos = 0;
  for (let y = 0; y < height; y++) {
    const ft = raw[rpos++];
    const curRaw = raw.subarray(rpos, rpos + stride); rpos += stride;
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride);
    const cur = Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      let a = x - bpp >= 0 ? cur[x - bpp] : 0;
      let b = prev[x];
      let c = x - bpp >= 0 ? prev[x - bpp] : 0;
      let v = curRaw[x];
      switch (ft) {
        case 0: break;
        case 1: v = (v + a) & 255; break;
        case 2: v = (v + b) & 255; break;
        case 3: v = (v + ((a + b) >> 1)) & 255; break;
        case 4: {
          const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
          v = (v + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 255; break;
        }
      }
      cur[x] = v;
    }
    cur.copy(out, y * stride);
  }
  return { width, height, bpp, out };
}

const file = process.argv[2];
const cols = parseInt(process.argv[3], 10);
const rows = parseInt(process.argv[4], 10);
const startY = process.argv[5] ? parseFloat(process.argv[5]) : 0;
const endY = process.argv[6] ? parseFloat(process.argv[6]) : 1;
const { width, height, bpp, out } = decodePNG(fs.readFileSync(file));

function px(x, y) {
  const i = (y * width + x) * bpp;
  return [out[i], out[i + 1], out[i + 2]];
}

// Brightness ramp
const ramp = ' .:-=+*#%@';
function brightChar(v) {
  const i = Math.min(9, Math.floor(v * 10));
  return ramp[i];
}

// Hue classifier: map to a letter. Used to distinguish hue regions.
function hueChar(r, g, b, lum) {
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  const d = max - min;
  let h = 0;
  if (d > 8) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h = (h + 6) % 6 / 6;
  } else h = -1;
  const sat = max > 0 ? d / max : 0;
  // Very dark -> '.' regardless of hue (night background, shadows).
  if (lum < 0.16) return '.';
  if (lum > 0.78 && sat < 0.2) return ' ';     // near-white background
  if (sat < 0.14) return '.';                  // grey
  if (h < 0.1 || h > 0.93) return 'O';         // red/orange
  if (h < 0.2) return 'Y';                     // yellow/gold
  if (h < 0.42) return 'T';                    // green/teal
  if (h < 0.58) return 'G';                    // cyan/blue
  if (h < 0.78) return 'P';                    // indigo/violet
  return 'M';                                  // magenta/pink
}

const y0 = Math.floor(height * startY);
const y1 = Math.floor(height * endY);
const cellH = (y1 - y0) / rows;
const cellW = width / cols;
let outLines = [];
for (let r = 0; r < rows; r++) {
  let line = '';
  for (let c = 0; c < cols; c++) {
    const cx = Math.min(width - 1, Math.floor((c + 0.5) * cellW));
    const cy = Math.min(y1 - 1, Math.floor(y0 + (r + 0.5) * cellH));
    const [R, G, B] = px(cx, cy);
    const lum = (0.2126 * R + 0.7152 * G + 0.0722 * B) / 255;
    const ch = hueChar(R, G, B, lum);
    if (ch === ' ' || ch === '.') line += brightChar(lum);
    else line += ch;
  }
  outLines.push(line);
}
console.log(outLines.join('\n'));
