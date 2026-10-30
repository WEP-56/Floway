import { useEffect, useState } from "react";
import { Plus, RefreshCw } from "lucide-react";
import { useApp, fmtClock, type PageKey } from "@/store";
import { IconButton, ModalHostContext, Snackbar } from "@/components/ui";
import { NAV_ITEMS, PAGE_TITLES } from "@/nav";
import { Dashboard } from "@/pages/Dashboard";
import { Nodes } from "@/pages/Nodes";
import { Subscriptions } from "@/pages/Subscriptions";
import { Settings } from "@/pages/Settings";
import { ImportSubModal } from "@/components/ImportSubModal";
import { cn } from "@/utils/cn";

const SCREEN_W = 375;
const SCREEN_H = 780;
const BEZEL = 12;

function usePhoneScale() {
  const [w, setW] = useState(() => (typeof window === "undefined" ? 1440 : window.innerWidth));
  useEffect(() => {
    const on = () => setW(window.innerWidth);
    window.addEventListener("resize", on);
    return () => window.removeEventListener("resize", on);
  }, []);
  if (w < 480) return 0.78;
  if (w < 1100) return 0.9;
  return 1;
}

/* ---------- status bar glyphs ---------- */
function SignalBars() {
  return (
    <svg width="17" height="11" viewBox="0 0 17 11" fill="currentColor" aria-hidden>
      {[0, 1, 2, 3].map((i) => (
        <rect key={i} x={i * 4.3} y={8 - i * 2.4} width="3" height={3 + i * 2.4} rx="1" opacity={i === 3 ? 0.35 : 1} />
      ))}
    </svg>
  );
}

function Wifi() {
  return (
    <svg width="16" height="11" viewBox="0 0 16 11" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" aria-hidden>
      <path d="M1.5 3.6a10 10 0 0 1 13 0" />
      <path d="M4 6.3a6.4 6.4 0 0 1 8 0" />
      <path d="M6.7 8.9a2.6 2.6 0 0 1 2.6 0" />
    </svg>
  );
}

function Battery() {
  return (
    <svg width="25" height="12" viewBox="0 0 25 12" fill="none" aria-hidden>
      <rect x="0.5" y="0.5" width="21" height="11" rx="3.2" stroke="currentColor" opacity="0.4" />
      <rect x="2" y="2" width="15" height="8" rx="2" fill="currentColor" />
      <path d="M23.5 4v4a2.2 2.2 0 0 0 0-4z" fill="currentColor" opacity="0.4" />
    </svg>
  );
}

/* ------------------------------------------------------------------ */
export function MobileApp() {
  const { clock, toast, dismissToast, testing, testNodes, refreshAllSubs } = useApp();
  const [page, setPage] = useState<PageKey>("dashboard");
  const [scrollY, setScrollY] = useState(0);
  const [importOpen, setImportOpen] = useState(false);
  const [host, setHost] = useState<HTMLDivElement | null>(null);
  const scale = usePhoneScale();

  const go = (p: PageKey) => {
    setPage(p);
    setScrollY(0);
  };
  const scrolled = scrollY > 4;
  const collapsed = scrollY > 44;
  const outerW = SCREEN_W + BEZEL * 2;
  const outerH = SCREEN_H + BEZEL * 2;

  return (
    <div className="relative shrink-0" style={{ width: outerW * scale, height: outerH * scale }}>
      <div className="absolute top-0 left-0 origin-top-left" style={{ transform: `scale(${scale})` }}>
        {/* device */}
        <div className="relative rounded-[54px] bg-[#0b0c10] shadow-phone ring-1 ring-white/10" style={{ padding: BEZEL }}>
          <span className="absolute top-[150px] -left-[3px] h-8 w-[4px] rounded-l bg-[#24262e]" />
          <span className="absolute top-[198px] -left-[3px] h-14 w-[4px] rounded-l bg-[#24262e]" />
          <span className="absolute top-[176px] -right-[3px] h-16 w-[4px] rounded-r bg-[#24262e]" />

          {/* screen */}
          <div
            ref={setHost}
            className="relative flex flex-col overflow-hidden rounded-[42px] bg-canvas"
            style={{ width: SCREEN_W, height: SCREEN_H }}
          >
            <ModalHostContext.Provider value={host}>
              {/* status bar + top app bar share one container color (MD3 on-scroll elevation) */}
              <div
                className={cn(
                  "relative z-20 shrink-0 transition-colors duration-300",
                  scrolled ? "bg-frame" : "bg-canvas",
                )}
              >
                <div className="relative flex h-11 items-center justify-between px-7 text-[14px] font-semibold">
                  <span className="tabular-nums">{fmtClock(clock)}</span>
                  <span className="absolute top-[10px] left-1/2 h-[26px] w-[94px] -translate-x-1/2 rounded-full bg-black" />
                  <span className="flex items-center gap-1.5">
                    <SignalBars />
                    <Wifi />
                    <Battery />
                  </span>
                </div>
                <div className="flex h-14 items-center pr-2 pl-5">
                  <h2
                    className={cn(
                      "text-[19px] font-medium transition-all duration-300 ease-emph",
                      collapsed ? "translate-y-0 opacity-100" : "translate-y-2 opacity-0",
                    )}
                  >
                    {PAGE_TITLES[page]}
                  </h2>
                  <div className="ml-auto flex items-center">
                    {page === "nodes" && (
                      <IconButton label="测试延迟" onClick={testNodes} className="h-11 w-11">
                        <RefreshCw size={20} className={cn(testing && "animate-spin")} />
                      </IconButton>
                    )}
                    {page === "subs" && (
                      <IconButton label="更新全部订阅" onClick={refreshAllSubs} className="h-11 w-11">
                        <RefreshCw size={20} />
                      </IconButton>
                    )}
                  </div>
                </div>
              </div>

              {/* content — large title scrolls away, small title fades in */}
              <main
                key={page}
                onScroll={(e) => setScrollY(e.currentTarget.scrollTop)}
                className="animate-page no-sb min-h-0 flex-1 overflow-y-auto px-4 pb-[124px]"
              >
                <h1 className="px-1 pb-5 text-[32px] leading-tight font-medium tracking-tight">{PAGE_TITLES[page]}</h1>
                {page === "dashboard" && <Dashboard platform="mobile" onNavigate={go} />}
                {page === "nodes" && <Nodes platform="mobile" />}
                {page === "subs" && <Subscriptions platform="mobile" />}
                {page === "settings" && <Settings platform="mobile" />}
              </main>

              {/* MD3 extended FAB — shrinks while scrolling, moves up for snackbars */}
              {page === "subs" && (
                <button
                  type="button"
                  onClick={() => setImportOpen(true)}
                  aria-label="导入订阅"
                  className={cn(
                    "absolute right-4 z-20 flex h-14 items-center overflow-hidden rounded-[16px] bg-pcontainer text-onpcontainer shadow-float transition-all duration-300 ease-emph",
                    scrollY > 24 ? "w-14" : "w-[136px]",
                    toast ? "bottom-[166px]" : "bottom-[100px]",
                  )}
                >
                  <span className="grid h-14 w-14 shrink-0 place-items-center">
                    <Plus size={24} />
                  </span>
                  <span
                    className={cn(
                      "pr-5 text-[14.5px] font-medium whitespace-nowrap transition-opacity duration-200",
                      scrollY > 24 ? "opacity-0" : "opacity-100",
                    )}
                  >
                    导入订阅
                  </span>
                </button>
              )}

              {/* MD3 navigation bar */}
              <nav className="absolute inset-x-0 bottom-0 z-20 flex h-[86px] justify-around bg-frame px-2 pt-3">
                {NAV_ITEMS.map(({ key, label, icon: Icon }) => {
                  const active = page === key;
                  return (
                    <button
                      key={key}
                      type="button"
                      onClick={() => go(key)}
                      aria-current={active ? "page" : undefined}
                      data-ripple-in=".nav-ind"
                      className="flex w-[76px] flex-col items-center gap-1"
                    >
                      <span className="nav-ind relative grid h-8 w-16 place-items-center overflow-hidden rounded-full">
                        <span
                          className={cn(
                            "absolute inset-0 rounded-full bg-scontainer transition-all duration-300 ease-emph",
                            active ? "scale-x-100 opacity-100" : "scale-x-[0.4] opacity-0",
                          )}
                        />
                        <Icon
                          size={21}
                          strokeWidth={active ? 2.3 : 1.9}
                          className={cn("relative transition-colors", active ? "text-onscontainer" : "text-ink2")}
                        />
                      </span>
                      <span className={cn("text-[12px] transition-colors", active ? "font-semibold text-ink" : "font-medium text-ink2")}>
                        {label}
                      </span>
                    </button>
                  );
                })}
              </nav>

              <span className="pointer-events-none absolute bottom-[7px] left-1/2 z-30 h-[5px] w-[120px] -translate-x-1/2 rounded-full bg-ink/30" />

              {toast && (
                <Snackbar
                  key={toast.id}
                  toast={toast}
                  className="bottom-[100px]"
                  onAction={() => {
                    toast.action?.run();
                    dismissToast();
                  }}
                />
              )}

              <ImportSubModal open={importOpen} onClose={() => setImportOpen(false)} platform="mobile" />
            </ModalHostContext.Provider>
          </div>
        </div>
      </div>
    </div>
  );
}
