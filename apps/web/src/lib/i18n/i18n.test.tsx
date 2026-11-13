import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { HealthPill, IncidentStatusBadge } from "@/components/ui/status";

import { I18nProvider } from "./client";
import { resolveLocale } from "./config";
import { en } from "./messages/en";
import { vi } from "./messages/vi";
import { hasMessage, makeFmt, timeAgo, translate } from "./translate";

function leaves(node: unknown, prefix = ""): [string, string][] {
  if (typeof node === "string") return [[prefix, node]];
  return Object.entries(node as Record<string, unknown>).flatMap(([k, v]) => leaves(v, prefix ? `${prefix}.${k}` : k));
}

const placeholders = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();

describe("dictionaries", () => {
  const enLeaves = new Map(leaves(en));
  const viLeaves = new Map(leaves(vi));

  it("have the same keys", () => {
    expect([...viLeaves.keys()].sort()).toEqual([...enLeaves.keys()].sort());
  });

  it("keep every placeholder in the Vietnamese text", () => {
    const broken = [...enLeaves].filter(([k, s]) => placeholders(s).join() !== placeholders(viLeaves.get(k) ?? "").join());
    expect(broken.map(([k]) => k)).toEqual([]);
  });

  it("have no empty translations", () => {
    expect([...viLeaves].filter(([, s]) => !s.trim()).map(([k]) => k)).toEqual([]);
  });
});

describe("translate", () => {
  it("fills placeholders and falls back to English for unknown locales' gaps", () => {
    expect(translate("en", "overview.urgentMany", { n: 3 })).toBe("3 critical or major incidents are open.");
    expect(translate("vi", "overview.urgentMany", { n: 3 })).toBe("Đang có 3 sự cố nghiêm trọng hoặc mức cao.");
  });

  it("resolves keys that contain dots (API error codes)", () => {
    expect(translate("vi", "errors.auth.invalid_credentials")).toBe("Email hoặc mật khẩu không đúng.");
    expect(hasMessage("errors.auth.email_taken")).toBe(true);
    expect(hasMessage("errors.nope.missing")).toBe(false);
  });

  it("formats relative time and numbers per language", () => {
    const now = Date.UTC(2026, 10, 12, 12);
    expect(timeAgo(new Date(now - 5 * 60_000).toISOString(), now, "vi")).toBe("5 phút trước");
    expect(timeAgo(null, now, "vi")).toBe("chưa có");
    expect(makeFmt("vi").ms(1650)).toBe("1,65 s");
    expect(makeFmt("en").ms(1650)).toBe("1.65 s");
    expect(makeFmt("vi").pct(0.053)).toBe("5,3%");
  });
});

describe("resolveLocale", () => {
  it.each([
    ["vi", null, "vi"],
    ["en", "vi-VN,vi;q=0.9", "en"], // a saved choice wins
    [undefined, "vi-VN,vi;q=0.9,en;q=0.8", "vi"],
    [undefined, "fr-FR,en;q=0.5,vi;q=0.9", "vi"], // highest-ranked supported language
    [undefined, "fr-FR", "en"],
    ["xx", undefined, "en"],
  ])("cookie %s + Accept-Language %s → %s", (cookie, header, expected) => {
    expect(resolveLocale(cookie, header)).toBe(expected);
  });
});

describe("components", () => {
  it("render in the provider's language", () => {
    render(
      <I18nProvider locale="vi">
        <HealthPill health="degraded" />
        <IncidentStatusBadge status="acknowledged" />
      </I18nProvider>,
    );
    expect(screen.getByText("Suy giảm")).toBeInTheDocument();
    expect(screen.getByText("Đã xác nhận")).toBeInTheDocument();
  });
});
