# App Store Teaser — QA Notes

## Exports

| File | Pixels | Duration | Audio |
|------|--------|----------|-------|
| `promo/exports/app-store-teaser-886x1920.mp4` | 886×1920 | ~28 s | Music bed + scripted game SFX |
| `promo/exports/app-store-teaser-1200x1600.mp4` | 1200×1600 | ~28 s | Music bed + scripted game SFX |

Re-render:

```bash
./promo/render.sh all    # or iphone | ipad
```

## Approach

- Logical layout at phone/pad size; recorder scales to export pixels.
- Fixed 30 fps encode clock (engine external clock) to avoid dual-clock judder.
- Final answer pinned at level-completion path start; swim-out at 2×.
- Audio: production `music_background.m4a` + CAF SFX cues muxed after video (Simulator cannot tap `AVAudioEngine`).

## QA checkpoints

- [x] Exact pixel sizes
- [x] Audio track present (music + SFX cues)
- [x] Finale bubble at completion gather point; 2× swim-out
- [x] No camera zoom judder (`unlockZoom = 1`)
- [ ] Opening swim: confirm no local back-and-forth on device playback
