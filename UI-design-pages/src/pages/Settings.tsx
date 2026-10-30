import { useState, type ReactNode } from "react";
import {
  Archive,
  BarChart3,
  Check,
  Download,
  EyeOff,
  Info,
  Keyboard,
  Languages,
  LogOut,
  Network,
  Palette,
  Power,
  RefreshCw,
  SlidersHorizontal,
  Upload,
  Zap,
} from "lucide-react";
import { useApp } from "@/store";
import {
  ACCENTS,
  ACCENT_KEYS,
  APP_VERSION,
  BUILD_DATE,
  CORE_VERSION,
  LANGUAGE_LABEL,
  LOG_LEVELS,
  SHORTCUTS,
  STACKS,
  THEME_LABEL,
  swatchBackground,
  type AppSettings,
} from "@/data";
import {
  AppMark,
  Button,
  Card,
  Field,
  Kbd,
  Modal,
  RadioList,
  Row,
  SectionLabel,
  Segmented,
  Spinner,
  Switch,
  WavyProgress,
  type Platform,
} from "@/components/ui";
import { cn } from "@/utils/cn";

type PanelKey = "language" | "theme" | "backup" | "shortcuts" | "basic" | "advanced" | "close" | "stats" | "about";

/* ------------------------------------------------------------------ */
function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mb-5 break-inside-avoid">
      <SectionLabel>{title}</SectionLabel>
      <Card className="p-1.5">{children}</Card>
    </section>
  );
}

function ToggleRow({
  icon,
  title,
  summary,
  checked,
  onChange,
}: {
  icon: ReactNode;
  title: string;
  summary: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <Row
      icon={icon}
      title={title}
      subtitle={summary}
      onClick={() => onChange(!checked)}
      trailing={<Switch checked={checked} onChange={onChange} label={title} />}
    />
  );
}

/** list item rendered as a tonal tile inside dialogs */
function TileToggle({
  title,
  summary,
  checked,
  onChange,
}: {
  title: string;
  summary: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <Row
      className="bg-tile px-4 hover:bg-tile"
      title={title}
      subtitle={summary}
      onClick={() => onChange(!checked)}
      trailing={<Switch checked={checked} onChange={onChange} label={title} />}
    />
  );
}

function PanelLabel({ children }: { children: ReactNode }) {
  return <div className="mb-2 px-1 text-[13px] font-semibold text-primary">{children}</div>;
}

/* ------------------------------------------------------------------ */
export function Settings({ platform }: { platform: Platform }) {
  const { settings, set, notify } = useApp();
  const [panel, setPanel] = useState<PanelKey | null>(null);
  const [checking, setChecking] = useState(false);
  const pc = platform === "pc";

  const checkUpdate = () => {
    if (checking) return;
    setChecking(true);
    window.setTimeout(() => {
      setChecking(false);
      notify(`已是最新版本 ${APP_VERSION}`);
    }, 1600);
  };

  const closeLabel = pc
    ? settings.closeBehavior === "tray"
      ? "最小化到系统托盘"
      : "退出程序"
    : settings.closeBehavior === "tray"
      ? "保留后台运行"
      : "退出应用";

  const general = (
    <Group title="通用">
      <Row
        icon={<Languages size={19} />}
        title="语言"
        subtitle={LANGUAGE_LABEL[settings.language]}
        onClick={() => setPanel("language")}
      />
      <Row
        icon={<Palette size={19} />}
        title="主题"
        subtitle={`${THEME_LABEL[settings.theme]} · ${ACCENTS[settings.accent].label}`}
        onClick={() => setPanel("theme")}
      />
    </Group>
  );

  const shortcuts = pc ? (
    <Group title="快捷键">
      <Row
        icon={<Keyboard size={19} />}
        title="键盘快捷键"
        subtitle={`${SHORTCUTS.length} 个全局快捷键`}
        onClick={() => setPanel("shortcuts")}
      />
    </Group>
  ) : null;

  const proxy = (
    <Group title="代理">
      <Row
        icon={<Network size={19} />}
        title="基本配置"
        subtitle={`混合端口 ${settings.mixedPort} · 系统代理${settings.systemProxy ? "已开启" : "已关闭"}`}
        onClick={() => setPanel("basic")}
      />
      <Row
        icon={<SlidersHorizontal size={19} />}
        title="进阶配置"
        subtitle={`${settings.tunMode ? "TUN 模式" : "常规模式"} · ${STACKS[settings.stack]} 网络栈`}
        onClick={() => setPanel("advanced")}
      />
    </Group>
  );

  const behavior = (
    <Group title="应用行为">
      <ToggleRow
        icon={<Power size={19} />}
        title="开机自启动"
        summary={pc ? "登录系统后自动运行" : "设备开机后自动运行"}
        checked={settings.autoStart}
        onChange={(v) => set("autoStart", v)}
      />
      <ToggleRow
        icon={<EyeOff size={19} />}
        title="静默启动"
        summary={pc ? "启动时不显示主窗口" : "启动时保持在后台"}
        checked={settings.silentStart}
        onChange={(v) => set("silentStart", v)}
      />
      <ToggleRow
        icon={<Zap size={19} />}
        title="自动开启代理"
        summary="应用启动后立即连接"
        checked={settings.autoConnect}
        onChange={(v) => set("autoConnect", v)}
      />
      <Row
        icon={<LogOut size={19} />}
        title={pc ? "关闭按钮行为" : "返回键行为"}
        subtitle={closeLabel}
        onClick={() => setPanel("close")}
      />
      <Row
        icon={<BarChart3 size={19} />}
        title="统计范围"
        subtitle={settings.statsScope === "total" ? "全部流量" : "本次会话"}
        onClick={() => setPanel("stats")}
      />
    </Group>
  );

  const data = (
    <Group title="数据">
      <Row
        icon={<Archive size={19} />}
        title="备份与恢复"
        subtitle="上次备份 10 月 8 日 21:34"
        onClick={() => setPanel("backup")}
      />
    </Group>
  );

  const about = (
    <Group title="关于">
      <Row
        icon={<Info size={19} />}
        title="版本信息"
        subtitle={`${APP_VERSION} · ${CORE_VERSION}`}
        onClick={() => setPanel("about")}
      />
      <Row
        icon={<RefreshCw size={19} />}
        title="检查更新"
        subtitle={checking ? "正在检查…" : "当前已是最新版本"}
        onClick={checkUpdate}
        trailing={checking ? <Spinner size={22} className="mr-2" /> : undefined}
      />
    </Group>
  );

  return (
    <>
      {pc ? (
        <div className="columns-1 gap-5 @2xl:columns-2">
          {general}
          {shortcuts}
          {proxy}
          {behavior}
          {data}
          {about}
        </div>
      ) : (
        <div>
          {general}
          {proxy}
          {behavior}
          {data}
          {about}
        </div>
      )}
      <SettingsPanels
        panel={panel}
        onClose={() => setPanel(null)}
        platform={platform}
        checking={checking}
        onCheck={checkUpdate}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/* Dialogs / bottom sheets                                             */
/* ------------------------------------------------------------------ */
function SettingsPanels({
  panel,
  onClose,
  platform,
  checking,
  onCheck,
}: {
  panel: PanelKey | null;
  onClose: () => void;
  platform: Platform;
  checking: boolean;
  onCheck: () => void;
}) {
  const { settings, set, notify } = useApp();
  const pc = platform === "pc";

  /** single-choice sheets on mobile dismiss themselves after picking */
  const pick = <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => {
    set(key, value);
    if (!pc) window.setTimeout(onClose, 220);
  };

  return (
    <>
      <Modal open={panel === "language"} onClose={onClose} platform={platform} title="语言" subtitle="选择界面显示语言">
        <RadioList
          value={settings.language}
          onChange={(v) => pick("language", v)}
          options={[
            { value: "zh", label: "简体中文" },
            { value: "en", label: "English" },
            { value: "ja", label: "日本語" },
          ]}
        />
      </Modal>

      <Modal open={panel === "theme"} onClose={onClose} platform={platform} title="主题" subtitle="外观模式与动态配色">
        <div className="space-y-6">
          <RadioList
            value={settings.theme}
            onChange={(v) => set("theme", v)}
            options={[
              { value: "system", label: THEME_LABEL.system, desc: "与系统外观保持一致" },
              { value: "light", label: THEME_LABEL.light },
              { value: "dark", label: THEME_LABEL.dark },
            ]}
          />
          <div>
            <PanelLabel>主题色</PanelLabel>
            <div className="flex justify-between gap-1 px-1 pt-1">
              {ACCENT_KEYS.map((k) => {
                const sel = settings.accent === k;
                return (
                  <button
                    key={k}
                    type="button"
                    data-noripple
                    onClick={() => set("accent", k)}
                    aria-label={ACCENTS[k].label}
                    aria-pressed={sel}
                    className="flex w-14 flex-col items-center gap-2"
                  >
                    <span
                      className={cn(
                        "grid h-12 w-12 place-items-center rounded-full transition-all duration-300 ease-spring",
                        sel ? "scale-100 shadow-card" : "scale-[0.86] hover:scale-95",
                      )}
                      style={{ background: swatchBackground(k) }}
                    >
                      {sel && (
                        <span className="grid h-6 w-6 place-items-center rounded-full bg-white/90 text-neutral-900">
                          <Check size={14} strokeWidth={3} />
                        </span>
                      )}
                    </span>
                    <span className={cn("text-[12px]", sel ? "font-semibold text-ink" : "text-ink2")}>
                      {ACCENTS[k].label}
                    </span>
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      </Modal>

      <Modal
        open={panel === "backup"}
        onClose={onClose}
        platform={platform}
        title="备份与恢复"
        subtitle="备份包含订阅、节点选择与全部设置"
      >
        <div className="space-y-2">
          <Row
            className="bg-tile hover:bg-tile"
            icon={<Upload size={18} />}
            title="导出备份"
            subtitle="保存为 .flvp 文件"
            onClick={() => notify("备份已导出")}
          />
          <Row
            className="bg-tile hover:bg-tile"
            icon={<Download size={18} />}
            title="从文件恢复"
            subtitle="选择备份文件并覆盖当前配置"
            onClick={() => notify("请选择备份文件")}
          />
        </div>
      </Modal>

      <Modal open={panel === "shortcuts"} onClose={onClose} platform={platform} title="键盘快捷键" subtitle="在系统任意位置均可使用">
        <div className="space-y-2">
          {SHORTCUTS.map((s) => (
            <div key={s.desc} className="flex items-center justify-between gap-3 rounded-[16px] bg-tile px-4 py-3">
              <span className="text-[14px] font-medium">{s.desc}</span>
              <span className="flex shrink-0 items-center gap-1">
                {s.keys.map((k) => (
                  <Kbd key={k}>{k}</Kbd>
                ))}
              </span>
            </div>
          ))}
        </div>
      </Modal>

      <Modal open={panel === "basic"} onClose={onClose} platform={platform} title="基本配置" subtitle="代理端口与系统接入方式">
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <Field label="混合端口" value={settings.mixedPort} onChange={(v) => set("mixedPort", v)} placeholder="7890" />
            <Field label="SOCKS 端口" value={settings.socksPort} onChange={(v) => set("socksPort", v)} placeholder="7891" />
          </div>
          <div className="space-y-2">
            <TileToggle
              title="系统代理"
              summary="自动设置系统 HTTP / SOCKS 代理"
              checked={settings.systemProxy}
              onChange={(v) => set("systemProxy", v)}
            />
            <TileToggle
              title="允许局域网连接"
              summary="局域网设备可通过本机代理上网"
              checked={settings.allowLan}
              onChange={(v) => set("allowLan", v)}
            />
            <TileToggle
              title="TUN 模式"
              summary={pc ? "虚拟网卡接管全部流量，需要管理员权限" : "通过 VPN 接口接管全部流量"}
              checked={settings.tunMode}
              onChange={(v) => set("tunMode", v)}
            />
          </div>
        </div>
      </Modal>

      <Modal open={panel === "advanced"} onClose={onClose} platform={platform} title="进阶配置" subtitle="内核高级选项，修改后自动重载">
        <div className="space-y-5">
          <div className="space-y-2">
            <TileToggle
              title="域名嗅探"
              summary="从 TLS / HTTP 流量中识别真实域名"
              checked={settings.sniff}
              onChange={(v) => set("sniff", v)}
            />
            <TileToggle title="IPv6" summary="允许代理 IPv6 流量" checked={settings.ipv6} onChange={(v) => set("ipv6", v)} />
          </div>
          <div>
            <PanelLabel>日志级别</PanelLabel>
            <Segmented
              size="sm"
              full
              value={settings.logLevel}
              onChange={(v) => set("logLevel", v)}
              options={LOG_LEVELS.map((l) => ({ value: l, label: l.toUpperCase() }))}
            />
          </div>
          <div>
            <PanelLabel>网络栈</PanelLabel>
            <RadioList
              value={settings.stack}
              onChange={(v) => set("stack", v)}
              options={Object.entries(STACKS).map(([value, label]) => ({ value, label }))}
            />
          </div>
          <Field label="DNS 服务器" value={settings.dns} onChange={(v) => set("dns", v)} mono />
        </div>
      </Modal>

      <Modal
        open={panel === "close"}
        onClose={onClose}
        platform={platform}
        title={pc ? "关闭按钮行为" : "返回键行为"}
        subtitle={pc ? "点击窗口关闭按钮时" : "在主界面按下返回键时"}
      >
        <RadioList
          value={settings.closeBehavior}
          onChange={(v) => pick("closeBehavior", v)}
          options={
            pc
              ? [
                  { value: "tray", label: "最小化到系统托盘", desc: "窗口关闭后继续在后台运行" },
                  { value: "quit", label: "退出程序", desc: "关闭窗口并结束代理进程" },
                ]
              : [
                  { value: "tray", label: "保留后台运行", desc: "返回桌面，代理保持连接" },
                  { value: "quit", label: "退出应用", desc: "结束应用并断开代理" },
                ]
          }
        />
      </Modal>

      <Modal open={panel === "stats"} onClose={onClose} platform={platform} title="统计范围" subtitle="仪表盘流量统计的计算方式">
        <RadioList
          value={settings.statsScope}
          onChange={(v) => pick("statsScope", v)}
          options={[
            { value: "total", label: "全部流量", desc: "累计所有历史流量" },
            { value: "session", label: "本次会话", desc: "仅统计本次启动后的流量" },
          ]}
        />
      </Modal>

      <Modal
        open={panel === "about"}
        onClose={onClose}
        platform={platform}
        icon={<AppMark size={64} />}
        title="FLVPcore"
        subtitle={`版本 ${APP_VERSION} · ${BUILD_DATE}`}
      >
        <div className="space-y-2">
          <Row
            className="bg-tile px-4"
            title="内核"
            trailing={<span className="text-[13px] text-ink2">{CORE_VERSION}</span>}
          />
          <Row
            className="bg-tile px-4"
            title="平台"
            trailing={<span className="text-[13px] text-ink2">{pc ? "Windows 11 · x64" : "Android 15 · arm64"}</span>}
          />
          <div className="pt-3">
            {checking && <WavyProgress className="mb-4" />}
            <Button
              className="w-full"
              onClick={onCheck}
              disabled={checking}
              icon={<RefreshCw size={16} className={cn(checking && "animate-spin")} />}
            >
              {checking ? "正在检查…" : "检查更新"}
            </Button>
          </div>
        </div>
      </Modal>
    </>
  );
}
