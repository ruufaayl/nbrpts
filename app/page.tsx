"use client";

// NBRPTS Homepage — cinematic editorial single-page component.
// Adapted from the Claude Design handoff (homepage.jsx) for Next.js 16.

import Link from "next/link";
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type ComponentType,
  type ReactNode,
} from "react";
import {
  ArrowRight,
  ArrowUpRight,
  Brain,
  Check,
  Copy,
  Database,
  FileCheck2,
  Code2,
  Hospital,
  ShieldCheck,
} from "lucide-react";

type Hue = "emerald" | "steel" | "violet" | "amber";
const HUE: Record<Hue, string> = {
  emerald: "var(--hue-emerald)",
  steel:   "var(--hue-steel)",
  violet:  "var(--hue-violet)",
  amber:   "var(--hue-amber)",
};

/* ------------------------------------------------------------------ *
 *  Reveal-on-scroll wrapper                                           *
 * ------------------------------------------------------------------ */
function Reveal({
  children, delay = 0, className = "", style,
}: {
  children: ReactNode; delay?: number; className?: string; style?: CSSProperties;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) {
          setTimeout(() => el.classList.add("in"), delay);
          io.disconnect();
        }
      },
      { threshold: 0.15, rootMargin: "0px 0px -60px 0px" },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [delay]);
  return (
    <div ref={ref} className={`reveal ${className}`} style={style}>
      {children}
    </div>
  );
}

/* ------------------------------------------------------------------ *
 *  Custom cursor — hidden on touch, scoped to body.cursor-immersive  *
 * ------------------------------------------------------------------ */
function CustomCursor() {
  const ref = useRef<HTMLDivElement>(null);
  const [label, setLabel] = useState("");
  const [hover, setHover] = useState(false);

  useEffect(() => {
    const dot = ref.current;
    if (!dot) return;
    let x = window.innerWidth / 2, y = window.innerHeight / 2;
    let tx = x, ty = y;
    let raf = 0;
    const onMove = (e: MouseEvent) => { tx = e.clientX; ty = e.clientY; };
    const onOver = (e: MouseEvent) => {
      const target = e.target as HTMLElement | null;
      if (!target) return;
      const tagged = target.closest<HTMLElement>("[data-cursor]");
      if (tagged) {
        setLabel(tagged.getAttribute("data-cursor") ?? "");
        setHover(true);
      } else if (target.closest("a, button")) {
        setLabel(""); setHover(true);
      } else {
        setLabel(""); setHover(false);
      }
    };
    const tick = () => {
      x += (tx - x) * 0.22; y += (ty - y) * 0.22;
      dot.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%)`;
      raf = requestAnimationFrame(tick);
    };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseover", onOver);
    raf = requestAnimationFrame(tick);
    return () => {
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseover", onOver);
      cancelAnimationFrame(raf);
    };
  }, []);

  const cls = "cursor-dot" + (label ? " label" : hover ? " hover" : "");
  return <div ref={ref} className={cls} aria-hidden="true">{label}</div>;
}

/* ------------------------------------------------------------------ *
 *  Image slot — gradient placeholder until real photography is wired *
 * ------------------------------------------------------------------ */
function ImageSlot({
  caption, hue = "emerald", aspect = "3 / 4",
}: { caption: string; hue?: Hue; aspect?: string }) {
  return (
    <div
      style={{
        position: "absolute", inset: 0,
        background: `
          radial-gradient(ellipse at 30% 25%, color-mix(in oklch, ${HUE[hue]} 30%, transparent), transparent 65%),
          radial-gradient(ellipse at 70% 75%, color-mix(in oklch, var(--hue-violet) 22%, transparent), transparent 70%),
          linear-gradient(180deg, oklch(0.22 0.01 240), oklch(0.13 0.005 240))
        `,
        aspectRatio: aspect,
        display: "flex", alignItems: "center", justifyContent: "center",
        padding: 32,
      }}
    >
      <div
        className="font-mono"
        style={{
          fontSize: 11,
          letterSpacing: "0.18em",
          textTransform: "uppercase",
          color: "var(--color-fg-muted)",
          textAlign: "center",
          maxWidth: "20ch",
          lineHeight: 1.6,
        }}
      >
        {caption}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ *
 *  Hero — kinetic word + letter reveal                                *
 * ------------------------------------------------------------------ */
function RegisteredWord({ delay = 0 }: { delay?: number }) {
  const letters = "registered".split("");
  return (
    <span
      className="text-shimmer font-display"
      style={{ fontStyle: "italic", fontWeight: 300, display: "inline-block", position: "relative" }}
    >
      {letters.map((l, i) => (
        <span key={i} className="split-letter" style={{ animationDelay: `${delay + i * 0.06}s` }}>
          {l}
        </span>
      ))}
    </span>
  );
}

function Hero() {
  const headline = "Every Pakistani child,".split(" ");
  const tail = "the day they're born.".split(" ");
  return (
    <section
      style={{
        position: "relative",
        minHeight: "100vh",
        paddingTop: 140,
        paddingBottom: 80,
      }}
    >
      <div
        className="container"
        style={{
          position: "relative",
          zIndex: 2,
          display: "grid",
          gridTemplateColumns: "1.4fr 1fr",
          gap: 60,
          alignItems: "center",
        }}
      >
        <div>
          <div
            className="eyebrow word-in"
            style={{
              display: "inline-flex", alignItems: "center", gap: 10,
              padding: "8px 14px", borderRadius: 9999,
              background: "var(--glass-bg)", border: "1px solid var(--glass-border)",
              backdropFilter: "blur(12px)", WebkitBackdropFilter: "blur(12px)",
              color: "var(--color-fg-muted)",
              animationDelay: "0.05s",
            }}
          >
            <span
              style={{
                width: 6, height: 6, borderRadius: 9999,
                background: "var(--color-accent)",
                boxShadow: "0 0 12px var(--color-accent-glow)",
              }}
            />
            CS2013 · Spring 2026 · FAST-NUCES
          </div>

          <h1
            className="font-display"
            style={{
              marginTop: 32, marginBottom: 0,
              fontWeight: 300,
              lineHeight: 0.98,
              letterSpacing: "-0.04em",
              wordSpacing: "0.12em",
              maxWidth: "18ch",
              fontSize: "clamp(56px, 8vw, 96px)",
            }}
          >
            {headline.map((w, i) => (
              <span
                key={`h-${i}`}
                className="word-in"
                style={{ animationDelay: `${0.15 + i * 0.08}s`, marginRight: "0.42em" }}
              >
                {w}
              </span>
            ))}
            <br />
            <RegisteredWord delay={0.15 + headline.length * 0.08} />
            <span style={{ display: "inline-block", width: "0.42em" }} />
            {tail.map((w, i) => (
              <span
                key={`t-${i}`}
                className="word-in"
                style={{ animationDelay: `${0.55 + i * 0.08}s`, marginRight: "0.42em" }}
              >
                {w}
              </span>
            ))}
          </h1>

          <p
            className="word-in"
            style={{
              animationDelay: "0.95s",
              marginTop: 40, maxWidth: "58ch",
              lineHeight: 1.55,
              color: "var(--color-fg-muted)",
              fontSize: 18,
            }}
          >
            NBRPTS turns every registered hospital into a direct data-entry point for NADRA.
            Births stream in continuously, a deterministic verification engine reviews them in real time,
            and B-Forms are ready for collection before parents leave the delivery ward.
          </p>

          <div
            className="word-in"
            style={{
              animationDelay: "1.05s", marginTop: 44,
              display: "flex", flexWrap: "wrap", gap: 12, alignItems: "center",
            }}
          >
            <Link
              href="/dev"
              data-cursor="Open →"
              className="accent-glow lift"
              style={{
                display: "inline-flex", alignItems: "center", gap: 10,
                padding: "16px 26px", borderRadius: 9999,
                background: "linear-gradient(135deg, var(--color-accent), var(--color-accent-strong))",
                color: "var(--color-accent-fg)",
                fontSize: 15, fontWeight: 600, letterSpacing: "-0.005em",
              }}
            >
              Open the database observatory
              <ArrowRight size={16} strokeWidth={2} />
            </Link>
            <a
              href="https://github.com/ruufaayl/nbrpts"
              data-cursor="GitHub"
              target="_blank" rel="noreferrer"
              className="glass lift"
              style={{
                display: "inline-flex", alignItems: "center", gap: 10,
                padding: "16px 24px", borderRadius: 9999,
                fontSize: 15, fontWeight: 500, color: "var(--color-fg)",
              }}
            >
              <Code2 size={16} strokeWidth={1.8} /> View on GitHub
            </a>
            <Link
              href="/login"
              data-cursor="Sign in"
              style={{
                marginLeft: 6, padding: "14px 6px",
                fontSize: 14, color: "var(--color-fg-muted)",
                borderBottom: "1px solid var(--glass-border)",
              }}
            >
              Sign in →
            </Link>
          </div>

          <div
            className="word-in"
            style={{
              animationDelay: "1.3s", marginTop: 96,
              display: "flex", alignItems: "center", gap: 14,
            }}
          >
            <span
              style={{
                width: 1, height: 28,
                background: "linear-gradient(to bottom, transparent, oklch(1 0 0 / 0.4), transparent)",
              }}
            />
            <span
              className="font-mono"
              style={{
                fontSize: 11, letterSpacing: "0.22em",
                textTransform: "uppercase", color: "var(--color-fg-subtle)",
              }}
            >
              Scroll · the system in seven movements
            </span>
          </div>
        </div>

        <div
          className="word-in"
          style={{
            animationDelay: "0.7s", position: "relative",
            aspectRatio: "3 / 4", borderRadius: 22,
          }}
        >
          <div
            className="video-frame glass-highlight"
            style={{
              position: "absolute", inset: 0,
              background: "linear-gradient(180deg, oklch(0.19 0.007 240), oklch(0.13 0.005 240))",
              border: "1px solid var(--glass-border-strong)",
            }}
          >
            <ImageSlot caption="Delivery ward · mother & child · NADRA imagery" hue="emerald" />
            <div className="video-frame__corner tl" />
            <div className="video-frame__corner tr" />
            <div className="video-frame__corner bl" />
            <div className="video-frame__corner br" />
            <div className="rec-dot">REC · LIVE</div>
            <div
              style={{
                position: "absolute", left: 18, bottom: 16, right: 18,
                display: "flex", justifyContent: "space-between", alignItems: "flex-end",
                color: "var(--color-fg)", zIndex: 4,
              }}
            >
              <div>
                <div
                  className="font-mono"
                  style={{
                    fontSize: 10, letterSpacing: "0.22em",
                    textTransform: "uppercase", color: "var(--color-accent)",
                  }}
                >
                  FACILITY · KARACHI
                </div>
                <div
                  className="font-display"
                  style={{ fontSize: 22, fontWeight: 300, letterSpacing: "-0.025em", marginTop: 4 }}
                >
                  Aga Khan · Ward 4B
                </div>
              </div>
              <div
                className="font-mono"
                style={{
                  fontSize: 10, letterSpacing: "0.18em",
                  color: "var(--color-fg-muted)", textAlign: "right",
                }}
              >
                03:14 AM PKT<br />2026.05.10
              </div>
            </div>
          </div>
          <div
            aria-hidden
            style={{
              position: "absolute", inset: -20, borderRadius: 28,
              background: "radial-gradient(ellipse at center, var(--color-accent-glow), transparent 65%)",
              filter: "blur(40px)", opacity: 0.5, zIndex: -1,
            }}
          />
        </div>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ *
 *  Marquee ticker                                                     *
 * ------------------------------------------------------------------ */
function Marquee() {
  const items = [
    "Every birth observable",
    "3NF · 13 tables · 24 indexes",
    "Eight-rule verification engine",
    "B-Form before discharge",
    "NADRA-direct from delivery ward",
    "19 sequential migrations",
    "Realtime query log",
    "FAST-NUCES · Spring 2026",
  ];
  const set = [...items, ...items];
  return (
    <div style={{ position: "relative", zIndex: 2, padding: "0 0 40px" }}>
      <div
        className="marquee-mask"
        style={{
          borderTop: "1px solid var(--glass-border)",
          borderBottom: "1px solid var(--glass-border)",
          padding: "22px 0",
          background: "linear-gradient(180deg, oklch(1 0 0 / 0.01), transparent)",
        }}
      >
        <div className="marquee">
          {set.map((s, i) => (
            <span
              key={i}
              className="font-display"
              style={{
                fontSize: 28, fontStyle: "italic", fontWeight: 300,
                letterSpacing: "-0.025em", color: "var(--color-fg)",
                display: "inline-flex", alignItems: "center", gap: 60, whiteSpace: "nowrap",
              }}
            >
              {s}
              <span
                style={{
                  width: 6, height: 6, borderRadius: 99,
                  background: "var(--color-accent)",
                  boxShadow: "0 0 12px var(--color-accent-glow)",
                }}
              />
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ *
 *  Counter strip                                                       *
 * ------------------------------------------------------------------ */
function CountUp({ value, suffix = "", duration = 1200 }: { value: string; suffix?: string; duration?: number }) {
  const ref = useRef<HTMLSpanElement>(null);
  const [n, setN] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const target = parseInt(value, 10);
    const io = new IntersectionObserver(([e]) => {
      if (!e.isIntersecting) return;
      const start = performance.now();
      const tick = (t: number) => {
        const k = Math.min(1, (t - start) / duration);
        const e2 = 1 - Math.pow(1 - k, 3);
        setN(Math.round(target * e2));
        if (k < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
      io.disconnect();
    }, { threshold: 0.4 });
    io.observe(el);
    return () => io.disconnect();
  }, [value, duration]);
  return <span ref={ref}>{n}{suffix}</span>;
}

function CounterStrip() {
  const stats = [
    { value: "13", suffix: "",  label: "Tables in 3NF",  caption: "Normalized to third normal form" },
    { value: "8",  suffix: "",  label: "SQL triggers",   caption: "Cascading state machine" },
    { value: "20", suffix: "+", label: "Business RPCs",  caption: "Server-side procedures" },
    { value: "19", suffix: "",  label: "Migrations",     caption: "Sequenced & reversible" },
  ];
  return (
    <section style={{ position: "relative", zIndex: 2, padding: "60px 0 120px" }}>
      <div className="container">
        <Reveal>
          <div
            style={{
              display: "flex", alignItems: "baseline", justifyContent: "space-between",
              flexWrap: "wrap", gap: 24, marginBottom: 28,
            }}
          >
            <div className="eyebrow">The system, in numbers</div>
            <div
              className="font-mono"
              style={{
                fontSize: 11, letterSpacing: "0.22em",
                textTransform: "uppercase", color: "var(--color-fg-subtle)",
              }}
            >
              <span style={{ color: "var(--color-accent)" }}>●</span> live · supabase postgres
            </div>
          </div>
        </Reveal>
        <Reveal delay={80}>
          <div
            style={{
              borderTop: "1px solid var(--glass-border-strong)",
              borderBottom: "1px solid var(--glass-border)",
              padding: "44px 0",
              display: "grid", gridTemplateColumns: "repeat(4, 1fr)",
              gap: 0,
            }}
          >
            {stats.map((s, i) => (
              <div
                key={s.label}
                style={{
                  padding: "0 32px",
                  borderRight: i < stats.length - 1 ? "1px solid var(--glass-border)" : "none",
                }}
              >
                <div
                  className="font-mono"
                  style={{
                    fontSize: 10, letterSpacing: "0.22em",
                    textTransform: "uppercase", color: "var(--color-fg-subtle)",
                  }}
                >
                  {String(i + 1).padStart(2, "0")}
                </div>
                <div
                  className="font-display"
                  style={{
                    marginTop: 18,
                    fontSize: "clamp(64px, 8vw, 120px)",
                    fontWeight: 300, lineHeight: 0.92, letterSpacing: "-0.05em",
                    fontFeatureSettings: '"tnum"',
                  }}
                >
                  <CountUp value={s.value} suffix={s.suffix} />
                </div>
                <div
                  style={{
                    marginTop: 18, fontSize: 15,
                    color: "var(--color-fg)", letterSpacing: "-0.01em",
                  }}
                >
                  {s.label}
                </div>
                <div
                  className="font-mono"
                  style={{
                    marginTop: 6, fontSize: 11,
                    color: "var(--color-fg-subtle)", letterSpacing: "0.04em",
                  }}
                >
                  {s.caption}
                </div>
              </div>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ *
 *  Problem section                                                    *
 * ------------------------------------------------------------------ */
function Problem() {
  return (
    <section style={{ position: "relative", zIndex: 2, padding: "60px 0 120px" }}>
      <div className="container">
        <Reveal>
          <div
            style={{
              display: "flex", alignItems: "baseline", justifyContent: "space-between",
              flexWrap: "wrap", gap: 24, marginBottom: 60,
            }}
          >
            <div className="eyebrow">01 — Why this exists</div>
            <div
              className="font-mono"
              style={{
                fontSize: 11, letterSpacing: "0.18em",
                textTransform: "uppercase", color: "var(--color-fg-subtle)",
                maxWidth: 360, textAlign: "right", lineHeight: 1.6,
              }}
            >
              UNICEF · State of the World&apos;s Children<br />
              <span style={{ color: "var(--color-fg-muted)" }}>estimate · 2024</span>
            </div>
          </div>
        </Reveal>

        <Reveal delay={80}>
          <blockquote
            className="font-display"
            style={{
              fontStyle: "italic", fontWeight: 300,
              fontSize: "clamp(48px, 7vw, 104px)",
              lineHeight: 1.0, letterSpacing: "-0.04em",
              margin: 0, maxWidth: "20ch",
            }}
          >
            <span
              style={{
                color: "var(--color-fg-subtle)", fontStyle: "normal",
                fontSize: "0.5em", verticalAlign: "0.5em", marginRight: 10,
              }}
            >
              “
            </span>
            Pakistan registers fewer than{" "}
            <span
              style={{
                color: "var(--color-accent)", fontStyle: "normal",
                fontFamily: "var(--font-mono)",
                fontSize: "0.74em", letterSpacing: "-0.02em",
              }}
            >
              42%
            </span>{" "}
            of births within a year of birth.
            <span
              style={{
                color: "var(--color-fg-subtle)", fontStyle: "normal",
                fontSize: "0.5em", verticalAlign: "0.5em", marginLeft: 6,
              }}
            >
              ”
            </span>
          </blockquote>
        </Reveal>

        <div
          style={{
            marginTop: 100,
            display: "grid", gridTemplateColumns: "1fr 1fr",
            gap: 64, alignItems: "start",
          }}
        >
          <Reveal delay={120}>
            <div
              className="video-frame glass-highlight"
              style={{
                aspectRatio: "4 / 5", borderRadius: 18,
                border: "1px solid var(--glass-border)",
                background: "var(--color-bg-elev)",
                position: "relative",
              }}
            >
              <ImageSlot caption="Hospital ward · paper birth slips · NADRA queue" hue="violet" aspect="4 / 5" />
              <div className="video-frame__corner tl" />
              <div className="video-frame__corner tr" />
              <div className="video-frame__corner bl" />
              <div className="video-frame__corner br" />
              <div style={{ position: "absolute", left: 16, bottom: 14, zIndex: 4 }}>
                <div
                  className="font-mono"
                  style={{
                    fontSize: 9, letterSpacing: "0.22em",
                    textTransform: "uppercase", color: "var(--color-fg)",
                  }}
                >
                  FIG. 01 · The paper trail
                </div>
              </div>
            </div>
          </Reveal>

          <Reveal delay={180}>
            <div
              style={{
                paddingTop: 24,
                display: "flex", flexDirection: "column", gap: 28,
              }}
            >
              <p
                style={{
                  fontSize: 21, lineHeight: 1.55,
                  color: "var(--color-fg)", margin: 0,
                  letterSpacing: "-0.012em",
                }}
              >
                The decennial census is too slow to govern by. Births counted on
                paper, six years after the fact, can&apos;t underwrite school
                placement, vaccination outreach, or constituency boundaries.
              </p>
              <p
                style={{
                  fontSize: 17, lineHeight: 1.65,
                  color: "var(--color-fg-muted)", margin: 0,
                }}
              >
                NBRPTS treats every delivery ward as the registry&apos;s edge. The
                moment a baby is born, a single form crosses the wire to a
                Postgres database, runs through eight deterministic verification
                rules, and either materializes a B-Form or routes itself to a
                NADRA officer for human review.
              </p>
              <p
                style={{
                  fontSize: 17, lineHeight: 1.65,
                  color: "var(--color-fg-muted)", margin: 0,
                  fontStyle: "italic",
                }}
              >
                No paper. No backlog. No gap between the delivery room and the registry.
              </p>

              <div
                style={{
                  marginTop: 12, paddingTop: 24,
                  borderTop: "1px solid var(--glass-border)",
                  display: "flex", flexDirection: "column", gap: 14,
                }}
              >
                {[
                  ["Hospital → NADRA, in real time", "stream"],
                  ["Eight-rule audit on every record", "verify"],
                  ["B-Form before discharge", "issue"],
                ].map(([t, k]) => (
                  <div
                    key={t}
                    style={{
                      display: "flex", alignItems: "center",
                      justifyContent: "space-between", gap: 12,
                    }}
                  >
                    <span style={{ fontSize: 15, color: "var(--color-fg)", letterSpacing: "-0.005em" }}>{t}</span>
                    <span
                      className="font-mono"
                      style={{
                        fontSize: 10, letterSpacing: "0.22em",
                        textTransform: "uppercase", color: "var(--color-accent)",
                      }}
                    >
                      {k}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </Reveal>
        </div>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ *
 *  Portal grid                                                        *
 * ------------------------------------------------------------------ */
type PortalEntry = {
  href: string;
  n: string;
  section: string;
  title: string;
  body: string;
  icon: ComponentType<{ className?: string; style?: CSSProperties; size?: number; strokeWidth?: number }>;
  hue: string;
  chips: string[];
};

const PORTALS: PortalEntry[] = [
  {
    href: "/hospital",
    n: "01", section: "Front line", title: "Hospital portal",
    body: "Offline-first birth-record entry from the delivery ward. Auto-syncs the moment connectivity returns. Tamper-proof local cache so a power cut never erases a birth.",
    icon: Hospital, hue: HUE.emerald,
    chips: ["4-step submit form", "IndexedDB device", "RLS-scoped to facility"],
  },
  {
    href: "/ai-engine",
    n: "02", section: "Verification", title: "AI Engine",
    body: "Eight signals across mother age, weight, CNIC validity, duplicates and outcome. Auto-approves on high confidence; queues anomalies with a transparent reason trail.",
    icon: Brain, hue: HUE.steel,
    chips: ["Pure-SQL rules", "ai_review_log", "State-machine cascade"],
  },
  {
    href: "/officer",
    n: "03", section: "Authority", title: "Officer dashboard",
    body: "B-Form authorization, reissuance with documented reason, full audit trail, and district-level population analytics for NADRA officers.",
    icon: ShieldCheck, hue: HUE.violet,
    chips: ["Verify · Reject · Flag", "Reissue with reason", "Province × district stats"],
  },
  {
    href: "/dev",
    n: "04", section: "Transparency", title: "Database observatory",
    body: "Live query feed, an interactive ER diagram, and a trigger lab. Every screen is a database lecture — open the hood, watch the rows move, read the EXPLAIN plan.",
    icon: Database, hue: HUE.amber,
    chips: ["Realtime query log", "Interactive triggers", "EXPLAIN traces"],
  },
];

function PortalCard({ p }: { p: PortalEntry }) {
  const ref = useRef<HTMLAnchorElement>(null);
  const [hover, setHover] = useState(false);
  const [pos, setPos] = useState({ x: 0, y: 0 });

  const onMove = useCallback((e: React.MouseEvent<HTMLAnchorElement>) => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    setPos({
      x: (e.clientX - r.left - r.width / 2) / r.width,
      y: (e.clientY - r.top - r.height / 2) / r.height,
    });
  }, []);

  const Icon = p.icon;
  return (
    <Link
      href={p.href}
      ref={ref}
      data-cursor="Enter →"
      onMouseMove={onMove}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => { setHover(false); setPos({ x: 0, y: 0 }); }}
      className="lift"
      style={{
        position: "relative", display: "block",
        borderRadius: 28, overflow: "hidden",
        transform: hover ? `translate3d(${pos.x * 8}px, ${pos.y * 8 - 2}px, 0)` : "translate3d(0,0,0)",
        transition: "transform 0.45s cubic-bezier(.2,0,0,1), box-shadow 0.45s cubic-bezier(.2,0,0,1)",
      }}
    >
      <div
        aria-hidden
        style={{
          position: "absolute", inset: -1,
          opacity: hover ? 0.85 : 0.25,
          transition: "opacity 0.6s ease",
          background: `radial-gradient(ellipse 80% 60% at ${50 + pos.x * 30}% ${10 + pos.y * 20}%, ${p.hue} 0%, transparent 65%)`,
          filter: "blur(36px)",
          pointerEvents: "none",
        }}
      />

      <div
        className="glass glass-highlight"
        style={{
          position: "relative", borderRadius: 28,
          padding: "36px 36px 32px",
          height: "100%", minHeight: 320,
        }}
      >
        <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between" }}>
          <div
            style={{
              width: 56, height: 56, borderRadius: 16,
              display: "flex", alignItems: "center", justifyContent: "center",
              background: `linear-gradient(135deg, color-mix(in oklch, ${p.hue} 22%, transparent), transparent)`,
              border: `1px solid color-mix(in oklch, ${p.hue} 30%, transparent)`,
              boxShadow: `0 0 24px -8px color-mix(in oklch, ${p.hue} 60%, transparent)`,
            }}
          >
            <Icon size={22} strokeWidth={1.5} style={{ color: p.hue }} />
          </div>
          <div
            className="font-mono"
            style={{
              fontSize: 11, letterSpacing: "0.22em",
              textTransform: "uppercase", color: "var(--color-fg-subtle)",
              display: "flex", alignItems: "center", gap: 14,
            }}
          >
            <span style={{ color: p.hue, fontSize: 13, letterSpacing: "0.18em" }}>{p.n}</span>
            <span>{p.section}</span>
            <ArrowUpRight
              size={14}
              style={{
                color: "var(--color-fg-subtle)",
                transform: hover ? "translate(2px,-2px)" : "translate(0,0)",
                transition: "transform 0.3s ease",
              }}
            />
          </div>
        </div>

        <h3
          className="font-display"
          style={{
            marginTop: 40, marginBottom: 0,
            fontSize: 36, fontWeight: 300, lineHeight: 1.05, letterSpacing: "-0.03em",
          }}
        >
          {p.title}
        </h3>

        <p
          style={{
            marginTop: 14, marginBottom: 24,
            fontSize: 16, lineHeight: 1.6,
            color: "var(--color-fg-muted)", maxWidth: "44ch",
          }}
        >
          {p.body}
        </p>

        <ul
          style={{
            listStyle: "none", padding: 0, margin: 0,
            display: "flex", flexWrap: "wrap", gap: 6,
          }}
        >
          {p.chips.map((c) => (
            <li
              key={c}
              className="font-mono"
              style={{
                fontSize: 11, letterSpacing: "0.04em",
                padding: "6px 12px", borderRadius: 999,
                background: "var(--glass-bg)", border: "1px solid var(--glass-border)",
                color: "var(--color-fg-muted)",
              }}
            >
              {c}
            </li>
          ))}
        </ul>

        <div
          aria-hidden
          style={{
            position: "absolute", left: 36, right: 36, bottom: 18,
            height: 1, background: "var(--glass-border)", overflow: "hidden",
          }}
        >
          <div
            style={{
              position: "absolute", inset: 0,
              background: `linear-gradient(90deg, transparent, ${p.hue}, transparent)`,
              transform: hover ? "translateX(0)" : "translateX(-110%)",
              transition: "transform 0.9s cubic-bezier(.2,0,0,1)",
            }}
          />
        </div>
      </div>
    </Link>
  );
}

function PortalGrid() {
  return (
    <section style={{ position: "relative", zIndex: 2, padding: "100px 0 120px" }}>
      <div className="container">
        <Reveal>
          <div
            style={{
              display: "flex", alignItems: "baseline", justifyContent: "space-between",
              flexWrap: "wrap", gap: 24, marginBottom: 36,
            }}
          >
            <div>
              <div className="eyebrow">02 — Four interfaces · One database</div>
              <h2
                className="font-display"
                style={{
                  marginTop: 16, marginBottom: 0,
                  fontSize: "clamp(38px, 5vw, 64px)",
                  fontWeight: 300, letterSpacing: "-0.035em", lineHeight: 1.05,
                  maxWidth: "20ch",
                }}
              >
                One schema. Four lenses pointed at it.
              </h2>
            </div>
            <p
              style={{
                maxWidth: 360, fontSize: 16,
                color: "var(--color-fg-muted)", lineHeight: 1.55,
              }}
            >
              Each portal is RLS-scoped against a single Postgres database. Hospitals
              write, the engine evaluates, officers approve, the public observatory
              reads. Same rows, different masks.
            </p>
          </div>
        </Reveal>

        <Reveal delay={80}>
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(2, 1fr)",
              gap: 14,
            }}
          >
            {PORTALS.map((p) => <PortalCard key={p.href} p={p} />)}
          </div>
        </Reveal>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ *
 *  Pipeline                                                            *
 * ------------------------------------------------------------------ */
function Pipeline() {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => {
      if (e.isIntersecting) { el.classList.add("in"); io.disconnect(); }
    }, { threshold: 0.35 });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  const STEPS = [
    { icon: Hospital,    label: "Hospital",  sub: "submits · PENDING",   hue: HUE.emerald },
    { icon: Brain,       label: "AI Engine", sub: "scores · transitions", hue: HUE.steel },
    { icon: ShieldCheck, label: "Officer",   sub: "reviews · FLAGGED",    hue: HUE.violet },
    { icon: FileCheck2,  label: "B-Form",    sub: "ready · for parent",   hue: HUE.amber },
  ];

  return (
    <section style={{ position: "relative", zIndex: 2, padding: "60px 0 120px" }}>
      <div className="container">
        <Reveal>
          <div className="eyebrow">03 — End-to-end pipeline</div>
          <h2
            className="font-display"
            style={{
              marginTop: 16, marginBottom: 0,
              fontSize: "clamp(34px, 4.6vw, 58px)",
              fontWeight: 300, fontStyle: "italic",
              letterSpacing: "-0.03em", lineHeight: 1.06,
              maxWidth: "28ch",
            }}
          >
            From the delivery room to the parent&apos;s hand —{" "}
            <span style={{ fontStyle: "normal", color: "var(--color-accent)" }}>
              in under 60 seconds.
            </span>
          </h2>
        </Reveal>

        <Reveal delay={120}>
          <div
            ref={ref}
            className="glass glass-highlight pipeline"
            style={{
              marginTop: 56, borderRadius: 28,
              padding: "56px 48px 48px", position: "relative",
            }}
          >
            <svg
              viewBox="0 0 1200 220"
              preserveAspectRatio="none"
              style={{ width: "100%", height: 220, display: "block" }}
              aria-hidden
            >
              <defs>
                <linearGradient id="pipeGrad" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%" stopColor="oklch(0.78 0.16 158)" />
                  <stop offset="33%" stopColor="oklch(0.7 0.16 220)" />
                  <stop offset="66%" stopColor="oklch(0.75 0.14 280)" />
                  <stop offset="100%" stopColor="oklch(0.78 0.12 80)" />
                </linearGradient>
                <filter id="pipeGlow"><feGaussianBlur stdDeviation="3" /></filter>
              </defs>

              <path
                d="M 80 110 C 280 110, 280 110, 480 110 S 720 110, 880 110 S 1120 110, 1120 110"
                stroke="oklch(1 0 0 / 0.07)" strokeWidth="1" fill="none"
              />
              <path
                className="pipeline-path"
                d="M 80 110 C 280 110, 280 110, 480 110 S 720 110, 880 110 S 1120 110, 1120 110"
                stroke="url(#pipeGrad)" strokeWidth="1.5" fill="none"
                strokeLinecap="round"
              />
              <path
                className="pipeline-path"
                d="M 80 110 C 280 110, 280 110, 480 110 S 720 110, 880 110 S 1120 110, 1120 110"
                stroke="url(#pipeGrad)" strokeWidth="6" fill="none"
                opacity="0.32" filter="url(#pipeGlow)"
              />

              {[80, 426, 773, 1120].map((x) => (
                <g key={x}>
                  <circle cx={x} cy={110} r={6} fill="oklch(0.13 0.005 240)" stroke="url(#pipeGrad)" strokeWidth="1.5" />
                  <circle cx={x} cy={110} r={2.4} fill="url(#pipeGrad)" />
                </g>
              ))}
            </svg>

            <div
              style={{
                display: "grid", gridTemplateColumns: "repeat(4, 1fr)",
                gap: 18, marginTop: -100, position: "relative", zIndex: 2,
              }}
            >
              {STEPS.map((s, i) => {
                const Icon = s.icon;
                return (
                  <div key={s.label} style={{ textAlign: "center", padding: "0 12px" }}>
                    <div
                      style={{
                        width: 56, height: 56, borderRadius: 18,
                        display: "inline-flex", alignItems: "center", justifyContent: "center",
                        background: `linear-gradient(135deg, color-mix(in oklch, ${s.hue} 18%, transparent), oklch(0.13 0.005 240))`,
                        border: `1px solid color-mix(in oklch, ${s.hue} 35%, transparent)`,
                        boxShadow: `0 0 30px -6px color-mix(in oklch, ${s.hue} 50%, transparent)`,
                      }}
                    >
                      <Icon size={22} strokeWidth={1.5} style={{ color: s.hue }} />
                    </div>
                    <div
                      className="font-mono"
                      style={{
                        marginTop: 16, fontSize: 11, letterSpacing: "0.18em",
                        textTransform: "uppercase", color: s.hue, opacity: 0.9,
                      }}
                    >
                      {String(i + 1).padStart(2, "0")}
                    </div>
                    <div
                      className="font-display"
                      style={{
                        marginTop: 6, fontSize: 22, fontWeight: 300, letterSpacing: "-0.025em",
                      }}
                    >
                      {s.label}
                    </div>
                    <div
                      className="font-mono"
                      style={{
                        marginTop: 6, fontSize: 11, letterSpacing: "0.12em",
                        textTransform: "uppercase", color: "var(--color-fg-subtle)",
                      }}
                    >
                      {s.sub}
                    </div>
                  </div>
                );
              })}
            </div>

            <div
              style={{
                display: "grid", gridTemplateColumns: "repeat(4, 1fr)",
                marginTop: 44, gap: 18,
                borderTop: "1px solid var(--glass-border)", paddingTop: 28,
              }}
            >
              {[
                { l: "row inserted",    r: "births" },
                { l: "rules evaluated", r: "8 signals" },
                { l: "decision",        r: "verify · reject · flag" },
                { l: "issued",          r: "B-Form PDF + audit" },
              ].map((c) => (
                <div key={c.l}>
                  <div
                    className="font-mono"
                    style={{
                      fontSize: 10, letterSpacing: "0.22em",
                      textTransform: "uppercase", color: "var(--color-fg-subtle)",
                    }}
                  >
                    {c.l}
                  </div>
                  <div style={{ marginTop: 6, fontSize: 14, color: "var(--color-fg)" }}>{c.r}</div>
                </div>
              ))}
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ *
 *  Demo accounts                                                      *
 * ------------------------------------------------------------------ */
type Account = { letter: string; name: string; role: string; email: string; hue: string };

function AccountCard({ a }: { a: Account }) {
  const [copied, setCopied] = useState(false);
  const onCopy = () => {
    if (typeof navigator !== "undefined" && navigator.clipboard) {
      navigator.clipboard.writeText(a.email);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  };
  return (
    <div
      className="glass glass-highlight lift"
      style={{
        borderRadius: 24, padding: 28,
        display: "flex", flexDirection: "column", gap: 24,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
        <div
          style={{
            width: 56, height: 56, borderRadius: 16,
            display: "flex", alignItems: "center", justifyContent: "center",
            background: `linear-gradient(135deg, color-mix(in oklch, ${a.hue} 60%, transparent), color-mix(in oklch, ${a.hue} 18%, transparent))`,
            border: `1px solid color-mix(in oklch, ${a.hue} 35%, transparent)`,
            color: "var(--color-bg)", fontWeight: 700,
            fontFamily: "var(--font-display)", fontSize: 24, fontStyle: "italic",
          }}
        >
          {a.name.split(" ").map((p) => p[0]).join("").slice(0, 2)}
        </div>
        <div>
          <div
            className="font-mono"
            style={{
              fontSize: 10, letterSpacing: "0.22em",
              textTransform: "uppercase", color: a.hue, opacity: 0.9,
            }}
          >
            {a.role}
          </div>
          <div style={{ marginTop: 4, fontSize: 17, fontWeight: 500, letterSpacing: "-0.01em" }}>
            {a.name}
          </div>
        </div>
      </div>

      <div
        style={{
          display: "flex", alignItems: "center",
          justifyContent: "space-between", gap: 12,
        }}
      >
        <div className="font-mono" style={{ fontSize: 13, color: "var(--color-fg-muted)" }}>
          {a.email}
        </div>
        <button
          type="button"
          onClick={onCopy}
          data-cursor={copied ? "Copied" : "Copy"}
          className="font-mono"
          style={{
            display: "inline-flex", alignItems: "center", gap: 8,
            padding: "8px 12px", borderRadius: 999,
            background: copied
              ? "color-mix(in oklch, var(--color-accent) 18%, transparent)"
              : "var(--glass-bg)",
            border: `1px solid ${copied ? "color-mix(in oklch, var(--color-accent) 50%, transparent)" : "var(--glass-border)"}`,
            fontSize: 11, letterSpacing: "0.16em", textTransform: "uppercase",
            color: copied ? "var(--color-accent)" : "var(--color-fg-muted)",
            transition: "all 0.25s ease",
            cursor: "pointer",
          }}
        >
          {copied ? <Check size={12} strokeWidth={2.4} /> : <Copy size={12} strokeWidth={1.8} />}
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
    </div>
  );
}

function DemoAccounts() {
  const ACCOUNTS: Account[] = useMemo(() => [
    { letter: "A", name: "Aku Naveed", role: "Hospital staff", email: "aku@nbrpts.demo",   hue: HUE.emerald },
    { letter: "A", name: "Aisha Khan", role: "NADRA officer",  email: "aisha@nbrpts.demo", hue: HUE.violet  },
    { letter: "A", name: "Admin",      role: "System admin",   email: "admin@nbrpts.demo", hue: HUE.steel   },
  ], []);

  return (
    <section style={{ position: "relative", zIndex: 2, padding: "60px 0 120px" }}>
      <div className="container">
        <Reveal>
          <div
            style={{
              display: "flex", alignItems: "baseline", justifyContent: "space-between",
              flexWrap: "wrap", gap: 24, marginBottom: 36,
            }}
          >
            <div>
              <div className="eyebrow">04 — Demo accounts</div>
              <h2
                className="font-display"
                style={{
                  marginTop: 16, marginBottom: 0,
                  fontSize: "clamp(34px, 4.4vw, 56px)",
                  fontWeight: 300, letterSpacing: "-0.03em",
                  lineHeight: 1.05, maxWidth: "20ch",
                }}
              >
                Sign in as anyone in the loop.
              </h2>
            </div>
            <div
              className="font-mono"
              style={{
                padding: "10px 14px", borderRadius: 999,
                background: "var(--glass-bg)", border: "1px solid var(--glass-border)",
                fontSize: 11, letterSpacing: "0.18em", textTransform: "uppercase",
                color: "var(--color-fg-muted)",
              }}
            >
              Password · <span style={{ color: "var(--color-accent)" }}>demo1234</span>
            </div>
          </div>
        </Reveal>

        <Reveal delay={120}>
          <div
            style={{
              display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14,
            }}
          >
            {ACCOUNTS.map((a) => <AccountCard key={a.email} a={a} />)}
          </div>
        </Reveal>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ *
 *  Architecture preview                                                *
 * ------------------------------------------------------------------ */
function Architecture() {
  const tables = [
    { id: "facility",     x: 60,  y: 60,  w: 220, label: "facility",         col: "id · name · district · province",       hue: HUE.emerald },
    { id: "mother",       x: 60,  y: 230, w: 220, label: "mother",           col: "cnic · name · age · district",          hue: HUE.emerald },
    { id: "father",       x: 60,  y: 400, w: 220, label: "father",           col: "cnic · name",                            hue: HUE.emerald },
    { id: "births",       x: 360, y: 220, w: 280, label: "births",           col: "id · facility_id · mother_cnic · status", hue: "var(--color-accent)" },
    { id: "ai_log",       x: 720, y: 60,  w: 220, label: "ai_review_log",    col: "birth_id · score · rules · decision",   hue: HUE.steel },
    { id: "officer_act",  x: 720, y: 230, w: 220, label: "officer_actions",  col: "officer_id · birth_id · type · reason", hue: HUE.violet },
    { id: "bform",        x: 720, y: 400, w: 220, label: "b_form",           col: "birth_id · serial · issued_at",         hue: HUE.amber },
  ];
  const VB_W = 1000, VB_H = 540;

  const links: Array<[string, string, "L" | "R"]> = [
    ["facility",    "births", "L"],
    ["mother",      "births", "L"],
    ["father",      "births", "L"],
    ["ai_log",      "births", "R"],
    ["officer_act", "births", "R"],
    ["bform",       "births", "R"],
  ];

  return (
    <section style={{ position: "relative", zIndex: 2, padding: "60px 0 120px" }}>
      <div className="container">
        <Reveal>
          <div
            style={{
              display: "grid", gridTemplateColumns: "1.1fr 1fr",
              gap: 80, alignItems: "end", marginBottom: 36,
            }}
          >
            <div>
              <div className="eyebrow">05 — Architecture</div>
              <h2
                className="font-display"
                style={{
                  marginTop: 16, marginBottom: 0,
                  fontSize: "clamp(38px, 5vw, 68px)",
                  fontWeight: 300, letterSpacing: "-0.035em", lineHeight: 1.04,
                  maxWidth: "22ch",
                }}
              >
                The schema is the product.
              </h2>
            </div>
            <div
              className="font-mono"
              style={{
                fontSize: 13, color: "var(--color-fg-muted)",
                letterSpacing: "0.04em", lineHeight: 1.7,
              }}
            >
              13 tables · 12 enums · 24 indexes · 86 seed rows<br />
              Third normal form · 19 sequential migrations<br />
              <span style={{ color: "var(--color-fg-subtle)" }}>
                // every constraint is named. every trigger is observable.
              </span>
            </div>
          </div>
        </Reveal>

        <Reveal delay={120}>
          <div
            className="glass glass-highlight"
            style={{
              borderRadius: 28, padding: "32px 28px",
              position: "relative", overflow: "hidden",
            }}
          >
            <svg viewBox={`0 0 ${VB_W} ${VB_H}`} style={{ width: "100%", height: "auto", display: "block" }}>
              <defs>
                <linearGradient id="erLine" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%" stopColor="oklch(1 0 0 / 0)" />
                  <stop offset="50%" stopColor="oklch(0.78 0.16 158 / 0.5)" />
                  <stop offset="100%" stopColor="oklch(1 0 0 / 0)" />
                </linearGradient>
              </defs>

              {links.map(([fromId, toId, side]) => {
                const from = tables.find((t) => t.id === fromId);
                const to = tables.find((t) => t.id === toId);
                if (!from || !to) return null;
                const fromY = from.y + 28;
                const toY = to.y + 28;
                const x1 = side === "L" ? from.x + from.w : from.x;
                const x2 = side === "L" ? to.x : to.x + to.w;
                const cx = (x1 + x2) / 2;
                const d = `M ${x1} ${fromY} C ${cx} ${fromY}, ${cx} ${toY}, ${x2} ${toY}`;
                return (
                  <g key={fromId + toId}>
                    <path d={d} stroke="oklch(1 0 0 / 0.1)" strokeWidth="1" fill="none" />
                    <path d={d} stroke="url(#erLine)" strokeWidth="1.5" fill="none" />
                  </g>
                );
              })}

              {tables.map((t) => {
                const isCenter = t.id === "births";
                const stroke = isCenter ? "var(--color-accent)" : "oklch(1 0 0 / 0.16)";
                return (
                  <g key={t.id}>
                    <rect
                      x={t.x} y={t.y} width={t.w} height={56} rx={10}
                      fill="oklch(0.165 0.006 240 / 0.6)"
                      stroke={stroke}
                      strokeWidth={isCenter ? 1.5 : 1}
                    />
                    {isCenter && (
                      <rect
                        x={t.x - 4} y={t.y - 4} width={t.w + 8} height={64} rx={14}
                        fill="none" stroke="oklch(0.78 0.16 158 / 0.18)" strokeWidth={1}
                      />
                    )}
                    <circle cx={t.x + 14} cy={t.y + 22} r={3} fill={isCenter ? "var(--color-accent)" : t.hue} />
                    <text x={t.x + 26} y={t.y + 22} fontFamily="JetBrains Mono" fontSize="13"
                      fill="var(--color-fg)" style={{ letterSpacing: 0.5 }} dominantBaseline="middle">
                      {t.label}
                    </text>
                    <text x={t.x + 14} y={t.y + 42} fontFamily="JetBrains Mono" fontSize="10"
                      fill="var(--color-fg-subtle)" style={{ letterSpacing: 0.3 }} dominantBaseline="middle">
                      {t.col}
                    </text>
                  </g>
                );
              })}
            </svg>

            <div
              style={{
                display: "grid", gridTemplateColumns: "repeat(4, 1fr)",
                gap: 18, marginTop: 24,
                borderTop: "1px solid var(--glass-border)", paddingTop: 22,
              }}
            >
              {[
                ["13", "Tables in 3NF"],
                ["12", "Enum types"],
                ["24", "Indexes"],
                ["19", "Migrations"],
              ].map(([v, l]) => (
                <div key={l}>
                  <div
                    className="font-display"
                    style={{ fontSize: 28, fontWeight: 300, letterSpacing: "-0.025em" }}
                  >
                    {v}
                  </div>
                  <div
                    className="font-mono"
                    style={{
                      marginTop: 4, fontSize: 10, letterSpacing: "0.22em",
                      textTransform: "uppercase", color: "var(--color-fg-subtle)",
                    }}
                  >
                    {l}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </Reveal>

        <Reveal delay={200}>
          <div style={{ marginTop: 18, display: "flex", gap: 12, flexWrap: "wrap" }}>
            <Link
              href="/dev/schema"
              data-cursor="ER →"
              className="glass lift"
              style={{
                display: "inline-flex", alignItems: "center", gap: 10,
                padding: "12px 18px", borderRadius: 999,
                fontSize: 14, color: "var(--color-fg)",
              }}
            >
              Browse the live ER diagram <ArrowUpRight size={14} />
            </Link>
            <Link
              href="/dev/triggers"
              data-cursor="Triggers →"
              className="glass lift"
              style={{
                display: "inline-flex", alignItems: "center", gap: 10,
                padding: "12px 18px", borderRadius: 999,
                fontSize: 14, color: "var(--color-fg)",
              }}
            >
              Open the trigger lab <ArrowUpRight size={14} />
            </Link>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ *
 *  Closing CTA                                                        *
 * ------------------------------------------------------------------ */
function ClosingCTA() {
  return (
    <section style={{ position: "relative", zIndex: 2, padding: "120px 0 120px" }}>
      <div style={{ position: "absolute", inset: 0, pointerEvents: "none" }} aria-hidden>
        <div
          style={{
            position: "absolute", left: "50%", top: "50%",
            transform: "translate(-50%, -50%)",
            width: "70vw", height: "70vw", maxWidth: 900, maxHeight: 900,
            background: "radial-gradient(circle at center, oklch(0.78 0.16 158 / 0.22), transparent 60%)",
            filter: "blur(60px)",
          }}
        />
      </div>
      <div className="container" style={{ position: "relative", zIndex: 2, textAlign: "center" }}>
        <Reveal>
          <div
            className="eyebrow"
            style={{
              display: "inline-block", padding: "8px 14px", borderRadius: 999,
              background: "var(--glass-bg)", border: "1px solid var(--glass-border)",
            }}
          >
            06 — In closing
          </div>
        </Reveal>
        <Reveal delay={80}>
          <h2
            className="font-display"
            style={{
              margin: "32px auto 0",
              fontSize: "clamp(48px, 8vw, 112px)",
              fontWeight: 300, letterSpacing: "-0.04em", lineHeight: 0.98,
              maxWidth: "16ch",
            }}
          >
            Built in <span style={{ fontStyle: "italic", color: "var(--color-accent)" }}>10 phases</span>.
            Every query observable.
          </h2>
        </Reveal>
        <Reveal delay={160}>
          <div
            style={{
              marginTop: 56, display: "flex", flexWrap: "wrap", gap: 14,
              justifyContent: "center",
            }}
          >
            <Link
              href="/dev"
              data-cursor="Open →"
              className="accent-glow lift"
              style={{
                display: "inline-flex", alignItems: "center", gap: 10,
                padding: "20px 32px", borderRadius: 9999,
                background: "linear-gradient(135deg, var(--color-accent), var(--color-accent-strong))",
                color: "var(--color-accent-fg)",
                fontSize: 16, fontWeight: 600,
              }}
            >
              Open the observatory
              <ArrowRight size={16} strokeWidth={2} />
            </Link>
            <a
              href="https://github.com/ruufaayl/nbrpts/blob/main/deliverables/NBRPTS_Report.pdf"
              target="_blank" rel="noreferrer"
              data-cursor="PDF"
              className="glass lift"
              style={{
                display: "inline-flex", alignItems: "center", gap: 10,
                padding: "20px 30px", borderRadius: 9999,
                fontSize: 16, fontWeight: 500, color: "var(--color-fg)",
              }}
            >
              Read the report PDF
              <ArrowUpRight size={16} strokeWidth={2} />
            </a>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ *
 *  Footer                                                              *
 * ------------------------------------------------------------------ */
function Footer() {
  return (
    <footer
      style={{
        position: "relative", zIndex: 2, padding: "60px 0 60px",
        borderTop: "1px solid var(--glass-border)",
      }}
    >
      <div
        className="container"
        style={{
          display: "grid", gridTemplateColumns: "1fr 1.5fr auto",
          gap: 40, alignItems: "start",
        }}
      >
        <div>
          <div
            className="font-display"
            style={{
              fontSize: 28, fontWeight: 300, letterSpacing: "-0.04em",
              display: "flex", alignItems: "center", gap: 10,
            }}
          >
            <span
              style={{
                width: 10, height: 10, borderRadius: 3,
                background: "linear-gradient(135deg, var(--color-accent), var(--color-accent-strong))",
                boxShadow: "0 0 12px var(--color-accent-glow)",
              }}
            />
            NBRPTS
          </div>
          <div
            className="font-mono"
            style={{
              marginTop: 10, fontSize: 11, letterSpacing: "0.22em",
              textTransform: "uppercase", color: "var(--color-fg-subtle)",
            }}
          >
            National Birth Registry &<br />Population Tracking System
          </div>
        </div>

        <div
          style={{
            fontSize: 14, lineHeight: 1.7,
            color: "var(--color-fg-muted)", maxWidth: 520,
          }}
        >
          Built with Next.js 16, Supabase Postgres, and a deterministic rules
          engine. Every screen, every portal, every query observable.
          <div style={{ marginTop: 16, fontSize: 12, color: "var(--color-fg-subtle)" }}>
            CS2013 · Introduction to Database Systems · FAST-NUCES Spring 2026
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 10, alignItems: "flex-end" }}>
          <a
            href="https://github.com/ruufaayl/nbrpts"
            target="_blank" rel="noreferrer"
            data-cursor="GitHub"
            className="glass lift"
            style={{
              display: "inline-flex", alignItems: "center", gap: 10,
              padding: "10px 16px", borderRadius: 999, fontSize: 13,
            }}
          >
            <Code2 size={14} /> ruufaayl/nbrpts
          </a>
          <Link
            href="/login"
            data-cursor="Sign in"
            style={{
              fontSize: 12, color: "var(--color-fg-subtle)", letterSpacing: "0.06em",
            }}
          >
            sign in →
          </Link>
        </div>
      </div>
    </footer>
  );
}

/* ------------------------------------------------------------------ *
 *  Page chrome                                                         *
 * ------------------------------------------------------------------ */
function PageCurtain() {
  const [out, setOut] = useState(false);
  useEffect(() => {
    const t = setTimeout(() => setOut(true), 1100);
    return () => clearTimeout(t);
  }, []);
  return (
    <div className={"curtain " + (out ? "out" : "")} aria-hidden>
      <div className="curtain__mark">
        NBRPTS<span style={{ color: "var(--color-accent)", fontStyle: "normal" }}>.</span>
      </div>
    </div>
  );
}

function ScrollProgress() {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const onScroll = () => {
      const h = document.documentElement;
      const k = h.scrollTop / Math.max(1, h.scrollHeight - h.clientHeight);
      if (ref.current) ref.current.style.transform = `scaleX(${Math.min(1, Math.max(0, k))})`;
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener("scroll", onScroll);
  }, []);
  return <div ref={ref} className="scroll-progress" aria-hidden />;
}

/* ------------------------------------------------------------------ *
 *  Page export                                                         *
 * ------------------------------------------------------------------ */
export default function Home() {
  // Lock body to immersive cursor while this page is mounted.
  useEffect(() => {
    document.body.classList.add("cursor-immersive");
    return () => document.body.classList.remove("cursor-immersive");
  }, []);

  return (
    <main style={{ position: "relative", overflow: "hidden" }}>
      <div className="bg-video" aria-hidden>
        <div className="bg-video__layer l1" />
        <div className="bg-video__layer l2" />
        <div className="bg-video__layer l3" />
      </div>
      <div className="color-grade" aria-hidden />
      <div className="film-grain" aria-hidden />
      <ScrollProgress />
      <PageCurtain />
      <CustomCursor />

      <Hero />
      <Marquee />
      <CounterStrip />
      <Problem />
      <PortalGrid />
      <Pipeline />
      <DemoAccounts />
      <Architecture />
      <ClosingCTA />
      <Footer />
    </main>
  );
}
