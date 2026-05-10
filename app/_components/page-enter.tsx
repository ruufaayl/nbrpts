"use client";

import { motion } from "framer-motion";

// Wrap a page's main content with a polished fade-in-up entry.
// Children are passed through unchanged on the server; we just add motion.
export function PageEnter({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: [0.2, 0, 0, 1] }}
      className={className}
    >
      {children}
    </motion.div>
  );
}
