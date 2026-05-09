import dagre from "@dagrejs/dagre";
import { Position, type Edge, type Node } from "@xyflow/react";

const NODE_WIDTH = 280;
const NODE_HEIGHT_HEADER = 48;
const NODE_HEIGHT_PER_COL = 22;

export function estimateNodeHeight(columnCount: number) {
  return NODE_HEIGHT_HEADER + Math.max(columnCount, 1) * NODE_HEIGHT_PER_COL + 16;
}

export function layoutGraph(nodes: Node[], edges: Edge[]) {
  const g = new dagre.graphlib.Graph();
  g.setDefaultEdgeLabel(() => ({}));
  g.setGraph({ rankdir: "LR", ranksep: 80, nodesep: 32, marginx: 24, marginy: 24 });

  for (const node of nodes) {
    const height =
      typeof node.data === "object" && node.data && "height" in node.data
        ? (node.data.height as number)
        : 200;
    g.setNode(node.id, { width: NODE_WIDTH, height });
  }
  for (const edge of edges) {
    g.setEdge(edge.source, edge.target);
  }

  dagre.layout(g);

  const placedNodes = nodes.map((node) => {
    const pos = g.node(node.id);
    return {
      ...node,
      position: { x: pos.x - NODE_WIDTH / 2, y: pos.y - (pos.height as number) / 2 },
      sourcePosition: Position.Right,
      targetPosition: Position.Left,
    };
  });

  return { nodes: placedNodes, edges };
}
