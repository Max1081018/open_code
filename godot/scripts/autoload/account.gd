extends Node
## Accounts and the player profile, kept apart from gameplay saves.
##
## Providers:
##   guest   — a device-local account; the id is remembered so a returning
##             guest keeps their journey.
##   email   — DEVELOPMENT accounts stored on this device only (salted,
##             iterated SHA-256). There is no server in this build, so they
##             do not follow the player to another device, and password
##             reset shows its code on screen instead of emailing it.
##   google / apple — real sign-in needs a platform plugin and provider
##             credentials (see AUTH_CONFIG). Without them `provider_sign_in`
##             fails with a clear message; it never signs anyone in.
##
## Profile (one per account, user://profiles/<id>.json):
##   account_id, provider, display_name, email, selected_character,
##   unlocked_characters, start_island, created, last_played, version
## Each account's journey lives in its own save: `save_path()`.

signal changed

const ACCOUNTS_PATH := "user://accounts.json"
const SESSION_PATH := "user://session.json"
const PROFILE_DIR := "user://profiles"
const SAVE_DIR := "user://saves"
const AUTH_CONFIG := "res://auth_config.json"
const PROFILE_VERSION := 1
const HASH_ROUNDS := 12000
const LEGACY_SAVE := "user://starfall3d.save"

## The characters a profile can hold and which are playable in this build.
const CHARACTERS := {
	"heroine": {"name": "Lyra", "playable": true, "kit": "player"},
	"hero": {"name": "Kael", "playable": false, "kit": ""},
}

var profile: Dictionary = {}
var _reset_codes := {}   ## email -> [code, expires_unix]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(PROFILE_DIR)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_resume_session()


func signed_in() -> bool:
	return not profile.is_empty()


func provider() -> String:
	return String(profile.get("provider", ""))


# ------------------------------------------------------------- guest ---

func sign_in_guest() -> Dictionary:
	var accounts := _read_json(ACCOUNTS_PATH)
	var gid: String = String(accounts.get("_guest", ""))
	if gid == "":
		gid = "guest-" + _random_id()
		accounts["_guest"] = gid
		_write_json(ACCOUNTS_PATH, accounts)
	_open_profile(gid, "guest", "Traveller", "")
	# A journey begun before accounts existed belongs to the device's guest.
	if FileAccess.file_exists(LEGACY_SAVE) and not FileAccess.file_exists(save_path()):
		DirAccess.copy_absolute(LEGACY_SAVE, save_path())
	return {"ok": true}


# ------------------------------------------------------ email (dev) ---

func register(email: String, password: String, display_name: String) -> Dictionary:
	email = email.strip_edges().to_lower()
	var err := _check_email(email)
	if err != "":
		return {"ok": false, "error": err}
	if password.length() < 8:
		return {"ok": false, "error": "Use at least 8 characters for the password."}
	var accounts := _read_json(ACCOUNTS_PATH)
	var users: Dictionary = accounts.get("users", {})
	if users.has(email):
		return {"ok": false, "error": "An account with this email already exists."}
	var salt := _random_id()
	var id := "acc-" + _random_id()
	users[email] = {"id": id, "salt": salt, "hash": _hash(password, salt), "name": display_name.strip_edges()}
	accounts["users"] = users
	if not _write_json(ACCOUNTS_PATH, accounts):
		return {"ok": false, "error": "Could not save the account on this device."}
	_open_profile(id, "email", display_name.strip_edges() if display_name.strip_edges() != "" else email.get_slice("@", 0), email)
	return {"ok": true}


func sign_in_email(email: String, password: String) -> Dictionary:
	email = email.strip_edges().to_lower()
	var users: Dictionary = _read_json(ACCOUNTS_PATH).get("users", {})
	var u: Dictionary = users.get(email, {})
	if u.is_empty() or _hash(password, String(u.salt)) != String(u.hash):
		return {"ok": false, "error": "Email or password is incorrect."}
	_open_profile(String(u.id), "email", String(u.get("name", email)), email)
	return {"ok": true}


## Development reset: no mail service exists in this build, so the code is
## returned for the screen to show (clearly labelled) instead of emailed.
func request_password_reset(email: String) -> Dictionary:
	email = email.strip_edges().to_lower()
	var users: Dictionary = _read_json(ACCOUNTS_PATH).get("users", {})
	if not users.has(email):
		return {"ok": false, "error": "No account uses that email on this device."}
	var code := "%06d" % (randi() % 1000000)
	_reset_codes[email] = [code, Time.get_unix_time_from_system() + 600]
	return {"ok": true, "dev_code": code}


func confirm_password_reset(email: String, code: String, new_password: String) -> Dictionary:
	email = email.strip_edges().to_lower()
	var r: Array = _reset_codes.get(email, [])
	if r.is_empty() or String(r[0]) != code.strip_edges() or Time.get_unix_time_from_system() > float(r[1]):
		return {"ok": false, "error": "That code is wrong or has expired."}
	if new_password.length() < 8:
		return {"ok": false, "error": "Use at least 8 characters for the password."}
	var accounts := _read_json(ACCOUNTS_PATH)
	var users: Dictionary = accounts.get("users", {})
	var u: Dictionary = users[email]
	u.salt = _random_id()
	u.hash = _hash(new_password, String(u.salt))
	users[email] = u
	accounts["users"] = users
	_write_json(ACCOUNTS_PATH, accounts)
	_reset_codes.erase(email)
	return {"ok": true}


# ------------------------------------------------- google / apple ---

## True when this build carries both the platform plugin and credentials.
func provider_available(which: String) -> bool:
	var cfg := _read_json(AUTH_CONFIG)
	var conf: Dictionary = cfg.get(which, {})
	if conf.is_empty() or String(conf.get("client_id", "")) == "":
		return false
	var plugin := "GodotGoogleSignIn" if which == "google" else "GodotAppleSignIn"
	return Engine.has_singleton(plugin)


## Real provider sign-in. Without a configured provider this fails: it never
## pretends to authenticate.
func provider_sign_in(which: String) -> Dictionary:
	var label := "Google" if which == "google" else "Apple"
	if not provider_available(which):
		return {"ok": false, "error": "%s sign-in is not available in this build yet. Play as a guest: your journey is saved on this device." % label}
	# A configured build hands the token to the plugin's verified flow; the
	# account id is the provider's stable user id.
	var plugin := Engine.get_singleton("GodotGoogleSignIn" if which == "google" else "GodotAppleSignIn")
	var result: Dictionary = plugin.call("sign_in")
	if not result.get("ok", false):
		return {"ok": false, "error": String(result.get("error", "%s sign-in was cancelled." % label))}
	_open_profile(which + "-" + String(result.user_id), which, String(result.get("name", label + " player")), String(result.get("email", "")))
	return {"ok": true}


# ------------------------------------------------------------ profile ---

func sign_out() -> void:
	profile = {}
	DirAccess.remove_absolute(SESSION_PATH)
	changed.emit()


## The CharacterKit model of the chosen character (the heroine by default).
func character_kit() -> String:
	var id := String(profile.get("selected_character", "heroine"))
	var c: Dictionary = CHARACTERS.get(id, CHARACTERS.heroine)
	return String(c.kit) if c.playable else "player"


func save_path() -> String:
	if profile.is_empty():
		return LEGACY_SAVE
	return "%s/%s.save" % [SAVE_DIR, String(profile.account_id)]


func set_character(id: String) -> bool:
	if not CHARACTERS.has(id) or not CHARACTERS[id].playable or not id in profile.get("unlocked_characters", []):
		return false
	profile.selected_character = id
	_store_profile()
	return true


func set_start_island(id: String) -> void:
	if not signed_in():
		return   # no profile to keep it in (writing one made a broken profile)
	profile.start_island = id
	_store_profile()


func touch() -> void:
	if signed_in():
		profile.last_played = int(Time.get_unix_time_from_system())
		_store_profile()


func _open_profile(id: String, the_provider: String, display_name: String, email: String) -> void:
	var p := _read_json("%s/%s.json" % [PROFILE_DIR, id])
	profile = _validated(p, id, the_provider, display_name, email)
	_store_profile()
	_write_json(SESSION_PATH, {"account_id": id, "provider": the_provider})
	changed.emit()


## A loaded profile with every field present and of the right type.
func _validated(p: Dictionary, id: String, the_provider: String, display_name: String, email: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var out := {
		"version": PROFILE_VERSION,
		"account_id": id,
		"provider": the_provider,
		"display_name": display_name,
		"email": email,
		"selected_character": "heroine",
		"unlocked_characters": ["heroine"],
		"start_island": "",
		"created": now,
		"last_played": now,
	}
	for k in out:
		if p.has(k) and typeof(p[k]) == typeof(out[k]) and k not in ["account_id", "provider", "version"]:
			out[k] = p[k]
	if not CHARACTERS.has(out.selected_character) or not CHARACTERS[out.selected_character].playable:
		out.selected_character = "heroine"
	return out


func _resume_session() -> void:
	var s := _read_json(SESSION_PATH)
	var id := String(s.get("account_id", ""))
	if id == "":
		return
	var p := _read_json("%s/%s.json" % [PROFILE_DIR, id])
	if p.is_empty():
		return
	profile = _validated(p, id, String(s.get("provider", p.get("provider", "guest"))), String(p.get("display_name", "")), String(p.get("email", "")))


func _store_profile() -> void:
	if profile.has("account_id"):
		_write_json("%s/%s.json" % [PROFILE_DIR, String(profile.account_id)], profile)


# ------------------------------------------------------------ helpers ---

func _check_email(email: String) -> String:
	var re := RegEx.create_from_string("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
	return "" if re.search(email) else "Enter a valid email address."


func _hash(password: String, salt: String) -> String:
	var digest := (salt + ":" + password).to_utf8_buffer()
	for i in HASH_ROUNDS:
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA256)
		h.update(digest)
		h.update(salt.to_utf8_buffer())
		digest = h.finish()
	return digest.hex_encode()


func _random_id() -> String:
	return Crypto.new().generate_random_bytes(12).hex_encode()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


## Atomic: temp file then rename, so a crash never leaves half a file.
func _write_json(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK
