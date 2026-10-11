# -*- coding: utf-8 -*-
"""Rebuild hidden_item_hints.json: NPC name + place + method, keep missable/stance notes."""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(r"D:\Unpacking game")
CONTENT = ROOT / r"afb02f5bbd8d0d94fe47e171a61cd51ee2ffeb73\Output\Exports\Octopath_Traveler\Content"
XLSX = Path(r"D:\Users\10129\Downloads\Octopath Traveler Resource.xlsx")
OUT = ROOT / "hidden_item_hints.json"

TOWN_CN = {
    "Flamesgrace": "弗雷姆葛雷斯",
    "Atlasdam": "阿特拉斯达姆",
    "Rippletide": "利布尔泰德",
    "Cobbleston": "鹅卵石村",
    "Sunshade": "桑谢德",
    "Clearbrook": "库利亚布鲁克",
    "Bolderfall": "柏达弗尔",
    "S'warkii": "希・沃尔基",
    "Stillsnow": "史迪尔斯诺",
    "Noblecourt": "诺布尔寇德",
    "Goldshore": "葛鲁德修亚",
    "Stonegard": "斯托冈德",
    "Wellspring": "威尔斯宾克",
    "Saintsbridge": "圣特布里吉",
    "Quarrycrest": "库欧利克雷斯特",
    "Victors Hollow": "维克塔霍洛",
    "Northreach": "诺斯利奇",
    "Wispermill": "维斯帕米尔",
    "Grandport": "格兰波特",
    "Everhold": "艾巴霍多",
    "Marsalim": "马尔沙利姆",
    "Riverford": "利维福德",
    "Orewell": "欧亚威尔",
    "Duskbarrow": "达斯克瓦罗",
}
SKIP_HEADERS = {"NPC", "Tier 1", "Tier 2", "Tier 3"}


def load_rows(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))[0]["Rows"]


def text_value(text_rows: dict, key: str) -> str:
    if not key or key == "None":
        return ""
    row = text_rows.get(key) or {}
    t = row.get("Text") or {}
    return t.get("LocalizedString") or t.get("SourceString") or ""


def field(row, prefix: str):
    if not isinstance(row, dict):
        return None
    for k, v in row.items():
        if k.startswith(prefix):
            return v
    return None


def map_candidates(region: str, area_code: str) -> list[str]:
    out = []
    if not region or not area_code:
        return out
    kind, rest = area_code[0], area_code[1:]
    m = re.match(r"^(\d)(\d?)([A-Za-z]*)$", rest)
    if kind in ("D", "F") and m:
        level, sub, suffix = m.group(1), m.group(2), m.group(3)
        if suffix.lower() == "job":
            out.append(f"{kind}_{region}_{level}_Job")
        base = f"{kind}_{region}_{level}_{sub}" if sub else f"{kind}_{region}_{level}"
        if suffix and suffix.lower() != "job":
            su = suffix.upper()
            out.append(f"{base}_{su}")
            out.append(f"{base}{su}")
        out.append(base)
    if kind == "T":
        if len(rest) == 1:
            out.append(f"T_{region}_{rest}")
        elif len(rest) == 2:
            out.append(f"T_{region}_{rest[0]}_{rest[1]}")
            out.append(f"T_{region}_{rest}")
        elif len(rest) == 3:
            out.append(f"T_{region}_{rest[0]}_{rest[1]}_{rest[2]}")
            out.append(f"T_{region}_{rest}")
    return out


def object_map_name(text_rows: dict, object_id: str) -> str:
    parts = object_id.split("_")
    if len(parts) < 3:
        return ""
    region, area = parts[1], parts[2]
    for cand in map_candidates(region, area):
        name = text_value(text_rows, cand)
        if name:
            return name
    return f"{region}_{area}"


def norm_item_name(s: str) -> str:
    s = (s or "").strip()
    s = re.sub(r"^[\*＊]+\s*", "", s)
    s = re.sub(r"^\(\*\)\s*", "", s)
    s = s.replace("’", "'").replace("‘", "'").replace("'", "").replace(".", "")
    s = s.casefold()
    s = s.replace("nourshing", "nourishing").replace("myterious", "mysterious")
    s = re.sub(r"\s*\((m|l)\)", r" \1", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def npc_base_name(s: str) -> str:
    return re.sub(r"\s*\(\d+\)\s*$", "", (s or "").strip())


NPC_EN_OFFICIAL_CN = {
    "Guard": "卫兵",
}


def loc_cn(en: str, lang: dict[str, str]) -> str:
    en = (en or "").strip()
    if not en:
        return ""
    head = en.split("(")[0].strip()
    if head in NPC_EN_OFFICIAL_CN:
        return NPC_EN_OFFICIAL_CN[head]
    cn = lang.get(en) or lang.get(head) or TOWN_CN.get(en) or TOWN_CN.get(head) or en
    cn = str(cn).replace("／", "/").replace("\r", "")
    return cn.split("\n")[0].split("/")[0].strip()


def load_lang() -> dict[str, str]:
    out = dict(TOWN_CN)
    import openpyxl
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    for row in wb["Language"].iter_rows(values_only=True):
        if not row or len(row) < 2 or not row[1]:
            continue
        en = str(row[1]).strip()
        cn = None
        if len(row) > 7 and row[7]:
            cn = str(row[7]).strip()
        elif len(row) > 6 and row[6]:
            cn = str(row[6]).strip()
        if en and cn:
            out[en] = cn
    return out


def parse_hidden_from_npc(lang: dict[str, str]) -> list[dict]:
    import openpyxl
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    recs = []
    place_en = ""
    place_cn = ""
    npc = ""
    for row in wb["NPC"].iter_rows(values_only=True):
        cells = list(row)
        b = cells[1] if len(cells) > 1 else None
        d = cells[3] if len(cells) > 3 else None
        f = cells[5] if len(cells) > 5 else None
        drop = cells[14] if len(cells) > 14 else None
        steal_empty = not d or str(d).strip() in ("", "None")
        info_raw = str(f).strip() if f else ""
        drop_empty = not drop or str(drop).strip() in ("", "None", "Drop")

        if isinstance(b, str) and b.strip() and steal_empty and drop_empty and (
            not info_raw or info_raw.casefold() in ("none", "scrutinize / inquire")
        ):
            raw = b.strip()
            if raw in SKIP_HEADERS:
                continue
            place_en = raw
            place_cn = loc_cn(raw, lang)
            npc = ""
            continue

        if isinstance(b, str) and b.strip():
            npc = loc_cn(npc_base_name(b.strip()), lang)

        if not npc or not place_cn or not info_raw:
            continue
        if "hidden item" not in info_raw.casefold():
            continue
        lines = [ln.strip() for ln in re.split(r"[\n/]+", info_raw) if ln.strip()]
        items = [ln for ln in lines if ln.casefold() not in ("a hidden item", "hidden item", "none")]
        for it in items:
            recs.append({
                "place_en": place_en,
                "place_cn": place_cn,
                "npc": npc,
                "item_en": it,
                "item_norm": norm_item_name(it),
            })
    return recs


def load_original_hints() -> dict[str, str]:
    """Community stance text from the original PS1 table (not regenerated JSON)."""
    ps1 = ROOT / "build_hidden_item_hints.ps1"
    out = {}
    if not ps1.exists():
        return out
    text = ps1.read_text(encoding="utf-8")
    for m in re.finditer(r"'(HdnPnt_[A-Za-z0-9_]+)'\s*=\s*'([^']*)'", text):
        out[m.group(1)] = m.group(2)
    return out


def extract_prefix(old: str) -> str:
    if not old:
        return ""
    m = re.match(r"^(【[^】]+】)", old)
    return m.group(1) if m else ""


def extract_stance(old: str) -> str:
    """Keep landmark / 'actual item is elsewhere' / challenge notes from old hint."""
    if not old:
        return ""
    s = re.sub(r"^【[^】]+】", "", old).strip()
    s = re.sub(r"^赛拉斯/阿芬\s*打探：", "", s)
    s = re.sub(r"\s*→\s*小地图「!」拾取\s*$", "", s)
    # If old is only a generic person with no landmark, drop it (NPC name from sheet is better).
    return s.strip()


STANCE_NPC_KEYS = [
    (["圣火骑士"], ["圣火骑士"]),
    (["神官"], ["神官"]),
    (["看门狗", "三只"], ["看门狗"]),
    (["卫兵", "警卫"], ["警卫", "卫兵"]),
    (["劳工", "工人"], ["工人"]),
    (["引座员", "侍者"], ["引座员", "侍者"]),
    (["村长"], ["村长"]),
    (["梅莉儿"], ["梅莉儿"]),
    (["贝尔"], ["贝尔"]),
    (["奇兰"], ["奇兰", "使者"]),
    (["商人", "古董商", "旧货"], ["商人", "旧货商", "古董"]),
    (["渔夫"], ["渔夫"]),
    (["船长"], ["船长"]),
    (["舞娘", "舞者"], ["舞娘", "舞者"]),
    (["招待"], ["招待"]),
    (["母亲"], ["母亲"]),
    (["父亲"], ["父亲"]),
    (["女孩", "少女", "小女孩"], ["女孩", "少女", "小孩"]),
    (["男孩", "少年"], ["少年", "男孩", "小孩"]),
    (["老妇", "老婆婆"], ["老婆婆"]),
    (["老人"], ["老人"]),
    (["镇民", "村民"], ["市民", "村民", "镇民"]),
    (["狗"], ["狗", "看门狗"]),
]


def pick_by_stance(cands: list[dict], stance: str) -> dict | None:
    if not stance or not cands:
        return None
    for keys, npc_bits in STANCE_NPC_KEYS:
        if any(k in stance for k in keys):
            for r in cands:
                if any(b in r["npc"] for b in npc_bits):
                    return r
    return None


def place_score(place_cn: str, map_name: str) -> int:
    if not place_cn or not map_name:
        return 0
    if place_cn == map_name:
        return 3
    if place_cn in map_name or map_name in place_cn:
        return 2
    town = place_cn.split(" ")[0].split("-")[0]
    if town and len(town) >= 3 and map_name.startswith(town):
        return 1
    return 0


def scrub_stance(stance: str, npc: str) -> str:
    if not stance:
        return ""
    for keys, bits in STANCE_NPC_KEYS:
        if npc and any(b in npc for b in bits):
            continue
        for k in sorted(keys, key=len, reverse=True):
            if k in stance:
                stance = stance.replace(k, "")
    stance = re.sub(r"\s+", " ", stance).strip(" ；、的")
    return stance


def compose(prefix: str, npc: str, place: str, stance: str) -> str:
    who = f"{npc}（{place}）" if npc and place else (npc or place or "该地点 NPC")
    body = f"赛拉斯/阿芬打听：{who}"
    if stance:
        st = scrub_stance(stance, npc)
        if npc and st.replace(" ", "").startswith(npc.replace(" ", "")):
            extra = st[len(npc):].lstrip("：:，, ")
            if extra:
                body += f"；{extra}"
        elif st and st not in body:
            st = re.sub(r"^（[^）]+）[；;]?\s*", "", st)
            if st and st not in body:
                body += f"；{st}"
    body += " → 小地图「!」拾取"
    return (prefix + body) if prefix else body


def main() -> None:
    old = load_original_hints()
    if not old and OUT.exists():
        old = json.loads(OUT.read_text(encoding="utf-8"))

    lang = load_lang()
    excel = parse_hidden_from_npc(lang)
    item_rows = load_rows(CONTENT / "Item/Database/ItemDB.json")
    text_rows = load_rows(CONTENT / "GameText/Database/GameTextZH_CN.json")
    object_rows = load_rows(CONTENT / "Object/Database/ObjectData.json")
    inv = json.loads((ROOT / "collector_item_inventory.json").read_text(encoding="utf-8"))["items"]
    id_to_en = {int(x["id"]): x.get("en") or "" for x in inv}
    id_to_cn = {int(x["id"]): x.get("name") or "" for x in inv}

    hidden = []
    for oid, row in object_rows.items():
        if not oid.startswith("HdnPnt_"):
            continue
        label = row.get("HaveItemLabel") or "None"
        if label in ("None", None) or row.get("IsMoney"):
            item_en = ""
            item_cn = ""
            iid = 0
        else:
            item_cn = ""
            iid = 0
            prop = item_rows.get(label)
            if prop:
                iid = int(field(prop, "ItemID_") or 0)
                nk = field(prop, "ItemNameID_")
                item_cn = text_value(text_rows, nk) or id_to_cn.get(iid, "")
            item_en = id_to_en.get(iid, "")
        map_name = object_map_name(text_rows, oid)
        hidden.append({
            "oid": oid,
            "map_name": map_name,
            "item_en": item_en,
            "item_cn": item_cn,
            "item_norm": norm_item_name(item_en),
        })

    # Index excel by item
    by_item: dict[str, list[dict]] = defaultdict(list)
    for r in excel:
        by_item[r["item_norm"]].append(r)

    out = {}
    used_excel = set()
    matched = 0
    for h in hidden:
        oid = h["oid"]
        old_hint = old.get(oid, "")
        prefix = extract_prefix(old_hint)
        stance = extract_stance(old_hint)
        cands = []
        for r in by_item.get(h["item_norm"], []):
            sc = place_score(r["place_cn"], h["map_name"])
            if sc > 0:
                cands.append((sc, r))
        cands.sort(key=lambda x: -x[0])
        pick = None
        if cands:
            best = cands[0][0]
            top = [r for sc, r in cands if sc == best]
            leftover = [r for r in top if id(r) not in used_excel]
            pool = leftover or top
            pick = pick_by_stance(pool, stance) or pick_by_stance(top, stance)
            if pick is None:
                pick = leftover[0] if leftover else top[0]
        if pick:
            used_excel.add(id(pick))
            matched += 1
            out[oid] = compose(prefix, pick["npc"], pick["place_cn"], stance)
        elif old_hint:
            # Keep old, but if it lacks a place parenthesis, append map name.
            hint = old_hint
            if h["map_name"] and h["map_name"] not in hint:
                hint = hint.replace("赛拉斯/阿芬 打探：", f"赛拉斯/阿芬打听（{h['map_name']}）：", 1)
                hint = hint.replace("赛拉斯/阿芬打听：", f"赛拉斯/阿芬打听（{h['map_name']}）：", 1)
            out[oid] = hint
        else:
            loc = h["map_name"] or "该地图"
            item = h["item_cn"] or "隐藏道具"
            out[oid] = f"赛拉斯/阿芬打听（{loc}）后，小地图「!」拾取「{item}」"

    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"hidden={len(hidden)} excel_hidden={len(excel)} matched_npc={matched} wrote={len(out)}")


if __name__ == "__main__":
    main()
