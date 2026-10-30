import type { ReactNode } from "react";
import { Activity, ArrowDown, ArrowUp, ChevronRight, Globe2, Route, Timer } from "lucide-react";
import { useApp, fmtSpeed, fmtGB, fmtUptime, type PageKey } from "@/store";
import type { ProxyMode } from "@/data";
import { Card, PowerButton, ProgressBar, Segmented, Sparkline, StatusPill, type Platform } from "@/components/ui";
import { cn } from "@/utils/cn";

const MODE_OPTIONS: { value: ProxyMode; label: string }[] = [
  { value: "rule", label: "规则" },
  { value: "global", label: "全局" },
  { value: "direct", label: "直连" },
];

function Meta({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <div className="text-[12px] text-ink3">{label}</div>
      <div className="mt-1 truncate text-[14px] font-medium tabular-nums">{value}</div>
    </div>
  );
}

function SpeedCard({
  label,
  icon,
  kb,
  data,
  tone,
  footer,
  compact,
}: {
  label: string;
  icon: ReactNode;
  kb: number;
  data: number[];
  tone: "primary" | "ok";
  footer: ReactNode;
  compact?: boolean;
}) {
  const { value, unit } = fmtSpeed(kb);
  return (
    <Card className={compact ? "p-4" : "p-5"}>
      <div className="flex items-center gap-2.5 text-[13px] font-medium text-ink2">
        <span
          className={cn(
            "grid h-7 w-7 place-items-center rounded-full",
            tone === "primary" ? "bg-pcontainer text-onpcontainer" : "bg-ok/15 text-ok",
          )}
        >
          {icon}
        </span>
        {label}
      </div>
      <div className="mt-3 flex items-baseline gap-1.5">
        <span className={cn("leading-none font-medium tabular-nums", compact ? "text-[24px]" : "text-[30px]")}>{value}</span>
        <span className="text-[12px] text-ink3">{unit}</span>
      </div>
      <div className="mt-3">
        <Sparkline data={data} tone={tone} height={compact ? 32 : 40} />
      </div>
      <div className="mt-2 truncate text-[12px] text-ink3">{footer}</div>
    </Card>
  );
}

function QuotaCard({ onClick, className }: { onClick: () => void; className?: string }) {
  const { activeSub } = useApp();
  const ratio = activeSub.total ? activeSub.used / activeSub.total : 0;
  const left = Math.max(0, activeSub.total - activeSub.used);
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex flex-col rounded-[24px] bg-surface p-5 text-left shadow-card transition-shadow duration-300 hover:shadow-float",
        className,
      )}
    >
      <span className="text-[13px] font-medium text-ink2">订阅流量</span>
      <span className="mt-3 flex items-baseline gap-1.5">
        <span className="text-[30px] leading-none font-medium tabular-nums">{activeSub.used.toFixed(1)}</span>
        <span className="text-[12px] text-ink3">/ {activeSub.total} GB</span>
      </span>
      <span className="mt-auto block w-full pt-6">
        <ProgressBar value={ratio} tone={ratio > 0.75 ? "warn" : "primary"} />
      </span>
      <span className="mt-3 block truncate text-[12px] text-ink3">
        剩余 <span className="font-medium text-ink2 tabular-nums">{left.toFixed(1)} GB</span> · {activeSub.name}
      </span>
    </button>
  );
}

/* ------------------------------------------------------------------ */
function DesktopDashboard({ onNavigate }: { onNavigate: (p: PageKey) => void }) {
  const { running, toggleRunning, uptime, speed, hist, traffic, currentNode, activeSub, settings, set } = useApp();
  const scope = settings.statsScope === "total" ? "累计" : "本次";

  return (
    <div className="space-y-4">
      <Card className="p-7">
        <div className="flex items-center gap-6">
          <div className="min-w-0 flex-1">
            <StatusPill running={running} />
            <h2 className="mt-4 text-[34px] leading-tight font-medium tracking-tight">{running ? "已连接" : "未连接"}</h2>
            <p className="mt-1.5 flex items-center gap-2 text-[14px] text-ink2">
              <Globe2 size={15} className="text-ink3" />
              {currentNode.name} · {currentNode.proto}
            </p>
            <div className="mt-6 grid max-w-[440px] grid-cols-3 gap-6">
              <Meta label="运行时长" value={running ? fmtUptime(uptime) : "--:--:--"} />
              <Meta label="延迟" value={running && currentNode.latency != null ? `${currentNode.latency} ms` : "—"} />
              <Meta label="订阅" value={activeSub.name} />
            </div>
          </div>
          <PowerButton running={running} onToggle={toggleRunning} size={136} />
        </div>
      </Card>

      <div className="grid grid-cols-2 gap-4 @2xl:grid-cols-3">
        <SpeedCard
          label="下载"
          icon={<ArrowDown size={15} />}
          kb={speed.down}
          data={hist.down}
          tone="primary"
          footer={
            <>
              {scope} <span className="font-medium text-ink2 tabular-nums">{fmtGB(traffic.down)}</span>
            </>
          }
        />
        <SpeedCard
          label="上传"
          icon={<ArrowUp size={15} />}
          kb={speed.up}
          data={hist.up}
          tone="ok"
          footer={
            <>
              {scope} <span className="font-medium text-ink2 tabular-nums">{fmtGB(traffic.up)}</span>
            </>
          }
        />
        <QuotaCard onClick={() => onNavigate("subs")} className="col-span-2 @2xl:col-span-1" />
      </div>

      <Card className="flex flex-wrap items-center gap-x-4 gap-y-3 p-3 pl-5">
        <span className="text-[13px] font-medium text-ink2">代理模式</span>
        <Segmented size="sm" value={settings.mode} onChange={(v) => set("mode", v)} options={MODE_OPTIONS} />
        <button
          type="button"
          onClick={() => onNavigate("nodes")}
          className="ml-auto flex h-10 items-center gap-2 rounded-full bg-surf2 pr-3 pl-4 text-[13px] font-medium transition-colors hover:bg-surf3"
        >
          <Route size={15} className="text-ink3" />
          <span className="text-ink2">节点</span>
          <span>{currentNode.name}</span>
          <ChevronRight size={16} className="text-ink3" />
        </button>
      </Card>
    </div>
  );
}

/* ------------------------------------------------------------------ */
function MobileDashboard({ onNavigate }: { onNavigate: (p: PageKey) => void }) {
  const { running, toggleRunning, uptime, speed, hist, traffic, currentNode, settings, set } = useApp();
  const scope = settings.statsScope === "total" ? "累计" : "本次";

  return (
    <div className="space-y-3">
      <Card className="flex flex-col items-center px-5 pt-7 pb-6">
        <PowerButton running={running} onToggle={toggleRunning} size={150} />
        <div className="mt-5 text-[24px] font-medium">{running ? "已连接" : "未连接"}</div>
        <div className="mt-1 text-[13.5px] text-ink2">
          {currentNode.name} · {currentNode.proto}
        </div>
        <div className="mt-4 flex items-center gap-2">
          <span className="inline-flex h-8 items-center gap-1.5 rounded-[10px] bg-surf2 px-3 text-[12.5px] text-ink2">
            <Timer size={14} />
            <span className="font-medium tabular-nums">{running ? fmtUptime(uptime) : "--:--:--"}</span>
          </span>
          <span className="inline-flex h-8 items-center gap-1.5 rounded-[10px] bg-surf2 px-3 text-[12.5px] text-ink2">
            <Activity size={14} />
            <span className="font-medium tabular-nums">
              {running && currentNode.latency != null ? `${currentNode.latency} ms` : "—"}
            </span>
          </span>
        </div>
      </Card>

      <div className="grid grid-cols-2 gap-3">
        <SpeedCard
          compact
          label="下载"
          icon={<ArrowDown size={14} />}
          kb={speed.down}
          data={hist.down}
          tone="primary"
          footer={
            <>
              {scope} <span className="font-medium text-ink2">{fmtGB(traffic.down)}</span>
            </>
          }
        />
        <SpeedCard
          compact
          label="上传"
          icon={<ArrowUp size={14} />}
          kb={speed.up}
          data={hist.up}
          tone="ok"
          footer={
            <>
              {scope} <span className="font-medium text-ink2">{fmtGB(traffic.up)}</span>
            </>
          }
        />
      </div>

      <Card className="p-4">
        <div className="mb-3 px-1 text-[13px] font-medium text-ink2">代理模式</div>
        <Segmented full value={settings.mode} onChange={(v) => set("mode", v)} options={MODE_OPTIONS} />
      </Card>

      <button
        type="button"
        onClick={() => onNavigate("nodes")}
        className="flex w-full items-center gap-3.5 rounded-[24px] bg-surface p-4 text-left shadow-card"
      >
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-[15px] bg-pcontainer text-onpcontainer">
          <Route size={18} />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-[14.5px] font-medium">当前节点</span>
          <span className="mt-0.5 block truncate text-[12.5px] text-ink2">
            {currentNode.name} · {currentNode.sub}
          </span>
        </span>
        <ChevronRight size={18} className="text-ink3" />
      </button>
    </div>
  );
}

export function Dashboard({ platform, onNavigate }: { platform: Platform; onNavigate: (p: PageKey) => void }) {
  return platform === "pc" ? <DesktopDashboard onNavigate={onNavigate} /> : <MobileDashboard onNavigate={onNavigate} />;
}
