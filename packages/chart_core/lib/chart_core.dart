// PURPOSE: Mark the boundary of the ChartApp chart domain and state precisely what does and
//          does not live here, so that a later change does not quietly pull Flutter, a
//          database or a platform channel into the one package that must stay portable.
// INPUTS: None.
// OUTPUTS: A library with no public API in Phase 0. This is deliberate.
// KEYWORDS: chart-core, domain-boundary, pure-dart, phase-0, no-api-yet
//
// Phase 0 creates the package and nothing else. The domain types that belong here — the song
// model, chord grammar, transposition and the layout engine — are the subject of spikes S1
// (iReal codec), S3 (transposer) and S4 (layout), which are Phase 1 work.
//
// Inventing that API now, before those spikes have run, would fix the song model and the
// chord representation on a guess and then force the spikes to fit it rather than to inform
// it. The empty library is the honest state of the design at this point: the package exists
// so the workspace, the dependency graph and CI resolve it, and its contents land with the
// evidence that decides their shape.
//
// What this package must never depend on:
//   - flutter, or any package that requires a Flutter binding;
//   - storage_drift or any database package;
//   - ink_native or any platform channel.
//
// `dart test` must remain able to run every test in this package on a machine with no device,
// no emulator and no Android SDK. That property is what makes the domain cheap to verify and
// is the reason the dependency list above is empty.

/// Chart domain for ChartApp. No public API in Phase 0; see the file header for why.
library;
