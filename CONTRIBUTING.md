# Contributing to Galmuri

Galmuri is in experimental native development. Choose work from [TASKS.md](TASKS.md), which tracks milestones and completion. Start with the [documentation index](docs/README.md), [roadmap](docs/roadmap.md), and [glossary](GLOSSARY.md). Native core and UI work has resumed. Follow [local development](docs/local-development.md); real Chrome writes and publication remain gated.

## Make a focused contribution

- Explain the problem and observable behavior. Discuss changes to storage, permissions, supported formats, and merge rules before implementing them.
- Keep changes small and include affected callers, fixtures, and documentation. Follow the existing design and domain language.
- Distinguish a proposal from working behavior. Prototype interactions are not verified Chrome integration.
- Use synthetic fixtures. Never commit real bookmarks, profile directories, backup files, credentials, private URLs, personal screenshots, or agent/session state.
- Add focused behavioral tests for new nontrivial logic. Documentation-only edits do not need new unit tests.

The current executable check is:

```sh
node --test design/prototype.test.mjs
```

For prototype UI changes, open `design/galmuri-prototype.html` and check editing, cancellation, multi-selection, conflict choices, and narrow layouts. Do not add a browser automation dependency just to inspect the mockup. Run `swift test`, `python3 scripts/check-localization.py`, and `scripts/build-local.sh` for relevant native changes. Complete native acceptance and hosted CI remain pending.

## Documentation and translations

English is the authoritative source. Update [docs/README.md](docs/README.md) when adding or moving a document. Record substantial architectural trade-offs in [docs/adr](docs/adr/README.md) and product decisions in [docs/decisions.md](docs/decisions.md). Definitions belong in [GLOSSARY.md](GLOSSARY.md).

Keep all four READMEs consistent on project status, scope, commands, and limitations. The Korean specifications under `docs/ko/` are dated planning references, not automatically synchronized translations. Detailed Japanese and Chinese specifications are not available yet.

For app copy, update [localization/Localizable.xcstrings](localization/Localizable.xcstrings) and follow [docs/localization.md](docs/localization.md). Preserve key names, placeholders, brand names, URLs, and user content. Include context and identify whether a translation has received language review. Do not label a locale as shipped before native integration and locale QA pass.

## Pull requests and reports

Use the repository's issue and pull request templates once it is published. Explain what changed, why, and how it was checked; list any known limitation. Never test direct writes against a contributor's live Chrome profile. Sensitive reports follow [SECURITY.md](SECURITY.md).

Be respectful, assume good intent, and keep feedback specific to the work. Harassment, discrimination, and sharing someone else's private information are not acceptable.

## License

By contributing material you are entitled to contribute, you agree to provide it under the repository's [MIT license](LICENSE). Preserve attribution and license notices for any approved third-party material; do not copy code or assets with unknown licensing.
