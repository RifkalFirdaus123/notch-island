# NotchIsland: tells the island when a long terminal command finishes.
# Add this line to ~/.zshrc:
#
#   source ~/.notchisland/notchisland.zsh
#
# Settings (set them before the `source` line):
#   NOTCHISLAND_MIN_SECONDS   only commands that ran at least this long (default 10)
#   NOTCHISLAND_IGNORE        first words to skip (editors, pagers, shells, agents…)

zmodload zsh/datetime 2>/dev/null || return 0
autoload -Uz add-zsh-hook

typeset -g __notchisland_notify="${${(%):-%x}:A:h}/bin/notchisland-notify"
typeset -g __notchisland_cmd=""
typeset -gF __notchisland_start=0
: ${NOTCHISLAND_MIN_SECONDS:=10}
: ${NOTCHISLAND_IGNORE:="vim nvim vi nano emacs less more man ssh mosh top htop btop tmux screen watch tail claude codex gemini aider opencode python python3 node irb psql mysql sqlite3 redis-cli docker-compose"}

__notchisland_preexec() {
    __notchisland_cmd="$1"
    __notchisland_start=$EPOCHREALTIME
}

__notchisland_precmd() {
    local exit_code=$?
    (( __notchisland_start > 0 )) || return 0
    local cmd="$__notchisland_cmd"
    local -F elapsed=$(( EPOCHREALTIME - __notchisland_start ))
    __notchisland_cmd=""
    __notchisland_start=0

    (( elapsed >= NOTCHISLAND_MIN_SECONDS )) || return 0
    local first="${${(z)cmd}[1]}"
    [[ " $NOTCHISLAND_IGNORE " == *" ${first:t} "* ]] && return 0
    [[ -x "$__notchisland_notify" ]] || return 0

    local secs=${elapsed%.*} took
    if (( secs >= 3600 )); then took="$(( secs / 3600 ))h $(( secs % 3600 / 60 ))m"
    elif (( secs >= 60 )); then took="$(( secs / 60 ))m $(( secs % 60 ))s"
    else took="${secs}s"; fi

    if (( exit_code == 0 )); then
        "$__notchisland_notify" -s ok -t terminal "$cmd" "$took" &!
    else
        "$__notchisland_notify" -s fail -t terminal "$cmd" "exit $exit_code · $took" &!
    fi
}

add-zsh-hook preexec __notchisland_preexec
add-zsh-hook precmd __notchisland_precmd
