extends SceneTree

## One-shot diagnostic: fetches each official mission page, runs the real
## parser, prints the facts found and dumps the extracted text so the
## filtering rules can be tuned against actual page content.

var started := false

func _initialize() -> void:
	pass

func _process(_delta: float) -> bool:
	if not started:
		started = true
		_run()
	return false

func _run() -> void:
	var live = load("res://scripts/simulation/DashboardLive.gd").new()
	root.add_child(live)
	var pages: Dictionary = {
		"JPSS-2": "https://science.nasa.gov/mission/jpss/",
		"SWOT": "https://science.nasa.gov/mission/swot/",
		"TEMPO": "https://science.nasa.gov/mission/tempo/",
	}
	for mode in pages:
		var req := HTTPRequest.new()
		req.timeout = 25.0
		root.add_child(req)
		var err := req.request(String(pages[mode]))
		if err != OK:
			print("%s request() failed: %d" % [mode, err])
			quit(1)
			return
		var out: Array = await req.request_completed
		var result: int = out[0]
		var code: int = out[1]
		var body: PackedByteArray = out[3]
		var html := body.get_string_from_utf8() if result == HTTPRequest.RESULT_SUCCESS and code == 200 else ""
		print("%s result=%d code=%d bytes=%d" % [mode, result, code, body.size()])
		var facts: Array = live._parse_facts(html)
		print("%s facts=%d" % [mode, facts.size()])
		for f in facts:
			print("  - ", f)
		var txt: String = live._extract_text(html)
		var file := FileAccess.open("res://tools/_diag_parse_%s.txt" % mode, FileAccess.WRITE)
		if file:
			file.store_string(txt.substr(0, 40000))
			file.close()
	print("done")
	quit(0)
