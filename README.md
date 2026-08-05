# Ashura

A free and open source hybrid manga + anime client for iOS and iPadOS.

Ashura is built on top of two excellent open source projects:
- [Aidoku](https://github.com/Aidoku/Aidoku) — the manga reading engine, WASM source system, downloads, and library management.
- [Sora](https://github.com/cranci1/Sora) — anime/video streaming concepts that inform Ashura's video player and browse experience.

Ashura merges both worlds into a single library, letting you track and read manga alongside watching anime, with a shared source-browsing experience and per-media-kind history and library filters.

## Features
- [x] No ads
- [x] Robust WASM source system
- [x] Online reading through external sources
- [x] Downloads
- [x] Tracker integration (AniList, MyAnimeList, and more)
- [x] Dual manga/anime library, browse, and history filtering
- [x] Video playback shell for anime streaming sources (in progress)

## Installation

### AltStore / SideStore (nightly)

Source URL:

```
https://remmody.github.io/Ashura/apps.json
```

Landing page with one-tap add links: https://remmody.github.io/Ashura/

Nightly unsigned IPAs are published to the [`nightly` release](https://github.com/remmody/Ashura/releases/tag/nightly) and picked up automatically by that source.

### Manual Installation

Build from source using Xcode, or download the IPA from the nightly release / Actions artifacts.

## Contributing

Ashura is under active development. Issues and pull requests are welcome.

## License

This repo (excluding translations) is licensed under [GPLv3](LICENSE), consistent with the licenses of both Aidoku and Sora, the projects it is based on. See [NOTICE](NOTICE) for attribution details.

### Translations
Translations are licensed separately from the app code, under [Apache 2.0](https://spdx.org/licenses/Apache-2.0.html).

## Acknowledgements

Ashura would not exist without the work of the [Aidoku](https://github.com/Aidoku/Aidoku) and [Sora](https://github.com/cranci1/Sora) teams and their contributors. Ashura is not affiliated with either project. See [NOTICE](NOTICE) for full attribution.
