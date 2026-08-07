# Localization

Everything the player reads lives in `Number Reef/Localizable.xcstrings`. No view
branches on a language code.

The app offers **77 languages**. Two of them — English and Dutch — are really
translated; the other 75 carry a complete copy of the English text, every unit
marked `new`, so they read in English until someone writes them.

## Translating a language

Two ways in. Either works, and they can be mixed.

**In Xcode.** Open `Localizable.xcstrings`, pick the language, and replace the
English text. Xcode flips each unit from `new` to `translated` as you go, and the
progress figure beside the language is the honest measure of what is left.

**Through the spreadsheet**, which is what to hand to a translator or a
translation service:

```bash
python3 Tools/export_translations.py
```

writes `Tools/translations.csv` — semicolon-separated, UTF-8 with a BOM so Excel
opens Amharic and Khmer intact. One row per translatable unit, one column per
language, with English and Dutch filled in as reference. Then:

```bash
python3 Tools/import_translations.py Tools/translations.csv --dry-run
```

checks a returned sheet without touching anything; drop `--dry-run` to write it
in. `--only de,fr` imports just those languages, so the sheet can come back in
pieces.

### What the sheet expects

| column | |
|---|---|
| `key`, `variant` | the row's identity. Everything else may be rewritten; **these two must survive untouched.** |
| `max_chars` | a guideline, derived from how long English and Dutch run. The app scales text down before it clips, so this is advice, not a limit. |
| `instruction` | the key's comment plus what is mechanically true of this row: which placeholders to keep, whether it is a plural form, how long to aim for. |
| `en`, `nl` | reference. |
| the rest | one column per language, empty and waiting. |

`variant` is empty for a plain string, `plural.one` for a plural category, and
`bubbles.plural.one` for a category inside the substitution named `bubbles`.

**An empty cell is never destructive.** It keeps whatever that unit had before —
an existing translation stays, an untouched unit keeps its English stand-in,
still marked `new`. So a sheet returned with one language filled in cannot
disturb another, and no column is ever left with a hole in it.

**Add rows for plural categories your language needs.** English has `one` and
`other`; Polish also needs `few`, Arabic needs six. Copy the row, change
`plural.one` to `plural.few`, fill only your column. The reverse is fine too:
Japanese can leave `plural.one` empty and only fill `plural.other`.

A language may also disagree with English about *whether* a string inflects at
all — Dutch splits two notification lines English leaves flat, and leaves flat an
accessibility label English inflects. Fill the shape your language needs; the
importer follows it.

### What blocks an import

Nothing is written unless every check passes. An import is refused when a
translation drops one of the arguments the code passes, or reaches for one that
does not exist — that is the class of mistake that crashes or prints the wrong
number. Spelling the same argument differently is allowed and only warned about:
`%#@times@` and `%1$lld` both render argument one, the first with plural
agreement, and choosing between them is the translator's call.

Running long, or bold markers that do not close, are reported and let through.

Every key carries a comment saying where it appears and what constrains it. Read
it before translating: several strings sit in badges only a few characters wide,
and a few are reused in more than one sentence.

## The rule that shapes all of this

**A language's column must never be partly filled with blanks.** SwiftUI resolves
`Text("some.key")` out of the single `.lproj` matching the current locale and does
*not* fall through to English for a key that is missing or empty there — it
prints the raw key on screen. Verified both ways in the simulator.

So a language is in one of two safe states:

- **absent from the catalog entirely** — the app falls back to English cleanly,
  including number formatting and right-to-left layout; or
- **present and complete**, with English standing in for whatever is not written
  yet.

Never leave it in between. If you add a language by hand in Xcode, Xcode creates
it *empty* — copy the English column into it before building, or delete it again.
`Text` is the only path with this constraint: `L(...)` and `L(key:)` both fall
back to English explicitly in code.

## Adding a language to the roster

1. One row in `AppLanguage.all` (`Number Reef/Localization.swift`):

   ```swift
   AppLanguage(code: "ka", flag: "\u{1F1EC}\u{1F1EA}", searchName: "Georgian")
   ```

   The name shown in the list is the endonym, read from the language's own
   locale; `searchName` only feeds the search field. Pass `displayName:` if the
   endonym reads wrong.
2. Add the language to the catalog with a full English copy (see above), and to
   `knownRegions` in the project — Xcode does the second for you.
3. **Optionally, teach it to speak.** Add a row to `SpokenMath.lexicons`
   (`Number Reef/SpokenMath.swift`) so the sums can be read aloud. A language
   without a row simply plays no spoken sums; nothing else changes.

Right-to-left languages need no extra work: `AppLanguage.isRightToLeft` reads the
direction from the language itself and the root view sets `\.layoutDirection`
from it.

Codes are matched through CLDR, so regional and script variants and the legacy
spellings all land on the right row — a device set to `nb-NO` finds the roster's
`no`, and that row's strings are found in `nb.lproj`, which is what Xcode names
the folder.

## Conventions in the catalog

- **Emphasis is Markdown.** `**like this**`. Put the bold where the stress falls
  in your language — it does not have to be the same words as in English.
  `emphasizedAttributedString` parses it; nothing else in the app understands a
  house notation.
- **Counted nouns use plural variations,** not a bare `%lld`. Xcode's editor
  offers "Vary by plural" on the key. Give your language every category it
  needs — Polish and Russian need more than two, and English's two say nothing
  about that. Where a noun is invariant after a number, a plain string is
  correct; `parentGate.tapInstruction` is pluralised in English and not in
  Dutch, and both are right.
- **Numbers never live inside a sentence.** The level count, the animal count
  and the starting goal all arrive as arguments, so a translation never goes
  stale when a constant changes. Keep it that way.
- **Standalone numbers go through `LN(_:)`,** which formats them in the chosen
  language — grouping separators and, where it applies, the language's own
  numerals. A bare `"\(value)"` in a `Text` is a bug.
- **Argument order is yours.** Use positional specifiers (`%1$@`, `%2$lld`)
  freely; the code passes arguments in a fixed order but the sentence does not
  have to.
- **`game.end.completionTitle %@`** takes a drawn badge, not text. Put `%@`
  wherever the badge belongs in your sentence — it may lead or follow.

## Things that are deliberately not translated

- The sums themselves. Digits and operators are language-neutral, and the
  decimal separator follows the chosen locale.
- The App Store price, which arrives already formatted by StoreKit.
- Character and shape *identifiers* (`octopus`, `triangle`); only their
  `character.*` and `parentGate.shape.*` names are shown.

## Checking your work

The in-app flag picker switches language live, with no restart, so every screen
can be checked in one run. Watch for text that is clipped rather than scaled —
German and Finnish run long, and the level cards and streak chip are the tightest
places in the app.

## State of the translations

English and Dutch are written and checked. **German, French, Spanish, Italian,
Portuguese, Russian and Polish** were rewritten by hand for the strings the bulk
delivery got wrong, and are correct: informal register, proper plural agreement
(Russian and Polish carry `few` and `many`), and the collectible called a bubble.

The other 68 languages came from a bulk delivery and carry three known defects.
None of them break the app; all of them read as translation quality.

- **Plural agreement.** Most of those languages write the singular noun in both
  plural categories, so a count above one reads "5 Blase" rather than "5 Blasen".
  Affects the 16 plural keys. English, Dutch and the seven hand-written
  languages are correct. Languages that do not inflect after a numeral —
  Chinese, Japanese, Korean, Thai, Turkish, Vietnamese, Indonesian, Malay,
  Hungarian — are unaffected by construction.
- **The collectible.** 20 languages still call a bubble a *trophy*, a leftover
  from the app's previous incarnation. A mechanical rename was tried and
  reverted: substituting the noun broke agreement with the surrounding
  quantifier ("uns quants bombolla més"), which reads worse than the wrong word
  in a fluent sentence. These need a translator, not a script.
- **Register.** A handful of languages address the player formally, which does
  not suit an app for children.

`Tools/translations-todo.csv` holds every outstanding unit, ready to hand back
to a translator and run through `import_translations.py`.

## Known caveats in the roster

- **Chinese ships as `zh` and Portuguese as `pt`,** one variant each. In-app that
  is fine. On the App Store it is not: App Store Connect has no plain "Chinese"
  (only Simplified and Traditional) and treats bare `pt` as Brazilian. If the
  listing needs European Portuguese or a specific Chinese script, those rows
  become `pt-PT` and `zh-Hans` / `zh-Hant` — a roster change, not a code change.
- **Several languages share a flag.** Four are spoken in Spain (Basque, Catalan,
  Galician, Spanish), ten in India, three in China, two in South Africa. The list
  is picked by name, and the collapsed button only ever shows the *current*
  flag, so this is legible — but it does mean a flag alone never identifies a
  language here.
- **Welsh uses the tag-sequence flag** (🏴󠁧󠁢󠁷󠁬󠁳󠁿), which renders on Apple platforms
  but shows as a plain black flag on some others.
