import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { I18nProvider } from "@/lib/i18n/client";

import { AiPanel, aiErrorMessage, AnalysisView, type Investigation } from "./ai-panel";
import { dollars } from "./ai-settings";

function wrap(ui: ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

const inv = {
  id: "inv-1",
  incident_id: "i1",
  incident_key: "INC-1001",
  incident_title: "Checkout latency",
  incident_severity: "sev2",
  trigger: "manual",
  status: "succeeded",
  provider: "fake",
  model: "fake-rules-v1",
  is_demo_provider: true,
  summary: "Most likely: deploy",
  error_code: null,
  created_at: new Date().toISOString(),
  finished_at: null,
  prompt_version: "investigate_v1",
  data_gaps: [],
  error_detail: null,
  tool_calls_used: 0,
  tokens_used: 0,
  started_at: null,
  requested_by: null,
  my_feedback: null,
  evidence: [
    {
      ref: "EV-1",
      kind: "deployment",
      title: "checkout deploy v2.14.0",
      excerpt: { text: "v2.14.0 deployed 12 min before the incident" },
      source_query: { type: "deployment" },
      observed_at: null,
    },
  ],
  proposals: [
    {
      id: "p1",
      kind: "remediate",
      description: "Roll back",
      risk: "sensitive",
      status: "proposed",
      decided_by: null,
      decided_at: null,
      decision_note: null,
      executes_automatically: false,
    },
    {
      id: "p2",
      kind: "remediate",
      description: "Purge the cache",
      risk: "destructive",
      status: "proposed",
      decided_by: null,
      decided_at: null,
      decision_note: null,
      executes_automatically: false,
    },
  ],
  result: {
    incident_id: "INC-1001",
    summary: "Latency rose after v2.14.0",
    impact: "Checkout is slow",
    probable_causes: [
      {
        cause: "Bad deploy",
        status: "hypothesis",
        confidence: 0.62,
        confidence_label: "medium",
        reasoning: "Timing",
        evidence_refs: ["EV-1"],
        counter_evidence_refs: [],
        how_to_verify: "Compare before/after",
      },
    ],
    recommended_actions: [
      { action: "Roll back", kind: "remediate", risk: "sensitive", rationale: "", requires_approval: true, proposal_id: "p1" },
      { action: "Purge the cache", kind: "remediate", risk: "destructive", rationale: "", requires_approval: true, proposal_id: "p2" },
    ],
    data_gaps: ["No traces"],
    limitations: "Demo analyzer, not an LLM.",
    adjustments: [],
  },
} as unknown as Investigation;

afterEach(() => vi.unstubAllGlobals());

describe("AnalysisView", () => {
  it("labels hypotheses, shows computed evidence and the demo analyzer", async () => {
    render(<AnalysisView inv={inv} canAct isAdmin={false} onDecide={() => {}} />);
    expect(screen.getByText(/Hypotheses — not confirmed/)).toBeInTheDocument();
    expect(screen.getByText("DEMO ANALYZER · NOT AN LLM")).toBeInTheDocument();
    expect(screen.getByText("MEDIUM · 62%")).toBeInTheDocument();
    expect(screen.getByText("No traces")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "EV-1" }));
    expect(screen.getByText("v2.14.0 deployed 12 min before the incident")).toBeInTheDocument();
    expect(screen.getByText(/not by the AI/)).toBeInTheDocument();
  });

  it("asks for confirmation before approving and keeps destructive steps for admins", async () => {
    const onDecide = vi.fn();
    const confirm = vi.fn().mockReturnValue(true);
    vi.stubGlobal("confirm", confirm);
    render(<AnalysisView inv={inv} canAct isAdmin={false} onDecide={onDecide} />);
    expect(screen.getAllByRole("button", { name: "Approve" })).toHaveLength(1); // not the destructive one
    expect(screen.getByText(/An admin must decide/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Approve" }));
    expect(confirm.mock.calls[0][0]).toMatch(/DevPulse does not run it/);
    expect(onDecide).toHaveBeenCalledWith("p1", true);
  });

  it("viewers can read but not decide", () => {
    render(<AnalysisView inv={inv} canAct={false} isAdmin={false} onDecide={() => {}} />);
    expect(screen.queryByRole("button", { name: "Approve" })).toBeNull();
  });
});

describe("AiPanel", () => {
  it("explains why an investigation can't start", async () => {
    const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
      if (init?.method === "POST")
        return new Response(
          JSON.stringify({ status: 409, code: "ai.disabled", detail: "AI is disabled", title: "Conflict" }),
          { status: 409 },
        );
      if (url.endsWith("/investigations")) return Response.json([]);
      return Response.json({});
    });
    vi.stubGlobal("fetch", fetchMock);
    wrap(<AiPanel orgId="o1" incidentRef="INC-1" canAct isAdmin={false} />);
    await userEvent.click(await screen.findByRole("button", { name: "Investigate with AI" }));
    await waitFor(() => expect(screen.getByText(/turned off for this organization/)).toBeInTheDocument());
  });

  it("asks for the analysis in the viewer's language", async () => {
    const bodies: unknown[] = [];
    const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        bodies.push(JSON.parse(String(init.body)));
        return Response.json({ ...inv, status: "queued", result: null, language: "vi" }, { status: 202 });
      }
      if (url.endsWith("/investigations")) return Response.json([]);
      return Response.json({});
    });
    vi.stubGlobal("fetch", fetchMock);
    wrap(
      <I18nProvider locale="vi">
        <AiPanel orgId="o1" incidentRef="INC-1" canAct isAdmin={false} />
      </I18nProvider>,
    );
    await userEvent.click(await screen.findByRole("button", { name: "Điều tra bằng AI" }));
    await waitFor(() => expect(bodies).toEqual([{ language: "vi" }]));
  });

  it("shows failures without blocking the incident", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) =>
        url.endsWith("/investigations")
          ? Response.json([{ id: "inv-1" }])
          : Response.json({ ...inv, status: "failed", result: null, error_code: "ai.no_evidence" }),
      ),
    );
    wrap(<AiPanel orgId="o1" incidentRef="INC-1" canAct isAdmin={false} />);
    expect(await screen.findByText("Analysis unavailable")).toBeInTheDocument();
    expect(screen.getByText(/no telemetry for this incident/)).toBeInTheDocument();
  });
});

describe("helpers", () => {
  it("formats micro-dollars and error codes", () => {
    expect(dollars(4_400)).toBe("$0.0044");
    expect(dollars(14_400)).toBe("$0.01");
    expect(dollars(20_000_000)).toBe("$20.00");
    expect(aiErrorMessage("ai.budget_exceeded")).toMatch(/budget/);
    expect(aiErrorMessage("other", "Server detail")).toBe("Server detail");
  });
});
