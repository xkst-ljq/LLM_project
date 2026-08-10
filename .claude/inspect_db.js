const fs = require('fs');
const p = process.argv[2];
const buf = fs.readFileSync(p);
const text = buf.toString('latin1');
const paths = [];
const re = /card_image_path/gi;
let m;
while ((m = re.exec(text)) && paths.length < 10) {
  paths.push(text.substr(m.index, 120).replace(/[^\x20-\x7e一-鿿]/g, '.'));
}
console.log('card_image_path refs found:', paths.length);
paths.forEach(x => console.log('  ' + x));
// Also look for character names (known: Mira, Lume, Riven)
for (const name of ['Mira', 'Lume', 'Riven', 'Noct']) {
  const idx = text.indexOf(name);
  console.log(name + ' at byte offset:', idx);
}
