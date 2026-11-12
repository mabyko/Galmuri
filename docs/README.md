# Galmuri documentation

English is the source of truth for current requirements and implementation status. These documents describe an **experimental SwiftUI macOS app**, not a public release. Native editing, fixture-driven merge, and app-owned synthetic apply/recovery are available; real Chrome write support is still gated.

## Start here

| Document | Purpose |
| --- | --- |
| [Tasks](../TASKS.md) | Milestone progress, next task, completion checkboxes, and blockers |
| [Product plan](product-plan.md) | Agreed requirements, proposed scope, flows, and completion criteria |
| [Roadmap](roadmap.md) | Next steps and evidence required at each milestone |
| [Design specification](design-spec.md) | Native screen structure and prototype limits |
| [Technical validation](technical-validation.md) | Permissions, identity, formats, merge, writes, and recovery |
| [Local development](local-development.md) | Build, launch, isolated workspaces, and data locations |
| [Labs](labs.md) | Experimental API/file apply, downloadable extension and installation limits |
| [Release notes](release-notes.md) | Release-by-release changes and detailed current status |
| [Localization](localization.md) | English source, four locales, copy, and release validation |
| [Decision history](decisions.md) | Product discussion outcomes and open questions |
| [Architecture decisions](adr/README.md) | Durable trade-offs and their consequences |
| [Profile connection](profile-connection.md) | Guided Chrome access, explicit profile selection, sample preservation and acceptance limits |
| [macOS bookmark-access research](research/macos-bookmark-access.md) | Standard folder selection, targeted Settings grants and official competing app approaches |
| [Native/API refinement](native-refinement.md) | Gray/blue native editing, bounded records, acknowledged stop and measured merge performance |
| [Chrome API workspaces](chrome-api-workspace.md) | Persistent semantic editing, 3-way review, dedicated API apply, soft removal, restore and interrupted-state adoption |
| [Chrome bridge proof](chrome-bridge-proof.md) | Pairing-only Stage A setup, permissions, protocol, evidence and remaining limits |
| [Chrome API bridge proposal](chrome-api-bridge-plan.md) | Original extension/Native Messaging design, staged evidence gates and links to implemented checkpoints |
| [Chrome apply and HTML handoff](research/chrome-apply-and-html-handoff.md) | Direct-apply constraints, additive HTML import, manual transfer and replacement limits |
| [Permission-row navigation](research/permission-row-navigation.md) | Controlled app-row navigation experiments and implementation limits |
| [Editing UX](editing-ux.md) | Native edit/delete affordances, selection safety, reference decisions and verification limits |
| [Encrypted-store adapter](encrypted-store-adapter.md) | Deferred encrypted support, disabled Labs placeholder and historical core/browser evidence |
| [Code verification](code-verification.md) | Automated/structural evidence and remaining environment acceptance |
| [Validation record](validation.md) | Checks actually completed, with explicit gaps |
| [Glossary](../GLOSSARY.md) | Domain terms and consistent meanings |

## Languages

The project overview is available in [English](../README.md), [Korean](../README.ko.md), [Japanese](../README.ja.md), and [Simplified Chinese](../README.zh-Hans.md). The original [Korean planning references](ko/README.md) are preserved with their date. They are not maintained as exact translations of every future English change. Detailed Japanese and Chinese specifications have not been translated.

## Maintaining the record

Update [TASKS.md](../TASKS.md) when starting or completing work; it is the only progress checklist. Update the product plan when accepted requirements change. Keep proposed implementation choices clearly labeled. Record a substantial architecture decision in an ADR when understanding the rejected alternative matters. Add evidence to the validation record only after a check actually runs. Do not turn a discussion, a translated string, or a mock interaction into a claim of implemented behavior.

Public documents use relative paths and synthetic examples. Local home paths, private browser data, session identifiers, and runtime receipts do not belong in public documentation. Community policies live in [CONTRIBUTING.md](../CONTRIBUTING.md) and [SECURITY.md](../SECURITY.md).
