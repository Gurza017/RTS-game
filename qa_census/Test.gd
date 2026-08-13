extends Node

## ПЕРЕПИСЬ СЦЕНЫ: из чего на самом деле состоит карта.
## Нужна, чтобы решения по декорациям принимались по числам, а не на глаз.
## Запуск: godot --headless --path . res://qa_census/Test.tscn

const MAIN := preload("res://scenes/Main.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var by_class: Dictionary = {}
	var mesh_owners: Dictionary = {}
	var total := 0
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		total += 1
		var c := n.get_class()
		by_class[c] = int(by_class.get(c, 0)) + 1
		# У кого именно висят MeshInstance3D — по скрипту владельца ветки
		if n is MeshInstance3D:
			var owner_name := "(_world напрямую)"
			var p := n.get_parent()
			while p != null and p != main:
				var scr: Script = p.get_script()
				if scr != null:
					owner_name = scr.resource_path.get_file()
					break
				p = p.get_parent()
			mesh_owners[owner_name] = int(mesh_owners.get(owner_name, 0)) + 1
		for ch in n.get_children():
			stack.append(ch)

	var out := PackedStringArray()
	out.append("")
	out.append("═══ ПЕРЕПИСЬ Main.tscn ═══")
	out.append("узлов всего: %d" % total)
	out.append("Performance.OBJECT_NODE_COUNT: %d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	out.append("")
	out.append("── по классам (что чаще 5 раз) ──")
	var rows: Array = []
	for k in by_class:
		rows.append([k, by_class[k]])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for r in rows:
		if int(r[1]) >= 5:
			out.append("  %-28s %6d" % [r[0], r[1]])
	out.append("")
	out.append("── MeshInstance3D по владельцу ветки ──")
	var rows2: Array = []
	for k in mesh_owners:
		rows2.append([k, mesh_owners[k]])
	rows2.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for r in rows2:
		out.append("  %-28s %6d" % [r[0], r[1]])
	out.append("")
	out.append("ресурсных узлов в группе resource_nodes: %d"
		% get_tree().get_nodes_in_group("resource_nodes").size())
	print("\n".join(out))
	get_tree().quit(0)
