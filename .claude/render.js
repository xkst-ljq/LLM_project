// Usage: node render.js <png> <cols> <rows> <density>
const fs = require('fs');
const zlib = require('zlib');
function decodePNG(buf) {
  let pos = 8, w = 0, h = 0, ct = 0, idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos), type = buf.toString('ascii', pos + 4, pos + 8);
    if (type === 'IHDR') { w = buf.readUInt32BE(pos + 8); h = buf.readUInt32BE(pos + 12); ct = buf[pos + 17]; }
    if (type === 'IDAT') idat.push(buf.subarray(pos + 8, pos + 8 + len));
    if (type === 'IEND') break;
    pos += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const bpp = ct === 6 ? 4 : 3, stride = w * bpp;
  const out = Buffer.alloc(h * stride); let rp = 0;
  for (let y = 0; y < h; y++) {
    const ft = raw[rp++], curRaw = raw.subarray(rp, rp + stride); rp += stride;
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride);
    const cur = Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      let a = x - bpp >= 0 ? cur[x - bpp] : 0, b = prev[x], c = x - bpp >= 0 ? prev[x - bpp] : 0, v = curRaw[x];
      switch (ft) {
        case 0: break;
        case 1: v = (v + a) & 255; break;
        case 2: v = (v + b) & 255; break;
        case 3: v = (v + ((a + b) >> 1)) & 255; break;
        case 4: { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v = (v + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 255; break; }
      }
      cur[x] = v;
    }
    cur.copy(out, y * stride);
  }
  return { w, h, bpp, out };
}
function render(f, cols, rows, scale) {
  const { w, h, bpp, out } = decodePNG(fs.readFileSync(f));
  function px(x, y) { const i = (y * w + x) * bpp; return [out[i], out[i + 1], out[i + 2]]; }
  const ramp = ' .:-=+*#%@';
  function hue(r, g, b, lum) {
    const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
    let hh = -1;
    if (d > 8) {
      if (max === r) hh = ((g - b) / d) % 6; else if (max === g) hh = (b - r) / d + 2; else hh = (r - g) / d + 4;
      hh = ((hh + 6) % 6) / 6;
    }
    const sat = max > 0 ? d / max : 0;
    if (lum < 0.16) return '.';
    if (lum > 0.78 && sat < 0.2) return ' ';
    if (sat < 0.14) return '.';
    if (hh < 0.1 || hh > 0.93) return 'O'; if (hh < 0.2) return 'Y'; if (hh < 0.42) return 'T'; if (hh < 0.58) return 'G'; if (hh < 0.78) return 'P'; return 'M';
  }
  const W = w / scale, H = h / scale;
  const cellW = W / cols, cellH = H / rows;
  let lines = [];
  for (let r = 0; r < rows; r++) {
    let line = '';
    for (let c = 0; c < cols; c++) {
      const cx = Math.min(w - 1, Math.round((c + 0.5) * cellW * scale));
      const cy = Math.min(h - 1, Math.round((r + 0.5) * cellH * scale));
      const [R, G, B] = px(cx, cy);
      const lum = (0.2126 * R + 0.7152 * G + 0.0722 * B) / 255;
      const ch = hue(R, G, B, lum);
      line += (ch === ' ' || ch === '.') ? ramp[Math.min(9, Math.floor(lum * 10))] : ch;
    }
    lines.push(line);
  }
  return lines.join('\n');
}
console.log(render(process.argv[2], parseInt(process.argv[3]), parseInt(process.argv[4]), parseFloat(process.argv[5])));
