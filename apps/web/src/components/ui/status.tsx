import { cn } from "@/lib/utils";

type Health = "healthy" | "degraded" | "critical" | "unknown";
type Severity = "sev1" | "sev2" | "sev3" | "sev4";

const HEALTH: Record<Health, { label: string; className: string; icon: string }> = {
  healthy: { label: "Healthy", className: "text-healthy bg-healthy/10", icon: "●" },
  degraded: { label: "Degraded", className: "text-degraded bg-degraded/10", icon: "▲" },
  critical: { label: "Critical", className: "text-critical bg-critical/10", icon: "■" },
  unknown: { label: "Unknown", className: "text-unknown bg-unknown/10", icon: "○" },
};

/** Status is never colour-only: shape + label. */
export function HealthPill({ health }: { health: Health }) {
  const h = HEALTH[health];
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-sm px-2 py-0.5 text-xs font-semibold", h.className)}>
      <span aria-hidden>{h.icon}</span>
      {h.label}
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
  return (
    <span className="rounded bg-violet/15 px-1.5 py-px text-[10px] font-bold tracking-wide text-violet">DEMO</span>
  );
}

export function timeAgo(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return "never";
  const s = Math.max(0, (now - new Date(iso).getTime()) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

type IncidentStatus = "triggered" | "acknowledged" | "resolved";

const INCIDENT_STATUS: Record<IncidentStatus, { label: string; className: string; icon: string }> = {
  triggered: { label: "Triggered", className: "text-critical bg-critical/10", icon: "■" },
  acknowledged: { label: "Acknowledged", className: "text-degraded bg-degraded/10", icon: "▲" },
  resolved: { label: "Resolved", className: "text-healthy bg-healthy/10", icon: "●" },
};

/** Incident status with shape + label (never colour alone). */
export function IncidentStatusBadge({ status }: { status: IncidentStatus }) {
  const s = INCIDENT_STATUS[status];
  return (
    <span className={cn("inline-flex shrink-0 items-center gap-1 rounded-sm px-2 py-0.5 text-xs font-semibold", s.className)}>
      <span aria-hidden>{s.icon}</span>
      <span>{s.label}</span>
    </span>
  );
}
