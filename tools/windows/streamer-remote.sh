#!/usr/bin/env bash
# streamer-remote.sh — one Mac-side command to drive the Windows laptop's PaintStreamer
# (STREAM.md §7 stage 3, deliverable 5). Wraps the SSH line every worker/orchestrator
# session already uses, plus the tar-and-build step "deploy" needs before it can hand
# off to tools/windows/streamer.ps1 on the other end.
#
# Usage:
#   tools/windows/streamer-remote.sh start|stop|status|sources
#   tools/windows/streamer-remote.sh log [n]
#   tools/windows/streamer-remote.sh deploy [--source <worktree>]   # tar/scp + build + publish + restart
#   tools/windows/streamer-remote.sh install                        # first-time: firewall + scheduled task
#   tools/windows/streamer-remote.sh test                           # dotnet test on the laptop
#   tools/windows/streamer-remote.sh raw '<powershell>'             # escape hatch
#
# IMPORTANT: PC's login shell on the laptop IS PowerShell 5.1 (sshd's default shell for
# that account), so the ssh command argument is fed straight to powershell.exe — do NOT
# wrap it in `powershell -Command "..."` again, which just adds a second, conflicting
# layer of quoting (found the hard way: "The string is missing the terminator" on the
# first real deploy attempt).
#
# All state (source, published app, task) lives on the laptop; this script has none of
# its own beyond the SSH connection details below. streamer.ps1 itself is staged once
# per deploy to C:\Users\PC\src\streamer-tools (outside the source tree it drives, so
# a re-tar of streamer/ never clobbers the copy currently running).
set -euo pipefail

SSH_KEY="${PAINTSTREAMER_SSH_KEY:-$HOME/.ssh/paintapp_windows}"
HOST="${PAINTSTREAMER_HOST:-PC@100.104.85.111}"
DOTNET_EXE="${PAINTSTREAMER_DOTNET_EXE:-C:\\dotnet\\dotnet.exe}"
REMOTE_TOOLS="C:\\Users\\PC\\src\\streamer-tools"
REMOTE_SRC="C:\\Users\\PC\\src\\streamer"

ssh_ps() {
    ssh -i "$SSH_KEY" -o BatchMode=yes -o LogLevel=ERROR "$HOST" "$1"
}

cmd="${1:-}"
shift || true

case "$cmd" in
    start|stop|status|sources)
        ssh_ps "powershell -ExecutionPolicy Bypass -File '$REMOTE_TOOLS\\streamer.ps1' $cmd"
        ;;
    log)
        n="${1:-50}"
        ssh_ps "powershell -ExecutionPolicy Bypass -File '$REMOTE_TOOLS\\streamer.ps1' log $n"
        ;;
    deploy)
        src="."
        if [[ "${1:-}" == "--source" ]]; then src="$2"; fi
        worktree_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
        if [[ "$src" == "." ]]; then src="$worktree_root"; fi

        tmp_tar="$(mktemp -t stream-payload).tar.gz"
        echo "== Taring streamer/, tools/windows and the AU-splitter fixture from $src =="
        # Streamer.Tests.csproj references the fixture by a relative path
        # (..\..\PaintSoftwareUITests\Fixtures\...) so it lands at the same path on
        # both sides -- shipping streamer/ alone and not this file makes `dotnet test`
        # fail at MSBuild's copy-to-output step with "could not copy ... was not found",
        # which looks like a missing file rather than an incomplete tar.
        #
        # COPYFILE_DISABLE=1 stops macOS's bsdtar from writing an AppleDouble "._Foo.cs"
        # sidecar for every file carrying an xattr (this Mac tags files it creates with
        # com.apple.provenance, so this is every .cs file, not a stray few) — found for
        # real on stage 4's first deploy: `dotnet publish` globs **/*.cs, so it compiled
        # both Foo.cs and the sidecar and failed the whole build on the sidecar with
        # "CS2015: ... is a binary file instead of a text file", against a source tree
        # that was otherwise perfectly fine.
        COPYFILE_DISABLE=1 tar czf "$tmp_tar" -C "$src" streamer tools/windows \
            PaintSoftwareUITests/Fixtures/stream-testsrc-640x360.h264

        echo "== Copying to the laptop via scp =="
        ssh_ps 'New-Item -ItemType Directory -Force -Path C:\Users\PC\src | Out-Null'
        scp -i "$SSH_KEY" -o BatchMode=yes -o LogLevel=ERROR "$tmp_tar" "$HOST:C:/Users/PC/src/stream-payload.tar.gz"
        rm -f "$tmp_tar"

        echo "== Extracting on the laptop and staging streamer-tools =="
        # NOTE: no path here may end the whole command string in a bare trailing
        # backslash — Windows OpenSSH's non-interactive exec wraps this argument in its
        # own closing double quote, and CommandLineToArgvW's escaping rule reads a
        # backslash-then-quote at that boundary as an ESCAPED quote, not a terminator
        # ("The string is missing the terminator" — hit this for real on the first
        # deploy attempt with a trailing "...streamer-tools\" here).
        ssh_ps 'Remove-Item -Recurse -Force C:\Users\PC\src\streamer -ErrorAction SilentlyContinue; tar xzf C:\Users\PC\src\stream-payload.tar.gz -C C:\Users\PC\src; Remove-Item C:\Users\PC\src\stream-payload.tar.gz; New-Item -ItemType Directory -Force -Path C:\Users\PC\src\streamer-tools | Out-Null; Copy-Item -Force C:\Users\PC\src\tools\windows\*.ps1 C:\Users\PC\src\streamer-tools'

        echo "== Running streamer.ps1 deploy on the laptop (publish + restart) =="
        ssh_ps "powershell -ExecutionPolicy Bypass -File '$REMOTE_TOOLS\\streamer.ps1' deploy -SourceDir '$REMOTE_SRC'"
        ;;
    install)
        echo "== Running install-streamer.ps1 on the laptop (first-time setup) =="
        echo "   (run 'deploy' at least once first, so streamer-tools + source exist)"
        ssh_ps "powershell -ExecutionPolicy Bypass -File '$REMOTE_TOOLS\\install-streamer.ps1' -SourceDir '$REMOTE_SRC'"
        ;;
    test)
        ssh_ps "& '$DOTNET_EXE' test '$REMOTE_SRC\\PaintStreamer.sln'"
        ;;
    raw)
        ssh_ps "$1"
        ;;
    *)
        echo "usage: $0 {start|stop|status|sources|log [n]|deploy [--source <dir>]|install|test|raw '<powershell>'}" >&2
        exit 1
        ;;
esac
