#!/usr/bin/env python3
"""
Extract BTS leader personality data from CIV4LeaderHeadInfos.xml
and merge into leaders.json.
"""

import xml.etree.ElementTree as ET
import json
import os

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LEADERS_XML = os.path.join(BASE_DIR, "beyond", "Beyond the Sword", "Assets", "XML", "Civilizations", "CIV4LeaderHeadInfos.xml")
LEADERS_JSON = os.path.join(BASE_DIR, "data", "leaders.json")

# Map BTS leader names to our JSON IDs
BTS_TO_JSON = {
    "LEADER_ALEXANDER": "alexander",
    "LEADER_AUGUSTUS": "augustus_caesar",
    "LEADER_ASOKA": "asoka",
    "LEADER_BISMARCK": "bismarck",
    "LEADER_BOUDICA": "boudica",
    "LEADER_BRENNUS": "brennus",
    "LEADER_CATHERINE": "catherine",
    "LEADER_CHARLEMAGNE": "charlemagne",
    "LEADER_CHURCHILL": "churchill",
    "LEADER_CYRUS": "cyrus",
    "LEADER_DARIUS": "darius",
    "LEADER_DE_GAULLE": "de_gaulle",
    "LEADER_ELIZABETH": "elizabeth",
    "LEADER_FREDERICK": "frederick",
    "LEADER_GANDHI": "gandhi",
    "LEADER_GENGHIS_KHAN": "genghis_khan",
    "LEADER_GILGAMESH": "gilgamesh",
    "LEADER_HAMMURABI": "hammurabi",
    "LEADER_HANNIBAL": "hannibal",
    "LEADER_HATSHEPSUT": "hatshepsut",
    "LEADER_HUAYNA_CAPAC": "huayna_capac",
    "LEADER_ISABELLA": "isabella",
    "LEADER_JOAO": "joao",
    "LEADER_JULIUS_CAESAR": "julius_caesar",
    "LEADER_JUSTINIAN": "justinian",
    "LEADER_KUBLAI_KHAN": "kublai_khan",
    "LEADER_LINCOLN": "lincoln",
    "LEADER_LOUIS_XIV": "louis_xiv",
    "LEADER_MANSA_MUSA": "mansa_musa",
    "LEADER_MAO": "mao_zedong",
    "LEADER_MEHMED": "mehmed",
    "LEADER_MONTEZUMA": "montezuma",
    "LEADER_NAPOLEON": "napoleon",
    "LEADER_PACAL": "pacal",
    "LEADER_PERICLES": "pericles",
    "LEADER_PETER": "peter",
    "LEADER_QIN_SHI_HUANG": "qin_shi_huang",
    "LEADER_RAGNAR": "ragnar",
    "LEADER_RAMESSES": "ramesses",
    "LEADER_ROOSEVELT": "roosevelt",
    "LEADER_SALADIN": "saladin",
    "LEADER_SHAKA": "shaka",
    "LEADER_SITTING_BULL": "sitting_bull",
    "LEADER_STALIN": "stalin",
    "LEADER_SULEIMAN": "suleiman",
    "LEADER_SURYAVARMAN": "suryavarman",
    "LEADER_TOKUGAWA": "tokugawa",
    "LEADER_VICTORIA": "victoria",
    "LEADER_WANG_KON": "wang_kon",
    "LEADER_WASHINGTON": "washington",
    "LEADER_WILLEM": "willem_van_oranje",
    "LEADER_ZARA_YAQOB": "zara_yaqob",
}

# Map BTS civic names to our JSON IDs
CIVIC_MAP = {
    "CIVIC_DESPOTISM": "despotism",
    "CIVIC_HEREDITARY_RULE": "hereditary_rule",
    "CIVIC_POLICE_STATE": "police_state",
    "CIVIC_REPRESENTATION": "representation",
    "CIVIC_UNIVERSAL_SUFFRAGE": "universal_suffrage",
    "CIVIC_BARBARISM": "barbarism",
    "CIVIC_SLAVERY": "slavery",
    "CIVIC_SERFDOM": "serfdom",
    "CIVIC_CASTE_SYSTEM": "caste_system",
    "CIVIC_EMANCIPATION": "emancipation",
    "CIVIC_TRIBALISM": "tribalism",
    "CIVIC_VASSALAGE": "vassalage",
    "CIVIC_BUREAUCRACY": "bureaucracy",
    "CIVIC_NATIONHOOD": "nationhood",
    "CIVIC_FREE_SPEECH": "free_speech",
    "CIVIC_DECENTRALIZATION": "decentralization",
    "CIVIC_MERCANTILISM": "mercantilism",
    "CIVIC_FREE_MARKET": "free_market",
    "CIVIC_STATE_PROPERTY": "state_property",
    "CIVIC_ENVIRONMENTALISM": "environmentalism",
    "CIVIC_ORGANIZED_RELIGION": "organized_religion",
    "CIVIC_THEOCRACY": "theocracy",
    "CIVIC_PACIFISM": "pacifism",
    "CIVIC_FREE_RELIGION": "free_religion",
}

RELIGION_MAP = {
    "RELIGION_BUDDHISM": "buddhism",
    "RELIGION_HINDUISM": "hinduism",
    "RELIGION_JUDAISM": "judaism",
    "RELIGION_CONFUCIANISM": "confucianism",
    "RELIGION_CHRISTIANITY": "christianity",
    "RELIGION_TAOISM": "taoism",
    "RELIGION_ISLAM": "islam",
    "NONE": "",
}

# BTS flavor type mapping
FLAVOR_MAP = {
    "FLAVOR_MILITARY": "military",
    "FLAVOR_RELIGION": "religion",
    "FLAVOR_PRODUCTION": "production",
    "FLAVOR_GOLD": "gold",
    "FLAVOR_SCIENCE": "science",
    "FLAVOR_CULTURE": "culture",
    "FLAVOR_GROWTH": "growth",
}


def get_xml_text(elem, tag, ns, default="0"):
    child = elem.find(f"{ns}{tag}")
    if child is not None and child.text:
        return child.text.strip()
    return default


def parse_leaders_xml():
    tree = ET.parse(LEADERS_XML)
    root = tree.getroot()
    ns = root.tag[:root.tag.index('}') + 1] if '}' in root.tag else ''

    container = None
    for child in root:
        if 'LeaderHeadInfos' in child.tag:
            container = child
            break

    if container is None:
        print("ERROR: Could not find LeaderHeadInfos element")
        return {}

    leaders = {}
    for info in container:
        leader_type = get_xml_text(info, "Type", ns, "")
        if not leader_type:
            continue

        # Core personality values
        data = {
            "base_attitude": int(get_xml_text(info, "iBaseAttitude", ns, "0")),
            "base_peace_weight": int(get_xml_text(info, "iBasePeaceWeight", ns, "5")),
            "warmonger_respect": int(get_xml_text(info, "iWarmongerRespect", ns, "1")),
            "espionage_weight": int(get_xml_text(info, "iEspionageWeight", ns, "80")),
            "max_war_rand": int(get_xml_text(info, "iMaxWarRand", ns, "100")),
            "make_peace_rand": int(get_xml_text(info, "iMakePeaceRand", ns, "30")),
            "dogpile_war_rand": int(get_xml_text(info, "iDogpileWarRand", ns, "50")),
            "raze_city_prob": int(get_xml_text(info, "iRazeCityProb", ns, "20")),
            "build_unit_prob": int(get_xml_text(info, "iBuildUnitProb", ns, "40")),
            "wonder_construct_rand": int(get_xml_text(info, "iWonderConstructRand", ns, "30")),
            "base_attack_odds_change": int(get_xml_text(info, "iBaseAttackOddsChange", ns, "0")),
        }

        # Favorite civic
        fav_civic = get_xml_text(info, "FavoriteCivic", ns, "NONE")
        data["favorite_civic"] = CIVIC_MAP.get(fav_civic, "")

        # Favorite religion
        fav_religion = get_xml_text(info, "FavoriteReligion", ns, "NONE")
        data["favorite_religion"] = RELIGION_MAP.get(fav_religion, "")

        # Flavor values
        flavors = {}
        flavors_elem = info.find(f"{ns}Flavors")
        if flavors_elem is not None:
            for flavor_entry in flavors_elem:
                ftype = flavor_entry.find(f"{ns}FlavorType")
                fval = flavor_entry.find(f"{ns}iFlavor")
                if ftype is not None and fval is not None:
                    json_flavor = FLAVOR_MAP.get(ftype.text, None)
                    if json_flavor:
                        flavors[json_flavor] = int(fval.text)
        if flavors:
            data["flavor"] = flavors

        # Diplomatic thresholds
        thresholds = {}
        for threshold_name in ["DeclareWarRefuseAttitudeThreshold", "NoTechTradeThreshold",
                               "OpenBordersRefuseAttitudeThreshold", "DefensivePactRefuseAttitudeThreshold",
                               "DemandTributeAttitudeThreshold"]:
            val = get_xml_text(info, threshold_name, ns, "")
            if val and val != "NONE":
                # Convert ATTITUDE_X to integer (FURIOUS=0, ANNOYED=1, CAUTIOUS=2, PLEASED=3, FRIENDLY=4)
                attitude_map = {
                    "ATTITUDE_FURIOUS": 0, "ATTITUDE_ANNOYED": 1,
                    "ATTITUDE_CAUTIOUS": 2, "ATTITUDE_PLEASED": 3, "ATTITUDE_FRIENDLY": 4
                }
                thresholds[threshold_name] = attitude_map.get(val, 2)

        if thresholds:
            data["diplomatic_thresholds"] = thresholds

        leaders[leader_type] = data

    return leaders


def update_leaders_json():
    bts_leaders = parse_leaders_xml()
    print(f"Parsed {len(bts_leaders)} leaders from BTS XML")

    with open(LEADERS_JSON, "r") as f:
        json_data = json.load(f)

    changes = 0
    for bts_type, bts_data in bts_leaders.items():
        json_id = BTS_TO_JSON.get(bts_type)
        if json_id is None or json_id not in json_data:
            continue

        leader = json_data[json_id]
        leader_changes = []

        # Add personality fields
        for key in ["base_attitude", "base_peace_weight", "warmonger_respect",
                     "espionage_weight", "max_war_rand", "make_peace_rand",
                     "dogpile_war_rand", "raze_city_prob", "build_unit_prob",
                     "wonder_construct_rand", "base_attack_odds_change"]:
            if key in bts_data:
                old_val = leader.get(key, None)
                leader[key] = bts_data[key]
                if old_val != bts_data[key]:
                    leader_changes.append(f"  {key}: {old_val} -> {bts_data[key]}")

        # Update favorite civic
        if bts_data.get("favorite_civic"):
            old = leader.get("favorite_civic", "")
            if old != bts_data["favorite_civic"]:
                leader["favorite_civic"] = bts_data["favorite_civic"]
                leader_changes.append(f"  favorite_civic: {old} -> {bts_data['favorite_civic']}")

        # Add favorite religion
        if "favorite_religion" in bts_data:
            leader["favorite_religion"] = bts_data["favorite_religion"]

        # Update flavor values from BTS
        if "flavor" in bts_data:
            if "flavor" not in leader:
                leader["flavor"] = {}
            for fkey, fval in bts_data["flavor"].items():
                old = leader["flavor"].get(fkey, None)
                leader["flavor"][fkey] = fval
                if old != fval:
                    leader_changes.append(f"  flavor.{fkey}: {old} -> {fval}")

        # Add diplomatic thresholds
        if "diplomatic_thresholds" in bts_data:
            leader["diplomatic_thresholds"] = bts_data["diplomatic_thresholds"]

        if leader_changes:
            changes += 1
            print(f"\n{json_id} ({bts_type}):")
            for c in leader_changes[:10]:  # Limit output
                print(c)
            if len(leader_changes) > 10:
                print(f"  ... and {len(leader_changes) - 10} more")

    # Write updated JSON
    with open(LEADERS_JSON, "w") as f:
        json.dump(json_data, f, indent="\t", ensure_ascii=False)
        f.write("\n")

    print(f"\nUpdated {changes} leaders in leaders.json")


if __name__ == "__main__":
    update_leaders_json()
