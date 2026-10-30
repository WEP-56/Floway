import { useState } from "react";
import { ClipboardPaste } from "lucide-react";
import { useApp } from "@/store";
import { Button, Field, Modal, type Platform } from "@/components/ui";

export function ImportSubModal({
  open,
  onClose,
  platform,
}: {
  open: boolean;
  onClose: () => void;
  platform: Platform;
}) {
  const { importSub } = useApp();
  const [name, setName] = useState("");
  const [url, setUrl] = useState("");

  const close = () => {
    setName("");
    setUrl("");
    onClose();
  };

  const valid = name.trim() !== "" && /^https?:\/\/\S+$/i.test(url.trim());

  const submit = () => {
    if (!valid) return;
    importSub(name.trim(), url.trim());
    close();
  };

  return (
    <Modal
      open={open}
      onClose={close}
      platform={platform}
      title="导入订阅"
      subtitle="支持 Clash、Sing-box 与 V2Ray 订阅链接"
      footer={
        <>
          <Button variant="text" onClick={close}>
            取消
          </Button>
          <Button onClick={submit} disabled={!valid}>
            导入
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <Field label="名称" value={name} onChange={setName} placeholder="例如：FLVP 高级订阅" />
        <Field label="订阅链接" value={url} onChange={setUrl} placeholder="https://" mono />
        <button
          type="button"
          onClick={() => {
            setUrl("https://sub.flvp.io/api/v1/client/subscribe?token=4c9e2a");
            if (!name.trim()) setName("新订阅");
          }}
          className="inline-flex h-8 items-center gap-2 rounded-[10px] bg-tile px-3 text-[13px] font-medium text-ink2 transition-colors hover:text-ink"
        >
          <ClipboardPaste size={15} />
          从剪贴板粘贴
        </button>
      </div>
    </Modal>
  );
}
