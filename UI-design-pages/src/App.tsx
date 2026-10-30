import { Check, Moon, Sun } from "lucide-react";
import { AppProvider, useApp } from "@/store";
import { ACCENTS, ACCENT_KEYS, swatchBackground } from "@/data";
import { DesktopApp } from "@/components/DesktopApp";
import { MobileApp } from "@/components/MobileApp";
import { AppMark } from "@/components/ui";
import { useRipple } from "@/ripple";
import { cn } from "@/utils/cn";

function SectionHead({ title, en, sub }: { title: string; en: string; sub: string }) {
  return (
    <div className="px-1">
      <h2 className="text-[12px] font-bold tracking-[0.2em] text-ink3">
        {title} · {en}
      </h2>
      <p className="mt-1 text-[12.5px] text-ink2">{sub}</p>
    </div>
  );
}

function Preview() {
  const { resolvedTheme, toggleTheme, settings, set } = useApp();
  useRipple();

  return (
    <div className="preview-bg min-h-screen">
      <header className="mx-auto flex max-w-[1560px] flex-wrap items-center gap-4 px-6 pt-8 pb-8 sm:px-10">
        <AppMark size={40} />
        <div className="min-w-0">
          <h1 className="text-[20px] font-semibold tracking-tight">FLVPcore</h1>
          <p className="mt-0.5 text-[12.5px] text-ink2">跨平台代理客户端 · 界面预览</p>
        </div>

        <div className="ml-auto flex items-center gap-3">
          <div className="flex items-center gap-1 rounded-full bg-surface p-1.5 shadow-card" role="group" aria-label="主题色">
            {ACCENT_KEYS.map((k) => {
              const sel = settings.accent === k;
              return (
                <button
                  key={k}
                  type="button"
                  data-noripple
                  title={ACCENTS[k].label}
                  aria-label={ACCENTS[k].label}
                  aria-pressed={sel}
                  onClick={() => set("accent", k)}
                  className={cn(
                    "grid h-7 w-7 place-items-center rounded-full transition-transform duration-300 ease-spring",
                    sel ? "scale-100" : "scale-75 hover:scale-90",
                  )}
                  style={{ background: swatchBackground(k) }}
                >
                  {sel && <Check size={13} strokeWidth={3.2} className="text-white drop-shadow" />}
                </button>
              );
            })}
          </div>
          <button
            type="button"
            onClick={toggleTheme}
            aria-label="切换深浅色"
            title="切换深浅色"
            className="grid h-10 w-10 place-items-center rounded-full bg-surface text-ink2 shadow-card transition-colors hover:text-ink"
          >
            {resolvedTheme === "dark" ? <Sun size={18} /> : <Moon size={18} />}
          </button>
        </div>
      </header>

      <main className="mx-auto flex max-w-[1560px] flex-wrap items-start justify-center gap-x-14 gap-y-14 px-6 pb-14 sm:px-10">
        <section className="flex max-w-[1080px] min-w-0 flex-[1_1_720px] flex-col gap-4">
          <SectionHead title="桌面端" en="DESKTOP" sub="Windows · macOS · Linux" />
          <DesktopApp />
        </section>

        <section className="flex shrink-0 flex-col gap-4">
          <SectionHead title="移动端" en="MOBILE" sub="Android · iOS · HarmonyOS" />
          <MobileApp />
        </section>
      </main>

      <footer className="mx-auto max-w-[1560px] px-6 pb-12 text-center text-[11.5px] leading-relaxed text-ink3 sm:px-10">
        Material Design 3 Expressive · 以色差、阴影与形状区分层级，无分割线
        <br />
        两端共享同一状态，所有按钮、开关、节点与订阅均可交互 · FLVPcore v1.4.2
      </footer>
    </div>
  );
}

export default function App() {
  return (
    <AppProvider>
      <Preview />
    </AppProvider>
  );
}
