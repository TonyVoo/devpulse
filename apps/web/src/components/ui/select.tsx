"use client";

import {
  Children,
  isValidElement,
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type KeyboardEvent,
  type ReactElement,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";

import { cn } from "@/lib/utils";

type OptionProps = { value?: string | number; disabled?: boolean; children?: ReactNode };
type Opt = { value: string; label: ReactNode; text: string; disabled: boolean };

type SelectProps = {
  /** Classes for the wrapper (width/flex); the trigger always fills it. */
  className?: string;
  size?: "sm" | "md";
  value?: string;
  defaultValue?: string;
  /** Same shape as a native change event, so call sites read `e.target.value`. */
  onChange?: (e: { target: { value: string } }) => void;
  /** Submitted with the surrounding form through a hidden input. */
  name?: string;
  disabled?: boolean;
  id?: string;
  "aria-label"?: string;
  /** `<option>` elements, exactly as for a native select. */
  children?: ReactNode;
};

function textOf(node: ReactNode): string {
  if (node == null || typeof node === "boolean") return "";
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textOf).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return textOf(node.props.children);
  return "";
}

function readOptions(children: ReactNode): Opt[] {
  const out: Opt[] = [];
  Children.forEach(children, (child) => {
    if (!isValidElement(child)) return;
    if (child.type !== "option") {
      out.push(...readOptions((child as ReactElement<{ children?: ReactNode }>).props.children));
      return;
    }
    const p = (child as ReactElement<OptionProps>).props;
    const text = textOf(p.children);
    out.push({ value: p.value != null ? String(p.value) : text, label: p.children, text, disabled: !!p.disabled });
  });
  return out;
}

type Place = { left: number; width: number; top?: number; bottom?: number; maxHeight: number };

/**
 * DevPulse dropdown: a select-only combobox (WAI-ARIA APG pattern). Focus stays on the
 * trigger; the list is a portal so tables and cards with overflow never clip it.
 * Keys: ↑/↓/Home/End move, Enter/Space choose, Esc closes, Tab chooses and moves on,
 * typing jumps to a matching option.
 */
export function Select({
  className,
  size = "md",
  value,
  defaultValue,
  onChange,
  name,
  disabled,
  id,
  "aria-label": ariaLabel,
  children,
}: SelectProps) {
  const options = readOptions(children);
  const [inner, setInner] = useState(defaultValue ?? options[0]?.value ?? "");
  const current = value ?? inner;
  const selectedIndex = Math.max(0, options.findIndex((o) => o.value === current));
  const selected = options[selectedIndex];

  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(selectedIndex);
  const [place, setPlace] = useState<Place | null>(null);
  const [labelName, setLabelName] = useState<string>();
  const name_ = ariaLabel ?? labelName;
  const trigger = useRef<HTMLButtonElement>(null);
  const list = useRef<HTMLUListElement>(null);
  const typed = useRef({ text: "", at: 0 });
  const listId = useId();
  const optId = (i: number) => `${listId}-o${i}`;

  const enabled = (i: number) => !!options[i] && !options[i].disabled;
  const step = (from: number, dir: 1 | -1) => {
    for (let i = from + dir; i >= 0 && i < options.length; i += dir) if (enabled(i)) return i;
    return from;
  };
  const first = () => step(-1, 1);
  const last = () => step(options.length, -1);

  const choose = (i: number) => {
    const o = options[i];
    if (!o || o.disabled) return;
    if (value === undefined) setInner(o.value);
    if (o.value !== current) onChange?.({ target: { value: o.value } });
  };

  const show = () => {
    if (disabled) return;
    setActive(enabled(selectedIndex) ? selectedIndex : first());
    setOpen(true);
  };
  const close = () => setOpen(false);

  // A role=combobox button doesn't take its name from a wrapping <label> in every browser,
  // so name it explicitly with the label's own text (not the selected value inside it).
  useLayoutEffect(() => {
    if (ariaLabel) return;
    const label = trigger.current?.closest("label");
    const own = label
      ? [...label.childNodes]
          .filter((n) => n.nodeType === Node.TEXT_NODE)
          .map((n) => n.textContent)
          .join(" ")
          .trim()
      : "";
    setLabelName(own || undefined);
  }, [ariaLabel]);

  const measure = useCallback(() => {
    const t = trigger.current;
    if (!t) return;
    const r = t.getBoundingClientRect();
    const gap = 4;
    const margin = 8;
    const below = window.innerHeight - r.bottom - gap - margin;
    const above = r.top - gap - margin;
    const want = Math.min(288, (list.current?.scrollHeight ?? 288) + 2);
    const width = Math.min(Math.max(r.width, 160), window.innerWidth - margin * 2);
    const left = Math.min(Math.max(margin, r.left), window.innerWidth - width - margin);
    if (below >= want || below >= above) {
      setPlace({ left, width, top: r.bottom + gap, maxHeight: Math.max(120, below) });
    } else {
      setPlace({ left, width, bottom: window.innerHeight - r.top + gap, maxHeight: Math.max(120, above) });
    }
  }, []);

  useLayoutEffect(() => {
    if (!open) return;
    measure();
    window.addEventListener("resize", measure);
    window.addEventListener("scroll", measure, true);
    return () => {
      window.removeEventListener("resize", measure);
      window.removeEventListener("scroll", measure, true);
    };
  }, [open, measure]);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: PointerEvent) => {
      const t = e.target as Node;
      if (!trigger.current?.contains(t) && !list.current?.contains(t)) close();
    };
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [open]);

  useEffect(() => {
    if (open) document.getElementById(optId(active))?.scrollIntoView?.({ block: "nearest" });
    // optId is derived from a stable id
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, active, place]);

  const typeahead = (key: string) => {
    const now = Date.now();
    typed.current.text = now - typed.current.at > 600 ? key : typed.current.text + key;
    typed.current.at = now;
    const q = typed.current.text.toLowerCase();
    const start = open ? active : selectedIndex;
    const order = [...options.keys()].map((k) => (start + (q.length === 1 ? 1 : 0) + k) % options.length);
    const hit = order.find((i) => enabled(i) && options[i].text.toLowerCase().startsWith(q));
    if (hit === undefined) return;
    if (open) setActive(hit);
    else choose(hit);
  };

  const onKeyDown = (e: KeyboardEvent<HTMLButtonElement>) => {
    if (disabled) return;
    const k = e.key;
    if (!open) {
      if (["ArrowDown", "ArrowUp", "Enter", " "].includes(k)) {
        e.preventDefault();
        show();
        if (k === "ArrowUp") setActive(enabled(selectedIndex) ? selectedIndex : last());
      } else if (k === "Home" || k === "End") {
        e.preventDefault();
        show();
        setActive(k === "Home" ? first() : last());
      } else if (k.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey) {
        typeahead(k);
      }
      return;
    }
    switch (k) {
      case "ArrowDown":
        e.preventDefault();
        setActive((a) => (e.altKey ? a : step(a, 1)));
        break;
      case "ArrowUp":
        e.preventDefault();
        if (e.altKey) {
          choose(active);
          close();
        } else setActive((a) => step(a, -1));
        break;
      case "Home":
      case "PageUp":
        e.preventDefault();
        setActive(first());
        break;
      case "End":
      case "PageDown":
        e.preventDefault();
        setActive(last());
        break;
      case "Enter":
      case " ":
        e.preventDefault();
        choose(active);
        close();
        break;
      case "Escape":
        e.preventDefault();
        close();
        break;
      case "Tab":
        choose(active);
        close();
        break;
      default:
        if (k.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey) typeahead(k);
    }
  };

  return (
    <span className={cn("relative inline-flex min-w-0", className)}>
      {name !== undefined && <input type="hidden" name={name} value={current} />}
      <button
        ref={trigger}
        id={id}
        type="button"
        role="combobox"
        aria-label={name_}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        aria-activedescendant={open ? optId(active) : undefined}
        disabled={disabled}
        onClick={() => (open ? close() : show())}
        onKeyDown={onKeyDown}
        onBlur={close}
        className={cn(
          "flex w-full min-w-0 cursor-pointer items-center rounded-md border border-line bg-canvas pl-3 pr-9 text-left text-sm text-fg",
          "transition-colors hover:border-fg-subtle focus-visible:border-cyan focus-visible:outline-none",
          "disabled:cursor-not-allowed disabled:opacity-60",
          open && "border-cyan",
          size === "sm" ? "min-h-9" : "min-h-10",
        )}
      >
        <span className="truncate">{selected?.label}</span>
        <svg
          aria-hidden
          viewBox="0 0 16 16"
          className={cn(
            "pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-fg-muted transition-transform",
            open && "rotate-180",
          )}
        >
          <path d="M4 6l4 4 4-4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {open &&
        createPortal(
          <ul
            ref={list}
            id={listId}
            role="listbox"
            aria-label={name_}
            tabIndex={-1}
            // Keep focus on the trigger while clicking in the list.
            onMouseDown={(e) => e.preventDefault()}
            style={{
              position: "fixed",
              left: place?.left ?? -9999,
              width: place?.width,
              top: place?.top,
              bottom: place?.bottom,
              maxHeight: place?.maxHeight ? Math.min(288, place.maxHeight) : 288,
            }}
            className={cn(
              "z-50 overflow-y-auto overscroll-contain rounded-lg border border-line bg-surface p-1 text-sm text-fg shadow-xl shadow-black/30",
              "motion-safe:animate-[dp-pop_120ms_ease-out]",
              !place && "invisible",
            )}
          >
            {options.map((o, i) => {
              const isSelected = i === selectedIndex;
              return (
                <li
                  key={`${o.value}-${i}`}
                  id={optId(i)}
                  role="option"
                  aria-selected={isSelected}
                  aria-disabled={o.disabled || undefined}
                  onPointerMove={() => !o.disabled && i !== active && setActive(i)}
                  onClick={() => {
                    if (o.disabled) return;
                    choose(i);
                    close();
                  }}
                  className={cn(
                    "flex min-h-9 cursor-pointer select-none items-center gap-2 rounded-md py-1.5 pl-2 pr-3",
                    i === active && !o.disabled && "bg-raised",
                    isSelected && "font-medium text-cyan",
                    o.disabled && "cursor-not-allowed text-fg-subtle",
                  )}
                >
                  <svg aria-hidden viewBox="0 0 16 16" className={cn("size-4 shrink-0", !isSelected && "invisible")}>
                    <path d="M3.5 8.5l3 3 6-7" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                  <span className="min-w-0 break-words">{o.label}</span>
                </li>
              );
            })}
          </ul>,
          document.body,
        )}
    </span>
  );
}
