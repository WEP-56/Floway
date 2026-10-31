import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  Globe,
  Minus,
  Moon,
  PanelLeftClose,
  PanelLeftOpen,
  Plus,
  Square,
  Sun,
  X,
  Zap,
  type LucideIcon,
} from "lucide-react";
import { useApp, type PageKey } from "@/store";
import { Button, ModalHostContext, Snackbar, Switch } from "@/components/ui";
import { NAV_ITEMS, PAGE_TITLES } from "@/nav";
import { Dashboard } from "@/pages/Dashboard";
import { Nodes } from "@/pages/Nodes";
import { Subscriptions } from "@/pages/Subscriptions";
import { Settings } from "@/pages/Settings";
import { ImportSubModal } from "@/components/ImportSubModal";
import { cn } from "@/utils/cn";

/* ------------------------------------------------------------------ */
/* MD3 Expressive navigation rail item.
   Collapsed: 56×32 pill indicator with the label below.
   Expanded:  full-width 56px pill with the label inline.
   The icon keeps the same x position, so the morph stays smooth.      */
/* ------------------------------------------------------------------ */
function RailItem({
  icon: Icon,
  label,
  shortLabel,
  active,
  expanded,
  onClick,
}: {
  icon: LucideIcon;
  label: string;
  shortLabel?: string;
  active?: boolean;
  expanded: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-current={active ? "page" : undefined}
      aria-label={label}
      data-ripple-in=".rail-ind"
      className={cn(
        "group relative w-full shrink-0 outline-none transition-[height] duration-500 ease-emph",
        expanded ? "h-[60px]" : "h-[72px]",
      )}
    >
      <span
        className={cn(
          "rail-ind absolute overflow-hidden rounded-full transition-all duration-500 ease-emph",
          expanded ? "top-[2px] right-3 left-3 h-14" : "top-1 right-5 left-5 h-8",
          active ? "bg-scontainer" : "bg-transparent group-hover:bg-ink/[0.06]",
        )}
      />
      <span
        className={cn(
          "pointer-events-none absolute left-9 grid h-6 w-6 place-items-center transition-all duration-500 ease-emph",
          expanded ? "top-[18px]" : "top-2",
          active ? "text-onscontainer" : "text-ink2",
        )}
      >
        <Icon size={22} strokeWidth={active ? 2.3 : 1.9} />
      </span>
      <span
        className={cn(
          "pointer-events-none absolute inset-x-0 top-[42px] text-center text-[12px] transition-opacity",
          expanded ? "opacity-0 duration-100" : "opacity-100 delay-200 duration-300",
          active ? "font-semibold text-ink" : "font-medium text-ink2",
        )}
      >
        {shortLabel ?? label}
      </span>
      <span
        className={cn(
          "pointer-events-none absolute top-1/2 left-[72px] -translate-y-1/2 text-[14px] whitespace-nowrap transition-opacity",
          expanded ? "opacity-100 delay-200 duration-300" : "opacity-0 duration-100",
          active ? "font-semibold text-onscontainer" : "font-medium text-ink2",
        )}
      >
        {label}
      </span>
    </button>
  );
}

/* ------------------------------------------------------------------ */
export function DesktopApp() {
  const { settings, set, toast, dismissToast, resolvedTheme, toggleTheme, testing, testNodes } = useApp();
  const [page, setPage] = useState<PageKey>("dashboard");
  const [expanded, setExpanded] = useState(true);
  const manual = useRef(false);
  const [importOpen, setImportOpen] = useState(false);
  const [host, setHost] = useState<HTMLDivElement | null>(null);

  /* adaptive layout: the rail collapses automatically on narrow windows until the user toggles it */
  useEffect(() => {
    if (!host || typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(([entry]) => {
      if (!manual.current) setExpanded(entry.contentRect.width >= 900);
    });
    ro.observe(host);
    return () => ro.disconnect();
  }, [host]);

  const toggleRail = () => {
    manual.current = true;
    setExpanded((e) => !e);
  };

  const actions: Record<PageKey, ReactNode> = {
    dashboard: (
      <div className="flex items-center gap-3 rounded-full bg-surface py-1 pr-1 pl-4 shadow-card">
        <Globe size={15} className="text-ink3" />
        <span className="text-[13px] font-medium">系统代理</span>
        <Switch checked={settings.systemProxy} onChange={(v) => set("systemProxy", v)} label="系统代理" />
      </div>
    ),
    nodes: (
      <Button variant="tonal" size="sm" onClick={testNodes} disabled={testing} icon={<Zap size={15} />}>
        {testing ? "测试中…" : "测试延迟"}
      </Button>
    ),
    subs: (
      <Button size="sm" onClick={() => setImportOpen(true)} icon={<Plus size={16} />}>
        导入订阅
      </Button>
    ),
    settings: null,
  };

  return (
    <div
      ref={setHost}
      className="relative flex w-full max-w-[1080px] min-w-[720px] flex-col overflow-hidden rounded-[22px] bg-frame shadow-win ring-1 ring-black/5 dark:ring-white/5"
      style={{ height: 720 }}
    >
      <ModalHostContext.Provider value={host}>
        {/* window caption */}
        <div className="flex h-10 shrink-0 items-center">
          <span className="flex-1" />
          <span className="text-[12px] font-medium tracking-wide text-ink3">Floway</span>
          <div className="flex flex-1 justify-end">
            {[
              { icon: <Minus size={15} />, label: "最小化" },
              { icon: <Square size={11.5} />, label: "最大化" },
              { icon: <X size={15} />, label: "关闭" },
            ].map((b, i) => (
              <button
                key={b.label}
                type="button"
                aria-label={b.label}
                data-noripple
                className={cn(
                  "grid h-10 w-12 place-items-center text-ink2 transition-colors hover:bg-ink/[0.07] hover:text-ink",
                  i === 2 && "hover:bg-[#c42b1c] hover:text-white",
                )}
              >
                {b.icon}
              </button>
            ))}
          </div>
        </div>

        <div className="flex min-h-0 flex-1">
          {/* navigation rail */}
          <aside
            className={cn(
              "flex shrink-0 flex-col overflow-hidden pb-3 transition-[width] duration-500 ease-emph",
              expanded ? "w-[224px]" : "w-[96px]",
            )}
          >
            <div className="flex h-14 shrink-0 items-center pl-6">
              <button
                type="button"
                onClick={toggleRail}
                aria-label={expanded ? "收起侧边栏" : "展开侧边栏"}
                title={expanded ? "收起侧边栏" : "展开侧边栏"}
                className="grid h-12 w-12 place-items-center rounded-full text-ink2 transition-colors hover:bg-ink/[0.07] hover:text-ink"
              >
                {expanded ? <PanelLeftClose size={22} strokeWidth={1.9} /> : <PanelLeftOpen size={22} strokeWidth={1.9} />}
              </button>
            </div>

            <nav className="mt-3 flex flex-col">
              {NAV_ITEMS.map((item) => (
                <RailItem
                  key={item.key}
                  icon={item.icon}
                  label={item.label}
                  active={page === item.key}
                  expanded={expanded}
                  onClick={() => setPage(item.key)}
                />
              ))}
            </nav>

            <div className="mt-auto">
              <RailItem
                icon={resolvedTheme === "dark" ? Sun : Moon}
                label={resolvedTheme === "dark" ? "浅色模式" : "深色模式"}
                shortLabel={resolvedTheme === "dark" ? "浅色" : "深色"}
                expanded={expanded}
                onClick={toggleTheme}
              />
            </div>
          </aside>

          {/* content pane */}
          <div className="relative mr-3 mb-3 flex min-w-0 flex-1 flex-col overflow-hidden rounded-[24px] bg-canvas">
            <header className="flex h-[72px] shrink-0 items-center gap-3 px-7">
              <h1 className="text-[24px] font-medium tracking-tight">{PAGE_TITLES[page]}</h1>
              <div className="ml-auto flex items-center gap-2">{actions[page]}</div>
            </header>

            <main
              key={page}
              className="@container animate-page fade-top sb-thin min-h-0 flex-1 overflow-y-auto px-6 pt-2 pb-8"
            >
              {page === "dashboard" && <Dashboard platform="pc" onNavigate={setPage} />}
              {page === "nodes" && <Nodes platform="pc" />}
              {page === "subs" && <Subscriptions platform="pc" />}
              {page === "settings" && <Settings platform="pc" />}
            </main>

            {toast && (
              <Snackbar
                key={toast.id}
                toast={toast}
                onAction={() => {
                  toast.action?.run();
                  dismissToast();
                }}
              />
            )}
          </div>
        </div>

        <ImportSubModal open={importOpen} onClose={() => setImportOpen(false)} platform="pc" />
      </ModalHostContext.Provider>
    </div>
  );
}
