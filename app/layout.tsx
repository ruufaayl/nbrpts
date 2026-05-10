import type { Metadata } from "next";
import { Manrope, Fraunces, JetBrains_Mono } from "next/font/google";
import { Toaster } from "sonner";
import { AmbientBackdrop } from "./_components/ambient-backdrop";
import { GlobalNav } from "./_components/global-nav";
import { CommandPalette } from "./_components/command-palette";
import "./globals.css";

const manrope = Manrope({
  variable: "--font-sans",
  subsets: ["latin"],
  display: "swap",
});

const fraunces = Fraunces({
  variable: "--font-display",
  subsets: ["latin"],
  display: "swap",
  axes: ["opsz", "SOFT"],
});

const jetbrains = JetBrains_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "NBRPTS — National Birth Registry & Population Tracking System",
  description:
    "A real-time alternative to the decennial census of Pakistan. Hospital portal, AI verification, NADRA officer dashboard, and a live database observatory.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body
        className={`${manrope.variable} ${fraunces.variable} ${jetbrains.variable} antialiased`}
      >
        <AmbientBackdrop />
        <div className="relative z-10">
          <GlobalNav />
          {children}
        </div>
        <CommandPalette />
        <Toaster theme="dark" position="bottom-right" />
      </body>
    </html>
  );
}
