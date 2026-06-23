#!/usr/bin/env node
// Build assets/unit1/unit1_eng.json + assets/unit1/img/* from the standalone
// Unit1_Monitoring_15_Variants.html (offline guest English test, Grade 1).
//
// Source HTML defines three JS object literals:
//   const IMGS = { "<file>.jpg": "data:image/...;base64,...", ... }   (25 vocab)
//   const READING_IMGS = { "1": "data:...base64,...", ... }          (15 reading scenes)
//   const VARIANTS = { 1:{ vocabQ:[{img,q,opts,ans}], grammar:[{q,opts,ans}],
//                          spelling:[{sc,ans}], sentences:[{w,ans}],
//                          reading:{title,text,questions:[{type,q,opts?,ans}]} }, ... }
//
// Output schema (consumed by the Flutter Unit1 guest runner):
//   { test_key, grade, title, parts, variants:{ "1":{ vocab, grammar, spelling, sentences, reading } } }

const fs = require('fs');
const path = require('path');

const HTML = process.argv[2] || '/Users/max/Downloads/Unit1_Monitoring_15_Variants.html';
const REPO = path.resolve(__dirname, '..');
const OUT_JSON = path.join(REPO, 'assets/unit1/unit1_eng.json');
const OUT_IMGDIR = path.join(REPO, 'assets/unit1/img');

// --- balanced-brace literal extractor ---------------------------------------
function extractLiteral(txt, marker) {
  const at = txt.indexOf(marker);
  if (at < 0) throw new Error(`marker not found: ${marker}`);
  const open = txt.indexOf('{', at);
  let depth = 0, inStr = false, esc = false, quote = '';
  for (let i = open; i < txt.length; i++) {
    const c = txt[i];
    if (inStr) {
      if (esc) { esc = false; continue; }
      if (c === '\\') { esc = true; continue; }
      if (c === quote) inStr = false;
      continue;
    }
    if (c === '"' || c === "'") { inStr = true; quote = c; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return txt.slice(open, i + 1); }
  }
  throw new Error(`unbalanced braces for ${marker}`);
}

function evalObj(literal) {
  // JS object literals (unquoted keys, integer keys) — eval in a wrapper.
  // eslint-disable-next-line no-eval
  return eval('(' + literal + ')');
}

function writeDataUri(dataUri, destPath) {
  const m = /^data:[^;]+;base64,(.*)$/s.exec(dataUri);
  if (!m) throw new Error('not a base64 data URI');
  fs.writeFileSync(destPath, Buffer.from(m[1], 'base64'));
}

// --- main -------------------------------------------------------------------
console.log('Reading', HTML);
const txt = fs.readFileSync(HTML, 'utf8');

const IMGS = evalObj(extractLiteral(txt, 'const IMGS'));
const READING_IMGS = evalObj(extractLiteral(txt, 'const READING_IMGS'));
const VARIANTS = evalObj(extractLiteral(txt, 'const VARIANTS'));

const vocabKeys = Object.keys(IMGS);
const readingKeys = Object.keys(READING_IMGS);
const variantKeys = Object.keys(VARIANTS).sort((a, b) => +a - +b);
console.log(`IMGS=${vocabKeys.length} READING_IMGS=${readingKeys.length} VARIANTS=${variantKeys.length}`);

fs.mkdirSync(OUT_IMGDIR, { recursive: true });

// vocab images (keep original filenames, referenced by vocab[].img)
for (const fname of vocabKeys) writeDataUri(IMGS[fname], path.join(OUT_IMGDIR, fname));
// reading scenes -> reading_v<N>.jpg
for (const vk of readingKeys) writeDataUri(READING_IMGS[vk], path.join(OUT_IMGDIR, `reading_v${vk}.jpg`));

const variants = {};
for (const vk of variantKeys) {
  const v = VARIANTS[vk];
  const vocab = v.vocabQ.map(q => ({ img: q.img, q: q.q, opts: q.opts, ans: q.ans }));
  const grammar = v.grammar.map(q => ({ q: q.q, opts: q.opts, ans: q.ans }));
  const spelling = v.spelling.map(q => ({ scramble: q.sc, ans: q.ans }));
  const sentences = v.sentences.map(q => ({ words: q.w, ans: q.ans }));
  const r = v.reading;
  const reading = {
    img: `reading_v${vk}.jpg`,
    title: r.title,
    text: r.text,
    qs: r.questions.map(q => {
      const o = { type: q.type, q: q.q, ans: q.ans };
      if (q.opts) o.opts = q.opts;
      return o;
    }),
  };
  variants[vk] = { vocab, grammar, spelling, sentences, reading };
}

const out = {
  test_key: 'unit1_eng',
  grade: 1,
  title: '1-sinf Ingliz tili — Unit 1',
  parts: ['Vocabulary', 'Grammar', 'Spelling', 'Sentences', 'Reading'],
  variants,
};

fs.writeFileSync(OUT_JSON, JSON.stringify(out));
console.log('Wrote', OUT_JSON, `(${(fs.statSync(OUT_JSON).size / 1024).toFixed(0)} KB)`);

// --- validation -------------------------------------------------------------
let ok = true;
for (const vk of variantKeys) {
  const v = variants[vk];
  const counts = [v.vocab.length, v.grammar.length, v.spelling.length, v.sentences.length, v.reading.qs.length];
  const [vc, gc, sc, snc, rc] = counts;
  const total = vc + gc + sc + snc + rc;
  const bad = vc !== 25 || gc !== 6 || sc !== 6 || snc !== 6 || rc !== 6;
  if (bad) { ok = false; console.log(`  ⚠ v${vk}: vocab=${vc} grammar=${gc} spelling=${sc} sentences=${snc} reading=${rc} total=${total}`); }
}
console.log(ok ? '✅ all 15 variants: 25+6+6+6+6 = 49' : '❌ count mismatch (see above)');
console.log(`Images written: ${fs.readdirSync(OUT_IMGDIR).length} files`);
