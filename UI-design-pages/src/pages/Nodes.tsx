import { useMemo, useState } from "react";
import { Building2, House, Search, X, Zap } from "lucide-react";
import { useApp } from "@/store";
import type { NodeInfo } from "@/data";
import { Card, Chip, LatencyBadge, SectionLabel, WavyProgress, type Platform } from "@/components/ui";
import { cn } from "@/utils/cn";

const ALL = "全部";

function SearchBar({
  value,
  onChange,
  className,
}: {
  value: string;
  onChange: (v: string) => void;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex h-12 items-center gap-3 rounded-full bg-surf2 pr-1.5 pl-4 transition-shadow duration-200 focus-within:shadow-[inset_0_0_0_2px_var(--c-primary)]",
        className,
      )}
    >
      <Search size={18} className="shrink-0 text-ink2" />
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="搜索节点或协议"
        className="h-full min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-ink3"
      />
      {value && (
        <button
          type="button"
          onClick={() => onChange("")}
          aria-label="清除"
          className="grid h-9 w-9 place-items-center rounded-full text-ink2 hover:bg-ink/[0.07]"
        >
          <X size={16} />
        </button>
      )}
    </div>
  );
}

function NodeAvatar({ node, selected }: { node: NodeInfo; selected: boolean }) {
  const special =
    node.id === "auto" ? <Zap size={17} /> : node.id === "home" ? <House size={17} /> : node.id === "office" ? <Building2 size={17} /> : null;
  return (
    <span
      className={cn(
        "grid h-10 w-10 shrink-0 place-items-center rounded-[14px] text-[12px] font-bold tracking-wide transition-colors duration-300",
        selected ? "bg-primary text-onprimary" : "bg-surf2 text-ink2",
      )}
    >
      {special ?? node.region}
    </span>
  );
}

function NodeRow({
  node,
  selected,
  testing,
  onSelect,
}: {
  node: NodeInfo;
  selected: boolean;
  testing: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onSelect}
      aria-pressed={selected}
      className={cn(
        "flex w-full items-center gap-3.5 rounded-[18px] px-3 py-2.5 text-left transition-colors duration-300",
        selected ? "bg-pcontainer" : "hover:bg-ink/[0.045]",
      )}
    >
      <NodeAvatar node={node} selected={selected} />
      <span className="min-w-0 flex-1">
        <span className={cn("block truncate text-[14.5px] font-medium", selected && "text-onpcontainer")}>{node.name}</span>
        <span className={cn("mt-0.5 block truncate text-[12.5px]", selected ? "text-onpcontainer/75" : "text-ink2")}>
          {node.proto}
        </span>
      </span>
      <LatencyBadge ms={node.latency} testing={testing} />
    </button>
  );
}

export function Nodes({ platform }: { platform: Platform }) {
  const { nodes, selectedNodeId, selectNode, testing } = useApp();
  const [q, setQ] = useState("");
  const [group, setGroup] = useState(ALL);
  const mobile = platform === "mobile";

  const allGroups = useMemo(() => Array.from(new Set(nodes.map((n) => n.sub))), [nodes]);

  const groups = useMemo(() => {
    const kw = q.trim().toLowerCase();
    const map = new Map<string, NodeInfo[]>();
    for (const n of nodes) {
      if (group !== ALL && n.sub !== group) continue;
      if (kw && !n.name.toLowerCase().includes(kw) && !n.proto.toLowerCase().includes(kw)) continue;
      const arr = map.get(n.sub) ?? [];
      arr.push(n);
      map.set(n.sub, arr);
    }
    return [...map.entries()];
  }, [nodes, q, group]);

  return (
    <div className="space-y-5">
      <div className={cn("flex gap-3", mobile ? "flex-col" : "flex-wrap items-center")}>
        <SearchBar value={q} onChange={setQ} className={mobile ? "w-full" : "w-[300px]"} />
        <div className={cn("flex gap-2", mobile ? "no-sb -mx-4 overflow-x-auto px-4" : "flex-wrap")}>
          {[ALL, ...allGroups].map((g) => (
            <Chip key={g} selected={group === g} onClick={() => setGroup(g)}>
              {g}
            </Chip>
          ))}
        </div>
      </div>

      {testing && <WavyProgress />}

      {groups.length === 0 && (
        <Card className="flex flex-col items-center gap-3 py-14 text-ink3">
          <Search size={26} />
          <span className="text-[13.5px]">没有找到匹配的节点</span>
        </Card>
      )}

      {groups.map(([sub, list]) => (
        <section key={sub}>
          <SectionLabel className="flex items-center justify-between">
            <span>{sub}</span>
            <span className="text-[12px] font-medium text-ink3">{list.length} 个节点</span>
          </SectionLabel>
          <Card
            className={cn(
              "grid grid-cols-1 gap-0.5 p-1.5",
              !mobile && "@3xl:grid-cols-2 @3xl:[&>:only-child]:col-span-2",
            )}
          >
            {list.map((n) => (
              <NodeRow
                key={n.id}
                node={n}
                selected={n.id === selectedNodeId}
                testing={testing}
                onSelect={() => selectNode(n.id)}
              />
            ))}
          </Card>
        </section>
      ))}
    </div>
  );
}
