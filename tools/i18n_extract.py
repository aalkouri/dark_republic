#!/usr/bin/env python3
"""List player-visible English strings (scripts + data JSON) -> data/i18n/_source.json.

Heuristics: a script literal counts as text when it contains a space-separated word or a
capitalised word and is not a path/identifier/key. Lines tagged `# no-i18n` are skipped.
Run:  python3 tools/i18n_extract.py
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_SCRIPTS = {"hero_model.gd", "roster_hero.gd", "ground_disc.gd", "i18n.gd"}
STR = re.compile(r'(?<![\w&^])"((?:[^"\\\n]|\\.)*)"')
DATA_KEYS = {"name", "desc", "description", "bio", "epithet", "title", "text",
             "label", "ribbon", "tagline", "lines", "hint", "flavor", "unlock_text", "req", "blurb", "short"}
SKIP_TEXT = {"Master", "SFX", "STRESS", "Sparks", "Beam", "Zone", "Crystal", "+N", "Head", "Spine",
             "% of max HP", "%s_count", "%s_damage", "%s_pierce", "Pip%d", "zh_CN", "v0.1  ·  AtomAI",
             " (weapon)", "(weapon)", "Weapon: ", "Defeat ", "Learn a", "Unlocks", "Unlocks at level",
             "English", "Español", "Français", "Deutsch"}
# Built at runtime from pieces the scan can't see
EXTRA = ["%d s", "%d m", "%.1f / %d s", "%s  ·  %.1f / %d s", "Weapon", "Tome", "Item"]

def is_text(s: str, line: str) -> bool:
    if len(s) < 2 or not re.search(r"[A-Za-z]", s):
        return False
    if s.startswith(("res://", "user://", "--", "/", "#", "%s/", "ui_", "theme_")) or "://" in s:
        return False
    if re.fullmatch(r"[a-z0-9_./:\-]+", s):         # identifiers, keys, paths, actions
        return False
    if re.fullmatch(r"[A-Z][a-zA-Z0-9]*", s) and any(k in line for k in ("get_node", "find_child", ".name ==", "class_name", "has_method", "Engine.", "is_class", "ClassDB")):
        return False
    if re.fullmatch(r"#?[0-9a-fA-F]{6,8}", s):
        return False
    if any(k in line for k in ("push_error", "push_warning", "print(", "printerr", "assert(", "prints(", "_check(", "add_theme_", "set_meta", "get_meta", "has_meta", "connect(", "emit_signal", "set_shader_parameter", "InputMap.", "is_action", "ProjectSettings", "ConfigFile", "cf.set_value", "cf.get_value", "OS.", ".call(\"", "load(", "preload(")):
        return False
    if "no-i18n" in line or "debug_label" in line or "_smoke_report" in line or "print_verbose" in line or "save_jpg" in line:
        return False
    if s in SKIP_TEXT or s.startswith(("shader_type", "parameters/", "[center]", "[color=#", "  [color=#", "[font_size")):
        return False
    if not re.search(r"[A-Za-z]{2}", re.sub(r"%[-+0-9.]*[sdf]", "", s)):   # formats with no words
        return False
    if re.fullmatch(r"[A-Z][a-z]+[A-Z0-9][A-Za-z0-9]*", s):   # CamelCase node/bone names
        return False
    return True

def scripts():
    out = {}
    for f in sorted(os.listdir(os.path.join(ROOT, "scripts"))):
        if not f.endswith(".gd") or f in SKIP_SCRIPTS:
            continue
        for n, line in enumerate(open(os.path.join(ROOT, "scripts", f), encoding="utf-8"), 1):
            code = line.split("##")[0]
            stripped = code.lstrip()
            if stripped.startswith("#"):
                continue
            for m in STR.finditer(code):
                s = m.group(1).replace("\\n", "\n").replace('\\"', '"').replace("\\t", "\t")
                if is_text(s, code):
                    out.setdefault(s, []).append(f"{f}:{n}")
    return out

def walk(v, key, acc, where):
    if isinstance(v, dict):
        for k, x in v.items():
            if k.startswith("_") or k == "icon":
                continue
            walk(x, "@stat" if key == "stat_names" else k, acc, where)
    elif isinstance(v, list):
        for x in v:
            walk(x, key, acc, where)
    elif isinstance(v, str) and (key in DATA_KEYS or where == "taglines.json" or key == "@stat"):
        if re.search(r"[A-Za-z]", v):
            acc.setdefault(v, []).append(where)

def data():
    acc = {}
    for f in sorted(os.listdir(os.path.join(ROOT, "data"))):
        if f.endswith(".json"):
            walk(json.load(open(os.path.join(ROOT, "data", f), encoding="utf-8")), "", acc, f)
    return acc

if __name__ == "__main__":
    s, d = scripts(), data()
    allk = dict(s)
    for k in EXTRA:
        allk.setdefault(k, ["(runtime)"])
    for k, v in d.items():
        allk.setdefault(k, []).extend(v)
    os.makedirs(os.path.join(ROOT, "data", "i18n"), exist_ok=True)
    json.dump({k: allk[k] for k in sorted(allk)}, open(os.path.join(ROOT, "data", "i18n", "_source.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(len(s), "script strings,", len(d), "data strings,", len(allk), "total")
