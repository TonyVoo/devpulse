import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { breachRanges, describeRule } from "@/components/alerts/alert-rules";
import { isIsolated, thinLabels } from "@/components/charts/time-series";
import { AuditLog, diffKeys } from "@/components/audit/audit-log";
import { incidentWindow } from "@/components/incidents/incident-panels";
import { grantableRoles, MembersTable } from "@/components/orgs/members-table";
import { metricsQuery } from "@/components/services/service-detail";
import { isActive } from "@/components/shell/shell";

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn(), refresh: vi.fn() }), useParams: () => ({}), usePathname: () => "/" }));

function wrap(ui: ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}
afterEach(() => vi.unstubAllGlobals());

describe("pure helpers", () => {
  it("never offers roles above your own", () => {
    expect(grantableRoles("admin")).toEqual(["admin", "engineer", "viewer"]);
    expect(grantableRoles("owner")[0]).toBe("owner");
  });

  it("diffs audit snapshots", () => {
    expect(diffKeys({ role: "engineer", x: 1 }, { role: "admin", x: 1 })).toEqual(["role"]);
    expect(diffKeys(null, { enabled: true })).toEqual(["enabled"]);
  });

  it("turns breached preview points into ranges", () => {
    const at = (m: number) => new Date(Date.UTC(2026, 10, 12, 10, m)).toISOString();
    const pts = [
      { at: at(0), value: 1, breached: false },
      { at: at(5), value: 9, breached: true },
      { at: at(10), value: 9, breached: true },
      { at: at(15), value: 1, breached: false },
      { at: at(20), value: 9, breached: true },
    ];
    const r = breachRanges(pts);
    expect(r).toHaveLength(2);
    expect(r[0].to - r[0].from).toBe(5 * 60_000);
  });

  it("describes rules in plain words with units", () => {
    expect(
      describeRule({ metric: "http.server.error_rate", aggregation: "ratio", comparator: "gt", threshold: 0.05, window_s: 300, for_s: 120 }),
    ).toBe("error rate over 5 min > 5.0% for 2 min");
    expect(
      describeRule({ metric: "http.server.duration_ms", aggregation: "p95", comparator: "gte", threshold: 1500, window_s: 600, for_s: 0 }),
    ).toBe("p95(http.server.duration_ms) over 10 min ≥ 1.50 s");
  });

  it("frames an incident: 1h before → resolution (+15m), capped", () => {
    const now = Date.UTC(2026, 10, 12, 12);
    const w = incidentWindow({ started_at: new Date(now - 30 * 60_000).toISOString(), resolved_at: null }, now);
    expect(now - w.from.getTime()).toBe(90 * 60_000);
    expect(w.to.getTime()).toBe(now);
  });

  it("breaks the line across gaps instead of bridging them", async () => {
    const { toPoints } = await import("@/components/charts/time-series");
    const at = (h: number) => new Date(Date.UTC(2026, 10, 12, h)).toISOString();
    const pts = toPoints([[at(0), 1], [at(1), 2], [at(2), 3], [at(9), 4], [at(10), 5]]);
    expect(pts.map((p) => p.v)).toEqual([1, 2, 3, null, 4, 5]);
  });

  it("draws lone points and thins crowded marker labels", () => {
    const pts = [{ t: 0, v: null }, { t: 1, v: 5 }, { t: 2, v: null }, { t: 3, v: 1 }, { t: 4, v: 2 }];
    expect([0, 1, 2, 3, 4].map((i) => isIsolated(pts, i))).toEqual([false, true, false, false, false]);
    const kept = thinLabels(
      [
        { t: 10, label: "a" },
        { t: 11, label: "b" },
        { t: 60, label: "c" },
      ],
      [0, 100],
    );
    expect([...kept].sort()).toEqual([0, 2]);
  });

  it("builds metric queries and nav state", () => {
    const q = metricsQuery(["a:p95", "b"], new Date(0), new Date(1000));
    expect(new URLSearchParams(q).getAll("names")).toEqual(["a:p95", "b"]);
    expect(isActive("/o/1/incidents/INC-1", "/incidents", "/o/1")).toBe(true);
    expect(isActive("/o/1/incidents", "", "/o/1")).toBe(false);
  });
});

describe("MembersTable", () => {
  it("admins invite and get a one-time link; they can't edit themselves", async () => {
    const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
      if (url.endsWith("/members"))
        return Response.json([
          { user_id: "me", email: "me@x.dev", display_name: "Me", avatar_url: null, role: "admin", joined_at: "2026-01-01T00:00:00Z" },
          { user_id: "u2", email: "b@x.dev", display_name: "Bea", avatar_url: null, role: "engineer", joined_at: "2026-01-01T00:00:00Z" },
          { user_id: "u3", email: "o@x.dev", display_name: "Olu", avatar_url: null, role: "owner", joined_at: "2026-01-01T00:00:00Z" },
        ]);
      if (url.endsWith("/invitations") && init?.method === "POST")
        return Response.json({ id: "i1", email: "new@x.dev", role: "engineer", token: "tok123", expires_at: "", created_at: "" });
      return Response.json([]);
    });
    vi.stubGlobal("fetch", fetchMock);
    wrap(<MembersTable orgId="o1" myUserId="me" myRole="admin" />);
    expect(await screen.findByLabelText("Role for Bea")).toBeInTheDocument();
    expect(screen.queryByLabelText("Role for Me")).toBeNull(); // not yourself
    expect(screen.queryByLabelText("Role for Olu")).toBeNull(); // not above you
    await userEvent.type(screen.getByLabelText("Email"), "new@x.dev");
    await userEvent.click(screen.getByRole("button", { name: "Create invite link" }));
    expect(await screen.findByText(/\/invite\/tok123$/)).toBeInTheDocument();
    expect(screen.getByText(/shown once/)).toBeInTheDocument();
  });
});

describe("AuditLog", () => {
  it("filters by family and shows before/after", async () => {
    const fetchMock = vi.fn(async (url: string) =>
      url &&
      Response.json({
        items: [
          {
            id: "a1",
            actor_id: "u1",
            actor_name: "Ada",
            actor_type: "user",
            action: "member.role_changed",
            target_type: "membership",
            target_id: "u2",
            before: { role: "engineer" },
            after: { role: "admin" },
            ip: null,
            request_id: null,
            created_at: new Date().toISOString(),
          },
        ],
        next_cursor: null,
      }),
    );
    vi.stubGlobal("fetch", fetchMock);
    wrap(<AuditLog orgId="o1" />);
    expect(await screen.findByText("member.role_changed")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: /Show changes/ }));
    expect(screen.getByText("engineer")).toBeInTheDocument();
    expect(screen.getByText("admin")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("combobox", { name: "Show" }));
    await userEvent.click(screen.getByRole("option", { name: "Members" }));
    expect(screen.getByRole("combobox", { name: "Show" })).toHaveTextContent("Members");
    expect(String(fetchMock.mock.calls.at(-1)?.[0])).toContain("action_prefix=member.");
  });
});
