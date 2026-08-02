# MenuKit

De menu-onderdelen uit **Jumping Fox**, losgetrokken zodat je ze in een andere
app kunt hergebruiken. Alles is pure SwiftUI, zonder afhankelijkheden.

Wat erin zit:

1. **De zes onderwerp-cirkels** (`+ − × ÷ % ★`)
2. **De drie volgorde-knoppen**: Reeks · Hussel · Gemixt
3. **De vier knoppen van de ster** (supermix), inclusief de operator-uitlijning
4. **De info-pop-out**: tik nog eens op wat al geselecteerd is → kaartje met uitleg
5. **Welkomstscherm 2 en 3**, waar dezelfde keuzes in kindertaal worden gesteld
6. **Teksten in Nederlands en Engels** (`.strings` én `.xcstrings`)

---

## Bestanden

| Bestand | Inhoud |
|---|---|
| `MenuKitCore.swift` | Configuratie, thema, teksthaken, `PracticeMode`, `MenuTopic`, `SupermixOption`, `MenuSelectionStore` |
| `MenuKitInfoPopout.swift` | De pop-out: ankermeting, `InfoPopoutController`, `InfoPopoutHost`, het kaartje |
| `MenuKitPickers.swift` | `MenuTopicPicker`, `MenuModePicker`, `MenuSupermixPicker`, `MenuControlStack` |
| `MenuKitWelcome.swift` | Welkomstscherm 2 (onderwerp) en 3 (startniveau) |
| `MenuKitDemo.swift` | Werkend voorbeeldscherm — sleep dit in een leeg project en run |
| `Localization/nl.lproj/Localizable.strings` | Nederlandse teksten |
| `Localization/en.lproj/Localizable.strings` | Engelse teksten |
| `Localization/MenuKit.xcstrings` | Dezelfde teksten als String Catalog (Xcode 15+) |
| `LEVELLOGICA.md` | **Hoe de levels en sommen worden opgebouwd** per categorie en subcategorie: schaaltabellen, wat elke modus per onderwerp doet, de weging van de sterknoppen, afleiders, trofeeën en ontgrendeling |

Minimaal iOS 17 (vanwege `.snappy` en `ViewThatFits`). Wil je lager: vervang
`.snappy(duration: 0.2)` door `.easeOut(duration: 0.2)` en `ViewThatFits` in
`WelcomeTitle` door alleen de tweede kandidaat.

## Inbouwen in 4 stappen

```swift
// 1. Haken zetten (bijv. in je App-init)
MenuKit.localize = { L($0) }                       // of laat staan: NSLocalizedString
MenuKit.playTapSound = { AppAudio.shared.playMenuTap() }
MenuKit.onSelectionChanged = { big in jump(big: big) }

// 2. Twee objecten in je hoofdscherm
@StateObject private var selection = MenuSelectionStore()
@StateObject private var popout = InfoPopoutController()

// 3. Je scherm in de host wikkelen
InfoPopoutHost(controller: popout, selection: selection) {
    ScrollView { … }
}
.menuKitTheme(MenuKitTheme(deep: .brown, accent: .orange))

// 4. De besturing plaatsen waar je hem wilt
MenuControlStack(selection: selection, popout: popout)
```

`MenuControlStack` toont de cirkelrij en daaronder automatisch óf de drie
volgorde-knoppen, óf het sterrooster. Wil je ze los plaatsen, gebruik dan
`MenuTopicPicker` / `MenuModePicker` / `MenuSupermixPicker` afzonderlijk.

**Wat je wél zelf blijft doen:** je eigen levellijst tekenen en je eigen
opgaven genereren. De regels waarmee Jumping Fox dat doet — per categorie én per
subcategorie — staan in **[LEVELLOGICA.md](LEVELLOGICA.md)**.

Wat de selectie oplevert lees je uit de store:

```swift
selection.topicID          // "tables"
selection.mode             // .order / .random / .mixed
selection.supermixID       // "superAll" (alleen als het ster-onderwerp actief is)
selection.showsSupermixGrid
selection.levelIDSuffix    // "" / ".random" / ".mix"  → hang dit achter je level-id
```

De store bewaart alles in `UserDefaults` onder `ui.menuFilter`, `ui.menuMode` en
`ui.supermixCategory` (aan te passen via `MenuSelectionStore.Keys`).

---

## 1. De drie volgorde-knoppen: Reeks · Hussel · Gemixt

Drie even brede knoppen onder de onderwerp-cirkels. Ze bepalen niet *wat* je
oefent, maar in welke *volgorde*:

| Knop (NL / EN) | `PracticeMode` | Opgeslagen waarde | Betekenis |
|---|---|---|---|
| Reeks / Order | `.order` | `"standard"` | de rustige oplopende reeks |
| Hussel / Random | `.random` | `"random"` | alleen het eigen getal van dit level, geschud |
| Gemixt / Mixed | `.mixed` | `"mix"` | dit getal **of een lager**, door elkaar, met nadruk op de hogere kant |

Belangrijke details die je wilt overnemen:

- **Elke modus heeft zijn eigen score.** Via `mode.idSuffix` (`""`, `".random"`,
  `".mix"`) krijgt elk level per modus een eigen id. De lege suffix voor `.order`
  en `".mix"` voor `.mixed` zijn bewust ongewijzigd gebleven, zodat bestaande
  spelers hun trofeeën houden — `.random` was de nieuwe.
- **Het label krimpt, het lettertype niet.** `lineLimit(1)` +
  `minimumScaleFactor(0.6)`: een lang woord in een andere taal past nog steeds
  met z'n drieën naast elkaar zonder dat de korte labels kleiner worden.
- **Twee onderwerpen hebben andere labels.** Breuken en Procenten sorteren hun
  sub-levels niet op volgorde, maar veranderen *wat voor som* je krijgt. Zij
  krijgen daarom eigen labels én een eigen kopje in de pop-out
  (`ModeLabelOverride`):

  | Onderwerp | Reeks → | Hussel → | Kopje pop-out |
  |---|---|---|---|
  | Breuken | Eén deel | Meerdere | Delen |
  | Procenten | Heel | Komma | Soort |

  "Gemixt" houdt in beide gevallen zijn gedeelde label en tekst.
- **Een wissel wordt één runloop later doorgevoerd** (`DispatchQueue.main.async`
  in `MenuSelectionStore`). Zo krijgt de knop-animatie zijn beginframe voordat
  de zware levelgrid-wissel eroverheen walst. In Jumping Fox voorkwam dat dat de
  sprong van het personage halverwege werd omgeleid.

## 2. De vier knoppen van de ster

Kiest het kind het ster-onderwerp (Supermix), dan verdwijnen de drie
volgorde-knoppen en komt er een 2×2 rooster met vier zelfstandige categorieën.
Elke knop combineert steeds méér bewerkingen:

| Volgorde in het rooster | id | Toont | Pop-outtekst (NL) |
|---|---|---|---|
| linksboven | `superBasic` | `+ −` | Optellen en aftrekken |
| rechtsboven | `superTimes` | `+ − ×` | Optellen, aftrekken en vermenigvuldigen |
| linksonder | `superFraction` | `+ − × ÷` | Optellen, aftrekken, vermenigvuldigen en delen |
| rechtsonder | `superAll` | `+ − × ÷ %` | Optellen, aftrekken, vermenigvuldigen, delen en percentages |

De volgorde is dus **oplopend in complexiteit, van links naar rechts en van
boven naar beneden**. De operatorvolgorde zelf ligt vast: `+ − × ÷ %`.

### Hoe de symbolen zijn geformatteerd

Dit is het stukje dat je het snelst zou verliezen bij overtypen:

- **Vaste vakjes, geen HStack die uitlijnt op inhoud.** Elke kolom reserveert
  evenveel vakjes als zijn langste knop nodig heeft: links 4 (`+ − × ÷`), rechts
  5 (`+ − × ÷ %`). MenuKit rekent dat zelf uit, dus je kunt de lijst gewoon
  aanpassen.
- **Een kortere knop centreert zich in die vakjes.** `+ −` staat in vakje 2 en 3
  van 4, niet vooraan. Daardoor staan de gedeelde operatoren van de twee knoppen
  in dezelfde kolom netjes onder elkaar.
- **`%` krijgt zijn eigen, kleinere maat.** Bij dezelfde puntgrootte leest dat
  glyph optisch zwaarder dan de rest; het gaat naar 21/15 pt in plaats van
  26/19 pt (iPad/iPhone) en een vakje van 80 % breedte. Andere "zware" glyphs
  voeg je toe aan `MenuKitConfig.heavyOperatorGlyphs`.
- **De cirkels erboven hebben óók per symbool een eigen grootte** (`iconSize`):
  21 pt voor `+ − × ÷`, 19 pt voor `%`, 17 pt voor de gevulde ster — die leest
  namelijk het breedst. Een gedeelde hoogtebox van 24 pt houdt ze allemaal op
  dezelfde lijn. Op iPad wordt alles ×1,64 geschaald.

## 3. De info-pop-out ("tik nog eens")

Een tik op een knop die **al geselecteerd is** deed vroeger niets. Nu opent er
een klein kaartje onder de knop met een kopje en één regel uitleg.

Werking:

1. Elke knop meldt via `.reportAnchor("topic.tables")` zijn frame in de gedeelde
   coördinatenruimte `MenuKit.homeSpace`.
2. `InfoPopoutHost` zet die ruimte, verzamelt de frames en tekent het kaartje
   erbovenop — met een pijltje dat exact op de knop wijst en dat binnen de ronde
   hoeken blijft.
3. Een tik ernaast sluit de pop-out **en doet meteen waar die tik op landde**:
   een andere knop schakelt om, een levelkaart start. Alleen een tik op lege
   ruimte sluit enkel. Dat scheelt de gebruiker een tik.

Twee dingen die makkelijk over het hoofd worden gezien:

- **De breedte wordt gemeten, niet geraden.** `InfoPopoutCard.preferredWidth`
  meet kopje en tekst; past het op één regel, dan blijft het kaartje smal. Past
  het niet, dan zoekt een binaire zoektocht (9 stappen) de smalste breedte die
  nog op twee regels past — zodat de tweede regel geen lange lege staart
  overhoudt. De letterafstand van 0,6 pt in het kopje wordt in de meting
  meegerekend, anders breekt "Soorten sommen" onnodig af.
- **De eerste twee cirkels en de eerste volgorde-knop groeien naar rechts.**
  Die hebben ruimte zat aan hun rechterkant, dus hun kaartje blijft aan de
  linkerrand van de knop hangen (`InfoPopup.expandsRight`). De rest is
  gecentreerd en gebruikt de ruimte links. Alles wordt bovendien binnen 12 pt
  van de schermranden gehouden.

De kopjes: `Soorten sommen` boven onderwerpen én sterknoppen, `Volgorde` boven
de drie volgorde-knoppen, met `Delen` / `Soort` als afwijking voor Breuken en
Procenten.

## 4. Welkomstscherm 3

Scherm 2 kiest het onderwerp (dezelfde lijst als de cirkels). **Scherm 3 stelt
exact dezelfde vraag als de drie volgorde-knoppen, maar in kindertaal** — het is
letterlijk een voorselectie van `PracticeMode`:

| Rij in welkomstscherm 3 | Icoon | Zet |
|---|---|---|
| "Net begonnen" — *Oefenen met oplopende sommen.* | `leaf.fill` | `.order` (Reeks) |
| "Al wat geoefend" — *Sommen in willekeurige volgorde.* | `shuffle` | `.random` (Hussel) |
| "Al aardig goed" — *Verschillende mix-sommen door elkaar.* | `bolt.fill` | `.mixed` (Gemixt) |

Koos het kind in scherm 2 de **ster**, dan is er geen volgorde om te zetten. De
keuze wordt dan afgebeeld op het sterrooster: "Al aardig goed" → de meest
complete knop (`superAll`), de andere twee → de eenvoudigste (`superBasic`).

Na afloop staat het menu dus al goed: het juiste onderwerp geselecteerd, de
juiste volgorde-knop actief. De ondertitel noemt het gekozen onderwerp
(`"Kies een startpunt voor %@."`), met "dit onderwerp" als terugval.

Layoutdetail dat de moeite waard is: **alle drie de rijen delen één tekstschaal**
(`WelcomeLevelStep.sizing`). Die wordt bepaald door de breedste titel of
ondertitel in de actieve taal, zodat de rijen er in élke taal identiek uitzien.
Is een bescheiden verkleining niet genoeg (onder 0,78 op iPhone / 0,82 op iPad),
dan groeien alle drie de rijen even hard en mogen ze twee regels gebruiken.
`WelcomeTitle` doet iets vergelijkbaars voor de kop: past hij op één regel dan
blijft hij op één regel, anders wordt de meest gelijkmatige woordafbreking
gekozen in plaats van één los woord op regel twee.

---

## Je eigen onderwerpen gebruiken

Vervang de lijsten in `MenuKitConfig`; de rest past zich aan (ook het rooster en
de kolombreedtes):

```swift
MenuKitConfig.topics = [
    MenuTopic(id: "spelling", titleKey: "filter.spelling",
              icon: "textformat.abc", iconSize: 19, infoKey: "info.filter.spelling"),
    MenuTopic(id: "mixed", titleKey: "filter.mixed",
              icon: "star.fill", iconSize: 17, infoKey: "info.filter.mixed",
              usesSupermixGrid: true)
]

MenuKitConfig.supermixOptions = [
    SupermixOption(id: "light", operators: ["A", "B"], infoKey: "info.super.light"),
    …
]
```

Zes cirkels is wat comfortabel past op een iPhone; bij meer knoppen wordt de
cirkeldiameter (`MenuKitLayout.circleDiameter`) de beperkende factor.

## Teksten

Gebruik `Localization/MenuKit.xcstrings` (Xcode 15+, sleep 'm in je project) of
plak de regels uit de twee `.strings`-bestanden in je bestaande bestanden. De
sleutels zijn identiek aan die van Jumping Fox, dus vertalingen naar andere talen
kun je daar zo uit overnemen.

Eén verschil met Jumping Fox: daar heten de accessibility- en ondertitelsleutels
`"menu.accessibility.chooseMode %@"` en `"onboarding.level.subtitle %@"` (met de
`%@` in de sleutelnaam, de Xcode-stijl). MenuKit gebruikt de sleutels zónder
achtervoegsel en `String(format:)`.
