import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  ACCENTS,
  DEFAULT_SETTINGS,
  INITIAL_NODES,
  INITIAL_SUBS,
  type AppSettings,
  type NodeInfo,
  type SubInfo,
} from "./data";

export type PageKey = "dashboard" | "nodes" | "subs" | "settings";

export interface ToastData {
  id: number;
  msg: string;
  action?: { label: string; run: () => void };
}

const HIST_LEN = 48;
/** traffic accumulated before this session (used when stats scope = total) */
const HISTORY_BASE = { up: 28.64, down: 173.25 };

/** placeholder so views never crash when every subscription was removed */
const EMPTY_SUB: SubInfo = {
  id: "none",
  name: "未导入订阅",
  url: "",
  used: 0,
  total: 0,
  expire: "—",
  updated: "—",
  active: true,
};

interface AppValue {
  running: boolean;
  toggleRunning: () => void;
  uptime: number;
  speed: { up: number; down: number };
  hist: { down: number[]; up: number[] };
  /** traffic as displayed — depends on the statistics scope setting */
  traffic: { up: number; down: number };
  clock: Date;
  nodes: NodeInfo[];
  selectedNodeId: string;
  currentNode: NodeInfo;
  selectNode: (id: string) => void;
  testing: boolean;
  testNodes: () => void;
  subs: SubInfo[];
  activeSub: SubInfo;
  activateSub: (id: string) => void;
  importSub: (name: string, url: string) => void;
  removeSub: (id: string) => void;
  refreshSub: (id: string) => void;
  refreshAllSubs: () => void;
  settings: AppSettings;
  set: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  resolvedTheme: "light" | "dark";
  toggleTheme: () => void;
  toast: ToastData | null;
  notify: (msg: string, action?: ToastData["action"]) => void;
  dismissToast: () => void;
}

const AppCtx = createContext<AppValue | null>(null);

export function AppProvider({ children }: { children: ReactNode }) {
  const [running, setRunning] = useState(true);
  const [uptime, setUptime] = useState(2 * 3600 + 14 * 60 + 33);
  const [speed, setSpeed] = useState({ up: 0, down: 0 });
  const [hist, setHist] = useState<{ down: number[]; up: number[] }>(() => ({
    down: Array.from({ length: HIST_LEN }, (_, i) => 1800 + Math.sin(i / 4) * 900 + Math.random() * 400),
    up: Array.from({ length: HIST_LEN }, (_, i) => 220 + Math.sin(i / 3) * 90 + Math.random() * 60),
  }));
  const [session, setSession] = useState({ up: 1.24, down: 12.87 });
  const [clock, setClock] = useState(() => new Date());

  const [nodes, setNodes] = useState<NodeInfo[]>(INITIAL_NODES);
  const [selectedNodeId, setSelectedNodeId] = useState("hk-01");
  const [testing, setTesting] = useState(false);

  const [subs, setSubs] = useState<SubInfo[]>(INITIAL_SUBS);
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);
  const [systemDark, setSystemDark] = useState(
    () => typeof window !== "undefined" && !!window.matchMedia?.("(prefers-color-scheme: dark)").matches,
  );

  const [toast, setToast] = useState<ToastData | null>(null);
  const toastTimer = useRef<number | undefined>(undefined);
  const speedRef = useRef({ up: 0, down: 0 });

  const notify = useCallback((msg: string, action?: ToastData["action"]) => {
    setToast({ id: Date.now() + Math.random(), msg, action });
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), action ? 4500 : 2400);
  }, []);

  const dismissToast = useCallback(() => {
    window.clearTimeout(toastTimer.current);
    setToast(null);
  }, []);

  /* ---------- theme & dynamic color ---------- */
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = (e: MediaQueryListEvent) => setSystemDark(e.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, []);

  const resolvedTheme: "light" | "dark" =
    settings.theme === "system" ? (systemDark ? "dark" : "light") : settings.theme;

  useEffect(() => {
    document.documentElement.dataset.theme = resolvedTheme;
  }, [resolvedTheme]);

  useEffect(() => {
    const { h, k } = ACCENTS[settings.accent];
    const root = document.documentElement;
    root.style.setProperty("--h", String(h));
    root.style.setProperty("--k", String(k));
  }, [settings.accent]);

  const toggleTheme = useCallback(() => {
    setSettings((s) => ({ ...s, theme: resolvedTheme === "dark" ? "light" : "dark" }));
  }, [resolvedTheme]);

  /* ---------- traffic simulation ---------- */
  useEffect(() => {
    const id = window.setInterval(() => {
      setClock(new Date());
      if (!running) {
        speedRef.current = { up: 0, down: 0 };
        setSpeed({ up: 0, down: 0 });
        setHist((h) => ({ down: [...h.down.slice(1), 0], up: [...h.up.slice(1), 0] }));
        return;
      }
      setUptime((u) => u + 1);
      const t = Date.now() / 1000;
      const targetDown = Math.max(60, 1750 + 2050 * Math.sin(t / 6) + Math.random() * 850);
      const targetUp = Math.max(24, 190 + 380 * Math.sin(t / 4 + 1.2) + Math.random() * 140);
      const next = {
        down: speedRef.current.down + (targetDown - speedRef.current.down) * 0.32,
        up: speedRef.current.up + (targetUp - speedRef.current.up) * 0.32,
      };
      speedRef.current = next;
      setSpeed(next);
      setHist((h) => ({
        down: [...h.down.slice(-HIST_LEN + 1), next.down],
        up: [...h.up.slice(-HIST_LEN + 1), next.up],
      }));
      setSession((tr) => ({
        up: tr.up + (next.up * 1024) / 1e9,
        down: tr.down + (next.down * 1024) / 1e9,
      }));
    }, 1000);
    return () => window.clearInterval(id);
  }, [running]);

  /* ---------- actions ---------- */
  const toggleRunning = useCallback(() => {
    if (!running) setUptime(0);
    setRunning((r) => !r);
    notify(running ? "代理已停止" : "代理已启动");
  }, [running, notify]);

  const selectNode = useCallback(
    (id: string) => {
      setSelectedNodeId(id);
      const n = nodes.find((x) => x.id === id);
      if (!n) return;
      notify(n.id === "auto" ? "已开启自动选择" : `已切换到 ${n.name}`);
    },
    [nodes, notify],
  );

  const testNodes = useCallback(() => {
    if (testing) return;
    setTesting(true);
    setNodes((ns) => ns.map((n) => ({ ...n, latency: null })));
    window.setTimeout(() => {
      setNodes((ns) =>
        ns.map((n) => ({
          ...n,
          latency: n.id === "auto" ? Math.round(12 + Math.random() * 36) : Math.round(6 + Math.random() * 210),
        })),
      );
      setTesting(false);
      notify("延迟测试完成");
    }, 1400);
  }, [testing, notify]);

  const activateSub = useCallback(
    (id: string) => {
      setSubs((ss) => ss.map((s) => ({ ...s, active: s.id === id })));
      const s = subs.find((x) => x.id === id);
      notify(`已切换到「${s?.name ?? "订阅"}」`);
    },
    [subs, notify],
  );

  const importSub = useCallback(
    (name: string, url: string) => {
      setSubs((ss) => [
        ...ss,
        {
          id: `s${Date.now()}`,
          name,
          url,
          used: 0,
          total: 100,
          expire: "2027-12-31",
          updated: "刚刚",
          active: !ss.some((x) => x.active),
        },
      ]);
      notify(`已导入「${name}」`);
    },
    [notify],
  );

  const removeSub = useCallback(
    (id: string) => {
      const snapshot = subs;
      const target = subs.find((s) => s.id === id);
      setSubs((ss) => {
        const rest = ss.filter((s) => s.id !== id);
        if (target?.active && rest.length) rest[0] = { ...rest[0], active: true };
        return rest;
      });
      notify(`已删除「${target?.name ?? "订阅"}」`, { label: "撤销", run: () => setSubs(snapshot) });
    },
    [subs, notify],
  );

  const refreshSub = useCallback(
    (id: string) => {
      setSubs((ss) => ss.map((s) => (s.id === id ? { ...s, updated: "刚刚" } : s)));
      notify("订阅已更新");
    },
    [notify],
  );

  const refreshAllSubs = useCallback(() => {
    setSubs((ss) => ss.map((s) => ({ ...s, updated: "刚刚" })));
    notify("全部订阅已更新");
  }, [notify]);

  const set = useCallback(<K extends keyof AppSettings>(key: K, value: AppSettings[K]) => {
    setSettings((s) => ({ ...s, [key]: value }));
  }, []);

  const currentNode = useMemo(
    () => nodes.find((n) => n.id === selectedNodeId) ?? nodes[0],
    [nodes, selectedNodeId],
  );
  const activeSub = useMemo(() => subs.find((s) => s.active) ?? subs[0] ?? EMPTY_SUB, [subs]);

  const traffic = useMemo(
    () =>
      settings.statsScope === "total"
        ? { up: session.up + HISTORY_BASE.up, down: session.down + HISTORY_BASE.down }
        : session,
    [session, settings.statsScope],
  );

  const value: AppValue = {
    running,
    toggleRunning,
    uptime,
    speed,
    hist,
    traffic,
    clock,
    nodes,
    selectedNodeId,
    currentNode,
    selectNode,
    testing,
    testNodes,
    subs,
    activeSub,
    activateSub,
    importSub,
    removeSub,
    refreshSub,
    refreshAllSubs,
    settings,
    set,
    resolvedTheme,
    toggleTheme,
    toast,
    notify,
    dismissToast,
  };

  return <AppCtx.Provider value={value}>{children}</AppCtx.Provider>;
}

export function useApp() {
  const ctx = useContext(AppCtx);
  if (!ctx) throw new Error("useApp must be used inside <AppProvider>");
  return ctx;
}

/* ---------- formatters ---------- */
export function fmtSpeed(kb: number): { value: string; unit: string } {
  if (kb >= 1024) return { value: (kb / 1024).toFixed(2), unit: "MB/s" };
  return { value: kb.toFixed(0), unit: "KB/s" };
}

export function fmtGB(gb: number): string {
  if (gb >= 1024) return `${(gb / 1024).toFixed(2)} TB`;
  return `${gb.toFixed(2)} GB`;
}

export function fmtUptime(sec: number): string {
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  return [h, m, s].map((v) => String(v).padStart(2, "0")).join(":");
}

export function fmtClock(d: Date): string {
  return [d.getHours(), d.getMinutes()].map((v) => String(v).padStart(2, "0")).join(":");
}
