import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { HealthPill, SeverityChip, timeAgo } from "./status";

describe("status components", () => {
  it("labels health with text, not colour alone", () => {
    render(<HealthPill health="critical" />);
    expect(screen.getByText("Critical")).toBeInTheDocument();
  });

  it("renders severity as SEVn", () => {
    render(<SeverityChip severity="sev2" />);
    expect(screen.getByText("SEV2")).toBeInTheDocument();
  });

  it.each([
    [30, "just now"],
    [5 * 60, "5m ago"],
    [3 * 3600, "3h ago"],
    [2 * 86400, "2d ago"],
  ])("timeAgo(%i s) = %s", (secondsAgo, expected) => {
    const now = Date.UTC(2026, 10, 11, 12);
    expect(timeAgo(new Date(now - secondsAgo * 1000).toISOString(), now)).toBe(expected);
  });

  it("handles missing timestamps", () => {
    expect(timeAgo(null)).toBe("never");
  });
});
