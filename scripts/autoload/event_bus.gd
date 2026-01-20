extends Node
## Global event bus for decoupled communication between game systems.
## All game events are defined as signals here.

# Turn events
signal turn_started(turn_number, player)
signal turn_ended(turn_number, player)
signal all_turns_completed(turn_number)

# Unit events
signal unit_created(unit)
signal unit_destroyed(unit)
signal unit_selected(unit)
signal unit_deselected(unit)
signal unit_moved(unit, from_hex, to_hex)
signal unit_movement_finished(unit)
signal unit_attacked(attacker, defender)
signal unit_promoted(unit, promotion)
signal unit_healed(unit, amount)
signal unit_order_changed(unit, order)

# City events
signal city_founded(city, founder)
signal city_captured(city, old_owner, new_owner)
signal city_destroyed(city)
signal city_selected(city)
signal city_deselected(city)
signal city_grew(city, new_population)
signal city_starving(city)
signal city_production_completed(city, item)
signal city_building_constructed(city, building)
signal city_borders_expanded(city)

# Combat events
signal combat_started(attacker, defender)
signal combat_round(attacker, defender, attacker_damage, defender_damage)
signal combat_ended(winner, loser)
signal first_strike(attacker, defender, damage)
signal unit_withdrew(unit)

# Research events
signal research_started(player, tech)
signal research_completed(player, tech)
signal tech_unlocked(player, tech)

# Diplomacy events
signal war_declared(aggressor, target)
signal peace_declared(player1, player2)
signal trade_proposed(from_player, to_player, offer)
signal trade_accepted(from_player, to_player, offer)
signal trade_rejected(from_player, to_player)
signal first_contact(player1, player2)
signal open_borders_signed(player1, player2)
signal defensive_pact_signed(player1, player2)

# Religion events
signal religion_founded(player, religion, holy_city)
signal religion_spread(religion, city)
signal state_religion_adopted(player, religion)

# Civic events
signal civic_changed(player, category, civic_id)
signal anarchy_started(player, turns)
signal anarchy_ended(player)

# Corporation events
signal corporation_founded(corporation_id, city, founder)
signal corporation_spread(corporation_id, city)
signal corporation_destroyed(corporation_id)
signal corporation_hq_moved(corporation_id, new_city)

# Espionage events
signal espionage_points_changed(player_id, target_id, new_amount)
signal espionage_mission_executed(player_id, target_id, mission_id, result)
signal espionage_discovered(victim_id, perpetrator_id, mission_id)
signal spy_placed(spy_unit, city)
signal spy_captured(spy_unit, city)
signal spy_escaped(spy_unit)

# Project events
signal project_completed(player_id, project_id, city)
signal spaceship_ready(player_id)
signal spaceship_launched(player_id, success)

# Random event signals
signal random_event_triggered(event_data)
signal random_event_resolved(player_id, event_id, choice_index)

# Voting/UN signals
signal vote_source_activated(source_id, city)
signal vote_session_started(source_id, secretary_id, available_resolutions)
signal secretary_election_started(source_id, candidates)
signal secretary_elected(source_id, player_id)
signal vote_started(source_id, resolution_id, proposer_id)
signal vote_completed(source_id, resolution_id, passed, result)

# Culture events
signal culture_expanded(city, new_radius)
signal great_person_born(city, great_person_type)

# Victory events
signal victory_achieved(player, victory_type)
signal game_over(winner, victory_type)

# Map events
signal tile_revealed(hex, player)
signal tile_improved(hex, improvement)
signal resource_discovered(hex, resource)
signal fog_updated(player)

# UI events
signal selection_changed(selected)
signal show_city_screen(city)
signal hide_city_screen()
signal show_tech_tree()
signal hide_tech_tree()
signal show_diplomacy_screen(player)
signal hide_diplomacy_screen()
signal show_civics_screen()
signal hide_civics_screen()
signal show_trade_screen(from_player, to_player)
signal hide_trade_screen()
signal notification_added(message, type_name)

# Game state events
signal game_started()
signal game_loaded()
signal game_saved()
signal game_paused()
signal game_resumed()
