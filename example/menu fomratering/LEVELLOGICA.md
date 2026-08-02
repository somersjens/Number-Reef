# Levellogica — hoe de levels en de sommen worden opgebouwd

Naslag bij `MenuKit`. Alle code hieronder staat in Jumping Fox in
`Challenges.swift`; dit document beschrijft de regels zodat je ze in een andere
app kunt overnemen zonder het bestand te hoeven ontcijferen.

De opbouw is bewust in drie lagen gescheiden:

| Laag | Verantwoordelijk voor |
|---|---|
| `ChallengeScaling` | **de enige bron van waarheid** voor moeilijkheid: de reeksen, plafonds en groeicurves |
| `LevelCatalog` / `LevelConfig` | welke levels er zijn en wat er op de kaart staat (één keer berekend en gecached) |
| `QuestionEngine` | de sommen die één sessie genereert |
| `ProgressStore` | wat de speler heeft gehaald: scores, trofeeën, ontgrendeling |

Dat de kaart en de gegenereerde sommen uit dezelfde tabel komen, is geen detail:
het is de reden dat het getal dat een kind op de kaart ziet nooit uit de pas kan
lopen met de sommen die het krijgt.

---

## 1. Structuur: 12 gratis levels, 99 in totaal

Elk menu heeft **12 gratis levels**; Premium breidt hetzelfde menu uit tot
**99 levels** (`ChallengeScaling.freeLevelCount = 12`). De premiumlevels zijn
geen herhaling: elk kaartnummer blijft betekenisvol voor zijn eigen menu (het
getal dat je optelt, de tafel, het plafond waar je naartoe werkt).

Elk level bestaat drie keer — één keer per modus — en elke variant heeft zijn
eigen score. Het id is:

```
"<categorie>.<index><achtervoegsel>"      bv. "tables.7.mix"

Reeks   → ""          (bewust leeg gelaten: bestaande spelers houden hun scores)
Hussel  → ".random"   (de enige die later is toegevoegd)
Gemixt  → ".mix"      (bestond al onder die naam)
```

### Wat er op de kaart staat, per categorie

| Categorie | Kaartnummer | Betekenis |
|---|---|---|
| `addition` | `index` (1…99) | het getal dat je erbij optelt |
| `subtraction` | `index` (1…99) | het getal dat je eraf haalt |
| `tables` | `index` (1…99) | de tafel; 13–99 is Premium |
| `fractions` | `fractionDenominators[index-1]` | de noemer van dit level |
| `percentages` | `percentageLevels[index-1]` | het percentage van dit level |
| `superBasic/Times/Fraction/All` | `index` (1…99) | het levelnummer; de moeilijkheid zit in de plafonds binnen elke bewerking |

De vlag `isAdvanced` (waarschuwingsstijl op de kaart, en negatieve antwoorden
toegestaan bij het aanvullen van afleiders) staat aan voor: alle premiumlevels,
alle supermixlevels vanaf index 3, en het "onder nul"-level.

> **Legacy:** in de catalogus zitten ook nog vijf oude `…Mix`-categorieën
> (`additionMix`, `subtractionMix`, `tablesMix`, `fractionsMix`,
> `percentagesMix`) met hun eigen generatoren. Het huidige menu wijst er niet
> meer naar — "Gemixt" is nu een *modus* op de basiscategorie. Ze blijven
> bestaan voor oude opgeslagen scores en de intro-teksten. Neem ze in een
> nieuwe app niet over.

---

## 2. De schaaltabellen (`ChallengeScaling`)

### Optellen en aftrekken: de Reeks-route

De Reeks bestaat uit **drie groepen van vijf sommen** (15 per ronde), waarna hij
opnieuw begint:

```
groepsgrootte = 5
verschuivingen = [0, 1, 3]

optellen:   ander getal = n + verschuiving[groep] + positie × n
aftrekken:  startgetal  = 6n + verschuiving[groep] − positie × n
```

Voor **+2** levert dat op: `2+2 … 2+10`, dan `2+3 … 2+11`, dan `2+5 … 2+13`.
Voor **−2**: `12−2 … 4−2`, dan `13−2 … 5−2`, dan `15−2 … 7−2`.

Daaruit volgen twee plafonds die de andere modi hergebruiken:

```
optelplafond(n)  = 5n + 3
aftrekplafond(n) = 6n + 3
```

### Plafonds per menu

| Tabel | Waarde |
|---|---|
| `additionMixCeiling` | `[10, 15, 20, 30, 50, 100, 150, 200, 300, 500, 750, 1000]`, daarna `1000 + (i−12)×100` |
| `subtractionMixCeiling` | `[10, 15, 20, 30, 50, 100, 20, 150, 200, 300, 500, 1000]`, daarna `1000 + (i−12)×100` — de 20 op plek 7 is het "onder nul"-level |
| `tablesMixPool` | vaste poules t/m level 12 (`[1,2] → [1,2,3] → 1…5 → 1…8 → 1…10 → 1…12 → 1…12 → 2…12 → 3…12 → 4…12 → 5…12 → 6…12`), daarna een schuivend venster van 12 breed: `max(2, i−11)…min(99, i)` |
| `premiumCeiling` | `100 + max(1, i−12) × 10` → level 13 = 110, level 99 = 970 |

### Breuken en percentages: vaste leerlijnen

Beide zijn één lange lijst van 99 waarden in de bedoelde leervolgorde. Dezelfde
lijst voedt de kaart, de intro-tekst én de sommen.

```
noemers:      2, 4, 8, 3, 6, 12, 5, 10, 20, 7, 14, 28, 16, 32, 64, 128, …
percentages:  25, 50, 75, 5, 10, 15, 20, 40, 80, 30, 60, 90, 35, 45, …
```

Het patroon is telkens: een makkelijke stam, dan zijn verdubbelingen
(2 → 4 → 8, 3 → 6 → 12, 5 → 10 → 20). Bij percentages eerst de kwarten en
tienden, dan de vijfvouden, dan de even getallen, en pas achteraan de oneven
"lelijke" percentages.

Voor premium-mixlevels worden alleen de vriendelijke waarden herhaald, maar op
grote ronde getallen: noemers `[2, 4, 5, 8, 10, 20, 25]`, percentages
`[50, 25, 10, 20, 75, 5, 100]`.

---

## 3. Wat elke modus per categorie doet

Dit is de kern: **dezelfde drie knoppen betekenen per onderwerp iets anders**,
maar altijd volgens hetzelfde principe — Reeks is voorspelbaar, Hussel schudt
hetzelfde getal, Gemixt haalt er lagere levels bij.

### Optellen (kaart = *n*)

| Modus | Regel |
|---|---|
| **Reeks** | de vaste route van 15 sommen hierboven; het geoefende getal staat altijd vooraan |
| **Hussel** | altijd `+ n`, het andere getal is een geschudde waarde uit `1…5n+3`, en `n` mag links óf rechts staan |
| **Gemixt** | telt een getal uit `1…n` op (zwaartepunt bij de hogere), bij een willekeurig startgetal onder `max(20, 6n)` — op kaart 3 dus zowel `12 + 3` als `9 + 1`, maar nooit `14 + 5` |

### Aftrekken (kaart = *n*)

| Modus | Regel |
|---|---|
| **Reeks** | de vaste dalende route van 15 sommen |
| **Hussel** | altijd `− n`, startgetal geschud uit `n…6n+3`. **Nooit omgedraaid**, want een min is niet commutatief |
| **Gemixt** | haalt een getal uit `1…n` eraf (zwaartepunt hoog), startgetal uit `take…max(20, 6n)` |

### Tafels (kaart = de tafel *t*)

| Modus | Regel |
|---|---|
| **Reeks** | oneindige lus `t×1, t×2 … t×12`, dan weer van voren af aan |
| **Hussel** | elke vermenigvuldiger 1…12 precies één keer per ronde, geschud, en de tafel mag vóór of achter de `×` staan |
| **Gemixt** | tafel = gewogen keuze uit `1…t` (de hoogste het vaakst), vermenigvuldiger willekeurig 1…12 |

Bij elke vermenigvuldiging is er **2 % kans op een `× 0`-vraag** als herinnering
dat alles maal nul nul is. De afleiders daarvan zijn precies de verleidingen:
het getal zelf, en 1.

### Breuken (kaart = de noemer *d*) — andere labels

| Knop | Regel |
|---|---|
| **Eén deel** (Reeks) | altijd de stambreuk `1/d` van een geheel; het geheel is `d ×` een geschudde factor 1…6, zodat de antwoorden niet voorspelbaar oplopen |
| **Meerdere** (Hussel) | meestal meerdere delen (`3/8`, `6/8`…); in ±25 % van de gevallen alsnog één deel |
| **Gemixt** | `d` samen met de **makkelijkere delers die netjes in `d` passen en al eerder zijn geïntroduceerd** (8 → 2, 4, 8; 12 → 2, 3, 4, 6, 12). Nooit een moeilijker nieuw deel — een zevende van een geheel van level 3 zou zwaarder zijn, niet lichter |

Elke breukensom is symbolisch: `num/den × geheel = ?`, en wordt altijd berekend
als **eerst delen, dan vermenigvuldigen** (`geheel / den × num`), zodat de
tussenstap dezelfde is als die het kind maakt.

### Percentages (kaart = het percentage *p*) — andere labels

| Knop | Regel |
|---|---|
| **Heel** (Reeks) | `p% × geheel`, waarbij het geheel altijd netjes deelt: `geheel = 100/ggd(100,p) × factor`, factor geschud uit 1…8. Werkt voor élk percentage 1…100, niet alleen de vriendelijke |
| **Komma** (Hussel) | hetzelfde percentage, maar **precies 2 van elke 5 vragen** landen achter de komma; de andere drie blijven heel |
| **Gemixt** | dit percentage plus alle percentages van de levels ervóór (gewogen naar dit level), met **1 op de 5** achter de komma |

De komma-antwoorden zijn niet willekeurig: alleen de tienden `0,1–0,9`, de
kwarten `0,25 / 0,75` en de afgeronde derden `0,33 / 0,67` zijn toegestaan, en
het antwoord blijft ≤ 60. Alles wordt in **honderdsten als integer** gerekend —
nergens een floating-point afronding — en pas bij het tonen omgezet met de
decimaalscheider van de taal van de speler (komma in het Nederlands, punt in het
Engels).

Vanaf de tweede ronde is er 15 % kans op een omkeervraag `1/4 = ?` → `25%`, voor
de percentages die een bekende breuk hebben.

---

## 4. De vier knoppen van de ster

Elke sterknop is een zelfstandige reeks van 99 levels die de eerder geleerde
bewerkingen dooreen husselt. Alleen de genoemde bewerkingen komen voor, en de
**zwaardere weegt zwaarder**:

| Knop | Optellen | Aftrekken | Tafels | Breuken | Procenten |
|---|---|---|---|---|---|
| `superBasic` (`+ −`) | 50 | 50 | — | — | — |
| `superTimes` (`+ − ×`) | 20 | 30 | 50 | — | — |
| `superFraction` (`+ − × ÷`) | 10 | 15 | 25 | 50 | — |
| `superAll` (`+ − × ÷ %`) | 10 | 15 | 20 | 25 | 30 |

De moeilijkheid klimt met het levelnummer, en wel **exact volgens de regels van
het eigen menu van die bewerking** — dat is wat een supermixlevel eerlijk houdt:

| Bewerking | Bij supermixlevel *i* |
|---|---|
| optellen | klein getal = gewogen keuze uit `1…i`; het andere uit `1…5×klein+3` (hetzelfde plafond als de Hussel-route van dat getal) |
| aftrekken | af te trekken getal gewogen uit `1…i`; startgetal uit `klein…6×klein+3` |
| tafels | tafel gewogen uit `1…i` — level 1 geeft dus alleen `×1`-sommen, nooit `4×7` |
| breuken | noemer gewogen uit de eerste `i` noemers van de leerlijn |
| procenten | percentage gewogen uit de eerste `i` percentages van de leerlijn |

Elke som toont altijd **precies twee getallen en één bewerking** — ook in de
supermix. Geen kettingsommen.

---

## 5. Volgorde-mechaniek in de sessie

Vier hulpmiddelen bepalen hoe een reeks *aanvoelt*:

- **De vaste Reeks-routes** (optellen, aftrekken, tafels) rekenen hun volgende
  som rechtstreeks uit de stapteller: `stap % 15` in de reeksformule, of
  `(stap % 12) + 1` bij de tafels. Geen willekeur, dus altijd dezelfde route.
  *(In `Challenges.swift` staat daarnaast nog een `cycled(_:)`-helper — eerste
  ronde in volgorde, daarna geschud — die nu nergens meer wordt aangeroepen;
  neem die niet over.)*
- **`shuffledCycled(waarden)`** — vanaf de eerste ronde geschud, maar elke waarde
  komt nog steeds precies één keer per ronde voor. Zo blijft de oefening
  evenwichtig zonder dat de antwoorden 1, 2, 3 oplopen. Gebruikt door Hussel en
  door de gehelen bij breuken/percentages.
- Bij beide geldt: **een nieuwe ronde begint nooit met de waarde die de vorige
  afsloot**, anders zou dezelfde som twee keer achter elkaar komen. Daarnaast
  hergenereert de engine tot 15 keer zolang de vraagtekst gelijk is aan de vorige.
- **`weightedHardPick(lijst)`** — kiest uit een oplopend easy→hard lijstje met
  lineair groeiend gewicht (positie *i* krijgt gewicht *i+1*). De bovenste
  waarden komen dus het vaakst, de onderste blijven af en toe terugkomen. Dit is
  wat "Gemixt" zijn gewicht bovenin laat houden: bij de tafel van 12 komt ×3 nog
  af en toe langs, ×8 veel vaker. Het schaalt zichzelf over alle 99 levels
  zonder één per-level-instelling.
- **Foutenmandje** — tot 5 gemiste vragen worden bewaard; vanaf de derde vraag is
  er 20 % kans dat er eentje terugkeert. Dit staat **uit** in de vaste
  Reeks-routes van optellen, aftrekken en tafels, omdat die hun route niet mogen
  onderbreken.

---

## 6. Afleiders: bijna-missers, geen willekeur

Geen enkele afleider is een willekeurig getal. Ze zijn allemaal de fout die een
kind écht maakt:

| Categorie | Afleiders |
|---|---|
| optellen | ±1 / ±2 (tel-slippertjes), het andere getal (vergeten op te tellen), `antwoord + n` (twee keer opgeteld); bij grotere sommen ±10 (onthoudfout) en omgedraaide cijfers |
| aftrekken | ±1 / ±2, het startgetal (vergeten af te trekken), `antwoord − n` (twee keer afgetrokken), ±10 (leenfout), en de klassieke kolomfout: per kolom het kleinste van het grootste cijfer aftrekken (52 − 38 → 26 in plaats van 14) |
| onder nul | `b − a` — de tekenomkering is dé fout bij negatieve uitkomsten |
| tafels | buurproducten in dezelfde tafel (`t×(m±1)`) én dezelfde vermenigvuldiger in de buurtafel (`(t±1)×m`) — precies de verwarring bij het stampen |
| breuken | het eenheidsdeel (vergeten te vermenigvuldigen), teller één ernaast (`antwoord ± eenheid`), het complement (`geheel − antwoord`), ±1 |
| percentages | buurpercentages van hetzelfde geheel (25 % vs 50 %), het complement, ±1 |
| komma-antwoorden | de komma weggelaten (afgerond op heel), de tiende erboven/eronder, één geheel ernaast |

`makeQuestion` sluit af met een opruimstap: dubbele afleiders eruit, het juiste
antwoord eruit, en aanvullen tot er **acht** zijn — met varianten van het juiste
type (gehele getallen bij een getal, `n/d` bij een breuk, tienden bij een
komma-antwoord, `n0%` bij een percentage), zodat een aangevulde optie er nooit
uitspringt als "die hoort hier niet". Negatieve aanvullingen zijn alleen
toegestaan op `isAdvanced`-levels.

---

## 7. Voortgang, trofeeën en ontgrendelen

```
ontgrendeldrempel   = 8    beste score op het vorige level om het volgende te openen
voltooid            = 12   score waarbij een level als "gehaald" telt
```

Het **trofeedoel groeit mee met de modus**, zodat doorklimmen naar de zwaardere
knop ook meer waard is:

| Modus | Doel |
|---|---|
| Reeks | 20 |
| Hussel | 30 |
| Gemixt | 40 |
| Supermix (alle vier de knoppen, elke modus) | 50 |

Haal je het doel, dan komt er een **×-badge** bij (tot 100 keer) zonder dat de
beste score of het trofeetotaal verandert — het herhalen van een uitgespeeld
level blijft dus zichtbaar, maar levert geen oneindige trofeeën op.

Ontgrendelen:

- Level *i* opent als het **vorige level ≥ 8** scoorde. De poort kijkt naar het
  id **zonder modus-achtervoegsel**, dus naar de score van de Reeks-variant.
- Het eerste level van een sterknop heeft een **meervoudige poort**: alle
  basisvaardigheden die die knop combineert moeten ≥ 8 staan.

  | Knop | Vereist ≥ 8 op |
  |---|---|
  | `superBasic` | `addition.1`, `subtraction.1` |
  | `superTimes` | + `tables.1` |
  | `superFraction` | + `fractions.1` |
  | `superAll` | + `percentages.1` |

- `unlockProgress` geeft 0–1 richting die drempel, voor de "bijna open"-staat op
  de kaart.

Scores staan onder `best.<levelID>` (en `best.<levelID>.helper` voor de
hulpmodus), badges onder `max-completions.<levelID>`. Hulpmodus-trofeeën worden
apart geteld en verhogen de gewone score nooit; omgekeerd telt onbegeleid
behaalde voortgang wél mee in de hulpmodus.

---

## Als je dit overneemt in een andere app

De vier dingen die het systeem laten werken, los van rekenen:

1. **Eén schaaltabel voor alles.** Kaart, intro-tekst en gegenereerde inhoud
   lezen uit dezelfde lijst. Zo kunnen ze niet uit elkaar lopen.
2. **12 gratis, 99 totaal, met echte inhoud.** Elk premiumlevel heeft een eigen
   betekenisvol kaartnummer — nooit een herhaling van een gratis kaart.
3. **Drie modi op hetzelfde level, met eigen score en eigen doel.** Voorspelbaar
   → geschud → gemengd met eerdere stof, met een lineair gewicht dat vanzelf over
   99 levels meeschaalt (`weightedHardPick`).
4. **Afleiders zijn fouten, geen ruis.** Voor elk onderwerp: schrijf eerst op
   welke fouten je doelgroep echt maakt, en genereer die.
