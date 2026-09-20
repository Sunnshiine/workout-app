# Onboarding

Onboarding connects the athlete's Google account and training sheet. After sign-in the sheet picker lists the account's spreadsheets; choosing one syncs it and lands on its Current Session, never on a stale cached Block.

## Sub-features

- `onboarding-connect` shows the `Connect Google Sheet` call to action when signed out.
- `onboarding-pick` lists spreadsheets and selects one.
- `onboarding-sync-land` syncs the chosen sheet and shows its freshly parsed session.
- `onboarding-url` accepts a pasted spreadsheet URL instead of the list.

## How to get to it (user POV)

- First launch, or after Sign Out from Settings.
- Signed in with no sheet selected (`onboarding` fixture).

## Driving it with verify.sh

Preconditions:

- `verify.sh launch onboarding` landed on `Choose your training sheet` with no `Back Squat` in the tree.
- The list shows one row labeled `Replacement Training Log, 25y ago`.

- **List.** Capture the picker. Run `verify.sh shot picker`. The tree has the `Replacement Training Log` row and `Paste a URL instead`.
- **Pick.** Tap the row. Run `verify.sh tap --label "Replacement Training Log, 25y ago"`. The stage appears with `find stage-exercise-name` reading `Replacement Squat`, and `verify.sh tree --all | grep "Back Squat"` prints nothing, so the stale seeded Block is gone.
- **URL entry.** From a fresh `onboarding` launch, run `verify.sh tap --label "Paste a URL instead"`. A URL field and `onboarding-url-back-button` appear. Run `verify.sh tap --id onboarding-url-back-button` to return.
- **Signed-out wall.** Launch `settings`, run `verify.sh tap --id settings-sign-out-button`. `onboarding-connect-button` labeled `Connect Google Sheet` appears with `onboarding-title` reading `Plant the program.`
- **Proof.** Shoot the picker and the landed stage. Quote the `Replacement Squat` line and the absence of `Back Squat`.

## Gotchas

- `Connect Google Sheet` opens real Google sign-in. Fixture mode cannot complete it, so the connect path is proof of the wall only.
- The row label includes the modified date (`25y ago`, from the fixture's epoch date). Match the full label or tap by coordinates from the tree.
- The stale Block is in the store on purpose. Seeing `Back Squat` after picking the sheet is the bug this path guards against.
