class_name LoginPanel
extends Control
## Sign-in on the title screen. Pages:
##   choose   — Continue with Google / Apple, Email, Play as Guest
##   email    — sign in with email + password
##   register — create an email account
##   reset    — request a reset code, then set a new password
##   legal    — the privacy policy or terms
## Email accounts are DEVELOPMENT accounts kept on this device (the page says
## so); Google and Apple only sign in when the build carries their plugin
## and credentials, otherwise they explain why they cannot.
## Emits `signed_in` once Account holds a profile.

signal signed_in

var _box: VBoxContainer
var _error: Label
var _busy := false
var _page := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	show_page("choose")


func show_page(page: String, data := {}) -> void:
	_page = page
	for c in get_children():
		c.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.02, 0.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var p := UiKit.panel(Vector2(700, 0))
	p.position = Vector2(80, 300)
	add_child(p)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 16)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(_box)
	_error = UiKit.label("", 24, UiKit.ERROR)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(600, 0)
	match page:
		"choose":
			_heading("Welcome, traveller", "Sign in to keep your journey")
			_add(UiKit.button("Continue with Google", _provider.bind("google"), "normal", 600))
			_add(UiKit.button("Continue with Apple", _provider.bind("apple"), "normal", 600))
			if not Account.provider_available("google") and not Account.provider_available("apple"):
				var note := UiKit.label("Google and Apple sign-in are not set up in this build yet.", 20, UiKit.DIM, "italic")
				note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				note.custom_minimum_size = Vector2(600, 0)
				_box.add_child(note)
			_add(UiKit.button("Sign in with Email", show_page.bind("email"), "normal", 600))
			_add(UiKit.button("Play as Guest", _guest, "primary", 600))
			_box.add_child(_error)
			_legal_links()
		"email":
			_heading("Sign in", "Development account · stored on this device")
			var em := _field("Email", false, data.get("email", ""))
			var pw := _field("Password", true)
			_box.add_child(_error)
			_add(UiKit.button("Sign in", func(): _run(func(): return Account.sign_in_email(em.text, pw.text)), "primary", 600))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.add_child(UiKit.button("Create account", show_page.bind("register"), "quiet", 290, 52))
			row.add_child(UiKit.button("Forgot password?", show_page.bind("reset", {"email": em.text}), "quiet", 290, 52))
			_box.add_child(row)
			_add(UiKit.button("Back", show_page.bind("choose"), "quiet", 600, 52))
			pw.text_submitted.connect(func(_t): _run(func(): return Account.sign_in_email(em.text, pw.text)))
		"register":
			_heading("Create account", "Development account · stored on this device")
			var nm := _field("Name shown in game")
			var em := _field("Email")
			var pw := _field("Password (8+ characters)", true)
			var pw2 := _field("Confirm password", true)
			_box.add_child(_error)
			_add(UiKit.button("Create account", func():
				if pw.text != pw2.text:
					_fail("The passwords do not match.")
					return
				_run(func(): return Account.register(em.text, pw.text, nm.text)), "primary", 600))
			_add(UiKit.button("Back", show_page.bind("email"), "quiet", 600, 52))
		"reset":
			_heading("Reset password", "")
			var em := _field("Email", false, data.get("email", ""))
			var note := UiKit.label("DEVELOPMENT MODE: no email service is configured, so the reset code is shown here instead of being emailed.", 22, UiKit.DIM)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(600, 0)
			_box.add_child(note)
			var code := _field("Reset code")
			var pw := _field("New password", true)
			_box.add_child(_error)
			_add(UiKit.button("Send reset code", func():
				var r := Account.request_password_reset(em.text)
				if r.ok:
					_error.add_theme_color_override("font_color", UiKit.GOLD)
					_error.text = "Your reset code (development): %s" % r.dev_code
				else:
					_fail(r.error), "normal", 600))
			_add(UiKit.button("Set new password", func():
				var r := Account.confirm_password_reset(em.text, code.text, pw.text)
				if r.ok:
					show_page("email", {"email": em.text})
				else:
					_fail(r.error), "primary", 600))
			_add(UiKit.button("Back", show_page.bind("email"), "quiet", 600, 52))
		"legal":
			_heading(data.get("title", ""), "")
			var scroll := ScrollContainer.new()
			scroll.custom_minimum_size = Vector2(600, 520)
			var text := UiKit.label(_read_text(data.get("file", "")), 22, UiKit.PALE)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.custom_minimum_size = Vector2(570, 0)
			scroll.add_child(text)
			_box.add_child(scroll)
			_add(UiKit.button("Back", show_page.bind("choose"), "quiet", 600, 52))
	UiKit.appear(p)


func _heading(title: String, sub: String) -> void:
	var t := UiKit.label(title.to_upper(), 34, UiKit.PALE, "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(t)
	_box.add_child(UiKit.divider(560))
	if sub != "":
		var s := UiKit.label(sub, 26, UiKit.DIM, "italic")
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(s)


func _add(c: Control) -> void:
	_box.add_child(c)


func _field(placeholder: String, secret := false, value := "") -> LineEdit:
	var e := UiKit.field(placeholder, secret, 600)
	e.text = value
	_box.add_child(e)
	return e


func _legal_links() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.button("Privacy Policy", show_page.bind("legal", {"title": "Privacy Policy", "file": "res://assets/legal/privacy.txt"}), "quiet", 280, 52))
	row.add_child(UiKit.button("Terms of Use", show_page.bind("legal", {"title": "Terms of Use", "file": "res://assets/legal/terms.txt"}), "quiet", 280, 52))
	_box.add_child(row)


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""


func _guest() -> void:
	_run(func(): return Account.sign_in_guest())


func _provider(which: String) -> void:
	_run(func(): return Account.provider_sign_in(which))


func _fail(msg: String) -> void:
	_error.add_theme_color_override("font_color", UiKit.ERROR)
	_error.text = msg
	var t := _error.create_tween()
	_error.position.x = 0
	for i in 3:
		t.tween_property(_error, "position:x", 8.0, 0.04)
		t.tween_property(_error, "position:x", -8.0, 0.04)
	t.tween_property(_error, "position:x", 0.0, 0.04)


## Disable the page's buttons, show the working state for a frame (password
## hashing is deliberately slow), then report.
func _run(work: Callable) -> void:
	if _busy:
		return
	_busy = true
	_set_enabled(false)
	_error.add_theme_color_override("font_color", UiKit.DIM)
	_error.text = "Signing in…"
	await get_tree().process_frame
	await get_tree().process_frame
	var r: Dictionary = work.call()
	_busy = false
	if not is_inside_tree():
		return
	_set_enabled(true)
	if r.get("ok", false):
		_error.text = ""
		signed_in.emit()
	else:
		_fail(String(r.get("error", "Something went wrong.")))


func _set_enabled(on: bool) -> void:
	for c in _box.find_children("*", "Button", true, false):
		(c as Button).disabled = not on
