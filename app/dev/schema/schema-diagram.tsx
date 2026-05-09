"use client";

import { useMemo } from "react";
import {
  ReactFlow,
  Background,
  BackgroundVariant,
  Controls,
  MiniMap,
  type Edge,
  type Node,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import type { SchemaPayload } from "@/lib/schema/types";
import { estimateNodeHeight, layoutGraph } from "@/lib/schema/layout";
import { TableNode } from "./table-node";

const nodeTypes = { tableNode: TableNode };

export function SchemaDiagram({ payload }: { payload: SchemaPayload }) {
  const { nodes, edges } = useMemo(() => buildGraph(payload), [payload]);

  return (
    <div className="h-[78vh] w-full overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg)]">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        fitView
        fitViewOptions={{ padding: 0.15 }}
        proOptions={{ hideAttribution: true }}
        minZoom={0.25}
        maxZoom={1.6}
        nodesDraggable
        nodesConnectable={false}
        edgesFocusable={false}
      >
        <Background
          variant={BackgroundVariant.Dots}
          gap={24}
          size={1}
          color="rgba(255,255,255,0.06)"
        />
        <MiniMap
          pannable
          zoomable
          nodeColor={() => "rgba(120, 200, 160, 0.6)"}
          maskColor="rgba(0,0,0,0.5)"
          style={{
            background: "var(--color-bg-elev)",
            border: "1px solid var(--color-border)",
            borderRadius: 8,
          }}
        />
        <Controls
          style={{
            background: "var(--color-bg-elev)",
            border: "1px solid var(--color-border)",
            borderRadius: 8,
          }}
        />
      </ReactFlow>
    </div>
  );
}

function buildGraph(payload: SchemaPayload) {
  const rawNodes: Node[] = payload.tables.map((t) => ({
    id: t.name,
    type: "tableNode",
    position: { x: 0, y: 0 },
    data: { ...t, height: estimateNodeHeight(t.columns.length) },
  }));

  const rawEdges: Edge[] = payload.foreign_keys.map((fk, i) => ({
    id: `${fk.from_table}.${fk.from_column}->${fk.to_table}.${fk.to_column}-${i}`,
    source: fk.from_table,
    target: fk.to_table,
    type: "default",
    animated: true,
    style: { stroke: "rgba(120, 200, 160, 0.55)", strokeWidth: 1.4 },
    label: fk.from_column,
    labelStyle: {
      fontSize: 10,
      fontFamily: "var(--font-mono)",
      fill: "rgba(255,255,255,0.6)",
    },
    labelBgStyle: { fill: "rgba(20,20,20,0.85)" },
    labelBgPadding: [4, 4] as [number, number],
    labelBgBorderRadius: 4,
  }));

  return layoutGraph(rawNodes, rawEdges);
}
