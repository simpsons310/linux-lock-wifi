#!/usr/bin/env bash
# wifi-ap — list Wi-Fi access points and lock a connection to one of them.
#
# Usage:
#   wifi-ap                      interactive menu
#   wifi-ap list   [-a] [CONN]   table of access points (-a: all networks)
#   wifi-ap lock   [-b] [CONN]   pick an access point and lock to it (-b: strongest, no prompt)
#   wifi-ap unlock [CONN]        remove the lock
#   wifi-ap status [CONN]        show current connection, access point and lock
#
# CONN defaults to the active Wi-Fi connection.

set -uo pipefail

SEP=$'\x1f'

die()  { printf 'wifi-ap: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

need nmcli

# nmcli -t escapes ':' inside values as '\:'. Swap those for SEP before splitting.
unescape_terse() { sed "s/\\\\:/$SEP/g"; }
restore()        { printf '%s' "${1//$SEP/:}"; }
# nmcli -g escapes ':' and '\' with a backslash
unescape_get()   { sed 's/\\\(.\)/\1/g'; }

active_conn() {
    local name type
    while IFS=: read -r name type; do
        if [[ $type == 802-11-wireless ]]; then
            restore "$name"
            return 0
        fi
    done < <(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | unescape_terse)
    return 1
}

resolve_conn() {
    local conn=${1:-}
    if [[ -n $conn ]]; then
        nmcli -g connection.id connection show "$conn" >/dev/null 2>&1 \
            || die "no saved connection named '$conn'"
        printf '%s' "$conn"
        return
    fi
    active_conn || die "not connected to Wi-Fi (pass a connection name)"
}

conn_ssid()    { nmcli -g 802-11-wireless.ssid  connection show "$1" 2>/dev/null | unescape_get; }
locked_bssid() { nmcli -g 802-11-wireless.bssid connection show "$1" 2>/dev/null | unescape_get; }

current_bssid() {
    local active bssid
    while IFS=: read -r active bssid; do
        [[ $active == yes ]] && { restore "$bssid"; return; }
    done < <(nmcli -t -f ACTIVE,BSSID dev wifi list --rescan no 2>/dev/null | unescape_terse)
}

# Output, tab separated: bssid ssid chan freq signal security inuse
scan_aps() {
    local fields=IN-USE,BSSID,SSID,CHAN,FREQ,SIGNAL,SECURITY out
    info "Scanning..."
    out=$(nmcli -t -f "$fields" dev wifi list --rescan yes 2>/dev/null) \
        || out=$(nmcli -t -f "$fields" dev wifi list 2>/dev/null) \
        || die "scan failed"
    local inuse bssid ssid chan freq signal sec
    while IFS=: read -r inuse bssid ssid chan freq signal sec; do
        [[ -z $bssid ]] && continue
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$(restore "$bssid")" "$(restore "$ssid")" "$chan" "${freq%% *}" \
            "$signal" "$(restore "$sec")" "$inuse"
    done < <(printf '%s\n' "$out" | unescape_terse)
}

band_of() {
    local f=${1:-0}
    if   (( f >= 5925 )); then echo 6GHz
    elif (( f >= 4900 )); then echo 5GHz
    else echo 2.4GHz
    fi
}

bar_of() {
    local s=${1:-0} n i bar=
    n=$(( (s + 10) / 20 )); (( n > 5 )) && n=5; (( n < 0 )) && n=0
    for ((i = 0; i < 5; i++)); do
        if (( i < n )); then bar+='█'; else bar+='░'; fi
    done
    printf '%s' "$bar"
}

FMT='%-17s  %-6s  %4s  %s %3s%%  %-12s  %-22s  %s\n'

table_header() {
    printf '%-17s  %-6s  %4s  %-10s  %-12s  %-22s\n' BSSID BAND CH SIGNAL SECURITY SSID
}

# render_table SSID_FILTER LOCKED_BSSID  -> rows sorted strongest first
render_table() {
    local filter=$1 locked=${2^^}
    local bssid ssid chan freq signal sec inuse mark
    while IFS=$'\t' read -r bssid ssid chan freq signal sec inuse; do
        mark=
        [[ $inuse == '*' ]]         && mark+='● connected  '
        [[ ${bssid^^} == "$locked" ]] && mark+='◆ locked'
        printf "$FMT" "$bssid" "$(band_of "$freq")" "$chan" "$(bar_of "$signal")" \
            "$signal" "${sec:---}" "$ssid" "$mark"
    done < <(scan_aps | awk -F'\t' -v f="$filter" 'f == "" || $2 == f' | sort -t$'\t' -k5,5nr)
}

print_status() {
    local conn=$1 ssid locked current=
    ssid=$(conn_ssid "$conn")
    locked=$(locked_bssid "$conn")
    [[ $(active_conn) == "$conn" ]] && current=$(current_bssid)
    printf 'Connection : %s\n' "$conn"
    printf 'SSID       : %s\n' "$ssid"
    printf 'Connected  : %s\n' "${current:-not connected}"
    printf 'Locked to  : %s\n' "${locked:-not locked (free roaming)}"
}

cmd_status() {
    local conn
    conn=$(resolve_conn "${1:-}") || exit 1
    print_status "$conn"
}

cmd_list() {
    local all=0 conn= arg filter= locked=
    for arg in "$@"; do
        case $arg in
            -a|--all) all=1 ;;
            *) conn=$arg ;;
        esac
    done
    if (( ! all )); then
        if [[ -n $conn ]] || conn=$(active_conn); then
            conn=$(resolve_conn "$conn") || exit 1
            filter=$(conn_ssid "$conn")
            locked=$(locked_bssid "$conn")
            print_status "$conn"
            echo
        else
            info "Not connected; showing all networks."
        fi
    fi
    local rows
    rows=$(render_table "$filter" "$locked")
    [[ -z $rows ]] && die "no access points found${filter:+ for '$filter'}"
    table_header
    printf '%s\n' "$rows"
}

cmd_lock() {
    local best=0 conn= arg
    for arg in "$@"; do
        case $arg in
            -b|--best) best=1 ;;
            *) conn=$arg ;;
        esac
    done
    conn=$(resolve_conn "$conn") || exit 1

    local ssid locked rows choice bssid
    ssid=$(conn_ssid "$conn")
    locked=$(locked_bssid "$conn")
    rows=$(render_table "$ssid" "$locked")
    [[ -z $rows ]] && die "no access points found for '$ssid' (out of range?)"

    if (( best )); then
        choice=$(head -n1 <<<"$rows")
    else
        need fzf
        choice=$(fzf --layout=reverse --height=~60% --border \
                     --header="$(table_header)" \
                     --prompt="Lock '$ssid' to > " \
                     --info=hidden <<<"$rows") || { info "Cancelled."; exit 0; }
    fi

    bssid=${choice%% *}
    [[ $bssid =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || die "could not read BSSID from selection"

    nmcli connection modify "$conn" 802-11-wireless.bssid "$bssid" \
        || die "failed to set lock (try again with sudo)"
    info "Locked '$conn' to $bssid. Reconnecting..."

    if nmcli connection up "$conn" >/dev/null 2>&1; then
        info "Connected."
    else
        info "Could not connect to $bssid. Run 'wifi-ap unlock' to return to free roaming."
        exit 1
    fi
}

locked_profiles() {
    local name type b
    while IFS=: read -r name type; do
        [[ $type == 802-11-wireless ]] || continue
        name=$(restore "$name")
        b=$(locked_bssid "$name")
        [[ -n $b ]] && printf '%s\t%s\n' "$name" "$b"
    done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null | unescape_terse)
}

cmd_unlock() {
    local conn=${1:-}
    if [[ -z $conn ]] && ! conn=$(active_conn); then
        # not connected: offer the profiles that currently have a lock
        local profiles
        profiles=$(locked_profiles)
        [[ -z $profiles ]] && { info "No locked Wi-Fi profiles."; exit 0; }
        need fzf
        conn=$(fzf --layout=reverse --height=~40% --border --delimiter=$'\t' \
                   --header="Locked profiles" --prompt="Unlock > " <<<"$profiles") \
            || { info "Cancelled."; exit 0; }
        conn=${conn%%$'\t'*}
    fi
    conn=$(resolve_conn "$conn") || exit 1

    if [[ -z $(locked_bssid "$conn") ]]; then
        info "'$conn' is not locked."
        exit 0
    fi
    nmcli connection modify "$conn" 802-11-wireless.bssid "" \
        || die "failed to remove lock (try again with sudo)"
    info "Unlocked '$conn'. Takes effect on the next connection."
}

cmd_menu() {
    need fzf
    local choice
    choice=$(printf '%s\n' \
        "status   Show current connection and lock" \
        "list     Show access points of the current network" \
        "lock     Pick an access point and lock to it" \
        "unlock   Remove the lock (back to free roaming)" \
        "list-all Show access points of every network" |
        fzf --layout=reverse --height=~40% --border --prompt="wifi-ap > " --info=hidden) \
        || exit 0
    case ${choice%% *} in
        status)   cmd_status ;;
        list)     cmd_list ;;
        lock)     cmd_lock ;;
        unlock)   cmd_unlock ;;
        list-all) cmd_list -a ;;
    esac
}

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

case ${1:-} in
    "")              cmd_menu ;;
    status)          shift; cmd_status "$@" ;;
    list|ls)         shift; cmd_list "$@" ;;
    lock)            shift; cmd_lock "$@" ;;
    unlock)          shift; cmd_unlock "$@" ;;
    -h|--help|help)  usage ;;
    *)               usage; exit 1 ;;
esac