import { Gauge, Rss, Server, Settings, type LucideIcon } from "lucide-react";
import type { PageKey } from "./store";

export const NAV_ITEMS: { key: PageKey; label: string; icon: LucideIcon }[] = [
  { key: "dashboard", label: "仪表盘", icon: Gauge },
  { key: "nodes", label: "节点", icon: Server },
  { key: "subs", label: "订阅", icon: Rss },
  { key: "settings", label: "设置", icon: Settings },
];

export const PAGE_TITLES: Record<PageKey, string> = {
  dashboard: "仪表盘",
  nodes: "节点",
  subs: "订阅",
  settings: "设置",
};
