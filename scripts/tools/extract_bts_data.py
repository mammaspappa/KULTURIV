#!/usr/bin/env python3
"""
Extract Civ4 BTS XML data into KulturIV JSON format.

Usage:
    python3 scripts/tools/extract_bts_data.py [--units] [--buildings] [--techs] [--all]

    --units      Extract units only
    --buildings  Extract buildings only
    --techs      Extract techs only
    --civs       Extract civilizations (for UU/UB mapping)
    --all        Extract everything (default)
    --dry-run    Print JSON to stdout instead of writing files
    --merge      Merge with existing JSON (preserves KulturIV-only fields like symbol, description)

BTS XML path: beyond/Beyond the Sword/Assets/XML/
Output: data/*.json
"""

import xml.etree.ElementTree as ET
import json
import sys
import os
from pathlib import Path

# --- Paths ---
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent.parent
BTS_XML = PROJECT_DIR.parent / "beyond" / "Beyond the Sword" / "Assets" / "XML"
DATA_DIR = PROJECT_DIR / "data"


# --- XML Helpers ---
def find_text(el, ns, tag, default=""):
    """Get text of a child element, or default."""
    child = el.find(ns + tag)
    if child is not None and child.text and child.text.strip() not in ("", "NONE"):
        return child.text.strip()
    return default


def find_int(el, ns, tag, default=0):
    t = find_text(el, ns, tag, "")
    try:
        return int(t) if t else default
    except ValueError:
        return default


def find_float(el, ns, tag, default=0.0):
    t = find_text(el, ns, tag, "")
    try:
        return float(t) if t else default
    except ValueError:
        return default


def find_bool(el, ns, tag, default=False):
    t = find_text(el, ns, tag, "")
    return t == "1" or t.lower() == "true" if t else default


def bts_id_to_key(bts_id: str, prefix: str = "") -> str:
    """Convert BTS ID like UNIT_WARRIOR or TECH_BRONZE_WORKING to warrior or bronze_working."""
    s = bts_id
    if prefix and s.startswith(prefix):
        s = s[len(prefix):]
    return s.lower().strip("_")


def find_list(el, ns, list_tag, item_tag, text_tag=None):
    """Extract a list of text values from nested XML."""
    result = []
    container = el.find(ns + list_tag)
    if container is None:
        return result
    for item in container.findall(ns + item_tag):
        if text_tag:
            child = item.find(ns + text_tag)
            if child is not None and child.text and child.text != "NONE":
                result.append(child.text)
        else:
            if item.text and item.text != "NONE":
                result.append(item.text)
    return result


# --- Unit Class Defaults (needed for UU mapping) ---
def load_unit_class_defaults():
    """Load unit class -> default unit mapping."""
    path = BTS_XML / "Units" / "CIV4UnitClassInfos.xml"
    ns = "{x-schema:CIV4UnitSchema.xml}"
    tree = ET.parse(str(path))
    root = tree.getroot()

    defaults = {}  # UNITCLASS_X -> UNIT_X
    for info in root.iter(ns + "UnitClassInfo"):
        uc_type = find_text(info, ns, "Type")
        default_unit = find_text(info, ns, "DefaultUnitType")
        if uc_type and default_unit:
            defaults[uc_type] = default_unit
    return defaults


# --- Civilization UU/UB Mapping ---
def load_civ_unique_units():
    """Load civilization -> unique unit overrides."""
    path = BTS_XML / "Civilizations" / "CIV4CivilizationInfos.xml"
    ns = "{x-schema:CIV4CivilizationsSchema.xml}"
    tree = ET.parse(str(path))
    root = tree.getroot()

    class_defaults = load_unit_class_defaults()

    unique_units = {}  # BTS unit type -> {civ, replaces_class, replaces_default}
    civ_names = {}     # BTS civ type -> short name

    for civ in root.iter(ns + "CivilizationInfo"):
        civ_type = find_text(civ, ns, "Type")
        civ_short = find_text(civ, ns, "ShortDescription", "")
        civ_key = bts_id_to_key(civ_type, "CIVILIZATION_")
        civ_names[civ_type] = civ_key

        units_el = civ.find(ns + "Units")
        if units_el is None:
            continue
        for unit_pair in units_el.findall(ns + "Unit"):
            unit_class = find_text(unit_pair, ns, "UnitClassType")
            unit_type = find_text(unit_pair, ns, "UnitType")
            if unit_class and unit_type:
                default = class_defaults.get(unit_class, "")
                if unit_type != default:
                    unique_units[unit_type] = {
                        "civ": civ_key,
                        "replaces_class": unit_class,
                        "replaces_default": default,
                    }

    return unique_units, civ_names


def load_civ_unique_buildings():
    """Load civilization -> unique building overrides."""
    path = BTS_XML / "Civilizations" / "CIV4CivilizationInfos.xml"
    ns = "{x-schema:CIV4CivilizationsSchema.xml}"
    tree = ET.parse(str(path))
    root = tree.getroot()

    # Load building class defaults
    bc_path = BTS_XML / "Buildings" / "CIV4BuildingClassInfos.xml"
    bc_ns = "{x-schema:CIV4BuildingsSchema.xml}"
    bc_tree = ET.parse(str(bc_path))
    bc_root = bc_tree.getroot()

    bc_defaults = {}
    for info in bc_root.iter(bc_ns + "BuildingClassInfo"):
        bc_type = find_text(info, bc_ns, "Type")
        default_bld = find_text(info, bc_ns, "DefaultBuildingType")
        if bc_type and default_bld:
            bc_defaults[bc_type] = default_bld

    unique_buildings = {}
    for civ in root.iter(ns + "CivilizationInfo"):
        civ_type = find_text(civ, ns, "Type")
        civ_key = bts_id_to_key(civ_type, "CIVILIZATION_")

        blds_el = civ.find(ns + "Buildings")
        if blds_el is None:
            continue
        for bld_pair in blds_el.findall(ns + "Building"):
            bld_class = find_text(bld_pair, ns, "BuildingClassType")
            bld_type = find_text(bld_pair, ns, "BuildingType")
            if bld_class and bld_type:
                default = bc_defaults.get(bld_class, "")
                if bld_type != default:
                    unique_buildings[bld_type] = {
                        "civ": civ_key,
                        "replaces_class": bld_class,
                        "replaces_default": default,
                    }

    return unique_buildings


# --- Extract Units ---
def extract_units():
    """Parse CIV4UnitInfos.xml into units dict."""
    path = BTS_XML / "Units" / "CIV4UnitInfos.xml"
    ns = "{x-schema:CIV4UnitSchema.xml}"
    tree = ET.parse(str(path))
    root = tree.getroot()

    unique_units, _ = load_civ_unique_units()
    class_defaults = load_unit_class_defaults()

    # Map BTS combat types to our class names
    combat_map = {
        "UNITCOMBAT_MELEE": "melee",
        "UNITCOMBAT_MOUNTED": "mounted",
        "UNITCOMBAT_ARCHERY": "archery",
        "UNITCOMBAT_ARCHER": "archery",  # BTS uses both ARCHER and ARCHERY
        "UNITCOMBAT_SIEGE": "siege",
        "UNITCOMBAT_GUN": "gunpowder",
        "UNITCOMBAT_GUNPOWDER": "gunpowder",
        "UNITCOMBAT_ARMOR": "armor",
        "UNITCOMBAT_HELICOPTER": "helicopter",
        "UNITCOMBAT_NAVAL": "naval",
        "UNITCOMBAT_RECON": "recon",
        "UNITCOMBAT_AIR": "air",
        "UNITCOMBAT_MISSIONARY": "missionary",
    }

    # Map BTS domain to our fields
    domain_map = {
        "DOMAIN_LAND": "land",
        "DOMAIN_SEA": "sea",
        "DOMAIN_AIR": "air",
    }

    units = {}

    for info in root.iter(ns + "UnitInfo"):
        bts_type = find_text(info, ns, "Type")
        if not bts_type:
            continue

        # Skip animals and special units
        if "ANIMAL" in bts_type or bts_type in ("UNIT_NEANDERTHAL",):
            continue

        key = bts_id_to_key(bts_type, "UNIT_")

        # Basic stats
        unit = {
            "name": find_text(info, ns, "Description", key.replace("_", " ").title()),
            "bts_type": bts_type,
            "cost": find_int(info, ns, "iCost"),
            "strength": find_float(info, ns, "iCombat"),
            "movement": find_int(info, ns, "iMoves", 1),
            "required_tech": bts_id_to_key(find_text(info, ns, "PrereqTech"), "TECH_"),
        }

        # Unit class (combat type) — BTS uses "Combat" tag, not "UnitCombatType"
        combat_type = find_text(info, ns, "Combat")
        if not combat_type:
            combat_type = find_text(info, ns, "UnitCombatType")
        unit["unit_class"] = combat_map.get(combat_type, "")

        # Domain
        domain = find_text(info, ns, "DomainType")
        unit["domain"] = domain_map.get(domain, "land")

        # Resource prerequisites (OR-style: need any one of these)
        prereq_bonuses = []
        ors = info.find(ns + "PrereqBonuses")
        if ors is not None:
            for o in ors.findall(ns + "BonusType"):
                if o.text and o.text != "NONE":
                    prereq_bonuses.append(bts_id_to_key(o.text, "BONUS_"))

        # Single prereq bonus (BonusType is direct child of UnitInfo)
        prereq1 = find_text(info, ns, "BonusType")
        if not prereq1:
            prereq1 = find_text(info, ns, "PrereqBonus")
        if prereq1:
            prereq_bonuses.insert(0, bts_id_to_key(prereq1, "BONUS_"))

        # AND-style prereq
        prereq_and = []
        ands = info.find(ns + "PrereqBonusClassAnds")
        if ands is not None:
            for a in ands:
                bt = a.find(ns + "BonusType")
                if bt is not None and bt.text and bt.text != "NONE":
                    prereq_and.append(bts_id_to_key(bt.text, "BONUS_"))

        # BTS logic: BonusType is primary required resource.
        # PrereqBonuses is a SECONDARY requirement (need any one from the list).
        # If BonusType exists AND PrereqBonuses has entries, it's AND (need both).
        # If only PrereqBonuses exists (no BonusType), it's OR (need any one).
        if prereq1:
            unit["required_resource"] = bts_id_to_key(prereq1, "BONUS_")
            # PrereqBonuses becomes AND requirement when BonusType exists
            or_bonuses = []
            ors2 = info.find(ns + "PrereqBonuses")
            if ors2 is not None:
                for o2 in ors2.findall(ns + "BonusType"):
                    if o2.text and o2.text != "NONE":
                        or_bonuses.append(bts_id_to_key(o2.text, "BONUS_"))
            if or_bonuses:
                unit["required_resource_2"] = or_bonuses[0]
        elif prereq_bonuses:
            # No BonusType, just PrereqBonuses = OR list
            unit["required_resource"] = prereq_bonuses[0]
            if len(prereq_bonuses) > 1:
                unit["required_resource_or"] = prereq_bonuses[1]
        else:
            unit["required_resource"] = ""

        if prereq_and:
            unit["required_resource_2"] = prereq_and[0]

        # Combat modifiers (bonus_vs)
        bonus_vs = {}
        mods = info.find(ns + "UnitCombatMods")
        if mods is not None:
            for mod in mods.findall(ns + "UnitCombatMod"):
                ct = find_text(mod, ns, "UnitCombatType")
                cv = find_int(mod, ns, "iUnitCombatMod")
                if ct and cv:
                    cls = combat_map.get(ct, ct.lower().replace("unitcombat_", ""))
                    bonus_vs[cls] = cv / 100.0
        if bonus_vs:
            unit["bonus_vs"] = bonus_vs

        # Defense modifiers vs unit classes
        def_mods = {}
        defs = info.find(ns + "UnitClassDefenseMods")
        if defs is not None:
            for mod in defs.findall(ns + "UnitClassDefenseMod"):
                ct = find_text(mod, ns, "UnitClassType")
                cv = find_int(mod, ns, "iUnitClassMod")
                if ct and cv:
                    cls = bts_id_to_key(ct, "UNITCLASS_")
                    def_mods[cls] = cv / 100.0
        if def_mods:
            unit["bonus_vs_defense"] = def_mods

        # Special abilities
        unit["withdrawal_chance"] = find_int(info, ns, "iWithdrawalProb") / 100.0 if find_int(info, ns, "iWithdrawalProb") else 0
        unit["first_strikes"] = find_int(info, ns, "iFirstStrikes")
        unit["first_strike_chances"] = find_int(info, ns, "iFirstStrikeChances")
        unit["collateral_damage"] = find_int(info, ns, "iCollateralDamageLimit")
        unit["bombard_rate"] = find_int(info, ns, "iBombRate")
        unit["intercept_chance"] = find_int(info, ns, "iInterceptionProbability") / 100.0 if find_int(info, ns, "iInterceptionProbability") else 0
        unit["air_range"] = find_int(info, ns, "iAirRange")
        unit["cargo"] = find_int(info, ns, "iCargo")
        unit["no_defense_bonus"] = find_bool(info, ns, "bNoDefensiveBonus")
        unit["can_found_city"] = find_bool(info, ns, "bFound")

        # Nuke range
        nuke = find_int(info, ns, "iNukeRange", -1)
        if nuke >= 0:
            unit["nuke_range"] = nuke

        # Free promotions
        free_promos = find_list(info, ns, "FreePromotions", "FreePromotion", "PromotionType")
        if free_promos:
            unit["free_promotions"] = [bts_id_to_key(p, "PROMOTION_") for p in free_promos]

        # Upgrade paths
        upgrades = find_list(info, ns, "UnitClassUpgrades", "UnitClassUpgrade", "UnitClassUpgradeType")
        if upgrades:
            # Map class to default unit
            upgrade_units = []
            for uc in upgrades:
                default = class_defaults.get(uc, "")
                if default:
                    upgrade_units.append(bts_id_to_key(default, "UNIT_"))
            if upgrade_units:
                unit["upgrades_to"] = upgrade_units[0]  # Primary upgrade
                if len(upgrade_units) > 1:
                    unit["upgrades_to_alt"] = upgrade_units[1:]

        # Obsolete tech
        obs_tech = find_text(info, ns, "ObsoleteTech")
        if obs_tech:
            unit["obsolete_tech"] = bts_id_to_key(obs_tech, "TECH_")

        # Ocean travel (for naval)
        ocean = find_text(info, ns, "TerrainImpassables")
        # If TERRAIN_OCEAN is NOT in impassables, unit can cross ocean
        if domain == "DOMAIN_SEA":
            impassables = []
            terr_imp = info.find(ns + "TerrainImpassables")
            if terr_imp is not None:
                for ti in terr_imp.findall(ns + "TerrainImpassable"):
                    tt = find_text(ti, ns, "TerrainType")
                    bp = find_text(ti, ns, "bTerrainImpassable")
                    if tt and bp == "1":
                        impassables.append(tt)
            unit["ocean_travel"] = "TERRAIN_OCEAN" not in impassables

        # UU mapping
        if bts_type in unique_units:
            uu_info = unique_units[bts_type]
            unit["civilization"] = uu_info["civ"]
            if uu_info["replaces_default"]:
                unit["replaces"] = bts_id_to_key(uu_info["replaces_default"], "UNIT_")

        # Strip zero/empty/false values to keep JSON clean
        # But preserve fields the game code expects to always exist
        always_keep = {"cost", "strength", "movement", "required_tech",
                       "required_resource", "unit_class", "name"}
        clean = {}
        for k, v in unit.items():
            if k in always_keep:
                clean[k] = v
                continue
            if v == 0 or v == 0.0 or v == "" or v == False:
                continue
            if v == [] or v == {}:
                continue
            clean[k] = v

        units[key] = clean

    return units


# --- Extract Buildings ---
def extract_buildings():
    """Parse CIV4BuildingInfos.xml into buildings dict."""
    path = BTS_XML / "Buildings" / "CIV4BuildingInfos.xml"
    ns = "{x-schema:CIV4BuildingsSchema.xml}"
    tree = ET.parse(str(path))
    root = tree.getroot()

    unique_buildings = load_civ_unique_buildings()

    # Load building class info for wonder types
    bc_path = BTS_XML / "Buildings" / "CIV4BuildingClassInfos.xml"
    bc_tree = ET.parse(str(bc_path))
    bc_root = bc_tree.getroot()

    wonder_classes = set()  # classes with iMaxGlobalInstances=1
    national_classes = set()  # classes with iMaxPlayerInstances=1
    for info in bc_root.iter(ns + "BuildingClassInfo"):
        bc_type = find_text(info, ns, "Type")
        max_global = find_int(info, ns, "iMaxGlobalInstances", -1)
        max_player = find_int(info, ns, "iMaxPlayerInstances", -1)
        if max_global == 1:
            wonder_classes.add(bc_type)
        elif max_player == 1:
            national_classes.add(bc_type)

    buildings = {}

    for info in root.iter(ns + "BuildingInfo"):
        bts_type = find_text(info, ns, "Type")
        if not bts_type:
            continue

        key = bts_id_to_key(bts_type, "BUILDING_")
        bld_class = find_text(info, ns, "BuildingClass")

        building = {
            "name": find_text(info, ns, "Description", key.replace("_", " ").title()),
            "bts_type": bts_type,
            "cost": find_int(info, ns, "iCost"),
            "required_tech": bts_id_to_key(find_text(info, ns, "PrereqTech"), "TECH_"),
        }

        # Wonder type
        if bld_class in wonder_classes:
            building["wonder_type"] = "world"
        elif bld_class in national_classes:
            building["wonder_type"] = "national"

        # Obsolete tech
        obs = find_text(info, ns, "ObsoleteTech")
        if obs:
            building["obsolete_tech"] = bts_id_to_key(obs, "TECH_")

        # Required buildings
        req_blds = []
        prereq_el = info.find(ns + "PrereqBuildings")
        if prereq_el is not None:
            for pb in prereq_el:
                bt = find_text(pb, ns, "BuildingType")
                if bt:
                    req_blds.append(bts_id_to_key(bt, "BUILDING_"))
        # Also check BuildingClassNeededs
        needs_el = info.find(ns + "BuildingClassNeededs")
        if needs_el is not None:
            for bcn in needs_el.findall(ns + "BuildingClassNeeded"):
                bct = find_text(bcn, ns, "BuildingClassType")
                if bct:
                    req_blds.append(bts_id_to_key(bct, "BUILDINGCLASS_"))
        if req_blds:
            building["required_buildings"] = req_blds

        # Effects
        effects = {}

        # Yield changes (food, production, commerce)
        yield_changes = info.find(ns + "YieldChanges")
        if yield_changes is not None:
            yields = [find_int(yc, ns, "iYield") for yc in yield_changes.findall(ns + "iYield")]
            # BTS order: food, production, commerce
            if len(yields) >= 1 and yields[0]: effects["food"] = yields[0]
            if len(yields) >= 2 and yields[1]: effects["production"] = yields[1]
            if len(yields) >= 3 and yields[2]: effects["commerce"] = yields[2]

        # Yield modifiers (percentages)
        yield_mods = info.find(ns + "YieldModifiers")
        if yield_mods is not None:
            mods = [find_int(ym, ns, "iYield") for ym in yield_mods.findall(ns + "iYield")]
            if len(mods) >= 1 and mods[0]: effects["food_percent"] = mods[0] / 100.0
            if len(mods) >= 2 and mods[1]: effects["production_percent"] = mods[1] / 100.0
            if len(mods) >= 3 and mods[2]: effects["commerce_percent"] = mods[2] / 100.0

        # Commerce changes (gold, research, culture, espionage)
        commerce = info.find(ns + "CommerceChanges")
        if commerce is not None:
            vals = [find_int(cc, ns, "iCommerce") for cc in commerce.findall(ns + "iCommerce")]
            if len(vals) >= 1 and vals[0]: effects["gold"] = vals[0]
            if len(vals) >= 2 and vals[1]: effects["science"] = vals[1]
            if len(vals) >= 3 and vals[2]: effects["culture"] = vals[2]
            if len(vals) >= 4 and vals[3]: effects["espionage"] = vals[3]

        # Commerce modifiers (percentages)
        comm_mods = info.find(ns + "CommerceModifiers")
        if comm_mods is not None:
            mods = [find_int(cm, ns, "iCommerce") for cm in comm_mods.findall(ns + "iCommerce")]
            if len(mods) >= 1 and mods[0]: effects["gold_percent"] = mods[0] / 100.0
            if len(mods) >= 2 and mods[1]: effects["science_percent"] = mods[1] / 100.0
            if len(mods) >= 3 and mods[2]: effects["culture_percent"] = mods[2] / 100.0
            if len(mods) >= 4 and mods[3]: effects["espionage_percent"] = mods[3] / 100.0

        # Happiness / Health
        happiness = find_int(info, ns, "iHappiness")
        if happiness: effects["happiness"] = happiness
        health = find_int(info, ns, "iHealth")
        if health: effects["health"] = health

        # Global happiness/health
        g_happy = find_int(info, ns, "iAreaHappiness")
        if g_happy: effects["happiness_area"] = g_happy
        gg_happy = find_int(info, ns, "iGlobalHappiness")
        if gg_happy: effects["happiness_all_cities"] = gg_happy
        g_health = find_int(info, ns, "iAreaHealth")
        if g_health: effects["health_area"] = g_health
        gg_health = find_int(info, ns, "iGlobalHealth")
        if gg_health: effects["health_all_cities"] = gg_health

        # Defense
        defense = find_int(info, ns, "iDefenseModifier")
        if defense: effects["defense"] = defense / 100.0

        # Experience
        xp = find_int(info, ns, "iFreeExperience")
        if xp: effects["free_experience"] = xp

        # Trade routes
        trade = find_int(info, ns, "iTradeRoutes")
        if trade: effects["trade_routes"] = trade

        # Great people
        gp_rate = find_int(info, ns, "iGreatPeopleRateChange")
        if gp_rate:
            # Determine GP type from GreatPeopleUnitClass
            gp_class = find_text(info, ns, "GreatPeopleUnitClass")
            gp_map = {
                "UNITCLASS_PROPHET": "great_prophet_points",
                "UNITCLASS_ARTIST": "great_artist_points",
                "UNITCLASS_SCIENTIST": "great_scientist_points",
                "UNITCLASS_MERCHANT": "great_merchant_points",
                "UNITCLASS_ENGINEER": "great_engineer_points",
                "UNITCLASS_GREAT_SPY": "great_spy_points",
                "UNITCLASS_GREAT_GENERAL": "great_general_points",
            }
            gp_key = gp_map.get(gp_class, "great_person_points")
            effects[gp_key] = gp_rate

        # Free tech
        if find_bool(info, ns, "bFreeTech"):
            effects["free_tech"] = True

        # Golden age
        if find_bool(info, ns, "bGoldenAge"):
            effects["golden_age"] = True

        # Power
        if find_bool(info, ns, "bPower"):
            effects["provides_power"] = True

        # Food kept on growth
        food_kept = find_int(info, ns, "iFoodKept")
        if food_kept: effects["food_stored_on_growth"] = food_kept / 100.0

        # Maintenance modifier
        maint_mod = find_int(info, ns, "iMaintenanceModifier")
        if maint_mod: effects["maintenance_reduction"] = abs(maint_mod) / 100.0

        # Space production modifier
        space = find_int(info, ns, "iSpaceProductionModifier")
        if space: effects["space_production_percent"] = space / 100.0

        # Military production modifier
        mil_prod = find_int(info, ns, "iMilitaryProductionModifier")
        if mil_prod: effects["military_production_percent"] = mil_prod / 100.0

        # Free specialist slots
        free_spec = info.find(ns + "FreeSpecialistCounts")
        if free_spec is not None:
            for fs in free_spec.findall(ns + "FreeSpecialistCount"):
                st = find_text(fs, ns, "SpecialistType")
                sc = find_int(fs, ns, "iCount")
                if st and sc:
                    spec_key = bts_id_to_key(st, "SPECIALIST_")
                    effects[f"free_{spec_key}s"] = sc

        # Specialist slots (SpecialistCounts)
        spec_counts = info.find(ns + "SpecialistCounts")
        if spec_counts is not None:
            for sc_el in spec_counts.findall(ns + "SpecialistCount"):
                st = find_text(sc_el, ns, "SpecialistType")
                sc = find_int(sc_el, ns, "iSpecialistCount")
                if st and sc:
                    spec_key = bts_id_to_key(st, "SPECIALIST_")
                    effects[f"{spec_key}_slots"] = sc

        # Religion prereq
        prereq_religion = find_text(info, ns, "PrereqReligion")
        if prereq_religion:
            building["required_religion"] = bts_id_to_key(prereq_religion, "RELIGION_")

        # Requires holy city
        if find_bool(info, ns, "bHolyCity"):
            building["requires_holy_city"] = True

        # Government center (palace-like)
        if find_bool(info, ns, "bGovernmentCenter"):
            effects["second_palace"] = True

        # UB mapping
        if bts_type in unique_buildings:
            ub_info = unique_buildings[bts_type]
            building["civilization"] = ub_info["civ"]
            if ub_info["replaces_default"]:
                building["replaces"] = bts_id_to_key(ub_info["replaces_default"], "BUILDING_")

        if effects:
            building["effects"] = effects

        buildings[key] = building

    return buildings


# --- Extract Techs ---
def extract_techs():
    """Parse CIV4TechInfos.xml into techs dict."""
    path = BTS_XML / "Technologies" / "CIV4TechInfos.xml"
    ns = "{x-schema:CIV4TechnologiesSchema.xml}"
    tree = ET.parse(str(path))
    root = tree.getroot()

    techs = {}

    for info in root.iter(ns + "TechInfo"):
        bts_type = find_text(info, ns, "Type")
        if not bts_type:
            continue

        key = bts_id_to_key(bts_type, "TECH_")

        tech = {
            "name": find_text(info, ns, "Description", key.replace("_", " ").title()),
            "bts_type": bts_type,
            "cost": find_int(info, ns, "iCost"),
            "era": bts_id_to_key(find_text(info, ns, "Era"), "ERA_"),
        }

        # Grid position
        tech["grid_x"] = find_int(info, ns, "iGridX")
        tech["grid_y"] = find_int(info, ns, "iGridY")

        # Prerequisites (AND)
        prereqs = find_list(info, ns, "AndPreReqs", "PrereqTech")
        if prereqs:
            tech["prerequisites"] = [bts_id_to_key(p, "TECH_") for p in prereqs]

        # OR Prerequisites
        or_prereqs = find_list(info, ns, "OrPreReqs", "PrereqTech")
        if or_prereqs:
            tech["or_prerequisites"] = [bts_id_to_key(p, "TECH_") for p in or_prereqs]

        # Reveals resource
        reveals = find_text(info, ns, "FirstFreeUnitClass")  # Not quite right...
        # Check for BonusReveals
        bonus_reveals = info.find(ns + "BonusReveals")
        if bonus_reveals is not None:
            for br in bonus_reveals.findall(ns + "BonusReveal"):
                bt = find_text(br, ns, "BonusType")
                if bt:
                    tech["reveals_resource"] = bts_id_to_key(bt, "BONUS_")
                    break

        techs[key] = tech

    return techs


# --- Merge with Existing ---
def merge_data(extracted, existing, preserve_keys=None):
    """Merge extracted BTS data with existing KulturIV data.

    - New entries from BTS are added
    - Existing entries get BTS stats updated
    - KulturIV-only fields (symbol, description, etc.) are preserved
    """
    if preserve_keys is None:
        preserve_keys = {"symbol", "description", "era", "_note"}

    merged = {}

    # Start with extracted data
    for key, data in extracted.items():
        if key in existing and isinstance(existing[key], dict):
            # Merge: keep existing KulturIV fields, update from BTS
            entry = {}
            # First, copy preserved fields from existing
            for pk in preserve_keys:
                if pk in existing[key]:
                    entry[pk] = existing[key][pk]
            # Then overlay all BTS data
            entry.update(data)
            merged[key] = entry
        else:
            merged[key] = data

    # Keep any KulturIV-only entries not in BTS
    for key, data in existing.items():
        if key not in merged and isinstance(data, dict):
            data["_kulturiv_only"] = True
            merged[key] = data

    return merged


# --- Main ---
def main():
    args = sys.argv[1:]
    if not args:
        args = ["--all"]

    do_all = "--all" in args
    do_units = "--units" in args or do_all
    do_buildings = "--buildings" in args or do_all
    do_techs = "--techs" in args or do_all
    dry_run = "--dry-run" in args
    do_merge = "--merge" in args

    if do_units:
        print("Extracting units from BTS XML...")
        units = extract_units()
        print(f"  Found {len(units)} units")

        if do_merge and (DATA_DIR / "units.json").exists():
            with open(DATA_DIR / "units.json") as f:
                existing = json.load(f)
            units = merge_data(units, existing)
            print(f"  Merged with existing: {len(units)} total")

        if dry_run:
            print(json.dumps(units, indent=2)[:5000])
        else:
            with open(DATA_DIR / "units_bts.json", "w") as f:
                json.dump(units, f, indent=2)
            print(f"  Written to data/units_bts.json")

    if do_buildings:
        print("Extracting buildings from BTS XML...")
        buildings = extract_buildings()
        print(f"  Found {len(buildings)} buildings")

        if do_merge and (DATA_DIR / "buildings.json").exists():
            with open(DATA_DIR / "buildings.json") as f:
                existing = json.load(f)
            buildings = merge_data(buildings, existing)
            print(f"  Merged with existing: {len(buildings)} total")

        if dry_run:
            print(json.dumps(buildings, indent=2)[:5000])
        else:
            with open(DATA_DIR / "buildings_bts.json", "w") as f:
                json.dump(buildings, f, indent=2)
            print(f"  Written to data/buildings_bts.json")

    if do_techs:
        print("Extracting techs from BTS XML...")
        techs = extract_techs()
        print(f"  Found {len(techs)} techs")

        if do_merge and (DATA_DIR / "techs.json").exists():
            with open(DATA_DIR / "techs.json") as f:
                existing = json.load(f)
            techs = merge_data(techs, existing)
            print(f"  Merged with existing: {len(techs)} total")

        if dry_run:
            print(json.dumps(techs, indent=2)[:5000])
        else:
            with open(DATA_DIR / "techs_bts.json", "w") as f:
                json.dump(techs, f, indent=2)
            print(f"  Written to data/techs_bts.json")

    print("\nDone! Output written to data/*_bts.json files.")
    print("Review the _bts.json files, then rename to replace the originals when ready.")


if __name__ == "__main__":
    main()
