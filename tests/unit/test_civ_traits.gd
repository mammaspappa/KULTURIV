extends "res://addons/gut/test.gd"
## Phase 2 acceptance tests: civilizations with the "barbarian" trait are recognized as such,
## while normal civilizations are not. Replaces the old hardcoded id == "barbarian" checks.

const PlayerClass = preload("res://scripts/core/player.gd")

func test_barbarian_civ_has_barbarian_trait():
	var p = PlayerClass.new()
	p.player_id = -1
	p.civilization_id = "barbarian"
	assert_true(p.has_civ_trait("barbarian"))
	assert_true(p.is_barbarian())

func test_barbarian_civ_has_minor_trait():
	var p = PlayerClass.new()
	p.civilization_id = "barbarian"
	assert_true(p.has_civ_trait("minor"))

func test_normal_civ_is_not_barbarian():
	# Pick the first non-barbarian civ in the data.
	var first_normal = ""
	for cid in DataManager.civs.keys():
		if cid == "barbarian":
			continue
		first_normal = cid
		break
	assert_ne(first_normal, "", "expected at least one non-barbarian civ in civs.json")

	var p = PlayerClass.new()
	p.civilization_id = first_normal
	assert_false(p.is_barbarian(), "%s must not be barbarian" % first_normal)
	assert_false(p.has_civ_trait("barbarian"))

func test_unknown_civ_is_not_barbarian():
	var p = PlayerClass.new()
	p.civilization_id = "nonexistent_civ_id"
	assert_false(p.is_barbarian())
