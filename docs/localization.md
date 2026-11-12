# Localization policy

Initial policy · 2026-10-23. English is the source language. The maintainer requested Korean, Japanese, and Chinese in addition to English; Simplified Chinese is the working scope for the first Chinese locale.

## Coverage and status

| Locale | README | Initial app catalog | Native runtime and language QA |
| --- | --- | --- | --- |
| English (`en`) | Available; canonical | Source entries present | Integrated; basic selection/rendering checked; full QA pending |
| Korean (`ko`) | Available | Draft entries; needs review | Integrated; basic selection/rendering checked; full QA pending |
| Japanese (`ja`) | Available | Draft entries; needs review | Integrated; basic selection/rendering checked; full QA pending |
| Simplified Chinese (`zh-Hans`) | Available | Draft entries; needs review | Integrated; basic selection/rendering checked; full QA pending |

[Localizable.xcstrings](../localization/Localizable.xcstrings) contains 421 editing, permission, connection/onboarding, conflict, apply, recovery, count, diagnostic, and Settings/Labs entries compiled into the development app. Basic runtime language selection and English fallback have local evidence, but complete translation/accessibility QA is pending. The HTML prototype remains Korean-only. Detailed English specifications are canonical; `docs/ko/` preserves dated Korean planning references. Full Japanese/Chinese technical translations are not available yet. Traditional Chinese (`zh-Hant`) is outside the initial scope and must not be treated as equivalent to Simplified Chinese.

## Native implementation contract

- The development app declares English as its development language and the four localizations. `scripts/build-local.sh` compiles the catalog into the app resources.
- Follow the system/app preferred language when a supported localization exists; English is the fallback for unsupported languages and missing resources. Do not add an app-specific language picker unless a product need emerges.
- Use localizable SwiftUI/Foundation APIs and stable catalog keys. Do not concatenate translated sentence fragments, cache localized messages independent of locale, or translate app text with ad hoc runtime replacement.
- Preserve literal brand names, URLs, file paths, bookmark titles, folder names, and user-chosen profile names. Localize labels around them. A user's Korean bookmark title remains Korean in an English app.
- Distinguish language from region: format numbers, timestamps, and dates with locale-aware formatters, without changing source IDs/timestamps or URL bytes.
- Add complete-message plural variants and positional placeholders when count/dynamic messages are introduced. The native catalog includes plural variants for counts and contextual diagnostics; new system-provided error details can still appear in the OS language or English.
- Give translators context, especially destructive actions. “Save in Galmuri,” “apply to Chrome,” “original backup,” “workspace backup,” and “export” must stay distinct.
- Include accessibility labels, tooltips, menu commands, permission explanations, progress, validation errors, recovery instructions, and empty states in localization scope.

Apple's [String Catalog guide](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) documents centralized translations, comments, and plural/device variants. It was checked via Context7 and official documentation on 2026-10-23. API and tool availability must be matched to the chosen Xcode/macOS target during integration.

## Terms

| English | Korean | Japanese | Simplified Chinese |
| --- | --- | --- | --- |
| Bookmark | 북마크 | ブックマーク | 书签 |
| Profile | 프로필 | プロファイル | 配置文件 |
| Working copy | 작업본 | 作業コピー | 工作副本 |
| Original | 원본 | 原本 | 原始数据 |
| Apply changes | 변경사항 반영 | 変更を反映 | 应用更改 |
| Conflict | 충돌 | 競合 | 冲突 |
| Backup | 백업 | バックアップ | 备份 |
| Restore | 복원 | 復元 | 恢复 |

Keep **Galmuri** as the product name in every locale; the Korean name is **갈무리**. Do not translate “apply” as merely saving a working copy or exporting a file. See [GLOSSARY.md](../GLOSSARY.md) for the concepts behind these terms.

## Translation workflow

1. Change English source copy and its explanatory comment first. Stable keys are semantic identifiers, not translated strings.
2. Update all four values. Mark affected translations as needing review until reviewed in context. The current non-English entries have not had independent native-speaker review.
3. Keep placeholders, argument types/order, punctuation intent, and product names consistent. When plural messages are added, validate all required forms for each locale.
4. Update all READMEs together when status, supported languages, setup, or limitations change. Link technical details to canonical English documents rather than maintaining four divergent specifications.
5. Record native/locale evidence in [validation.md](validation.md). A JSON parse or catalog compilation does not establish visual correctness or language quality.

## Release acceptance

Verify all four locales in the native app, including system language selection, an unsupported-language fallback, missing-key detection, long text, mixed-script user content, VoiceOver, keyboard navigation, and narrow/wide windows. Test zero/one/many counts and localized dates when those resources exist. Inspect every apply, deletion, backup, and restore message in context, including errors and cancellation. Do not show raw keys or silently omit critical recovery information.

No locale is marked as shipped until the target is integrated and these checks pass. Review suggestions and glossary corrections are welcome through [CONTRIBUTING.md](../CONTRIBUTING.md).

## Validate the current resource

With Xcode's command-line tools available, run from the repository root:

```sh
galmuri_catalog_output="$(mktemp -d)"
xcrun xcstringstool compile localization/Localizable.xcstrings --output-directory "$galmuri_catalog_output"
```

The current catalog compiles to localized strings and plural resources in `en.lproj`, `ko.lproj`, `ja.lproj`, and `zh-Hans.lproj`. Output goes to a temporary directory and is not part of the source tree. This command checks catalog compilation only. `python3 scripts/check-localization.py` checks four-language coverage and literal native UI keys. Separate native language/fallback evidence is in [validation](validation.md).


On 2026-10-24 the checker gained format argument position/type and plural-branch validation, with `--self-test` regression assertions. All 186 entries and 107 literal native keys pass; 124 assertions against compiled resources cover zero/one/many counts and mixed-script arguments. These establish resource behavior, not native-speaker or accessibility acceptance.

The encrypted-store checkpoint adds eight compatibility/file-set diagnostics, bringing the current catalog to 194 entries. Four-language checker self-tests and resource compilation pass; the new translations remain marked for in-context review.

On 2026-10-25 four Settings/Labs strings were added for the disabled encrypted-bookmark placeholder, bringing the catalog to 198 entries. The non-English copy remains marked for in-context review. The placeholder is always off and unavailable; these resources do not enable encrypted storage or request Keychain access.

The 2026-10-25 editing UX pass adds seven strings (205 entries total) and revises Delete/Undo/Save copy across the four locales. Deletion counts include unique descendants and use compiled plural resources; user-authored names and paths remain untranslated. Non-English copy still needs native-speaker review.

The guided connection pass adds 20 four-language entries (225 total): empty welcome, folder-access explanation, profile selection, unavailable formats, unverified freshness and selected-profile counts. Non-English copy remains subject to native review.

The direct-discovery pass adds twelve four-language messages (237 total), covering normal lookup, optional folder access, missing locations and concise native-folder validation. These do not imply a successful real TCC grant.

The browser-selection preview adds generic browser/profile copy and formatted Chrome/Ego/folder names in all four locales. Experimental Ego warnings are localized without translating browser names or source paths. Native-speaker review remains pending.

The dedicated permission guide adds fifteen four-language entries for native access steps, pending/checking state, retry/back, System Settings instructions and launch failure. Browser and folder names are preserved as format arguments.

The Settings-first follow-up adds fifteen entries (272 total), with conditional Chrome Settings instructions, current app-name formatting, explicit chooser wording, ordinary-file-permission guidance and domain/code labels. Compiled format/plural checks pass; synthetic guide rendering does not establish native OS permission behavior or translation acceptance.

The 2026-10-27 Settings navigation fix adds two entries (274 total): a Files & Folders action label and manual-navigation fallback. The switch instructions preserve the current app name through a format argument; navigation failure names the full manual route. Non-English strings remain marked for in-context review.

The subsequent 2026-10-27 copy-only pass renames the Settings action to **Allow Files & Folders in Settings** (Korean: 설정에서 파일 및 폴더 승인하기) without adding keys. The catalog remains at 274 entries. The button opens the authorization location; only the user changes a permission. Four exact compiled action-label assertions complement existing resource checks.


The optional Accessibility guide adds nine entries (283 total), including broader-permission explanation, explicit request, ready/locating/manual/unavailable states and neutral success wording. Six new formatted messages preserve the actual app name. The checker finds 187 literal native keys; non-English additions require native-speaker review. Resource/capture evidence is in the [Release 16 checkpoint](validation.md#optional-accessibility-settings-navigation--2026-10-27).


Release 17 removes the nine withdrawn Accessibility messages and adds one four-language suspension notice: **275 catalog entries, 179 literal native keys**. Earlier 283-key and automatic-navigation results describe Release 16. Native-speaker review remains open; the new message says to expand the app manually and requires no Accessibility permission.

Release 18 removes the obsolete temporary-suspension notice after the mechanism was rejected: **274 catalog entries, 178 literal native keys**. Existing four-language manual steps remain; no new translation or permission request is added.


Release 19 clarifies four existing permission messages in all locales. The second-step heading now formats the current app name; the detail names its left disclosure arrow and Chrome switch, and the return instruction explicitly names Check Again. Catalog/key counts stay **274 / 178**; four new compiled heading assertions bring the resource total to **100**. Non-English copy remains marked for native-speaker review.

Release 20 adds the standard panel’s four-language **Allow Access to This Folder** label and updates existing folder/current-location/fallback copy: **275 entries, 179 literal native keys**. Compiled assertions include all four new confirmation labels; non-English copy remains marked for native-speaker review.

Release21 replaces three generic profile-storage badges/help strings with file observations, precise plaintext availability, modification-time labels, exclusions and six diagnostics: **291 catalog entries, 189 literal native keys**. The existing mixed-store warning now explains plaintext-only scope and blocked original apply. Types are filename observations and dates are not a latest-Chrome claim. Non-English strings need native-speaker review.


Release22 adds eight folder-navigation/type-separation messages: **299 catalog entries and 196 literal native keys**. Back/Forward/Enclosing Folder/path and folder-first/type labels are wired across all four locales. Folder names and URL text are not translated. Non-English entries still require in-context native-speaker review.


Release23 adds eight pending-discard/scope/review/undo-lifetime messages: **307 catalog entries and 204 literal native keys**. The full-profile discard confirmation and undo help are available in all four locales. Profile/item names and URLs remain user content; non-English strings need native-speaker review.


Release24 adds profile management, disk-refresh/merge review and selected-revert/opening messages: **337 catalog entries and 234 literal native keys**. Refresh uses disk-file/source-baseline wording rather than a Chrome apply or live-freshness claim. Non-English entries require native-speaker review.


### Chrome bridge proof · 2026-10-28

The app catalog now contains **347 entries / 244 literal native keys**. Ten bridge messages cover all four locales, including a preserved six-digit code placeholder. Compiled-resource checks total **404 assertions** across four locales. The unpacked proof extension keeps a separate four-language text module checked for matching keys, nonempty values and English fallback. Native own-window captures include the connection-request panel; translations and VoiceOver still need maintainer/native-speaker acceptance.

## API editor checkpoint · 2026-10-29

The current catalog contains **374 entries / 271 literal native keys** across four locales. API workspace, scope, source restrictions, review, conflict, restore and interrupted-state adoption labels are included; bridge copy now explains bookmark access. The checker/self-tests and catalog compilation pass; **512 compiled-resource assertions** preserve count/format behavior and mixed-script values. Native own-window runs produce 34 images per locale, including API workspace and review. These renders do not establish physical keyboard/VoiceOver acceptance or native-speaker translation quality; non-English additions remain marked for review.


## Native refinement · Release27

At the Release27 checkpoint, the catalog had **381 entries / 278 literal native keys** in four locales, with **540 compiled-resource assertions**. New messages distinguish stop requested, stopped/current-state review, experimental connection and compact file/test-source status. Non-English translations remain in review. Own-window capture now includes API native multi-selection, for 35 images per locale; this is not physical VoiceOver or native-speaker acceptance.

## Pending visibility and connection details · Release28

The catalog contains **386 entries / 281 literal native keys** across four locales, with **560 compiled-resource assertions**. Five new entries name Connection details, folder-content changes and pending removal, and explain an empty pending list. Native own-window checks include the details sheet, a two-record deletion and reviewed restore (38 captures per locale). Non-English copy remains marked for in-context/native-speaker review.

## Labs and extension installation · Release29

The current catalog has **400 entries / 294 literal native keys** in four locales. Fourteen new Labs/install messages describe per-profile unpacked setup, the bundled ZIP, native-host requirements, separate API/file conditions and unchanged real-profile restrictions. Checker self-tests and **616 compiled-resource assertions** cover the catalog. Translation/in-context review remains pending.

## Labs switches and pending review · Release30

**414 entries / 308 literal native keys** cover four locales. Fourteen messages explain saved-source pending comparison, no-op refresh, option failures, disabled file apply and selected-profile extension record evidence. The compiled-resource checker includes the new messages; non-English translations still need in-context/native-speaker review.

The Release30 compiled-resource run passes **672 assertions**. Four own-window runs produce **42 captures each**, including switch-off/on and extension-record labels. Physical text-size/VoiceOver and native-speaker acceptance remain open.

## Settings sidebar and registered-profile table · Release31

The current catalog contains **421 entries / 315 literal native keys** across four locales. Ten new messages cover General/Settings access, version/help, profile-table headers, manual rescan and empty/batch guidance; three selected-only messages are removed, and row statuses are shortened for the table. The compiled-resource checker drops obsolete keys and includes all new messages. Non-English and physical accessibility review remains open.

The Release31 resource run passes **700 assertions**. Four preferred-language own-window runs produce **44 captures each**, including Settings General/Labs and the three-state registered-profile table. These are render/synthetic checks, with physical accessibility and native-speaker review still pending.
