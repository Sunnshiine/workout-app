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
- **URL entry.** Launch `onboarding`. Run `verify.sh tap --label "Paste a URL instead"`. `Paste your sheet URL`, `onboarding-url-back-button`, and `Save` appear. `verify.sh tap --id onboarding-url-back-button` returns to the picker; open URL entry again. The field itself is not in the tree, so focus it with a tap between the title and `Save` (`verify.sh tap -x 201 -y 470` on this device). Run `verify.sh type junk`, then `verify.sh tap --label Save`. `That doesn't look like a Sheet URL` appears. Run `verify.sh axe key 42` four times, `verify.sh type "https://docs.google.com/spreadsheets/d/REPLACEMENT/edit"`, then `verify.sh tap --label Save`. `find stage-exercise-name` reads `Replacement Squat`.
- **Signed-out wall.** Launch `session`, open Settings from the stage (`settings.md`, **From the stage**), and run `verify.sh tap --id settings-sign-out-button`. `onboarding-connect-button` labeled `Connect Google Sheet` appears with `onboarding-title` reading `Plant the program.`

## Gotchas

- `Connect Google Sheet` opens real Google sign-in. Fixture mode cannot complete it, so the connect path is proof of the wall only.
- The row label ends in the sheet's age, counted from today (`25y ago` until 2027). Read the live label from `verify.sh tree` and match all of it.
- The stale Block is in the store on purpose. Seeing `Back Squat` after picking the sheet is the bug this path guards against.
