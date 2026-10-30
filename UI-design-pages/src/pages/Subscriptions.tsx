import { useEffect, useRef, useState } from "react";
import { CalendarClock, Copy, MoreVertical, Pencil, RefreshCw, Rss, Trash2, TriangleAlert } from "lucide-react";
import { useApp } from "@/store";
import type { SubInfo } from "@/data";
import { Button, Card, IconButton, ProgressBar, WavyProgress, type Platform } from "@/components/ui";
import { cn } from "@/utils/cn";

function daysLeft(expire: string) {
  const t = new Date(`${expire}T00:00:00`).getTime();
  if (Number.isNaN(t)) return Number.POSITIVE_INFINITY;
  return Math.ceil((t - Date.now()) / 86400000);
}

function SubCard({ sub, platform }: { sub: SubInfo; platform: Platform }) {
  const { activateSub, refreshSub, removeSub, notify } = useApp();
  const [menu, setMenu] = useState(false);
  const [updating, setUpdating] = useState(false);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => () => window.clearTimeout(timer.current), []);

  const mobile = platform === "mobile";
  const ratio = sub.total ? sub.used / sub.total : 0;
  const left = Math.max(0, sub.total - sub.used);
  const low = ratio > 0.75;
  const dLeft = daysLeft(sub.expire);
  const expiring = dLeft <= 30;
  const muted = sub.active ? "text-onpcontainer/75" : "text-ink3";

  const update = () => {
    if (updating) return;
    setUpdating(true);
    timer.current = window.setTimeout(() => {
      setUpdating(false);
      refreshSub(sub.id);
    }, 1300);
  };

  const menuItems = [
    {
      icon: <Copy size={17} />,
      label: "复制链接",
      run: () => notify("订阅链接已复制"),
    },
    {
      icon: <Pencil size={17} />,
      label: "编辑",
      run: () => notify("编辑订阅暂未开放"),
    },
    {
      icon: <Trash2 size={17} />,
      label: "删除",
      danger: true,
      run: () => removeSub(sub.id),
    },
  ];

  return (
    <Card className={cn("relative min-w-0 transition-colors duration-300", mobile ? "p-4" : "p-5", sub.active && "bg-pcontainer")}>
      <div className="flex items-start gap-3.5">
        <span
          className={cn(
            "grid h-11 w-11 shrink-0 place-items-center rounded-[15px] text-[16px] font-semibold transition-colors duration-300",
            sub.active ? "bg-primary text-onprimary" : "bg-surf2 text-ink2",
          )}
        >
          {sub.name.slice(0, 1)}
        </span>
        <div className="min-w-0 flex-1 pt-0.5">
          <div className="flex items-center gap-2">
            <h3 className={cn("truncate text-[15.5px] font-semibold", sub.active && "text-onpcontainer")}>{sub.name}</h3>
            {sub.active && (
              <span className="shrink-0 rounded-full bg-primary px-2 py-0.5 text-[11px] font-semibold text-onprimary">
                使用中
              </span>
            )}
          </div>
          <p className={cn("mt-0.5 truncate text-[12.5px]", muted)}>{sub.url}</p>
        </div>

        <div className="relative -mt-1 -mr-1">
          <IconButton label="更多操作" onClick={() => setMenu((m) => !m)} active={menu}>
            <MoreVertical size={19} />
          </IconButton>
          {menu && (
            <>
              <button
                type="button"
                data-noripple
                aria-label="关闭菜单"
                className="fixed inset-0 z-30 cursor-default"
                onClick={() => setMenu(false)}
              />
              <div className="animate-pop absolute top-full right-0 z-40 mt-1 w-[176px] origin-top-right rounded-[16px] bg-dialog py-2 shadow-float">
                {menuItems.map((m) => (
                  <button
                    key={m.label}
                    type="button"
                    onClick={() => {
                      setMenu(false);
                      m.run();
                    }}
                    className={cn(
                      "flex h-11 w-full items-center gap-3 px-4 text-left text-[14px] transition-colors hover:bg-ink/[0.06]",
                      m.danger ? "text-err" : "text-ink",
                    )}
                  >
                    <span className={m.danger ? "text-err" : "text-ink2"}>{m.icon}</span>
                    {m.label}
                  </button>
                ))}
              </div>
            </>
          )}
        </div>
      </div>

      <div className="mt-4">
        <div className="mb-2.5 flex items-baseline justify-between text-[12.5px]">
          <span className={sub.active ? "text-onpcontainer/85" : "text-ink2"}>
            已用 <span className="font-semibold tabular-nums">{sub.used.toFixed(1)}</span> / {sub.total} GB
          </span>
          <span className={cn("font-semibold tabular-nums", low ? "text-warn" : sub.active ? "text-onpcontainer" : "text-ink2")}>
            剩余 {left.toFixed(1)} GB
          </span>
        </div>
        <div className="flex h-2.5 items-center">
          {updating ? <WavyProgress /> : <ProgressBar value={ratio} tone={low ? "warn" : "primary"} />}
        </div>
      </div>

      <div className="mt-3.5 flex items-center gap-1.5">
        <div className={cn("flex min-w-0 flex-1 flex-wrap items-center gap-x-4 gap-y-1 text-[12px]", muted)}>
          <span className={cn("flex items-center gap-1.5", expiring && "font-medium text-warn")}>
            {expiring ? <TriangleAlert size={13} /> : <CalendarClock size={13} />}
            {expiring ? (dLeft > 0 ? `${dLeft} 天后到期` : "已到期") : `到期 ${sub.expire}`}
          </span>
          <span className="flex items-center gap-1.5">
            <RefreshCw size={13} />
            {updating ? "正在更新…" : `${sub.updated}更新`}
          </span>
        </div>
        <IconButton label="更新订阅" onClick={update}>
          <RefreshCw size={18} className={cn(updating && "animate-spin")} />
        </IconButton>
        {!sub.active && (
          <Button size="sm" variant="tonal" onClick={() => activateSub(sub.id)}>
            切换
          </Button>
        )}
      </div>
    </Card>
  );
}

export function Subscriptions({ platform }: { platform: Platform }) {
  const { subs } = useApp();

  if (subs.length === 0) {
    return (
      <Card className="flex flex-col items-center gap-3 px-6 py-14 text-center text-ink3">
        <span className="grid h-14 w-14 place-items-center rounded-[18px] bg-surf2 text-ink2">
          <Rss size={24} />
        </span>
        <span className="text-[14.5px] font-medium text-ink">暂无订阅</span>
        <span className="text-[12.5px]">{platform === "pc" ? "点击右上角「导入订阅」添加" : "点击右下角按钮导入订阅"}</span>
      </Card>
    );
  }

  return (
    <div className={cn("grid grid-cols-1", platform === "pc" ? "gap-4 @3xl:grid-cols-2" : "gap-3")}>
      {subs.map((s) => (
        <SubCard key={s.id} sub={s} platform={platform} />
      ))}
    </div>
  );
}
