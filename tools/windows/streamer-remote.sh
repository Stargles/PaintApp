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
        ssh_ps "powershell -NoProfile -Command \"& '$REMOTE_TOOLS\\streamer.ps1' $cmd\""
        ;;
    log)
        n="${1:-50}"
        ssh_ps "powershell -NoProfile -Command \"& '$REMOTE_TOOLS\\streamer.ps1' log $n\""
        ;;
    deploy)
        src="."
        if [[ "${1:-}" == "--source" ]]; then src="$2"; fi
        worktree_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
        if [[ "$src" == "." ]]; then src="$worktree_root"; fi

        tmp_tar="$(mktemp -t stream-payload).tar.gz"
        echo "== Taring streamer/ and tools/windows from $src =="
        tar czf "$tmp_tar" -C "$src" streamer tools/windows

        echo "== Copying to the laptop via scp =="
        ssh_ps 'powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path C:\Users\PC\src | Out-Null"'
        scp -i "$SSH_KEY" -o BatchMode=yes -o LogLevel=ERROR "$tmp_tar" "$HOST:C:/Users/PC/src/stream-payload.tar.gz"
        rm -f "$tmp_tar"

        echo "== Extracting on the laptop and staging streamer-tools =="
        ssh_ps 'powershell -NoProfile -Command "Remove-Item -Recurse -Force C:\Users\PC\src\streamer -ErrorAction SilentlyContinue; tar xzf C:\Users\PC\src\stream-payload.tar.gz -C C:\Users\PC\src; Remove-Item C:\Users\PC\src\stream-payload.tar.gz; New-Item -ItemType Directory -Force -Path C:\Users\PC\src\streamer-tools | Out-Null; Copy-Item -Force C:\Users\PC\src\tools\windows\*.ps1 C:\Users\PC\src\streamer-tools\"'

        echo "== Running streamer.ps1 deploy on the laptop (publish + restart) =="
        ssh_ps "powershell -NoProfile -Command \"& '$REMOTE_TOOLS\\streamer.ps1' deploy -SourceDir '$REMOTE_SRC'\""
        ;;
    install)
        echo "== Running install-streamer.ps1 on the laptop (first-time setup) =="
        echo "   (run 'deploy' at least once first, so streamer-tools + source exist)"
        ssh_ps "powershell -NoProfile -Command \"& '$REMOTE_TOOLS\\install-streamer.ps1' -SourceDir '$REMOTE_SRC'\""
        ;;
    test)
        ssh_ps "powershell -NoProfile -Command \"& '$DOTNET_EXE' test '$REMOTE_SRC\\PaintStreamer.sln'\""
        ;;
    raw)
        ssh_ps "$1"
        ;;
    *)
        echo "usage: $0 {start|stop|status|sources|log [n]|deploy [--source <dir>]|install|test|raw '<powershell>'}" >&2
        exit 1
        ;;
esac
