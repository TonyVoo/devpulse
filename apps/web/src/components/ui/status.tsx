"use client";

import { useI18n } from "@/lib/i18n/client";
import { cn } from "@/lib/utils";

export { timeAgo } from "@/lib/i18n/translate";

type Health = "healthy" | "degraded" | "critical" | "unknown";
type Severity = "sev1" | "sev2" | "sev3" | "sev4";

const HEALTH: Record<Health, { className: string; icon: string }> = {
  healthy: { className: "text-healthy bg-healthy/10", icon: "●" },
  degraded: { className: "text-degraded bg-degraded/10", icon: "▲" },
  critical: { className: "text-critical bg-critical/10", icon: "■" },
  unknown: { className: "text-unknown bg-unknown/10", icon: "○" },
};

/** Status is never colour-only: shape + label. */
export function HealthPill({ health }: { health: Health }) {
  const { t } = useI18n();
  const h = HEALTH[health];
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-sm px-2 py-0.5 text-xs font-semibold", h.className)}>
      <span aria-hidden>{h.icon}</span>
      {t(`status.${health}`)}
    </span>
  );
}

const SEV: Record<Severity, string> = {
  sev1: "border-critical/60 text-critical",
  sev2: "border-major/60 text-major",
  sev3: "border-degraded/60 text-degraded",
  sev4: "border-unknown/60 text-unknown",
};

export function SeverityChip({ severity }: { severity: Severity }) {
  return (
    <span className={cn("rounded-sm border px-1.5 py-px font-mono text-[11px] font-bold", SEV[severity])}>
      {severity.toUpperCase()}
    </span>
  );
}

export function DemoTag() {
  const { t } = useI18n();
  return (
    <span className="rounded bg-violet/15 px-1.5 py-px text-[10px] font-bold tracking-wide text-violet">
      {t("common.demo")}
    </span>
  );
}

type IncidentStatus = "triggered" | "acknowledged" | "resolved";

const INCIDENT_STATUS: Record<IncidentStatus, { className: string; icon: string }> = {
  triggered: { className: "text-critical bg-critical/10", icon: "■" },
  acknowledged: { className: "text-degraded bg-degraded/10", icon: "▲" },
  resolved: { className: "text-healthy bg-healthy/10", icon: "●" },
};

/** Incident status with shape + label (never colour alone). */
export function IncidentStatusBadge({ status }: { status: IncidentStatus }) {
  const { t } = useI18n();
  const s = INCIDENT_STATUS[status];
  return (
    <span className={cn("inline-flex shrink-0 items-center gap-1 rounded-sm px-2 py-0.5 text-xs font-semibold", s.className)}>
      <span aria-hidden>{s.icon}</span>
      <span>{t(`status.${status}`)}</span>
    </span>
  );
}
