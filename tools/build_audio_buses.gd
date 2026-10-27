extends SceneTree
## Creates res://default_bus_layout.tres: Master <- Ambience, SFX, Voices.
## SFX and Voices get a concrete-room reverb; Voices also a low-pass for muffling.
func _init() -> void:
	var layout := AudioBusLayout.new()
	ResourceSaver.save(layout, "res://default_bus_layout.tres")
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(1)
	for spec in [["Ambience", -6.0], ["SFX", 0.0], ["Voices", 0.0]]:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, spec[0])
		AudioServer.set_bus_volume_db(i, spec[1])
		AudioServer.set_bus_send(i, "Master")
		if spec[0] != "Ambience":
			var rv := AudioEffectReverb.new()
			rv.room_size = 0.7
			rv.damping = 0.6
			rv.wet = 0.22 if spec[0] == "SFX" else 0.3
			rv.dry = 1.0
			AudioServer.add_bus_effect(i, rv)
	ResourceSaver.save(AudioServer.generate_bus_layout(), "res://default_bus_layout.tres")
	print("bus layout saved: ", AudioServer.bus_count, " buses")
	quit()
