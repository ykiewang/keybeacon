<!--
SYNC IMPACT REPORT (temporary; remove before committing the amended constitution)
=================================================================================
Version change: [blank template placeholders] → 1.1.0
Bump rationale: The committed file had been reset to the unfilled scaffold. This
  amendment re-instantiates the full governance document. Relative to the current
  (empty) baseline this ADDS six principles plus three governance sections, i.e. a
  MINOR expansion of materially new guidance (per operator decision 2026-10-24).
  Principle names/semantics match the "v1.0.0" referenced throughout specs/001 and
  specs/002 Constitution Checks, reconstructed from those citations (.specify/ is
  not version-controlled, so the prior file text was unrecoverable from git).

Modified principles (placeholder → concrete):
  [PRINCIPLE_1_NAME] → I. Wire-Contract Self-Containment
  [PRINCIPLE_2_NAME] → II. Backward Compatibility is Non-Negotiable
  [PRINCIPLE_3_NAME] → III. Identity From Protocol, Not Branding
  [PRINCIPLE_4_NAME] → IV. Observable Degradation Over Guessing
  [PRINCIPLE_5_NAME] → V. Spec-First Development (NON-NEGOTIABLE)
  (added sixth)      → VI. Bilingual Normative Docs

Added sections:
  - Platform Scope & Delivery (was [SECTION_2_NAME])
  - Testing & Verification Discipline (was [SECTION_3_NAME])
  - Governance (instantiated from the GOVERNANCE_RULES placeholder)

Removed sections: none (all template placeholders replaced).

Templates / artefacts consistency:
  ✅ specs/001-connectivity-power/plan.md  — references 6 principles + Testing
     Discipline + Governance; consistent with this document.
  ✅ specs/002-zmk-keybeacon-kbp11/plan.md — "6 principles + Platform Scope +
     Testing Discipline + Governance"; consistent.
  ✅ conformance/tests/test_payload_parsing.py / test_us4_fields.py — quote the
     Testing & Verification Discipline clause verbatim; consistent.
  ⚠ .specify/templates/plan-template.md — contains a generic "Constitution Check"
     gate; no principle-name coupling, no update required.

Deferred / TODO: none. RATIFICATION_DATE resolved to 2026-10-06 (earliest
  traceable adoption evidence) per operator decision.
=================================================================================
-->

# KeyBeacon Constitution

## Core Principles

### I. Wire-Contract Self-Containment

The `protocol/` module is the single source of truth for everything observable on the air.
Normative wire behaviour — service/characteristic UUIDs, byte offsets, field semantics, notify
rules — MUST be defined in `protocol/README.md` and MUST be implementable from that document
alone. The protocol definition MUST NOT depend on application source (`app/**`) or conformance
source (`conformance/**`); dependencies only ever point *toward* the protocol, never away from it.
Contracts under `specs/*/contracts/` are drafting ground; once ratified they are copied verbatim
into `protocol/` so no second source of truth survives.

**Rationale**: A third party must be able to build a conforming keyboard or host from the protocol
document with no access to this repository's code. Self-containment is what makes the standard
portable, vendorable, and independently versionable.

### II. Backward Compatibility is Non-Negotiable

The service UUID is the MAJOR-version signal. A MINOR change MUST keep the service UUID unchanged,
MUST keep every previously published payload byte-identical in layout and meaning, and MAY only
*add* optional characteristics/descriptors or append reserved-tolerant trailing bytes. Both
directions MUST keep working: an old app against new firmware, and a new app against old firmware.
Removing or redefining a published field, or repurposing the service UUID, is a MAJOR change and
MUST be justified in the amendment that introduces it.

**Rationale**: Keyboards and apps ship on independent timelines. Honest additive evolution is the
only way heterogeneous producer/consumer pairs can interoperate without coordinated upgrades.

### III. Identity From Protocol, Not Branding

Compatibility MUST be determined solely by presence of the KeyBeacon service UUID; display identity
MUST come solely from the BLE GAP device name. Implementations MUST NOT maintain a model
registry/whitelist, match on vendor, make, or model, or gate any behaviour on branding. Capability
MUST be derived structurally from what the firmware actually exposes (characteristics present,
capability bits set), never from "is this an X-brand board".

**Rationale**: KeyBeacon is implementation-neutral. Any keyboard that speaks KBP interoperates;
branding checks would fracture that universality and privilege specific hardware.

### IV. Observable Degradation Over Guessing

When data is missing, unknown, or stale, implementations MUST show honest nothing rather than a
fabricated value. A field whose capability is not declared MUST be hidden entirely (no placeholder,
no zero). Unavailable numeric values MUST use the defined sentinel, never a fake `0`. A field with
no update past the staleness threshold MUST be rendered as last-known value plus timestamp and
visibly de-emphasised; a transport disconnect MUST mark all fields stale immediately. Every
degradation event MUST emit exactly one structured diagnostic log entry. An unchanged snapshot MUST
suppress its notification.

**Rationale**: A screenless keyboard's whole value is trustworthy state. A confident wrong reading
is worse than a blank; silence on "no change" keeps an idle keyboard at zero traffic.

### V. Spec-First Development (NON-NEGOTIABLE)

Changes to `protocol/**`, `conformance/**`, or `app/*/Sources/**` MUST originate from a feature
specification under `specs/NNN-*/` produced through the Spec Kit workflow (specify → clarify → plan
→ tasks → analyze). Contracts are authored before implementation; published artefacts are updated
from the ratified contract, not the reverse. Code that lands without a traceable spec/plan is a
process violation and MUST be reworked through the workflow.

**Rationale**: The protocol is a durable public contract. Writing the contract first — and proving
it with analysis before code — is what keeps the wire format deliberate rather than emergent.

### VI. Bilingual Normative Docs

Every normative public document — `protocol/README.md`, `protocol/CHANGELOG.md`,
`conformance/CONFORMANCE.md`, `conformance/checklist.md`, and the repository root `README.md` — MUST
present English and 中文 side-by-side. The 中文 text MUST be a full mirror of the English, not a
summary, and MUST render the RFC 2119 terms stably: MUST → 必须, SHOULD → 应, MAY → 可.
Repository-internal working documents (e.g. files under `specs/*/contracts/`) are exempt.

**Rationale**: The standard targets a global audience of keyboard and app authors. A partial or
drifting translation would create two subtly different contracts; a full mirror keeps one.

## Platform Scope & Delivery

- The shipping host today is **macOS 12+**; Windows and Linux are planned and MUST reuse the same
  OS-neutral protocol without forking the wire format.
- The firmware reference stack is **ZMK**. Any firmware API names cited in docs are non-normative
  examples; conformance is judged **solely at the wire**, never by firmware internals.
- A **reference keyboard** MUST exist for end-to-end verification (historically Totem; Corne where a
  split/peripheral path is required). At least one scenario per feature MUST be reproducible on it.
- Split keyboards expose KeyBeacon only from the half holding the central (host-link) role;
  peripheral and recovery images MUST NOT advertise the service.

## Testing & Verification Discipline

- A new public type in `BleWidgetCore` without a matching XCTest MUST fail code review.
- Payload-parsing and classification logic MUST be covered by pure-function unit tests runnable
  without BLE hardware.
- Every feature MUST ship `specs/NNN/quickstart.md` with explicit Given/When/Then scenarios mapped
  to its FR/SC identifiers.
- Backward-compatibility and degradation paths MUST each have an executable or scripted verification
  (regression suite or quickstart scenario), not only prose.

## Governance

This constitution supersedes ad-hoc convention; where guidance conflicts, the constitution wins.

- **Amendments** MUST be made through this command, MUST record a Sync Impact Report, and MUST carry
  a semantic-version bump: MAJOR for backward-incompatible governance/principle removals or
  redefinitions, MINOR for a newly added or materially expanded principle/section, PATCH for
  clarifications and non-semantic refinements.
- **Compliance review**: any commit touching `protocol/**`, `conformance/**`, `app/*/Sources/**`, or
  `specs/*/contracts/**` MUST include an explicit Constitution Check in its PR description, and the
  feature's `/speckit-analyze` pass MUST report CRITICAL = 0 and HIGH = 0 before merge.
- **Runtime guidance** for day-to-day work lives in `AGENTS.md` and the per-feature `plan.md`
  Constitution Check sections, which MUST stay consistent with the principles above.

**Version**: 1.1.0 | **Ratified**: 2026-10-06 | **Last Amended**: 2026-10-24
