import { DeviceSimulator } from "./device-simulator";

export const dynamic = "force-dynamic";

export default function DevicePage() {
  return (
    <main className="mx-auto max-w-5xl px-6 py-10">
      <div>
        <h1 className="text-3xl font-medium tracking-tight md:text-4xl">
          Hospital device simulator
        </h1>
        <p className="mt-2 max-w-2xl text-sm text-[var(--color-fg-muted)]">
          The proposal calls for a tamper-proof, offline-first hardware device
          at every registered hospital. This page simulates one in your
          browser. Toggle the connection state, queue records while
          "offline," and watch them sync to NADRA when you're back online.
          The local store is IndexedDB.
        </p>
      </div>

      <div className="mt-10">
        <DeviceSimulator />
      </div>
    </main>
  );
}
