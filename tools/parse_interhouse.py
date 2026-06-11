#!/usr/bin/env python3
"""
Parser for Interhouse Grade 2 HTML test file.
Extracts JS variables, decodes base64 images, and generates canonical JSON.
"""

import re
import json
import base64
import html
import os
import sys

try:
    import json5
    HAS_JSON5 = True
except ImportError:
    HAS_JSON5 = False
    print("WARNING: json5 not available, using fallback parser", file=sys.stderr)

# ── Paths ──────────────────────────────────────────────────────────────────────
HTML_PATH = "/Users/max/Downloads/Interhouse_Grade2_Final.html"
OUT_DIR = "/Users/max/PycharmProjects/AlochiSchool/alochi-monitoring-flutter/assets/interhouse"
IMG_DIR = os.path.join(OUT_DIR, "img")
JSON_OUT = os.path.join(OUT_DIR, "interhouse_g2.json")

os.makedirs(IMG_DIR, exist_ok=True)


# ── Read HTML ──────────────────────────────────────────────────────────────────
print("Reading HTML file…")
with open(HTML_PATH, "r", encoding="utf-8") as f:
    raw = f.read()
print(f"  Read {len(raw):,} bytes")


# ── JS block extractor ─────────────────────────────────────────────────────────
def extract_js_block(source: str, var_name: str) -> str:
    """
    Extract the JS literal assigned to `var VAR_NAME = ...` by bracket-matching.
    Returns the raw JS literal string (object or array).
    """
    pattern = rf'var {re.escape(var_name)}\s*=\s*'
    m = re.search(pattern, source)
    if not m:
        raise ValueError(f"Could not find 'var {var_name}' in source")

    start = m.end()
    first_char = source[start]
    if first_char == '{':
        open_c, close_c = '{', '}'
    elif first_char == '[':
        open_c, close_c = '[', ']'
    else:
        raise ValueError(f"Unexpected first char '{first_char}' for var {var_name}")

    # Walk through source tracking bracket depth, skip strings
    depth = 0
    in_str = False
    str_char = None
    i = start
    while i < len(source):
        c = source[i]
        if in_str:
            if c == '\\':
                i += 2  # skip escaped char
                continue
            if c == str_char:
                in_str = False
        else:
            if c in ('"', "'"):
                in_str = True
                str_char = c
            elif c == open_c:
                depth += 1
            elif c == close_c:
                depth -= 1
                if depth == 0:
                    return source[start:i + 1]
        i += 1

    raise ValueError(f"Unmatched brackets for var {var_name}")


def preprocess_js(js_str: str) -> str:
    """
    Pre-process a JS literal so that json5 (and standard JSON) can parse it.
    Specifically handles bare numeric keys: {1: [...]} → {"1": [...]}
    """
    # Quote bare numeric keys:  `123:` → `"123":`
    # Must not match inside strings, so we do a simple pass (numbers at token boundaries)
    s = re.sub(r'(?<!["\d])(\d+)\s*:', r'"\1":', js_str)
    return s


def parse_js(js_str: str):
    """Parse JS object/array literal to Python."""
    processed = preprocess_js(js_str)
    if HAS_JSON5:
        # json5 handles unquoted string keys, trailing commas, etc.
        try:
            return json5.loads(processed)
        except Exception as e:
            print(f"  json5 parse error: {e}", file=sys.stderr)
    # Fallback: minimal manual conversion
    # Decode HTML entities
    s = html.unescape(processed)
    # Quote unquoted string keys  {word: → {"word":
    s = re.sub(r'(?<!["\w])(\b[a-zA-Z_]\w*\b)\s*:', r'"\1":', s)
    # JS booleans/null
    s = re.sub(r'\btrue\b', 'true', s)
    s = re.sub(r'\bfalse\b', 'false', s)
    s = re.sub(r'\bnull\b', 'null', s)
    return json.loads(s)


# ── Extract and decode IMGS ────────────────────────────────────────────────────
print("\nExtracting IMGS (vocab images)…")
imgs_block = extract_js_block(raw, "IMGS")

# Parse key list first (keys are short strings like "lamp")
img_keys = re.findall(r'"([^"]+)"\s*:', imgs_block)
print(f"  Found {len(img_keys)} image keys: {img_keys[:5]}…")

# Extract each image individually to avoid loading all base64 at once in memory
imgs_map = {}
for key in img_keys:
    # Match: "key":"data:image/...;base64,<data>"
    pat = rf'"{re.escape(key)}"\s*:\s*"data:image/[^;]+;base64,([^"]+)"'
    m = re.search(pat, imgs_block)
    if m:
        b64_data = m.group(1).strip()
        img_bytes = base64.b64decode(b64_data)
        fname = f"{key}.png"
        fpath = os.path.join(IMG_DIR, fname)
        with open(fpath, "wb") as f:
            f.write(img_bytes)
        imgs_map[key] = fname
        print(f"  Saved {fname} ({len(img_bytes):,} bytes)")
    else:
        print(f"  WARNING: no data found for IMGS key '{key}'", file=sys.stderr)

print(f"  Total vocab images saved: {len(imgs_map)}")


# ── Extract and decode RIMGS ───────────────────────────────────────────────────
print("\nExtracting RIMGS (reading passage images)…")
rimgs_block = extract_js_block(raw, "RIMGS")

rimg_keys = re.findall(r'"([^"]+)"\s*:', rimgs_block)
print(f"  Found {len(rimg_keys)} reading image keys: {rimg_keys}")

rimgs_map = {}
for key in rimg_keys:
    pat = rf'"{re.escape(key)}"\s*:\s*"data:image/[^;]+;base64,([^"]+)"'
    m = re.search(pat, rimgs_block)
    if m:
        b64_data = m.group(1).strip()
        img_bytes = base64.b64decode(b64_data)
        fname = f"{key}.png"
        fpath = os.path.join(IMG_DIR, fname)
        with open(fpath, "wb") as f:
            f.write(img_bytes)
        rimgs_map[key] = fname
        print(f"  Saved {fname} ({len(img_bytes):,} bytes)")
    else:
        print(f"  WARNING: no data found for RIMGS key '{key}'", file=sys.stderr)

print(f"  Total reading images saved: {len(rimgs_map)}")


# ── Extract VV ────────────────────────────────────────────────────────────────
print("\nExtracting VV (vocabulary variants)…")
vv_block = extract_js_block(raw, "VV")
VV = parse_js(vv_block)
# json5 may return int keys; normalise to str
VV = {str(k): v for k, v in VV.items()}
print(f"  Variants in VV: {sorted(VV.keys())}")


# ── Extract VA ────────────────────────────────────────────────────────────────
print("\nExtracting VA (grammar/spelling/reading/sentences)…")
va_block = extract_js_block(raw, "VA")
VA = parse_js(va_block)
VA = {str(k): v for k, v in VA.items()}
print(f"  Variants in VA: {sorted(VA.keys())}")


# ── Extract RD ────────────────────────────────────────────────────────────────
print("\nExtracting RD (reading passages)…")
rd_block = extract_js_block(raw, "RD")
RD = parse_js(rd_block)
RD = {str(k): v for k, v in RD.items()}
print(f"  Passages in RD: {sorted(RD.keys())}")


# ── Extract LV ────────────────────────────────────────────────────────────────
print("\nExtracting LV (level bands)…")
lv_block = extract_js_block(raw, "LV")
LV = parse_js(lv_block)
print(f"  Level bands: {len(LV)}")


# ── Build canonical JSON ───────────────────────────────────────────────────────
print("\nBuilding canonical JSON…")

def build_vocab(variant_vv):
    """Convert VV variant list to canonical vocab items."""
    result = []
    for item in variant_vv:
        img_key = item.get("img", "")
        fname = imgs_map.get(img_key, f"{img_key}.png")
        result.append({
            "type": "mc_img",
            "img": fname,
            "q": html.unescape(item.get("q", "")),
            "opts": [html.unescape(o) for o in item.get("opts", [])],
            "ans": item.get("ans", 0),
        })
    return result


def build_grammar(variant_va):
    """Convert VA grammar list to canonical items."""
    result = []
    for item in variant_va.get("grammar", []):
        result.append({
            "type": "mc",
            "q": html.unescape(item.get("q", "")),
            "opts": [html.unescape(o) for o in item.get("opts", [])],
            "ans": item.get("ans", 0),
        })
    return result


def build_spelling(variant_va):
    """Convert VA spelling list to canonical items."""
    result = []
    for item in variant_va.get("spelling", []):
        result.append({
            "type": "word",
            "scramble": html.unescape(item.get("sc", "")),
            "ans": html.unescape(item.get("ans", "")),
        })
    return result


def build_reading(variant_va):
    """Resolve reading passage for this variant."""
    rd_key = str(variant_va.get("reading", ""))
    passage = RD.get(rd_key, {})
    rimg_key = passage.get("img", "")
    img_fname = rimgs_map.get(rimg_key, f"{rimg_key}.png")

    qs = []
    for q in passage.get("qs", []):
        qtype = q.get("type", "mc")
        item = {"type": qtype, "q": html.unescape(q.get("q", ""))}
        if qtype == "mc":
            item["opts"] = [html.unescape(o) for o in q.get("opts", [])]
            item["ans"] = q.get("ans", 0)
        elif qtype == "yn":
            item["ans"] = q.get("ans", "YES")
        elif qtype == "fill":
            item["ans"] = html.unescape(q.get("ans", ""))
        qs.append(item)

    return {
        "img": img_fname,
        "title": html.unescape(passage.get("title", "")),
        "text": html.unescape(passage.get("text", "")),
        "qs": qs,
    }


def build_sentences(variant_va):
    """Convert VA sentences list to canonical items."""
    result = []
    for item in variant_va.get("sentences", []):
        result.append({
            "type": "sentence",
            "words": html.unescape(item.get("w", "")),
            "ans": html.unescape(item.get("ans", "")),
        })
    return result


def build_levels(lv_list):
    result = []
    for band in lv_list:
        result.append({
            "min": band.get("min", 0),
            "label": html.unescape(band.get("label", "")),
            "cambridge": html.unescape(band.get("camb", "")),
            "cefr": band.get("cefr", ""),
            "bg": band.get("bg", ""),
            "col": band.get("col", ""),
        })
    return result


# Assemble variants
variants = {}
all_variant_keys = sorted(set(VV.keys()) | set(VA.keys()), key=lambda x: int(x))
print(f"  Building variants: {all_variant_keys}")

for vk in all_variant_keys:
    vv_data = VV.get(vk, [])
    va_data = VA.get(vk, {})
    variants[vk] = {
        "vocab": build_vocab(vv_data),
        "grammar": build_grammar(va_data),
        "spelling": build_spelling(va_data),
        "reading": build_reading(va_data),
        "sentences": build_sentences(va_data),
    }

output = {
    "test_key": "interhouse_g2",
    "grade": 2,
    "parts": ["Vocabulary", "Grammar", "Spelling", "Reading", "Writing"],
    "scoring": {
        "shields_thresholds": [6, 5, 4, 3],
        "levels": build_levels(LV),
    },
    "variants": variants,
}


# ── Write JSON ─────────────────────────────────────────────────────────────────
print(f"\nWriting {JSON_OUT}…")
with open(JSON_OUT, "w", encoding="utf-8") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)
print(f"  Written ({os.path.getsize(JSON_OUT):,} bytes)")


# ── Verification summary ───────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("VERIFICATION SUMMARY")
print("=" * 60)

with open(JSON_OUT) as f:
    check = json.load(f)

print(f"test_key:      {check['test_key']}")
print(f"grade:         {check['grade']}")
print(f"variant count: {len(check['variants'])}")

for vk, vdata in sorted(check["variants"].items(), key=lambda x: int(x[0])):
    vocab_n = len(vdata["vocab"])
    gram_n = len(vdata["grammar"])
    spell_n = len(vdata["spelling"])
    read_qs = len(vdata["reading"]["qs"])
    sent_n = len(vdata["sentences"])
    status = "OK" if vocab_n == 6 and gram_n == 6 and spell_n == 6 and read_qs == 6 and sent_n == 6 else "MISMATCH"
    print(f"  variant {vk}: vocab={vocab_n} grammar={gram_n} spelling={spell_n} reading_qs={read_qs} sentences={sent_n}  [{status}]")

img_files = [f for f in os.listdir(IMG_DIR) if f.endswith(".png")]
print(f"\nImages in {IMG_DIR}:")
print(f"  Total: {len(img_files)} PNG files")
vocab_imgs = [f for f in img_files if not f.startswith("r")]
reading_imgs = [f for f in img_files if f.startswith("r") and f[1:3].isdigit()]
print(f"  Vocab images:   {len(vocab_imgs)}")
print(f"  Reading images: {len(reading_imgs)}")

print("\nDone.")
