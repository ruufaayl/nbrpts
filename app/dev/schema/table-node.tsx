"use client";

import { Handle, Position, type NodeProps } from "@xyflow/react";
import { KeyRound, Link2, Asterisk, ShieldCheck, ShieldOff } from "lucide-react";
import type { SchemaTable } from "@/lib/schema/types";

export function TableNode({ data, selected }: NodeProps) {
  const table = data as unknown as SchemaTable & { highlighted?: boolean };

  return (
    <div
      className={
        "w-[280px] overflow-hidden rounded-xl border bg-[var(--color-bg-card)] font-mono text-xs shadow-2xl shadow-black/40 transition " +
        (selected
          ? "border-[var(--color-accent)] ring-2 ring-[var(--color-accent)]/30"
          : table.highlighted
            ? "border-[var(--color-border-strong)]"
            : "border-[var(--color-border)]")
      }
    >
      <div className="flex items-center justify-between border-b border-[var(--color-border)] bg-[var(--color-bg-elev)] px-3 py-2.5">
        <div className="flex items-center gap-2">
          <span className="text-[10px] uppercase tracking-widest text-[var(--color-accent)]">
            table
          </span>
          <span className="text-sm font-medium text-[var(--color-fg)]">
            {table.name}
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span
            className="text-[10px] text-[var(--color-fg-subtle)]"
            title="row count (planner estimate)"
          >
            {Number(table.row_count) > 0 ? table.row_count : ""}
          </span>
          {table.rls_enabled ? (
            <ShieldCheck
              className="size-3.5 text-[var(--color-accent)]"
              aria-label="RLS enabled"
            />
          ) : (
            <ShieldOff
              className="size-3.5 text-[var(--color-fg-subtle)]"
              aria-label="RLS disabled"
            />
          )}
        </div>
      </div>

      <ul className="divide-y divide-[var(--color-border)]/60">
        {table.columns.map((col) => (
          <li
            key={col.name}
            className="flex items-center justify-between gap-2 px-3 py-1 text-[11px]"
          >
            <span className="flex min-w-0 items-center gap-1.5 text-[var(--color-fg)]">
              {col.is_primary_key ? (
                <KeyRound className="size-3 shrink-0 text-[var(--color-accent)]" />
              ) : col.is_foreign_key ? (
                <Link2 className="size-3 shrink-0 text-[var(--color-fg-muted)]" />
              ) : col.is_unique ? (
                <Asterisk className="size-3 shrink-0 text-[var(--color-fg-subtle)]" />
              ) : (
                <span className="size-3 shrink-0" />
              )}
              <span className="truncate">{col.name}</span>
              {!col.nullable && (
                <span className="text-[9px] text-[var(--color-fg-subtle)]">!</span>
              )}
            </span>
            <span className="shrink-0 truncate text-right text-[var(--color-fg-subtle)]">
              {shortType(col.type)}
            </span>
          </li>
        ))}
      </ul>

      <Handle
        type="target"
        position={Position.Left}
        className="!size-2 !border-0 !bg-[var(--color-accent)]/40"
      />
      <Handle
        type="source"
        position={Position.Right}
        className="!size-2 !border-0 !bg-[var(--color-accent)]/40"
      />
    </div>
  );
}

function shortType(t: string) {
  return t
    .replace("timestamp with time zone", "timestamptz")
    .replace("timestamp without time zone", "timestamp")
    .replace("character varying", "varchar")
    .replace("USER-DEFINED", "enum");
}
