"use client";

import { useCallback, useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Wifi, WifiOff, HardDrive, Plus, RefreshCw, CheckCircle2, AlertTriangle, Loader2, Trash2 } from "lucide-react";
import { toast } from "sonner";
import type { SubmitFormData } from "@/lib/hospital/types";
import { submitBirthRecordAction } from "../submit/actions";

const DB_NAME = "nbrpts-device";
const STORE_NAME = "queue";
const DB_VERSION = 1;

type QueuedItem = {
  id: string;          // local uuid
  payload: SubmitFormData;
  created_at: string;
  status: "PENDING" | "SYNCING" | "SYNCED" | "FAILED";
  brn?: string;
  error?: string;
};

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: "id" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function dbAll(): Promise<QueuedItem[]> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, "readonly");
    const store = tx.objectStore(STORE_NAME);
    const req = store.getAll();
    req.onsuccess = () => resolve(req.result as QueuedItem[]);
    req.onerror = () => reject(req.error);
  });
}

async function dbPut(item: QueuedItem): Promise<void> {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, "readwrite");
    tx.objectStore(STORE_NAME).put(item);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function dbDelete(id: string): Promise<void> {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, "readwrite");
    tx.objectStore(STORE_NAME).delete(id);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

const DEMO_PAYLOAD = (): SubmitFormData => {
  const ts = new Date(Date.now() - Math.floor(Math.random() * 1000 * 60 * 30))
    .toISOString()
    .slice(0, 16);
  return {
    mother_cnic:        "42101-1234567-1",
    mother_full_name:   "Ayesha Siddiqui",
    mother_dob:         "1995-03-14",
    mother_contact:     "+92-300-1111111",
    mother_address:     "Block 6, PECHS, Karachi",
    mother_province:    "SINDH",
    mother_district:    "Karachi-South",
    mother_blood_group: "A+",
    father_cnic:        "42101-9876543-2",
    father_full_name:   "Ali Siddiqui",
    father_dob:         "1990-05-20",
    father_contact:     "+92-321-1111111",
    attending_doctor:   "Dr. Ahmed Khan",
    doctor_license_no:  "PMDC-456789",
    birth_datetime:     ts,
    delivery_type:      "NORMAL",
    birth_weight_kg:    (3 + Math.random() * 0.8).toFixed(2),
    birth_outcome:      "LIVE_BIRTH",
    child_gender:       Math.random() < 0.5 ? "MALE" : "FEMALE",
    child_full_name:    "",
    remarks:            "Captured offline by device simulator",
  };
};

export function DeviceSimulator() {
  const [online, setOnline] = useState(false);
  const [items, setItems] = useState<QueuedItem[]>([]);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    setItems(await dbAll());
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const queue = useCallback(async () => {
    const item: QueuedItem = {
      id: crypto.randomUUID(),
      payload: DEMO_PAYLOAD(),
      created_at: new Date().toISOString(),
      status: "PENDING",
    };
    await dbPut(item);
    await refresh();
    toast.success("Record captured to local IndexedDB");
  }, [refresh]);

  const sync = useCallback(async () => {
    if (!online) {
      toast.error("Device is offline. Toggle it online first.");
      return;
    }
    setBusy(true);
    try {
      const pending = (await dbAll()).filter((i) => i.status === "PENDING" || i.status === "FAILED");
      if (pending.length === 0) {
        toast("Nothing to sync");
        return;
      }
      let ok = 0;
      let failed = 0;
      for (const item of pending) {
        await dbPut({ ...item, status: "SYNCING" });
        await refresh();
        const r = await submitBirthRecordAction(item.payload);
        if (r.ok) {
          await dbPut({ ...item, status: "SYNCED", brn: r.brn ?? undefined });
          ok++;
        } else {
          await dbPut({ ...item, status: "FAILED", error: r.error });
          failed++;
        }
        await refresh();
      }
      if (failed === 0) toast.success(`Synced ${ok} record${ok === 1 ? "" : "s"}`);
      else toast.error(`${ok} synced, ${failed} failed`);
    } finally {
      setBusy(false);
    }
  }, [online, refresh]);

  const clearSynced = useCallback(async () => {
    const all = await dbAll();
    for (const i of all.filter((x) => x.status === "SYNCED")) {
      await dbDelete(i.id);
    }
    await refresh();
    toast.success("Cleared synced records");
  }, [refresh]);

  // Auto-sync when toggling online
  useEffect(() => {
    if (online) {
      sync();
    }
  }, [online]); // eslint-disable-line react-hooks/exhaustive-deps

  const pendingCount = items.filter((i) => i.status === "PENDING" || i.status === "FAILED").length;

  return (
    <div className="space-y-6">
      <div className="grid gap-4 md:grid-cols-3">
        <ConnectionCard online={online} onToggle={() => setOnline((o) => !o)} pendingCount={pendingCount} />
        <StatTile
          icon={<HardDrive className="size-4" />}
          label="In local storage"
          value={items.length}
        />
        <StatTile
          icon={<RefreshCw className="size-4" />}
          label="Pending sync"
          value={pendingCount}
          tone={pendingCount > 0 ? "warn" : "default"}
        />
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <button
          onClick={queue}
          className="inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-4 py-2 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90"
        >
          <Plus className="size-4" />
          Capture demo record
        </button>
        <button
          onClick={sync}
          disabled={!online || busy || pendingCount === 0}
          className="inline-flex items-center gap-2 rounded-full border border-[var(--color-border)] px-4 py-2 text-sm transition hover:border-[var(--color-border-strong)] disabled:opacity-40"
        >
          {busy ? <Loader2 className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
          Sync now
        </button>
        <button
          onClick={clearSynced}
          className="inline-flex items-center gap-2 rounded-full border border-[var(--color-border)] px-4 py-2 text-sm text-[var(--color-fg-muted)] transition hover:border-[var(--color-border-strong)] hover:text-[var(--color-fg)]"
        >
          <Trash2 className="size-4" />
          Clear synced
        </button>
      </div>

      <div className="overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
        <div className="border-b border-[var(--color-border)] bg-[var(--color-bg-elev)] px-4 py-2.5 font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
          Local queue
        </div>
        {items.length === 0 ? (
          <div className="px-6 py-12 text-center text-sm text-[var(--color-fg-muted)]">
            No records yet. Click <span className="font-mono">Capture demo record</span> to add one.
          </div>
        ) : (
          <ul className="divide-y divide-[var(--color-border)]/60">
            <AnimatePresence initial={false}>
              {items
                .slice()
                .sort((a, b) => b.created_at.localeCompare(a.created_at))
                .map((i) => (
                  <motion.li
                    key={i.id}
                    initial={{ opacity: 0, y: -4 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0 }}
                    className="flex items-center gap-4 px-4 py-3 text-sm"
                  >
                    <StatusDot status={i.status} />
                    <div className="flex-1 min-w-0">
                      <div className="text-[var(--color-fg)]">
                        {i.payload.mother_full_name}{" "}
                        <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                          ({i.payload.mother_cnic})
                        </span>
                      </div>
                      <div className="font-mono text-[11px] text-[var(--color-fg-muted)]">
                        {i.payload.delivery_type} · {i.payload.birth_weight_kg} kg ·{" "}
                        {i.payload.child_gender} ·{" "}
                        {new Date(i.payload.birth_datetime).toLocaleString()}
                      </div>
                      {i.brn && (
                        <div className="mt-0.5 font-mono text-[10px] text-[var(--color-accent)]">
                          → {i.brn}
                        </div>
                      )}
                      {i.error && (
                        <div className="mt-0.5 font-mono text-[10px] text-[var(--color-danger)]">
                          {i.error}
                        </div>
                      )}
                    </div>
                    <div className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                      {i.status}
                    </div>
                  </motion.li>
                ))}
            </AnimatePresence>
          </ul>
        )}
      </div>
    </div>
  );
}

function ConnectionCard({
  online,
  onToggle,
  pendingCount,
}: {
  online: boolean;
  onToggle: () => void;
  pendingCount: number;
}) {
  return (
    <button
      onClick={onToggle}
      className={
        "flex items-center gap-3 rounded-2xl border p-4 text-left transition " +
        (online
          ? "border-[var(--color-accent)]/40 bg-[var(--color-accent)]/5"
          : "border-[var(--color-warn)]/40 bg-[var(--color-warn)]/5")
      }
    >
      <div
        className={
          "flex size-10 items-center justify-center rounded-lg " +
          (online
            ? "bg-[var(--color-accent)]/20 text-[var(--color-accent)]"
            : "bg-[var(--color-warn)]/20 text-[var(--color-warn)]")
        }
      >
        {online ? <Wifi className="size-5" /> : <WifiOff className="size-5" />}
      </div>
      <div>
        <div className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
          Device connection
        </div>
        <div
          className={
            "mt-0.5 font-mono text-base " +
            (online ? "text-[var(--color-accent)]" : "text-[var(--color-warn)]")
          }
        >
          {online ? "ONLINE" : "OFFLINE"}
        </div>
        <div className="mt-0.5 text-[10px] text-[var(--color-fg-muted)]">
          {online
            ? "Click to go offline"
            : pendingCount > 0
              ? `Click to go online — ${pendingCount} record${pendingCount === 1 ? "" : "s"} will sync`
              : "Click to go online"}
        </div>
      </div>
    </button>
  );
}

function StatTile({
  icon,
  label,
  value,
  tone,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  tone?: "warn" | "default";
}) {
  const colorClass =
    tone === "warn" ? "text-[var(--color-warn)]" : "text-[var(--color-fg)]";
  return (
    <div className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-4">
      <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        <span className="text-[var(--color-fg-muted)]">{icon}</span>
        {label}
      </div>
      <div className={"mt-2 font-mono text-3xl " + colorClass}>{value}</div>
    </div>
  );
}

function StatusDot({ status }: { status: QueuedItem["status"] }) {
  const map: Record<QueuedItem["status"], { color: string; icon: React.ReactNode }> = {
    PENDING:  { color: "var(--color-warn)",   icon: <span className="block size-2 rounded-full" style={{ background: "var(--color-warn)" }} /> },
    SYNCING:  { color: "var(--color-accent)", icon: <Loader2 className="size-3.5 animate-spin text-[var(--color-accent)]" /> },
    SYNCED:   { color: "var(--color-accent)", icon: <CheckCircle2 className="size-3.5 text-[var(--color-accent)]" /> },
    FAILED:   { color: "var(--color-danger)", icon: <AlertTriangle className="size-3.5 text-[var(--color-danger)]" /> },
  };
  return <span aria-label={status} className="flex size-3.5 items-center justify-center">{map[status].icon}</span>;
}
