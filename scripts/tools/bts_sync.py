#!/usr/bin/env python3
"""
Batch-update units.json and buildings.json from BTS XML reference files.
Compares current game data against Civ4 BTS XML and updates mismatched values.
"""

import xml.etree.ElementTree as ET
import json
import os
import sys

# Paths
BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
UNITS_XML = os.path.join(BASE_DIR, "beyond", "Beyond the Sword", "Assets", "XML", "Units", "CIV4UnitInfos.xml")
BUILDINGS_XML = os.path.join(BASE_DIR, "beyond", "Beyond the Sword", "Assets", "XML", "Buildings", "CIV4BuildingInfos.xml")
UNITS_JSON = os.path.join(BASE_DIR, "data", "units.json")
BUILDINGS_JSON = os.path.join(BASE_DIR, "data", "buildings.json")

# XML namespace
UNIT_NS = "{x-schema:CIV4UnitSchema.xml}"
BUILDING_NS = "{x-schema:CIV4BuildingsSchema.xml}"

# Explicit XML->JSON mappings for units with non-standard naming
UNIT_XML_TO_JSON = {
    "UNIT_TACTICAL_NUKE": "nuclear_missile",
    "UNIT_HORSE_ARCHER": "horseman",
    "UNIT_ROME_PRAETORIAN": "praetorian",
    "UNIT_GREEK_PHALANX": "phalanx",
    "UNIT_EGYPT_WARCHARIOT": "war_chariot",
    "UNIT_CHINA_CHOKONU": "cho_ko_nu",
    "UNIT_PERSIA_IMMORTAL": "immortal",
    "UNIT_ENGLISH_REDCOAT": "redcoat",
    "UNIT_FRENCH_MUSKETEER": "musketeer",
    "UNIT_GERMAN_PANZER": "panzer",
    "UNIT_RUSSIA_COSSACK": "cossack",
    "UNIT_AMERICAN_NAVY_SEAL": "navy_seal",
    "UNIT_JAPAN_SAMURAI": "samurai",
    "UNIT_INDIAN_FAST_WORKER": "fast_worker",
    "UNIT_MONGOL_KESHIK": "keshik",
    "UNIT_AZTEC_JAGUAR": "jaguar",
    "UNIT_ARABIA_CAMELARCHER": "camel_archer",
    "UNIT_SPANISH_CONQUISTADOR": "conquistador",
    "UNIT_PROPHET": "great_prophet",
    "UNIT_ARTIST": "great_artist",
    "UNIT_SCIENTIST": "great_scientist",
    "UNIT_MERCHANT": "great_merchant",
    "UNIT_ENGINEER": "great_engineer",
}

# Units in XML we skip (not in our game)
UNIT_SKIP = {
    "UNIT_LION", "UNIT_BEAR", "UNIT_PANTHER", "UNIT_WOLF",
    "UNIT_NUCLEAR_SUBMARINE", "UNIT_GUIDED_MISSILE", "UNIT_ATTACK_SUBMARINE",
    "UNIT_MISSILE_CRUISER", "UNIT_MARINE", "UNIT_PARATROOPER",
    "UNIT_SAM_INFANTRY", "UNIT_MOBILE_SAM", "UNIT_MOBILE_ARTILLERY",
    "UNIT_GUNSHIP", "UNIT_WORKBOAT", "UNIT_GALLEON", "UNIT_PRIVATEER",
    "UNIT_SHIP_OF_THE_LINE", "UNIT_IRONCLAD", "UNIT_STEALTH_DESTROYER",
    "UNIT_AIRSHIP", "UNIT_MACHINE_GUN", "UNIT_AT_INFANTRY",
    "UNIT_WAR_ELEPHANT", "UNIT_CUIRASSIER",
    # Civ-specific unique units not in our JSON
    "UNIT_INCAN_QUECHUA", "UNIT_CELTIC_GALLIC_WARRIOR", "UNIT_SUMERIAN_VULTURE",
    "UNIT_NATIVE_AMERICA_DOG_SOLDIER", "UNIT_VIKING_BESERKER",
    "UNIT_ZULU_IMPI", "UNIT_MAYA_HOLKAN", "UNIT_BABYLON_BOWMAN",
    "UNIT_ETHIOPIAN_OROMO_WARRIOR",
    "UNIT_KOREAN_HWACHA",
    "UNIT_MALI_SKIRMISHER",
    "UNIT_KHMER_BALLISTA_ELEPHANT",
    "UNIT_CARTHAGINIAN_NUMIDIAN_CAVALRY",
    "UNIT_HOLY_ROMAN_LANDSKNECHT",
    "UNIT_OTTOMAN_JANISSARY",
    "UNIT_PORTUGUESE_CARRACK",
    "UNIT_DUTCH_EAST_INDIAMAN",
    "UNIT_SIAMESE_SURIYOTHAI",
    "UNIT_BABYLONIAN_BOWMAN",
    "UNIT_BYZANTINE_CATAPHRACT",
}

# Missionary/Executive units - skip name matching for these
UNIT_RELIGIOUS_EXEC_SKIP = {"JEWISH", "CHRISTIAN", "ISLAMIC", "HINDU", "BUDDHIST", "CONFUCIAN", "TAOIST"}

BUILDING_XML_TO_JSON = {
    "BUILDING_PYRAMIDS": "the_pyramids",
    "BUILDING_GREAT_WALL": "the_great_wall",
    "BUILDING_ORACLE": "the_oracle",
    "BUILDING_GREAT_LIGHTHOUSE": "the_great_lighthouse",
    "BUILDING_COLOSSUS": "the_colossus",
    "BUILDING_HANGING_GARDENS": "the_hanging_gardens",
    "BUILDING_PARTHENON": "the_parthenon",
    "BUILDING_GREAT_LIBRARY": "the_great_library",
    "BUILDING_NOTRE_DAME": "notre_dame",
    "BUILDING_SISTINE_CHAPEL": "sistine_chapel",
    "BUILDING_ANGKOR_WAT": "angkor_wat",
    "BUILDING_APOSTOLIC_PALACE": "apostolic_palace",
    "BUILDING_SANKORE": "university_of_sankore",
    "BUILDING_VERSAILLES": "versailles",
    "BUILDING_TAJ_MAHAL": "taj_mahal",
    "BUILDING_STATUE_OF_LIBERTY": "statue_of_liberty",
    "BUILDING_EIFFEL_TOWER": "eiffel_tower",
    "BUILDING_BROADWAY": "broadway",
    "BUILDING_HOLLYWOOD": "hollywood",
    "BUILDING_ROCK_N_ROLL": "rock_n_roll",
    "BUILDING_UNITED_NATIONS": "united_nations",
    "BUILDING_PENTAGON": "the_pentagon",
    "BUILDING_INTERNET": "the_internet",
    "BUILDING_SPACE_ELEVATOR": "space_elevator",
    "BUILDING_HEROIC_EPIC": "heroic_epic",
    "BUILDING_NATIONAL_EPIC": "national_epic",
    "BUILDING_GLOBE_THEATRE": "globe_theatre",
    "BUILDING_HERMITAGE": "hermitage",
    "BUILDING_IRONWORKS": "ironworks",
    "BUILDING_OXFORD_UNIVERSITY": "oxford_university",
    "BUILDING_WALL_STREET": "wall_street",
    "BUILDING_RED_CROSS": "red_cross",
    "BUILDING_WEST_POINT": "west_point",
    "BUILDING_MT_RUSHMORE": "mt_rushmore",
    "BUILDING_CHICHEN_ITZA": "chichen_itza",
    "BUILDING_INTELLIGENCE_AGENCY": "intelligence_agency",
    "BUILDING_SECURITY_BUREAU": "security_bureau",
    "BUILDING_SCOTLAND_YARD": "scotland_yard",
    "BUILDING_STONEHENGE": "stonehenge",
}


def get_xml_text(elem, tag, ns, default="0"):
    """Get text from XML element with namespace, with default."""
    child = elem.find(f"{ns}{tag}")
    if child is not None and child.text:
        return child.text.strip()
    return default


def parse_units_xml():
    """Parse BTS CIV4UnitInfos.xml and extract unit stats."""
    tree = ET.parse(UNITS_XML)
    root = tree.getroot()
    ns = UNIT_NS

    units = {}
    infos = root.find(f"{ns}UnitInfos")
    if infos is None:
        print("ERROR: Could not find UnitInfos element")
        return units

    for unit_info in infos:
        unit_type = get_xml_text(unit_info, "Type", ns, "")
        if not unit_type:
            continue

        cost = int(get_xml_text(unit_info, "iCost", ns, "-1"))
        combat = int(get_xml_text(unit_info, "iCombat", ns, "0"))
        moves = int(get_xml_text(unit_info, "iMoves", ns, "1"))
        first_strikes = int(get_xml_text(unit_info, "iFirstStrikes", ns, "0"))
        chance_first_strikes = int(get_xml_text(unit_info, "iChanceFirstStrikes", ns, "0"))
        collateral_damage = int(get_xml_text(unit_info, "iCollateralDamage", ns, "0"))
        bombard_rate = int(get_xml_text(unit_info, "iBombardRate", ns, "0"))
        city_attack = int(get_xml_text(unit_info, "iCityAttack", ns, get_xml_text(unit_info, "iCityAttackModifier", ns, "0")))
        city_defense = int(get_xml_text(unit_info, "iCityDefense", ns, get_xml_text(unit_info, "iCityDefenseModifier", ns, "0")))

        units[unit_type] = {
            "cost": cost,
            "combat": combat,
            "moves": moves,
            "first_strikes": first_strikes,
            "chance_first_strikes": chance_first_strikes,
            "collateral_damage": collateral_damage,
            "bombard_rate": bombard_rate,
            "city_attack": city_attack,
            "city_defense": city_defense,
        }

    return units


def parse_buildings_xml():
    """Parse BTS CIV4BuildingInfos.xml and extract building stats."""
    tree = ET.parse(BUILDINGS_XML)
    root = tree.getroot()

    # Detect namespace
    ns = ""
    root_tag = root.tag
    if "}" in root_tag:
        ns = root_tag[:root_tag.index("}") + 1]

    buildings = {}
    # Try to find the container element
    container = None
    for child in root:
        if "BuildingInfos" in child.tag:
            container = child
            break

    if container is None:
        print("ERROR: Could not find BuildingInfos element")
        return buildings

    for bldg_info in container:
        bldg_type = get_xml_text(bldg_info, "Type", ns, "")
        if not bldg_type:
            continue

        cost = int(get_xml_text(bldg_info, "iCost", ns, "-1"))
        happiness = int(get_xml_text(bldg_info, "iHappiness", ns, "0"))
        health = int(get_xml_text(bldg_info, "iHealth", ns, "0"))
        defense = int(get_xml_text(bldg_info, "iDefenseModifier", ns, "0"))

        buildings[bldg_type] = {
            "cost": cost,
            "happiness": happiness,
            "health": health,
            "defense": defense,
        }

    return buildings


def map_unit_id(xml_type: str, json_keys: set) -> str | None:
    """Map XML unit type to JSON key."""
    # Skip known non-game units
    if xml_type in UNIT_SKIP:
        return None

    # Skip religious missionaries/executives (generic "missionary" in JSON)
    for rel in UNIT_RELIGIOUS_EXEC_SKIP:
        if f"_{rel}_" in xml_type:
            return None

    # Check explicit mapping
    if xml_type in UNIT_XML_TO_JSON:
        result = UNIT_XML_TO_JSON[xml_type]
        if result and result in json_keys:
            return result
        return None

    # Auto-map: remove UNIT_ prefix, lowercase
    json_id = xml_type.replace("UNIT_", "", 1).lower()
    if json_id in json_keys:
        return json_id
    return None


def map_building_id(xml_type: str, json_keys: set) -> str | None:
    """Map XML building type to JSON key."""
    # Check explicit mapping
    if xml_type in BUILDING_XML_TO_JSON:
        result = BUILDING_XML_TO_JSON[xml_type]
        if result and result in json_keys:
            return result
        return None

    # Auto-map: remove BUILDING_ prefix, lowercase
    json_id = xml_type.replace("BUILDING_", "", 1).lower()
    if json_id in json_keys:
        return json_id
    return None


def update_units(dry_run=False):
    """Compare and update units.json from BTS XML."""
    print("=" * 80)
    print("UNIT STATS COMPARISON: BTS XML vs units.json")
    print("=" * 80)

    xml_units = parse_units_xml()
    print(f"Parsed {len(xml_units)} units from BTS XML")

    with open(UNITS_JSON, "r") as f:
        json_data = json.load(f)

    json_keys = set(json_data.keys())
    changes = []
    matched = 0

    for xml_type, xml_stats in sorted(xml_units.items()):
        json_id = map_unit_id(xml_type, json_keys)
        if json_id is None:
            continue
        if json_id.startswith("_"):
            continue

        matched += 1
        unit = json_data[json_id]
        unit_changes = []

        # Compare cost (XML iCost vs JSON cost)
        if xml_stats["cost"] > 0:  # -1 means unbuildable in XML
            json_cost = unit.get("cost", 0)
            if json_cost != xml_stats["cost"]:
                unit_changes.append(f"  cost: {json_cost} -> {xml_stats['cost']}")
                if not dry_run:
                    unit["cost"] = xml_stats["cost"]

        # Compare strength (XML iCombat vs JSON strength)
        if xml_stats["combat"] > 0:
            json_str = unit.get("strength", 0)
            bts_str = float(xml_stats["combat"])
            if abs(json_str - bts_str) > 0.01:
                unit_changes.append(f"  strength: {json_str} -> {bts_str}")
                if not dry_run:
                    unit["strength"] = bts_str

        # Compare movement (XML iMoves vs JSON movement)
        json_moves = unit.get("movement", 1)
        if json_moves != xml_stats["moves"]:
            unit_changes.append(f"  movement: {json_moves} -> {xml_stats['moves']}")
            if not dry_run:
                unit["movement"] = xml_stats["moves"]

        # Compare first strikes
        if xml_stats["first_strikes"] > 0 or unit.get("first_strikes", 0) > 0:
            json_fs = unit.get("first_strikes", 0)
            if json_fs != xml_stats["first_strikes"]:
                unit_changes.append(f"  first_strikes: {json_fs} -> {xml_stats['first_strikes']}")
                if not dry_run:
                    if xml_stats["first_strikes"] > 0:
                        unit["first_strikes"] = xml_stats["first_strikes"]
                    elif "first_strikes" in unit:
                        del unit["first_strikes"]

        # Compare city_defense (XML uses percentage, JSON uses decimal)
        if xml_stats["city_defense"] > 0 or unit.get("city_defense", 0) > 0:
            json_cd = unit.get("city_defense", 0)
            bts_cd = xml_stats["city_defense"] / 100.0
            if abs(json_cd - bts_cd) > 0.01:
                unit_changes.append(f"  city_defense: {json_cd} -> {bts_cd}")
                if not dry_run:
                    if bts_cd > 0:
                        unit["city_defense"] = bts_cd
                    elif "city_defense" in unit:
                        del unit["city_defense"]

        if unit_changes:
            changes.append((json_id, unit_changes))
            print(f"\n{json_id} ({xml_type}):")
            for c in unit_changes:
                print(c)

    print(f"\nMatched {matched} units between XML and JSON")

    if not changes:
        print("No changes needed!")
    else:
        print(f"\n--- Total: {len(changes)} units with changes ---")

    if not dry_run and changes:
        with open(UNITS_JSON, "w") as f:
            json.dump(json_data, f, indent="\t", ensure_ascii=False)
            f.write("\n")
        print(f"\nWrote updated units.json ({len(changes)} units changed)")

    return len(changes)


def update_buildings(dry_run=False):
    """Compare and update buildings.json from BTS XML."""
    print("\n" + "=" * 80)
    print("BUILDING COSTS COMPARISON: BTS XML vs buildings.json")
    print("=" * 80)

    xml_buildings = parse_buildings_xml()
    print(f"Parsed {len(xml_buildings)} buildings from BTS XML")

    with open(BUILDINGS_JSON, "r") as f:
        json_data = json.load(f)

    json_keys = set(json_data.keys())
    changes = []
    matched = 0

    for xml_type, xml_stats in sorted(xml_buildings.items()):
        json_id = map_building_id(xml_type, json_keys)
        if json_id is None:
            continue
        if json_id.startswith("_"):
            continue

        matched += 1
        bldg = json_data[json_id]
        bldg_changes = []

        # Compare cost
        if xml_stats["cost"] > 0:
            json_cost = bldg.get("cost", 0)
            if json_cost != xml_stats["cost"]:
                bldg_changes.append(f"  cost: {json_cost} -> {xml_stats['cost']}")
                if not dry_run:
                    bldg["cost"] = xml_stats["cost"]

        if bldg_changes:
            changes.append((json_id, bldg_changes))
            print(f"\n{json_id} ({xml_type}):")
            for c in bldg_changes:
                print(c)

    print(f"\nMatched {matched} buildings between XML and JSON")

    if not changes:
        print("No changes needed!")
    else:
        print(f"\n--- Total: {len(changes)} buildings with changes ---")

    if not dry_run and changes:
        with open(BUILDINGS_JSON, "w") as f:
            json.dump(json_data, f, indent="\t", ensure_ascii=False)
            f.write("\n")
        print(f"\nWrote updated buildings.json ({len(changes)} buildings changed)")

    return len(changes)


if __name__ == "__main__":
    dry_run = "--dry-run" in sys.argv
    if dry_run:
        print("*** DRY RUN MODE - no files will be modified ***\n")

    unit_changes = update_units(dry_run)
    building_changes = update_buildings(dry_run)

    print(f"\n{'='*80}")
    print(f"Summary: {unit_changes} unit changes, {building_changes} building changes")
    if dry_run:
        print("(dry run - no files modified)")
    print(f"{'='*80}")
