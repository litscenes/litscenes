# Desktop install entry

2026-09-28T20:44:00Z Owner chose build-from-source installation. Added the canonical source installer and README command. Installation uses the public repository, existing Development packager, selected Xcode toolchain, per-user Applications destination, signature verification, an installation lock, and staged copy. Existing app paths are refused; source/build output is retained and reported. No app launch or project mutation. The website will serve a small bootstrap pointing to this canonical script. Publication must precede website activation; no commit, push, release, or submodule pin change performed.

2026-09-28T20:50:00Z The existing app builds successfully with Command Line Tools (Swift 6.1.2, macOS SDK 15.5), so installer prerequisites now check the actual compiler and SDK instead of requiring full Xcode selection. Existing swift build and all 1,345 tests pass in the canonical working tree.

2026-09-28T20:50:16Z Final shell syntax, ShellCheck, source hygiene, and git diff whitespace checks pass. No REUSE executable is available. Existing build and 1,345 tests passed; the full installer was not executed into the owner’s Applications folder. Canonical installer and README are ready locally; publication remains pending. No commit, push, or release performed.

2026-09-29T02:03:43Z installer-publication: Owner explicitly authorized committing and pushing only the prepared source installer and installation documentation to public main as the website release prerequisite. Preserve unrelated Desktop work. Bash syntax and ShellCheck pass; current public main is 894045226270c8b0aec7a895db75ca08549aa588.
