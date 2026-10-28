# Automatic renewal must retain the installed source

The iPad had verified Release `6fb979f4`, ahead of the managed clone’s `origin/main`.
The old renewal script always selected main, so renewing its signature could reinstall older code
and its older saved-file behavior.

The existing renewal state now records `LAST_SOURCE_SHA` after a successful install. Renewal selects
main when it contains that source; while main is older it selects the exact installed commit.
Unrelated, missing or invalid history refuses the build. The existing managed checkout, build paths,
strict signature check, five-day profile minimum and mint/retry rules remain the same. State updates
write a sibling temporary file and rename it atomically, preserving the prior record on failure.

The local script is `/Users/juliapark/PaintApp/deploy/resign.sh`. Its reviewed update is preserved in
[the exact patch](auto-resign-source-2026-10-28.patch). Apply only to original SHA256
`626a485d20df7d1f93cb205bb6fcdbd0d0dc398932c77bde6d4b8e173ea6df48`;
the resulting script is `655acf6732e5e22cdf42793f2e6932dc19dd12c2f678ed60d0820482f71e2b0c`.

`tools/test-resign-region.sh` tests the actual source/state helpers and actual post-install call,
local Git ancestry, failed installs, atomic write/rename failure, and all previous signing/profile
cases. Deliberately selecting old main, overwriting state in place, or recording the previous source
fails the corresponding assertions. Root reran the full harness successfully. ShellCheck was unavailable.

On October 28 root verified the installed artifact’s signature, executable hash and profile against
the installation receipt, imported its commit locally without changing the managed checkout, and
atomically seeded source, artifact path and the existing profile dates. The real selector retained
`6fb979f442f4d3da1299785de2a077a2058a4dfe`. The live dry run passed and reported 32 hours remaining.
No new build, install, environment or daemon change occurred. Activation evidence is under
`/Users/juliapark/PaintWork/s55-recorded-regressions/renewal-source-candidate/root-activation/`.

After every successful manual install, update all four existing state fields atomically from the
verified installed artifact: full source SHA, app path, profile expiry and creation. Import a private
branch commit into the managed clone first if necessary. Never advance this record before install
succeeds; never infer its source from the managed checkout’s current branch.
