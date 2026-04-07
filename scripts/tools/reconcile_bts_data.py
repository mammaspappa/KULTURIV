#!/usr/bin/env python3
"""
Reconcile live game data with BTS reference data.
Makes live data identical to BTS stats while preserving our key names.

Usage: python3 scripts/tools/reconcile_bts_data.py
"""
import json
from pathlib import Path

DATA_DIR = Path("data")

# === UNIT KEY MAPPING: BTS key -> our key ===
UNIT_KEY_MAP = {
    # Unique units (BTS uses civ-prefixed names, we use short names)
    "greek_phalanx": "phalanx",
    "rome_praetorian": "praetorian",
    "persia_immortal": "immortal",
    "arabia_camelarcher": "camel_archer",
    "egypt_warchariot": "war_chariot",
    "mongol_keshik": "keshik",
    "spanish_conquistador": "conquistador",
    "russia_cossack": "cossack",
    "english_redcoat": "redcoat",
    "german_panzer": "panzer",
    "japan_samurai": "samurai",
    "china_chokonu": "cho_ko_nu",
    "french_musketeer": "musketeer",
    "american_navy_seal": "navy_seal",
    "aztec_jaguar": "jaguar",
    "indian_fast_worker": "fast_worker",
    "viking_beserker": "berserker",
    "celtic_gallic_warrior": "gallic_warrior",
    "native_america_dog_soldier": "dog_soldier",
    "sumerian_vulture": "vulture",
    "byzantine_cataphract": "cataphract",
    "holy_roman_landsknecht": "landsknecht",
    "korean_hwacha": "hwacha",
    "ottoman_janissary": "janissary",
    "mali_skirmisher": "skirmisher",
    "babylon_bowman": "bowman",
    "maya_holkan": "holkan",
    "zulu_impi": "impi",
    "incan_quechua": "quechua",
    "ethiopian_oromo_warrior": "oromo_warrior",
    "khmer_ballista_elephant": "ballista_elephant",
    "carthage_numidian_cavalry": "numidian_cavalry",
    "netherlands_oostindievaarder": "oostindievaarder",
    "portugal_carrack": "carrack",
    # Great people
    "prophet": "great_prophet",
    "artist": "great_artist",
    "scientist": "great_scientist",
    "merchant": "great_merchant",
    "engineer": "great_engineer",
    # Missionaries (BTS has per-religion, we use generic)
    # We'll add per-religion missionaries from BTS
    # Other renames
    "tactical_nuke": "nuclear_missile",
}

# BTS entries to SKIP (animals, executives we handle differently)
UNIT_SKIP = {
    "bear", "lion", "wolf", "panther",  # animals
    "executive_1", "executive_2", "executive_3", "executive_4",
    "executive_5", "executive_6", "executive_7",  # we name these differently
}

# === BUILDING KEY MAPPING ===
BUILDING_KEY_MAP = {
    # Religion-specific buildings use same names mostly
    # UBs
    "egypt_obelisk": "burial_tomb",
    "mongol_ger": "ger",
    "china_pavilion": "pavilion",
    "rome_forum": "forum",
    "persia_apothecary": "apothecary",
    "aztec_sacrificial_altar": "sacrificial_altar",
    "spain_citadel": "citadel",
    "arabia_madrassa": "madrassa",
}

BUILDING_SKIP = set()

# Preserved fields (keep from live data, don't overwrite from BTS)
PRESERVE_FIELDS = {"symbol", "description", "_note", "era"}

# Units where BTS cost doesn't apply (our game uses production-based costs)
UNIT_COST_OVERRIDES = {
    "settler": 100,  # BTS uses food-based (cost=0), we use production
    "worker": 60,    # Same
}


def reconcile_entities(live_file, bts_file, key_map, skip_set, entity_type):
    """Make live data match BTS stats while using our key names."""
    with open(DATA_DIR / live_file) as f:
        live = json.load(f)
    with open(DATA_DIR / bts_file) as f:
        bts = json.load(f)

    live_d = {k: v for k, v in live.items() if isinstance(v, dict)}
    bts_d = {k: v for k, v in bts.items() if isinstance(v, dict) and not v.get("_kulturiv_only")}

    # Build reverse map: our_key -> bts_key
    reverse_map = {v: k for k, v in key_map.items()}

    result = {}
    matched = 0
    added = 0
    updated = 0

    # Process each BTS entry
    for bts_key, bts_data in bts_d.items():
        if bts_key in skip_set:
            continue

        # Determine our key name
        our_key = key_map.get(bts_key, bts_key)

        # Start with BTS data
        entry = dict(bts_data)

        # Remove BTS metadata
        entry.pop("bts_type", None)
        entry.pop("_kulturiv_only", None)

        # Resolve TXT_KEY names to readable names
        if entry.get("name", "").startswith("TXT_KEY_"):
            # Generate readable name from key
            name = our_key.replace("_", " ").title()
            entry["name"] = name

        # Fix resource references in BTS data (already using "horse" not "horses")

        # For units: fix upgrade/replaces references to use our key names
        if entity_type == "units":
            for ref_field in ["upgrades_to", "replaces"]:
                ref = entry.get(ref_field, "")
                if ref:
                    entry[ref_field] = key_map.get(ref, ref)
            alt_upgrades = entry.get("upgrades_to_alt", [])
            if alt_upgrades:
                entry["upgrades_to_alt"] = [key_map.get(u, u) for u in alt_upgrades]

        # Preserve KulturIV-specific fields from live data
        if our_key in live_d:
            for field in PRESERVE_FIELDS:
                if field in live_d[our_key]:
                    entry[field] = live_d[our_key][field]
            updated += 1
        else:
            added += 1

        # Apply game-specific overrides for units
        if entity_type == "units":
            if our_key in UNIT_COST_OVERRIDES:
                entry["cost"] = UNIT_COST_OVERRIDES[our_key]

            # Convert BTS boolean flags to abilities array (game code expects this)
            abilities = []
            if entry.pop("can_found_city", False):
                abilities.append("found_city")
            # Workers need build_improvements ability
            if our_key in ("worker", "fast_worker"):
                abilities.append("build_improvements")
            # Sea improvements
            if our_key == "workboat":
                abilities.append("build_sea_improvements")
            # Preserve existing abilities from live data if present
            if our_key in live_d and "abilities" in live_d[our_key]:
                for a in live_d[our_key]["abilities"]:
                    if a not in abilities:
                        abilities.append(a)
            if abilities:
                entry["abilities"] = abilities

        matched += 1
        result[our_key] = entry

    # Keep KulturIV-only entries that have no BTS equivalent
    for live_key, live_data in live_d.items():
        if live_key not in result:
            # Check if this is a duplicate of a BTS entry under a different name
            bts_key = reverse_map.get(live_key)
            if bts_key and bts_key in result:
                continue  # Already handled via mapping

            # Keep it but mark as KulturIV-only
            result[live_key] = live_data

    print(f"  Matched: {matched}, Updated: {updated}, Added new: {added}")
    print(f"  Total entries: {len(result)}")
    return result


def main():
    print("=== RECONCILING UNITS ===")
    units = reconcile_entities("units.json", "units_bts.json", UNIT_KEY_MAP, UNIT_SKIP, "units")
    with open(DATA_DIR / "units.json", "w") as f:
        json.dump(units, f, indent=2)
    print(f"  Written to data/units.json")

    print("\n=== RECONCILING BUILDINGS ===")
    buildings = reconcile_entities("buildings.json", "buildings_bts.json", BUILDING_KEY_MAP, BUILDING_SKIP, "buildings")
    with open(DATA_DIR / "buildings.json", "w") as f:
        json.dump(buildings, f, indent=2)
    print(f"  Written to data/buildings.json")

    print("\n=== RECONCILING TECHS ===")
    techs = reconcile_entities("techs.json", "techs_bts.json", {}, set(), "techs")
    with open(DATA_DIR / "techs.json", "w") as f:
        json.dump(techs, f, indent=2)
    print(f"  Written to data/techs.json")

    print("\nDone! Live data now matches BTS reference.")


if __name__ == "__main__":
    main()
