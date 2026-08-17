# Number Reef — App Store teaser

## Outputs

- `exports/app-store-teaser-886x1920.mp4` — iPhone portrait
- `exports/app-store-teaser-1200x1600.mp4` — iPad portrait
- `previews/` — contact-sheet frames
- `QA.md` — checklist and deviations

## Render

```bash
./promo/render.sh all       # both
./promo/render.sh iphone    # 886×1920
./promo/render.sh ipad      # 1200×1600
```

Requires Xcode + a booted iOS Simulator. Builds Debug with `-PromoTrailer` and `-PromoSize=…`, then pulls the MP4 from the app Documents folder.

## Source (in the app target)

`Number Reef/Promo/` — director, host, recorder, script, session, runtime.

Activated only when launched with `-PromoTrailer`. Normal Release builds do not enter this path.
