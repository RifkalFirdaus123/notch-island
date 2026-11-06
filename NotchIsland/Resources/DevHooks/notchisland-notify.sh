#!/bin/sh
# Sends an event to NotchIsland's Dev tab, which shows it on the island.
#
#   notchisland-notify [-s ok|fail|attention|info] [-t SOURCE] TITLE [DETAIL]
#   notchisland-notify --claude        Claude Code hook (reads the hook JSON on stdin)
#   notchisland-notify --codex JSON    Codex `notify` program (JSON is the last argument)
#
# Events are small property lists dropped in ~/.notchisland/inbox; the app
# picks them up and deletes them. Nothing leaves this Mac.
set -u

INBOX="${NOTCHISLAND_HOME:-$HOME/.notchisland}/inbox"
mkdir -p "$INBOX" 2>/dev/null || exit 0

STATUS=info
SOURCE=shell
PAYLOAD=""

case "${1:-}" in
    --claude)
        SOURCE=claude
        PAYLOAD="$(cat)"
        shift
        ;;
    --codex)
        SOURCE=codex
        shift
        # Codex appends the JSON as the last argument.
        for arg in "$@"; do PAYLOAD="$arg"; done
        set --
        ;;
esac

while getopts "s:t:" opt 2>/dev/null; do
    case "$opt" in
        s) STATUS="$OPTARG" ;;
        t) SOURCE="$OPTARG" ;;
        *) ;;
    esac
done
shift $((OPTIND - 1))

TITLE="${1:-}"
DETAIL="${2:-}"
[ -z "$TITLE" ] && [ -z "$PAYLOAD" ] && exit 0

ID="$(date +%s)-$$-$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
TMP="$INBOX/.$ID.tmp"

plutil -create xml1 "$TMP" >/dev/null 2>&1 || exit 0
plutil -insert source -string "$SOURCE" "$TMP" >/dev/null 2>&1
plutil -insert status -string "$STATUS" "$TMP" >/dev/null 2>&1
plutil -insert cwd -string "$PWD" "$TMP" >/dev/null 2>&1
plutil -insert time -string "$(date +%s)" "$TMP" >/dev/null 2>&1
[ -n "$TITLE" ] && plutil -insert title -string "$TITLE" "$TMP" >/dev/null 2>&1
[ -n "$DETAIL" ] && plutil -insert detail -string "$DETAIL" "$TMP" >/dev/null 2>&1
[ -n "$PAYLOAD" ] && plutil -insert payload -string "$PAYLOAD" "$TMP" >/dev/null 2>&1

# Rename last so the app never reads a half-written file.
mv "$TMP" "$INBOX/$ID.plist"
exit 0
