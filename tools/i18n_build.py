#!/usr/bin/env python3
"""Merge data/i18n/src/*.json ({english: [es, fr, ar, de, zh_CN, ja]}) into one catalog per
language (data/i18n/<locale>.json), checking that every %-placeholder survives in order.
Run after editing translations:  python3 tools/i18n_build.py"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALES = ["es", "fr", "ar", "de", "zh_CN", "ja"]
PH = re.compile(r"%[-+0-9.]*[sdf]")

src = {}
for f in sorted(os.listdir(os.path.join(ROOT, "data/i18n/src"))):
    if f.endswith(".json"):
        src.update(json.load(open(os.path.join(ROOT, "data/i18n/src", f), encoding="utf-8")))
bad = 0
for k, v in src.items():
    want = PH.findall(k)
    for loc, t in zip(LOCALES, v):
        if PH.findall(t) != want:
            print("placeholder mismatch [%s] %r -> %r" % (loc, k, t)); bad += 1
        if k.count("{") != t.count("{") or k.count("[b]") != t.count("[b]"):
            print("markup mismatch [%s] %r -> %r" % (loc, k, t)); bad += 1
keys = json.load(open(os.path.join(ROOT, "data/i18n/_source.json"), encoding="utf-8"))
missing = [k for k in keys if k not in src]
for i, loc in enumerate(LOCALES):
    out = {k: v[i] for k, v in src.items()}
    json.dump(out, open(os.path.join(ROOT, "data/i18n/%s.json" % loc), "w", encoding="utf-8"), ensure_ascii=False, indent=0, sort_keys=True)
print("%d translated strings, %d untranslated source strings, %d problems" % (len(src), len(missing), bad))
for k in missing:
    print("  untranslated:", repr(k))
sys.exit(1 if bad else 0)
