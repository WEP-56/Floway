import {
  createContext,
  useContext,
  useEffect,
  useId,
  useRef,
  useState,
  type HTMLAttributes,
  type KeyboardEvent,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { Check } from "lucide-react";
import { cn } from "@/utils/cn";
import type { ToastData } from "@/store";

export type Platform = "pc" | "mobile";

/** App shells provide their own root so dialogs cover the whole window. */
export const ModalHostContext = createContext<HTMLElement | null>(null);

/* ------------------------------------------------------------------ */
/* Brand mark                                                          */
/* ------------------------------------------------------------------ */
export function AppMark({ size = 32, className }: { size?: number; className?: string }) {
  return (
    <span
      className={cn(
        "grid shrink-0 place-items-center rounded-[30%] bg-gradient-to-br from-[#4c5bd4] to-[#8a5cf6] text-white shadow-card",
        className,
      )}
      style={{ width: size, height: size }}
      aria-hidden
    >
      <svg viewBox="0 0 24 24" width={size * 0.62} height={size * 0.62} fill="none">
        <circle cx="12" cy="12" r="3.1" fill="currentColor" />
        <ellipse cx="12" cy="12" rx="9.2" ry="4.1" transform="rotate(-28 12 12)" stroke="currentColor" strokeWidth="1.7" />
        <ellipse cx="12" cy="12" rx="9.2" ry="4.1" transform="rotate(52 12 12)" stroke="currentColor" strokeWidth="1.7" opacity="0.55" />
      </svg>
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Surfaces                                                            */
/* ------------------------------------------------------------------ */
export function Card({ className, children, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn("rounded-[24px] bg-surface shadow-card", className)} {...rest}>
      {children}
    </div>
  );
}

/** MD3 list sub-header — primary colored, Android settings style */
export function SectionLabel({ children, className }: { children: ReactNode; className?: string }) {
  return <h3 className={cn("px-4 pb-2 text-[13px] font-semibold text-primary", className)}>{children}</h3>;
}

/* ------------------------------------------------------------------ */
/* MD3 Switch (52×32, icon thumb, grows while pressed)                 */
/* ------------------------------------------------------------------ */
export function Switch({
  checked,
  onChange,
  disabled,
  label,
}: {
  checked: boolean;
  onChange?: (v: boolean) => void;
  disabled?: boolean;
  label?: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      data-noripple
      onClick={(e) => {
        e.stopPropagation();
        onChange?.(!checked);
      }}
      className={cn(
        "group relative h-8 w-[52px] shrink-0 rounded-full border-2 transition-colors duration-200",
        checked ? "border-primary bg-primary" : "border-ink3/70 bg-surf3",
        disabled && "cursor-not-allowed opacity-40",
      )}
    >
      <span
        className={cn(
          "pointer-events-none absolute top-1/2 h-10 w-10 -translate-y-1/2 rounded-full opacity-0 transition-all duration-200 group-hover:opacity-100",
          checked ? "left-[14px] bg-primary/12" : "left-[-6px] bg-ink/[0.08]",
        )}
      />
      <span
        className={cn(
          "absolute top-1/2 grid -translate-y-1/2 place-items-center rounded-full transition-all duration-300 ease-spring",
          checked
            ? "left-[22px] h-6 w-6 bg-onprimary group-active:left-[20px] group-active:h-7 group-active:w-7"
            : "left-[6px] h-4 w-4 bg-ink3 group-active:left-0 group-active:h-7 group-active:w-7",
        )}
      >
        <Check
          size={14}
          strokeWidth={3}
          className={cn("text-primary transition-all duration-200", checked ? "scale-100 opacity-100" : "scale-50 opacity-0")}
        />
      </span>
    </button>
  );
}

/* ------------------------------------------------------------------ */
/* MD3 Expressive connected button group (shape morph on select)       */
/* ------------------------------------------------------------------ */
export function Segmented<T extends string>({
  options,
  value,
  onChange,
  size = "md",
  full,
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
  size?: "sm" | "md";
  full?: boolean;
}) {
  const h = size === "sm" ? 34 : 42;
  const R = h / 2;
  const r = size === "sm" ? 7 : 9;
  return (
    <div className={cn("gap-[3px]", full ? "flex w-full" : "inline-flex")}>
      {options.map((o, i) => {
        const sel = o.value === value;
        const first = i === 0;
        const last = i === options.length - 1;
        const radius = sel
          ? `${R}px`
          : `${first ? R : r}px ${last ? R : r}px ${last ? R : r}px ${first ? R : r}px`;
        return (
          <button
            key={o.value}
            type="button"
            onClick={() => onChange(o.value)}
            style={{ height: h, borderRadius: radius }}
            className={cn(
              "flex items-center justify-center gap-1.5 font-medium whitespace-nowrap transition-[border-radius,background-color,color] duration-300 ease-emph",
              size === "sm" ? "px-4 text-[12.5px]" : "px-5 text-[13.5px]",
              full && "flex-1 px-2",
              sel ? "bg-primary text-onprimary" : "bg-surf2 text-ink2 hover:bg-surf3 hover:text-ink",
            )}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Buttons                                                             */
/* ------------------------------------------------------------------ */
export function Button({
  children,
  onClick,
  variant = "filled",
  size = "md",
  className,
  icon,
  disabled,
}: {
  children?: ReactNode;
  onClick?: () => void;
  variant?: "filled" | "tonal" | "text" | "danger";
  size?: "sm" | "md";
  className?: string;
  icon?: ReactNode;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={cn(
        "inline-flex shrink-0 items-center justify-center gap-2 rounded-full font-medium transition-all duration-200 active:scale-[0.97]",
        size === "sm" ? "h-9 px-4 text-[13px]" : "h-10 px-6 text-[14px]",
        variant === "filled" && "bg-primary text-onprimary hover:shadow-card",
        variant === "tonal" && "bg-scontainer text-onscontainer hover:shadow-card",
        variant === "text" && "px-3 text-primary hover:bg-primary/10",
        variant === "danger" && "bg-err/12 text-err hover:bg-err/20",
        disabled && "pointer-events-none opacity-45",
        className,
      )}
    >
      {icon}
      {children}
    </button>
  );
}

export function IconButton({
  children,
  onClick,
  className,
  label,
  active,
}: {
  children: ReactNode;
  onClick?: () => void;
  className?: string;
  label?: string;
  active?: boolean;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      className={cn(
        "grid h-10 w-10 shrink-0 place-items-center rounded-full text-ink2 transition-colors duration-200 hover:bg-ink/[0.07] hover:text-ink",
        active && "bg-scontainer text-onscontainer",
        className,
      )}
    >
      {children}
    </button>
  );
}

/** MD3 filter chip */
export function Chip({
  selected,
  onClick,
  children,
}: {
  selected: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "inline-flex h-8 shrink-0 items-center gap-1.5 rounded-[10px] text-[13px] font-medium whitespace-nowrap transition-all duration-200",
        selected ? "bg-scontainer pr-3 pl-2 text-onscontainer" : "bg-surf2 px-3 text-ink2 hover:text-ink",
      )}
    >
      {selected && <Check size={15} strokeWidth={2.6} />}
      {children}
    </button>
  );
}

/* ------------------------------------------------------------------ */
/* List item (div-based so trailing switches never nest in a button)   */
/* ------------------------------------------------------------------ */
export function Row({
  icon,
  title,
  subtitle,
  trailing,
  onClick,
  danger,
  className,
}: {
  icon?: ReactNode;
  title: ReactNode;
  subtitle?: ReactNode;
  trailing?: ReactNode;
  onClick?: () => void;
  danger?: boolean;
  className?: string;
}) {
  const interactive = !!onClick;
  return (
    <div
      role={interactive ? "button" : undefined}
      tabIndex={interactive ? 0 : undefined}
      data-ripple={interactive ? "" : undefined}
      onClick={onClick}
      onKeyDown={
        interactive
          ? (e: KeyboardEvent<HTMLDivElement>) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                onClick?.();
              }
            }
          : undefined
      }
      className={cn(
        "flex w-full items-center gap-4 rounded-[18px] px-3 py-3 text-left outline-none transition-colors duration-150",
        interactive && "hover:bg-ink/[0.045] focus-visible:bg-ink/[0.06]",
        className,
      )}
    >
      {icon && (
        <span
          className={cn(
            "grid h-10 w-10 shrink-0 place-items-center rounded-[14px] bg-surf2 text-ink2",
            danger && "bg-err/12 text-err",
          )}
        >
          {icon}
        </span>
      )}
      <span className="min-w-0 flex-1">
        <span className={cn("block truncate text-[14.5px] font-medium", danger && "text-err")}>{title}</span>
        {subtitle && <span className="mt-0.5 block truncate text-[12.5px] text-ink2">{subtitle}</span>}
      </span>
      {trailing}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Data display                                                        */
/* ------------------------------------------------------------------ */
export function Sparkline({
  data,
  tone = "primary",
  height = 34,
}: {
  data: number[];
  tone?: "primary" | "ok";
  height?: number;
}) {
  const id = useId().replace(/:/g, "");
  const max = Math.max(...data, 1);
  const pts = data.map((v, i) => [(i / (data.length - 1)) * 100, 30 - (v / max) * 25 - 2] as const);
  let line = `M ${pts[0][0].toFixed(2)} ${pts[0][1].toFixed(2)}`;
  for (let i = 1; i < pts.length; i++) {
    const [x0, y0] = pts[i - 1];
    const [x1, y1] = pts[i];
    const cx = (x0 + x1) / 2;
    line += ` C ${cx.toFixed(2)} ${y0.toFixed(2)}, ${cx.toFixed(2)} ${y1.toFixed(2)}, ${x1.toFixed(2)} ${y1.toFixed(2)}`;
  }
  const area = `${line} L 100 32 L 0 32 Z`;
  const stroke = tone === "primary" ? "var(--c-primary)" : "var(--c-ok)";

  return (
    <svg viewBox="0 0 100 32" preserveAspectRatio="none" className="w-full" style={{ height }} aria-hidden>
      <defs>
        <linearGradient id={`g${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={stroke} stopOpacity="0.26" />
          <stop offset="100%" stopColor={stroke} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill={`url(#g${id})`} />
      <path d={line} fill="none" stroke={stroke} strokeWidth="2" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

export function LatencyBadge({ ms, testing }: { ms: number | null; testing?: boolean }) {
  if (ms == null) {
    return (
      <span className={cn("text-[12.5px] font-medium text-ink3", testing && "animate-breathe")}>
        {testing ? "测试中" : "—"}
      </span>
    );
  }
  const tone = ms < 100 ? "text-ok" : ms < 200 ? "text-warn" : "text-err";
  const dot = ms < 100 ? "bg-ok" : ms < 200 ? "bg-warn" : "bg-err";
  return (
    <span className={cn("inline-flex items-center gap-1.5 text-[12.5px] font-semibold tabular-nums", tone)}>
      <span className={cn("h-1.5 w-1.5 rounded-full", dot)} />
      {ms} ms
    </span>
  );
}

/** MD3 (2024) linear progress — gap between indicator & track + stop dot */
export function ProgressBar({ value, tone = "primary" }: { value: number; tone?: "primary" | "warn" }) {
  const pct = Number.isFinite(value) ? Math.min(100, Math.max(0, value * 100)) : 0;
  const warn = tone === "warn";
  return (
    <div className="flex h-1.5 w-full items-center gap-[5px]" role="progressbar" aria-valuenow={Math.round(pct)}>
      <div
        className={cn("h-full min-w-[6px] rounded-full transition-[width] duration-700 ease-emph", warn ? "bg-warn" : "bg-primary")}
        style={{ width: `${pct}%` }}
      />
      <div className={cn("relative h-full min-w-[6px] flex-1 rounded-full", warn ? "bg-warn/20" : "bg-primary/15")}>
        <span
          className={cn(
            "absolute top-1/2 right-px h-1 w-1 -translate-y-1/2 rounded-full",
            warn ? "bg-warn" : "bg-primary",
          )}
        />
      </div>
    </div>
  );
}

/** MD3 Expressive wavy indeterminate progress */
export function WavyProgress({ className }: { className?: string }) {
  return <div className={cn("wavy-progress w-full", className)} role="progressbar" aria-busy="true" />;
}

/** MD3 circular indeterminate progress */
export function Spinner({ size = 20, className }: { size?: number; className?: string }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} className={cn("spinner shrink-0 text-primary", className)} aria-hidden>
      <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" />
    </svg>
  );
}

export function Kbd({ children }: { children: ReactNode }) {
  return (
    <kbd className="inline-flex h-7 min-w-[28px] items-center justify-center rounded-[8px] bg-surf2 px-2 font-sans text-[11.5px] font-semibold text-ink2 shadow-key">
      {children}
    </kbd>
  );
}

export function StatusPill({ running }: { running: boolean }) {
  return (
    <span
      className={cn(
        "inline-flex h-7 items-center gap-2 rounded-full px-3 text-[12.5px] font-semibold transition-colors duration-300",
        running ? "bg-ok/12 text-ok" : "bg-surf2 text-ink2",
      )}
    >
      <span className={cn("h-2 w-2 rounded-full", running ? "animate-breathe bg-ok" : "bg-ink3")} />
      {running ? "运行中" : "已停止"}
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Power button — MD3 Expressive shape morph (circle ⇄ 9-lobe cookie)  */
/* ------------------------------------------------------------------ */
function useTween(target: number, duration = 700) {
  const [value, setValue] = useState(target);
  const current = useRef(target);
  useEffect(() => {
    const from = current.current;
    if (Math.abs(from - target) < 1e-4) return;
    const t0 = performance.now();
    let raf = 0;
    const tick = (now: number) => {
      const p = Math.min(1, (now - t0) / duration);
      const c1 = 1.4;
      const c3 = c1 + 1;
      const eased = 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2); // ease-out-back
      const v = from + (target - from) * eased;
      current.current = v;
      setValue(v);
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [target, duration]);
  return value;
}

function blobPath(amp: number, lobes = 9, r = 43, steps = 180) {
  let d = "";
  for (let i = 0; i < steps; i++) {
    const t = (i / steps) * Math.PI * 2;
    const rr = r * (1 + amp * Math.cos(lobes * t));
    d += `${i ? "L" : "M"}${(50 + rr * Math.cos(t)).toFixed(2)} ${(50 + rr * Math.sin(t)).toFixed(2)}`;
  }
  return `${d}Z`;
}

export function PowerButton({
  running,
  onToggle,
  size = 120,
}: {
  running: boolean;
  onToggle: () => void;
  size?: number;
}) {
  const amp = useTween(running ? 0.075 : 0, 760);
  const pop = useTween(running ? 1 : 0.88, 620);
  return (
    <button
      type="button"
      data-noripple
      onClick={onToggle}
      aria-label={running ? "停止代理" : "启动代理"}
      className="relative grid shrink-0 place-items-center rounded-full outline-none transition-transform duration-200 active:scale-95"
      style={{ width: size, height: size }}
    >
      <svg
        viewBox="0 0 100 100"
        className="animate-rotate absolute inset-0 h-full w-full"
        style={{ animationPlayState: running ? "running" : "paused" }}
        aria-hidden
      >
        <path
          d={blobPath(amp)}
          style={{ fill: running ? "var(--c-pcontainer)" : "var(--c-surf2)", transition: "fill 0.5s ease" }}
        />
      </svg>
      <span
        className={cn(
          "relative grid place-items-center rounded-full transition-[background-color,color,box-shadow] duration-500",
          running ? "bg-primary text-onprimary shadow-float" : "bg-surf3 text-ink2",
        )}
        style={{ width: size * 0.6, height: size * 0.6, transform: `scale(${pop})` }}
      >
        <svg
          viewBox="0 0 24 24"
          width={size * 0.24}
          height={size * 0.24}
          fill="none"
          stroke="currentColor"
          strokeWidth="2.4"
          strokeLinecap="round"
        >
          <path d="M12 3.5v7.5" />
          <path d="M7.4 6.6a7 7 0 1 0 9.2 0" />
        </svg>
      </span>
    </button>
  );
}

/* ------------------------------------------------------------------ */
/* Modal — MD3 dialog (desktop) / draggable bottom sheet (mobile)      */
/* ------------------------------------------------------------------ */
export function Modal({
  open,
  onClose,
  title,
  subtitle,
  platform,
  children,
  footer,
  icon,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  subtitle?: string;
  platform: Platform;
  children: ReactNode;
  footer?: ReactNode;
  icon?: ReactNode;
}) {
  const host = useContext(ModalHostContext);
  const sheetRef = useRef<HTMLDivElement>(null);
  const dragStart = useRef<{ y: number; scale: number } | null>(null);
  const [drag, setDrag] = useState(0);
  const [dragging, setDragging] = useState(false);

  useEffect(() => {
    if (!open) {
      setDrag(0);
      setDragging(false);
      return;
    }
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  let body: ReactNode;

  if (platform === "pc") {
    body = (
      <div className="absolute inset-0 z-40 flex items-center justify-center p-8">
        <div className="animate-fade absolute inset-0 bg-black/30" onClick={onClose} />
        <div
          role="dialog"
          aria-modal="true"
          className="animate-pop relative flex max-h-full w-[440px] max-w-full flex-col rounded-[28px] bg-dialog p-6 shadow-float"
        >
          {icon && <div className="mb-4 flex justify-center">{icon}</div>}
          <h2 className={cn("text-[22px] leading-tight font-medium", icon && "text-center")}>{title}</h2>
          {subtitle && (
            <p className={cn("mt-2 text-[13.5px] leading-relaxed text-ink2", icon && "text-center")}>{subtitle}</p>
          )}
          <div className="sb-thin -mx-2 mt-5 min-h-0 flex-1 overflow-y-auto px-2 pb-1">{children}</div>
          <div className="mt-5 flex justify-end gap-2">
            {footer ?? (
              <Button variant="text" onClick={onClose}>
                完成
              </Button>
            )}
          </div>
        </div>
      </div>
    );
  } else {
    const end = () => {
      if (!dragStart.current) return;
      dragStart.current = null;
      setDragging(false);
      if (drag > 90) onClose();
      setDrag(0);
    };
    body = (
      <div className="absolute inset-0 z-40 flex flex-col justify-end">
        <div
          className="animate-fade absolute inset-0 bg-black/35"
          style={{ opacity: 1 - Math.min(drag / 400, 0.6) }}
          onClick={onClose}
        />
        <div
          ref={sheetRef}
          role="dialog"
          aria-modal="true"
          className={cn(
            "animate-sheet relative flex max-h-[88%] flex-col rounded-t-[28px] bg-dialog pb-8 shadow-float",
            !dragging && "transition-transform duration-300 ease-emph",
          )}
          style={{ transform: drag ? `translateY(${drag}px)` : undefined }}
        >
          <div
            className="touch-none px-6 pt-3 pb-1 select-none"
            onPointerDown={(e) => {
              const el = sheetRef.current;
              if (!el) return;
              dragStart.current = { y: e.clientY, scale: el.getBoundingClientRect().height / el.offsetHeight || 1 };
              setDragging(true);
              e.currentTarget.setPointerCapture(e.pointerId);
            }}
            onPointerMove={(e) => {
              if (!dragStart.current) return;
              setDrag(Math.max(0, (e.clientY - dragStart.current.y) / dragStart.current.scale));
            }}
            onPointerUp={end}
            onPointerCancel={end}
          >
            <div className="mx-auto h-1 w-8 rounded-full bg-ink3/50" />
            {icon && <div className="mt-5 flex justify-center">{icon}</div>}
            <h2 className={cn("mt-5 text-[20px] leading-tight font-medium", icon && "mt-3 text-center")}>{title}</h2>
            {subtitle && <p className={cn("mt-1.5 text-[13px] text-ink2", icon && "text-center")}>{subtitle}</p>}
          </div>
          <div className="no-sb mt-3 min-h-0 flex-1 overflow-y-auto px-6">{children}</div>
          {footer && <div className="mt-5 flex justify-end gap-2 px-6">{footer}</div>}
        </div>
      </div>
    );
  }

  return host ? createPortal(body, host) : body;
}

/* ------------------------------------------------------------------ */
/* Form helpers                                                        */
/* ------------------------------------------------------------------ */
export function Field({
  label,
  value,
  onChange,
  placeholder,
  mono,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  mono?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block px-1 text-[12.5px] font-medium text-ink2">{label}</span>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        spellCheck={false}
        className={cn(
          "h-12 w-full rounded-[14px] bg-tile px-4 text-[14px] text-ink outline-none transition-shadow duration-200 placeholder:text-ink3 focus:shadow-[inset_0_0_0_2px_var(--c-primary)]",
          mono && "font-mono text-[13px]",
        )}
      />
    </label>
  );
}

export function RadioList<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: { value: T; label: string; desc?: string }[];
  onChange: (v: T) => void;
}) {
  return (
    <div className="space-y-0.5" role="radiogroup">
      {options.map((o) => {
        const sel = value === o.value;
        return (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={sel}
            onClick={() => onChange(o.value)}
            className="flex w-full items-center gap-4 rounded-[16px] px-3 py-3 text-left transition-colors hover:bg-ink/[0.05]"
          >
            <span
              className={cn(
                "grid h-5 w-5 shrink-0 place-items-center rounded-full border-2 transition-colors duration-200",
                sel ? "border-primary" : "border-ink2",
              )}
            >
              <span
                className={cn(
                  "h-2.5 w-2.5 rounded-full bg-primary transition-transform duration-300 ease-spring",
                  sel ? "scale-100" : "scale-0",
                )}
              />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-[14.5px] font-medium">{o.label}</span>
              {o.desc && <span className="mt-0.5 block text-[12.5px] text-ink2">{o.desc}</span>}
            </span>
          </button>
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* MD3 snackbar                                                        */
/* ------------------------------------------------------------------ */
export function Snackbar({
  toast,
  onAction,
  className,
}: {
  toast: ToastData;
  onAction: () => void;
  className?: string;
}) {
  return (
    <div
      role="status"
      className={cn(
        "animate-toast absolute bottom-5 left-1/2 z-50 flex w-max max-w-[86%] min-w-[240px] -translate-x-1/2 items-center gap-2 rounded-[10px] bg-ink py-1.5 pl-4 text-canvas shadow-float",
        toast.action ? "pr-1.5" : "pointer-events-none pr-4",
        className,
      )}
    >
      <span className="min-w-0 flex-1 py-2 text-[13.5px] leading-snug">{toast.msg}</span>
      {toast.action && (
        <button
          type="button"
          onClick={onAction}
          className="shrink-0 rounded-full px-3 py-2 text-[13.5px] font-semibold text-invprimary transition-colors hover:bg-canvas/10"
        >
          {toast.action.label}
        </button>
      )}
    </div>
  );
}
