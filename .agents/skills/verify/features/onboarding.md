# Onboarding

Onboarding connects the athlete's Google account and training sheet. After sign-in the sheet picker lists the account's spreadsheets; choosing one, or pasting its URL, syncs it and lands on its Current Session, never on a stale cached Block.

## Sub-features

- `onboarding-connect` shows the `Connect Google Sheet` call to action when signed out.
- `onboarding-pick` lists spreadsheets and selects one.
- `onboarding-sync-land` syncs the chosen sheet and shows its freshly parsed session.
- `onboarding-url` accepts a pasted spreadsheet URL instead of the list, and rejects text that is not one.

## How to get to it (user POV)

- First launch, or after Sign Out from Settings.
- Signed in with no sheet selected (`onboarding` fixture).

## Driving it with verify.sh

Preconditions:

- `verify.sh launch onboarding` landed on `Choose your training sheet` with no `Back Squat` in the tree.
- The list shows one row labeled `Replacement Training Log, 25y ago`.

- **List.** Capture the picker. Run `verify.sh shot picker`. The tree has the `Replacement Training Log` row and `Paste a URL instead`.
- **Pick.** Tap the row. Run `verify.sh tap --label "Replacement Training Log, 25y ago"`, then `verify.sh shot landed`. The stage appears with `find stage-exercise-name` reading `Replacement Squat`, and `verify.sh tree --all | grep "Back Squat"` prints nothing, so the stale seeded Block is gone.
- **URL entry.** Launch `onboarding`. Run `verify.sh tap --label "Paste a URL instead"`. `Paste your sheet URL`, `onboarding-url-field`, `onboarding-url-back-button`, and `Save` appear. `verify.sh tap --id onboarding-url-back-button` returns to the picker; open URL entry again. Run `verify.sh tap --id onboarding-url-field` to focus it, `verify.sh type junk`, then `verify.sh tap --label Save`. `That doesn't look like a Sheet URL` appears. Run `verify.sh axe key 42` once. `find onboarding-url-field` reads `jun` and `verify.sh tree --all | grep "look like a Sheet URL"` prints nothing, because any edit clears the error, not only one that makes the URL valid. Run `verify.sh axe key 42` three more times, then `verify.sh type "https://docs.google.com/spreadsheets/d/REPLACEMENT/edit"`. `find onboarding-url-field` reads the URL and the grep still prints nothing. Run `verify.sh tap --label Save`. `find stage-exercise-name` reads `Replacement Squat`.
- **Signed-out wall.** Launch `session`, then reveal the session controls and tap the gear as `settings.md` **From the stage** does, stopping before its `settings-done-button` tap. Run `verify.sh tap --id settings-sign-out-button`. `onboarding-connect-button` labeled `Connect Google Sheet` appears with `onboarding-title` reading `Plant the program.`

## Gotchas

- `Connect Google Sheet` opens real Google sign-in. Fixture mode cannot complete it, so the connect path is proof of the wall only.
- The row label ends in the sheet's age, counted from today (`25y ago` until 2027). Read the live label from `verify.sh tree` and match all of it.
- The stale Block is in the store on purpose. Seeing `Back Squat` after picking the sheet is the bug this path guards against.
- `onboarding-url-field` reads its placeholder as its value until the athlete types, so an untouched field shows `Google Sheet URL` in both the label and the value column. Assert the typed URL, not an empty value.
