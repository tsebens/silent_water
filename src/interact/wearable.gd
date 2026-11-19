class_name Wearable
extends Interactable
## Something a player puts on and keeps on (the sonar headset). Click to put
## on, click again to take off. The cord is short: walking more than
## [member cord_length] from it takes it off. One wearer at a time.

signal worn_changed(worn_locally: bool)

@export var cord_length: float = 2.2


func _ready() -> void:
	super._ready()
	holder_changed.connect(func(peer_id: int) -> void: visible = peer_id == InteractableState.NO_HOLDER)


func begin_interaction() -> void:
	super.begin_interaction()
	worn_changed.emit(true)


func end_interaction() -> void:
	var was: bool = is_held_locally()
	super.end_interaction()
	if was:
		worn_changed.emit(false)


func _on_lost_hold() -> void:
	worn_changed.emit(false)


func interaction_hint() -> String:
	return "press E to put on · E again to take off"
