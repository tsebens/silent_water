class_name DevMenu
extends Control
## Developer-only connect menu. Not part of the game's diegetic UI.

signal host_requested(port: int)
signal join_requested(address: String, port: int)
signal terrain_lab_requested

@onready var _address: LineEdit = %Address
@onready var _port: SpinBox = %Port


func _ready() -> void:
	_address.text = Net.DEFAULT_ADDRESS
	_port.value = Net.DEFAULT_PORT
	(%Host as Button).pressed.connect(func() -> void: host_requested.emit(int(_port.value)))
	(%Join as Button).pressed.connect(
		func() -> void: join_requested.emit(_address.text.strip_edges(), int(_port.value))
	)
	(%TerrainLab as Button).pressed.connect(func() -> void: terrain_lab_requested.emit())
