# DevPulse — UI Design System

Direction: premium, dark-first engineering tool. Dense but calm. Color carries **meaning** (status) first, brand second. Glass and gradients are accents, never behind body text.

Tokens are defined once (`core/design_system/tokens.dart` and `apps/web/src/styles/tokens.css`) and mirrored; a CI check compares the two token files.

## 1. Color tokens

| Token | Dark (default) | Light | Use |
|---|---|---|---|
| `bg.base` | `#0A0E1A` deep navy | `#F7F8FB` | app background |
| `bg.surface` | `#111726` | `#FFFFFF` | cards, sheets |
| `bg.surfaceRaised` | `#182033` | `#FFFFFF` + shadow | modals, popovers |
| `bg.glass` | `rgba(24,32,51,0.72)` + 20px blur | `rgba(255,255,255,0.8)` | nav bar, sticky headers only |
| `border.subtle` | `#232C42` | `#E3E7EF` | dividers |
| `text.primary` | `#E8ECF5` | `#0E1424` | 14.9:1 on base |
| `text.secondary` | `#9AA5BE` | `#4A5470` | ≥ 7:1 |
| `text.tertiary` | `#8590AA` | `#5D6680` | ≥ 5:1 on every surface, metadata only |
| `accent.cyan` | `#22D3EE` | `#0E7490` | primary actions, focus, live data (white on light cyan: 5.4:1) |
| `accent.violet` | `#A78BFA` | `#6D28D9` | AI surfaces |
| `gradient.ai` | cyan → violet 135° | same, darker | AI badges, Copilot header (not text backgrounds) |
| `status.healthy` | `#34D399` | `#047857` | |
| `status.degraded` | `#FBBF24` | `#92400E` | |
| `status.major` | `#FB923C` | `#C2410C` | SEV2 |
| `status.critical` | `#FB7185` | `#BE123C` | |
| `status.unknown` | `#8592A6` | `#5B6678` | |
| `sev.1..4` | critical · major · degraded · unknown tokens | | severity chips |

Status is never color-only: every status pairs color with an icon and a label (colorblind-safe).

All text tokens are ≥ 4.5:1 on canvas, surface and raised in both themes (re-checked in the Phase 5 audit; several Phase 0 values were 3.3–4.4:1). Web and mobile use the same values.

## 2. Typography

- UI: **Inter** (variable). Code, IDs, versions, metric values: **JetBrains Mono** with tabular figures.
- Scale (sp): display 32/40 · title 22/28 · headline 18/24 · body 15/22 · bodySmall 13/18 · label 12/16 (medium, +0.2 tracking) · mono 13/18.
- Respect OS text scaling; layouts tested at 1.0×, 1.3×, 2.0×.

## 3. Spacing, radius, elevation, motion

- Spacing: 4-pt grid → `xs 4, sm 8, md 12, lg 16, xl 24, 2xl 32`. Screen gutter 16 (phone), 24 (tablet).
- Radius: `sm 6` (chips), `md 10` (inputs, buttons), `lg 16` (cards), `xl 24` (sheets).
- Elevation in dark mode = lighter surface + 1px `border.subtle`, not shadows.
- Motion: `fast 120ms` (press), `base 200ms` (state change), `slow 320ms` (route) with `easeOutCubic`; live-status pulse 1.6s only on critical items; all disabled under reduce-motion.

## 4. Components

| Component | Notes |
|---|---|
| `DpStatusDot` / `DpStatusPill` | health + label, optional pulse for critical |
| `DpSeverityChip` | SEV1–4 with icon |
| `DpMetricTile` | label, mono value, delta vs previous window, sparkline |
| `DpSparkline`, `DpTimeSeriesChart` | `fl_chart` on mobile, Recharts on web; threshold line, deployment markers on x-axis, accessible summary |
| `DpServiceRow`, `DpIncidentCard` | list items with status, service, age, assignee avatar, pending-sync indicator |
| `DpTimelineItem` | actor icon (user/system/AI), relative time, payload |
| `DpEvidenceCard` | evidence ref (EV-3), kind icon, excerpt, "view source" |
| `DpHypothesisCard` | cause, confidence bar + label (Low/Medium/High), cited evidence chips, "Hypothesis — not confirmed" tag |
| `DpBanner` | offline / stale / error / demo-data variants |
| `DpEmptyState`, `DpErrorState`, `DpSkeleton` | consistent illustrations/icons and copy |
| `DpButton` (primary/secondary/ghost/destructive), `DpTextField`, `DpSegmentedFilter`, `DpSearchBar`, `DpBottomSheet` | |

## 5. Designed states

| State | Treatment |
|---|---|
| Healthy | quiet: green dot + "Healthy", no emphasis, sorts below problems |
| Degraded | amber pill, delta on the offending metric highlighted |
| Critical incident | red severity chip, left accent bar, subtle pulse on dot, pinned at top of Overview |
| Empty | specific copy ("No open incidents — all clear") + next action ("Add a service", "Create alert rule") |
| Loading | skeletons matching final layout on first load; thin top progress for refresh |
| Offline | persistent slim banner "Offline · showing data from 10:42", actions queue with clock icon |
| API error | inline card with problem `title`, Retry, and request id (copyable) for support |
| Demo data | violet "Demo" tag on every demo-sourced item |

## 6. Accessibility

WCAG 2.2 AA contrast, 48dp touch targets, Semantics labels for all icon buttons and charts, focus order, screen-reader announcements for live status changes (polite) and sev1 (assertive), no information conveyed by color alone.

**Enforced by tests (Phase 5):**
- Mobile `test/features/a11y_test.dart`: Flutter's guideline checks on overview, incidents, incident detail, services, Copilot, AI chat, settings and sign-in, in dark and light: tap targets ≥ 48dp (Android) / 44pt (iOS), every tap target labelled, text contrast ≥ 4.5:1. Every screen also lays out at 2× text size without overflow. Reduce motion: page transitions are skipped (`ReduceMotionTransitionsBuilder`); the loading skeleton and charts stop animating.
- Web Playwright specs run axe (WCAG 2.0/2.1 A + AA) on every page they visit, in light and dark; any serious or critical violation fails the build. Loading skeletons are `role="status"`; charts are summarised for screen readers (the SVG is `aria-hidden`); button hover darkens instead of fading (fading broke contrast).
- Layout rules that came out of the audit: buttons wrap their label instead of overflowing; header and metadata rows use `Wrap`; list-tile trailing columns are bounded.
