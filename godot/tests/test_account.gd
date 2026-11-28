extends TestCase
## Accounts: guest play, development email accounts with hashed passwords,
## password reset, providers that refuse when unconfigured, profiles kept
## apart from saves, and the character choice.


func test_guest_and_email_accounts() -> void:
	Account.sign_out()
	check(not Account.signed_in(), "signed out to begin")
	var g := Account.sign_in_guest()
	check(g.ok, "guest sign-in works")
	var guest_id := String(Account.profile.account_id)
	check(guest_id.begins_with("guest-"), "a guest id")
	check(Account.save_path().contains(guest_id), "the guest's journey has its own save file")
	Account.sign_out()
	Account.sign_in_guest()
	check(String(Account.profile.account_id) == guest_id, "a returning guest is the same guest")
	Account.sign_out()
	var email := "test%d@example.com" % randi()
	check(not Account.register("not-an-email", "longenough", "X").ok, "a bad email is refused")
	check(not Account.register(email, "short", "X").ok, "a short password is refused")
	var r := Account.register(email, "correct horse", "Tester")
	check(r.ok, "registration works")
	check(Account.profile.display_name == "Tester", "the profile carries the name")
	var stored := FileAccess.get_file_as_string(Account.ACCOUNTS_PATH)
	check(not stored.contains("correct horse"), "the password itself is never stored")
	check(not Account.register(email, "another one", "Y").ok, "the same email cannot register twice")
	Account.sign_out()
	check(not Account.sign_in_email(email, "wrong password").ok, "a wrong password is refused")
	check(Account.sign_in_email(email, "correct horse").ok, "the right one signs in")
	var acc_id := String(Account.profile.account_id)
	check(acc_id != guest_id, "a different account from the guest")
	# Reset.
	Account.sign_out()
	var req := Account.request_password_reset(email)
	check(req.ok and String(req.dev_code).length() == 6, "a reset code is issued (development: shown on screen)")
	check(not Account.confirm_password_reset(email, "000000" if req.dev_code != "000000" else "111111", "new password!").ok, "a wrong code is refused")
	check(Account.confirm_password_reset(email, req.dev_code, "new password!").ok, "the right code sets the new password")
	check(not Account.sign_in_email(email, "correct horse").ok, "the old password no longer works")
	check(Account.sign_in_email(email, "new password!").ok, "the new one does")
	Account.sign_out()


func test_providers_refuse_without_configuration() -> void:
	Account.sign_out()
	for which in ["google", "apple"]:
		check(not Account.provider_available(which), "%s is not configured in this build" % which)
		var r := Account.provider_sign_in(which)
		check(not r.ok and String(r.error).contains("not available"), "%s sign-in explains why it cannot sign in" % which)
		check(not Account.signed_in(), "and nobody is signed in by it")


func test_character_choice() -> void:
	Account.sign_out()
	Account.sign_in_guest()
	check(not Account.set_character("hero"), "Kael cannot be chosen: not in this build")
	check(Account.set_character("heroine"), "the heroine can")
	check(Account.character_kit() == "player", "and the game builds her model")
	Account.set_start_island("coast")
	Account.sign_out()
	Account.sign_in_guest()
	check(Account.profile.start_island == "coast", "the start island is remembered on the profile")
	Account.set_start_island("")
	Account.sign_out()
