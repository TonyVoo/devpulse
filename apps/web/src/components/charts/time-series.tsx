"use client";

import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceArea,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

export type Point = { t: number; v: number | null };
export type Marker = { t: number; label: string; tone?: "deploy" | "incident" | "event" };

const TONE: Record<NonNullable<Marker["tone"]>, string> = {
  deploy: "var(--color-violet)",
  incident: "var(--color-critical)",
  event: "var(--color-fg-subtle)",
};

function clock(t: number): string {
  return new Date(t).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function dayClock(t: number): string {
  return new Date(t).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

/** Evenly spaced ticks across the axis (Recharts' own time ticks are sparse). */
export function timeTicks([from, to]: [number, number], count = 5): number[] {
  if (!(to > from)) return [from];
  const step = (to - from) / (count - 1);
  return Array.from({ length: count }, (_, i) => Math.round(from + i * step));
}

/**
 * Line chart for one metric. Missing data (`null`) is drawn as a gap, never as zero.
 * Deployments, the incident start and other events are vertical markers; an optional
 * threshold is a horizontal line, and breach ranges are shaded.
 */
export function TimeSeriesChart({
  title,
  points,
  format,
  markers = [],
  threshold,
  breaches = [],
  height = 200,
  domain,
  loading = false,
}: {
  title: string;
  points: Point[];
  format: (v: number) => string;
  markers?: Marker[];
  threshold?: number;
  breaches?: { from: number; to: number }[];
  height?: number;
  /** Time range of the x axis; defaults to the data's extent. */
  domain?: [number, number];
  loading?: boolean;
}) {
  const xDomain: [number | string, number | string] = domain ?? ["dataMin", "dataMax"];
  const span = domain ?? extent(points);
  const labelled = thinLabels(markers, span);
  const tickFormat = span[1] - span[0] > 20 * 3_600_000 ? dayClock : clock;
  const values = points.map((p) => p.v).filter((v): v is number => v !== null);
  const summary = values.length
    ? `${title}: ${values.length} points, min ${format(Math.min(...values))}, max ${format(Math.max(...values))}` +
      (markers.length ? `, ${markers.length} markers: ${markers.map((m) => m.label).join("; ")}` : "")
    : `${title}: no data in this range`;

  return (
    <figure className="min-w-0">
      <figcaption className="mb-1 text-xs font-medium text-fg-muted">{title}</figcaption>
      {/* Charts are summarised for screen readers; the SVG itself is decorative. */}
      <p className="sr-only">{summary}</p>
      {loading && values.length === 0 ? (
        <div className="animate-pulse rounded-md bg-raised" style={{ height }} role="status" aria-busy aria-label={`Loading ${title}`} />
      ) : values.length === 0 ? (
        <div
          className="flex items-center justify-center rounded-md border border-dashed border-line text-xs text-fg-subtle"
          style={{ height }}
        >
          No data in this range
        </div>
      ) : (
        <div aria-hidden style={{ height }}>
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={points} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
              <CartesianGrid stroke="var(--color-line)" strokeDasharray="3 3" vertical={false} />
              <XAxis
                dataKey="t"
                type="number"
                scale="time"
                domain={xDomain}
                allowDataOverflow
                ticks={timeTicks(span)}
                tickFormatter={tickFormat}
                tick={{ fill: "var(--color-fg-subtle)", fontSize: 11 }}
                stroke="var(--color-line)"
                minTickGap={40}
              />
              <YAxis
                tickFormatter={format}
                tick={{ fill: "var(--color-fg-subtle)", fontSize: 11 }}
                stroke="var(--color-line)"
                width={56}
              />
              <Tooltip
                labelFormatter={(t) => new Date(Number(t)).toLocaleString()}
                formatter={(v) => [typeof v === "number" ? format(v) : "no data", title]}
                contentStyle={{
                  background: "var(--color-surface)",
                  border: "1px solid var(--color-line)",
                  borderRadius: 6,
                  fontSize: 12,
                }}
              />
              {breaches.map((b) => (
                <ReferenceArea key={b.from} x1={b.from} x2={b.to} fill="var(--color-critical)" fillOpacity={0.08} />
              ))}
              {threshold !== undefined && (
                <ReferenceLine
                  y={threshold}
                  stroke="var(--color-critical)"
                  strokeDasharray="4 4"
                  label={{ value: `threshold ${format(threshold)}`, fill: "var(--color-critical)", fontSize: 11, position: "insideTopRight" }}
                />
              )}
              {markers.map((m, i) => (
                <ReferenceLine
                  key={`${m.t}-${m.label}`}
                  x={m.t}
                  stroke={TONE[m.tone ?? "event"]}
                  strokeDasharray={m.tone === "incident" ? undefined : "2 3"}
                  label={
                    labelled.has(i)
                      ? { value: m.label, fill: TONE[m.tone ?? "event"], fontSize: 10, position: "insideTopLeft" }
                      : undefined
                  }
                />
              ))}
              <Line
                type="monotone"
                dataKey="v"
                stroke="var(--color-cyan)"
                strokeWidth={2}
                dot={(props: { cx?: number; cy?: number; index?: number }) =>
                  isIsolated(points, props.index ?? -1) && props.cx !== undefined && props.cy !== undefined ? (
                    <circle key={props.index} cx={props.cx} cy={props.cy} r={2.5} fill="var(--color-cyan)" />
                  ) : (
                    <g key={props.index} />
                  )
                }
                connectNulls={false}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}
    </figure>
  );
}

function extent(points: Point[]): [number, number] {
  return points.length ? [points[0].t, points[points.length - 1].t] : [0, 1];
}

/** A value with no neighbours would be invisible as a line segment: draw it as a dot. */
export function isIsolated(points: Point[], i: number): boolean {
  if (i < 0 || points[i]?.v == null) return false;
  return points[i - 1]?.v == null && points[i + 1]?.v == null;
}

/** Indexes of markers whose labels fit (≥ 6% of the axis apart); others keep their line only. */
export function thinLabels(markers: Marker[], [from, to]: [number, number]): Set<number> {
  const gap = Math.max(1, (to - from) * 0.06);
  const order = markers.map((m, i) => [m.t, i] as const).sort((a, b) => a[0] - b[0]);
  const keep = new Set<number>();
  let last = -Infinity;
  for (const [t, i] of order) {
    if (t - last >= gap) {
      keep.add(i);
      last = t;
    }
  }
  return keep;
}

export const fmt = {
  ms: (v: number) => (v >= 1000 ? `${(v / 1000).toFixed(2)} s` : `${Math.round(v)} ms`),
  pct: (v: number) => `${(v * 100).toFixed(v < 0.01 ? 2 : 1)}%`,
  count: (v: number) => (v >= 1000 ? `${(v / 1000).toFixed(1)}k` : `${Math.round(v)}`),
  num: (v: number) => (Math.abs(v) >= 100 ? v.toFixed(0) : v.toFixed(2)),
};

/** Metric series from the API (`[iso, value|null][]`) → chart points. */
export function toPoints(series: [string, number | null][] | undefined): Point[] {
  return (series ?? []).map(([t, v]) => ({ t: new Date(t).getTime(), v }));
}
