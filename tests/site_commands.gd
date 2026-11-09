extends SceneTree

const EXE := "C:/x/AgentGuildBuilders.exe"

func _initialize() -> void:
	var page := FileAccess.get_file_as_string("res://site/index.md").replace("\r\n", "\n")
	var commands: Array = load("res://src/ui/main.gd").connect_commands(EXE, [])
	var failed := 0
	for entry in commands:
		var wanted: String = entry[1].replace("'%s'" % EXE, "$exe") if entry[0] != "Docker Agent" else entry[1].replace(EXE, "<exe>")
		if not page.contains(wanted):
			failed += 1
			printerr("FAIL the page's %s step isn't the Connect dialog's command: %s" % [entry[0], wanted])
	print("site commands: %d of %d match" % [commands.size() - failed, commands.size()])
	quit(1 if failed else 0)
