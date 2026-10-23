class_name Interactable
extends Node3D
## Objeto con el que el jugador puede interactuar (cofre, portal, tienda).
## El jugador busca el más cercano del grupo "interactable" y el HUD muestra el botón.

var prompt := "Interactuar"
var radius := 2.8
var enabled := true
var callback: Callable = Callable()
var kind := "generic"


func _ready() -> void:
	add_to_group("interactable")


func activate(player: Node) -> void:
	if enabled and callback.is_valid():
		callback.call(self)
