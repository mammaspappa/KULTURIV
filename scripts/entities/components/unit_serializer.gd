class_name UnitSerializer
extends RefCounted
## Unit save/load marshalling, extracted from unit.gd as part of Phase 5.
##
## Save format is intentionally flat (no nested components) to keep the v2 save schema stable.
## When the unit is later split into composition components (Phase 5+), each component should
## still serialize through this class so the on-disk shape doesn't change without a migrator.

const UnitOrder = preload("res://scripts/entities/unit.gd").UnitOrder

static func to_dict(unit) -> Dictionary:
	return {
		"unit_id": unit.unit_id,
		"owner_id": unit.player_owner.player_id if unit.player_owner else -1,
		"grid_position": {"x": unit.grid_position.x, "y": unit.grid_position.y},
		"health": unit.health,
		"experience": unit.experience,
		"level": unit.level,
		"movement_remaining": unit.movement_remaining,
		"is_fortified": unit.is_fortified,
		"fortify_bonus": unit.fortify_bonus,
		"promotions": unit.promotions,
		"current_order": unit.current_order,
		"order_target_improvement": unit.order_target_improvement,
		"build_progress": unit.build_progress,
		"has_attached_general": unit.attached_great_general != null,
	}

static func from_dict(unit, data: Dictionary) -> void:
	unit.unit_id = data.get("unit_id", "warrior")
	unit.grid_position = Vector2i(data.grid_position.x, data.grid_position.y)
	unit.health = data.get("health", 100.0)
	unit.experience = data.get("experience", 0)
	unit.level = data.get("level", 1)
	unit.movement_remaining = data.get("movement_remaining", 0.0)
	unit.is_fortified = data.get("is_fortified", false)
	unit.fortify_bonus = data.get("fortify_bonus", 0.0)
	unit.promotions.assign(data.get("promotions", []))
	unit.current_order = data.get("current_order", UnitOrder.NONE)
	unit.order_target_improvement = data.get("order_target_improvement", "")
	unit.build_progress = data.get("build_progress", 0)
	# For attached general, we use a placeholder since the actual general was consumed
	if data.get("has_attached_general", false):
		unit.attached_great_general = unit  # Non-null marker
	unit.position = GridUtils.grid_to_pixel(unit.grid_position)
	unit.update_visual()
