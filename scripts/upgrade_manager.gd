extends Control
## Upgrade selection screen shown on level-up (game is paused during display).

@onready var card_container: HBoxContainer = $Panel/VBox/CardContainer
@onready var title_label:    Label          = $Panel/VBox/TitleLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # runs while paused
	hide()
	GameManager.upgrade_available.connect(_show_upgrades)

func _show_upgrades(choices: Array) -> void:
	# Remove previous cards
	for child in card_container.get_children():
		child.queue_free()

	title_label.text = "LEVEL UP!  Lv %d" % GameManager.current_level

	for upgrade in choices:
		card_container.add_child(_build_card(upgrade))

	show()

func _build_card(upgrade: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(140, 210)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	# Upgrade name
	var name_lbl := Label.new()
	name_lbl.text = upgrade["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = upgrade["desc"]
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.modulate = Color(0.8, 0.9, 1.0)
	vbox.add_child(desc_lbl)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Select button
	var btn := Button.new()
	btn.text = "SELECT"
	btn.pressed.connect(func(): _on_select(upgrade))
	vbox.add_child(btn)

	return card

func _on_select(upgrade: Dictionary) -> void:
	hide()
	GameManager.apply_upgrade(upgrade)
