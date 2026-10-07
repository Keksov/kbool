#!/bin/bash
# kbool.sh — the kbool startup file (kklass/USES_PLAN.md U1, U2, U4, P1, P3).
#
#     source /path/to/kbool/kbool.sh        # or `source kbool.sh` through $PATH (U3)
#
# Loads the system units — kuse (the unit loader: kk.unit, kk.uses, kk.defined)
# and klib, kerr, kvar, kcfg — and registers them, so `kk.uses klib` is a no-op.
# Everything else is an ordinary unit: `kk.uses kklass`, `kk.uses tlist`.
# A unit's first header line sources this file when kbool is not loaded yet
# (U27), so `source some/unit.sh` in a bare shell works too.
#
# The kbool root is this file's own folder, taken lexically from BASH_SOURCE (no
# cd, no fork) and exported as KBOOL_HOME (P1: a unit outside the tree finds
# kbool.sh through it). KBOOL_HOME means only that (U38): a preset value naming
# another folder is overwritten with one WARNING. The system search path for
# `kk.uses NAME` is $KBOOL_HOME/kkore, $KBOOL_HOME/kklass and every folder of
# $KBOOL_HOME/kcl (U4).
#
# Then the configuration is read (U1b, kuse.sh "Configuration"): the system
# (/etc/kbool/config, else $ProgramData/kbool/config), user (~/.kbool/config,
# else $USERPROFILE/.kbool/config) and $KBOOL_CONFIG levels; no config at all
# means the built-in defaults (U4). kk.project adds the project level later.
#
# rc 0 = loaded (or already loaded); rc != 0 on EVERY failure path (P3) — a
# missing or failing kkore module, a KBOOL_CONFIG naming no file, an unreadable
# config — with the registry emptied and KBOOL_HOME restored, so the loader
# guard stays off and a later source can try again.

# The loader guard (C3): non-empty __KK_UNITS (an assoc with the sentinel [kbool]).
# A source of ANOTHER copy of kbool.sh while one is loaded is a no-op with one
# WARNING (the registry, KBOOL_HOME and the search paths stay the first copy's).
if [[ ${__KK_UNITS[@]@a} == A* ]]; then
    if [[ ${__KK_UNITS[kbool]-} != "${BASH_SOURCE[0]}" && ! ${__KK_UNITS[kbool]-} -ef ${BASH_SOURCE[0]} \
          && ${VERBOSE_KKLASS:-} != quiet ]]; then
        printf 'kbool: WARNING: %s is ignored: kbool is already loaded from %s\n' \
            "${BASH_SOURCE[0]}" "${__KK_UNITS[kbool]-?}" >&2
    fi
    return 0
fi

# Executed instead of sourced? Exact: a function called from a SOURCED file's top
# level sees FUNCNAME[1] == source (also for `bash -c 'source "$0"' kbool.sh`);
# called from an executed script's top level it sees `main`.
kk._kbool_sourced() { [[ ${FUNCNAME[1]-} == source ]]; }
if ! kk._kbool_sourced; then
    unset -f kk._kbool_sourced
    printf 'kbool: error: kbool.sh must be sourced, not executed (source %s)\n' "$0" >&2
    exit 2
fi
unset -f kk._kbool_sourced

# The work runs in a function: it gets locals and its own (empty) positional
# parameters — a plain `set --` here would clear the CALLER's, and kerr.sh must
# not see a caller's `set_trap` (C10).
kk._kbool_boot() {
    local __kk_src=$1 __kk_root __kk_n __kk_m __kk_f __kk_rc=0 \
          __kk_hs=${KBOOL_HOME+1} __kk_hv=${KBOOL_HOME-}
    set --
    case $__kk_src in
        */*|*\\*)
            __kk_root=${__kk_src%[/\\]*}
            if [[ -z $__kk_root ]]; then __kk_root=/; fi
            ;;
        *) __kk_root=. ;;
    esac
    if [[ $__kk_root == . ]]; then
        __kk_root=$PWD
    elif [[ $__kk_root != /* && $__kk_root != [A-Za-z]:* ]]; then
        __kk_root=$PWD/$__kk_root
    fi

    # 1. the loader itself, by plain source (it cannot carry a unit header)
    if [[ ! -f $__kk_root/kkore/kuse.sh ]]; then
        printf 'kbool: error: the unit loader %s is missing\n' "$__kk_root/kkore/kuse.sh" >&2
        return 2
    fi
    source "$__kk_root/kkore/kuse.sh" || {
        __kk_rc=$?
        printf 'kbool: error: loading %s failed (rc=%s)\n' "$__kk_root/kkore/kuse.sh" "$__kk_rc" >&2
        return "$__kk_rc"
    }
    if ! declare -F kk.unit kk.uses kk._unit_reset kk._unit_register kk._unit_lexnorm \
            kk._cfg_boot >/dev/null; then
        printf 'kbool: error: %s does not define the unit loader\n' "$__kk_root/kkore/kuse.sh" >&2
        return 2
    fi

    # 2. KBOOL_HOME: the lexically normalised root when it is the same folder
    kk._unit_lexnorm "$__kk_root"
    if [[ $__kk_n != "$__kk_root" && $__kk_n/kbool.sh -ef $__kk_src ]]; then
        __kk_root=$__kk_n
    fi
    export KBOOL_HOME=$__kk_root

    # 3. the registry: the sentinel first — from here on the guard holds, so a
    #    system unit's own header line 1 (U3) does not re-enter this file.
    #    __KK_LOADED (a one-element ASSOC) marks the registry as THIS shell's: a
    #    child bash may inherit the loader FUNCTIONS (`set -a` exports them too,
    #    and `bash -c` may exec the child in the parent's PID, so $$ proves
    #    nothing) but never an array. Every entry point checks it with
    #    `${__KK_LOADED[@]@a} == A` (set -u safe, O(1)) BEFORE it subscripts a
    #    registry table by a non-literal key — on a non-assoc table that key would
    #    be evaluated as ARITHMETIC (a path `d[$(cmd)]` would run cmd; R14).
    kk._unit_reset
    __KK_UNITS[kbool]=$__kk_root/kbool.sh
    __KK_UNIT_SYS[kbool]=1
    declare -gA __KK_LOADED=([on]=1)
    __KK_UNIT_SYSPATH=("$__kk_root/kkore" "$__kk_root/kklass" "$__kk_root/kcl/*")
    kk._unit_register kuse "$__kk_root/kkore/kuse.sh"

    # 4. the system units (U1), by plain source until they carry headers (U3).
    #    After each one, one function it must define: a module whose own re-source
    #    guard is already set (an inherited __KLIB_SOURCED=1) returns 0 having
    #    defined nothing (C2).
    for __kk_m in klib:kk.isInt kerr:ke.setTrap kvar:kv.framePush kcfg:kc.alias; do
        __kk_n=${__kk_m#*:}
        __kk_m=${__kk_m%%:*}
        __kk_f=$__kk_root/kkore/$__kk_m.sh
        if [[ ! -f $__kk_f ]]; then
            printf 'kbool: error: system unit %s is missing (%s)\n' "$__kk_m" "$__kk_f" >&2
            __kk_rc=2
            break
        fi
        source "$__kk_f" || __kk_rc=$?
        if (( __kk_rc != 0 )); then
            printf 'kbool: error: loading system unit %s failed (rc=%s, %s)\n' "$__kk_m" "$__kk_rc" "$__kk_f" >&2
            break
        fi
        if ! declare -F "$__kk_n" >/dev/null; then
            printf 'kbool: error: system unit %s did not define %s (%s; a stale re-source guard variable?)\n' \
                "$__kk_m" "$__kk_n" "$__kk_f" >&2
            __kk_rc=2
            break
        fi
        kk._unit_register "$__kk_m" "$__kk_f"
    done
    # the system units are not "used units" in the kk.project sense (U37), also
    # once they carry headers (U3) and kk.unit registers them
    __KK_UNIT_USED=""
    # 5. the configuration (U1b): system, user and KBOOL_CONFIG levels; a
    #    KBOOL_CONFIG naming no file or an unreadable config fails the load (P3)
    if (( __kk_rc == 0 )); then
        kk._cfg_boot || __kk_rc=$?
    fi
    if (( __kk_rc != 0 )); then
        kk._unit_reset
        if [[ -n $__kk_hs ]]; then
            KBOOL_HOME=$__kk_hv
        else
            unset KBOOL_HOME
        fi
        return "$__kk_rc"
    fi
    __KK_UNIT_DONE[kbool]=1
    # U38: KBOOL_HOME is where THIS kbool lives; a preset naming another folder
    # is overwritten with one WARNING (the config chain head is KBOOL_CONFIG)
    if [[ -n $__kk_hv && $__kk_hv != "$__kk_root" && ! $__kk_hv -ef $__kk_root ]]; then
        kk._unit_warn "KBOOL_HOME=$__kk_hv is ignored: kbool is loaded from $__kk_root"
    fi
    return 0
}

# __kk_unit_rc carries the rc past the cleanup (no file-scope `set --`: it would
# clear the caller's positional parameters).
kk._kbool_boot "${BASH_SOURCE[0]}" || {
    __kk_unit_rc=$?
    unset -f kk._kbool_boot
    return "$__kk_unit_rc"
}
unset -f kk._kbool_boot
return 0
