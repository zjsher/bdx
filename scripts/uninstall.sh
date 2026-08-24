#!/usr/bin/env bash
# bdx uninstaller — reverse the bdx installer.
#
# Prompts for each teardown step. By design this script does NOT touch your
# shell profile (the AGENT_HOME export stays until you remove it by
# hand). Defaults are conservative: destructive ops default to "no".
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/zeejers/bdx/refs/heads/development/scripts/uninstall.sh)
#   curl -fsSL https://raw.githubusercontent.com/zeejers/bdx/refs/heads/development/scripts/uninstall.sh | bash
#   ./uninstall.sh                # interactive
#   ./uninstall.sh --yes          # accept the default at every prompt (binaries: yes, data: no)
#   ./uninstall.sh --dry-run      # print what would be removed; touch nothing
#
# Note: --yes accepts DEFAULTS, not "yes to everything." Destructive prompts
# (deleting $AGENT_HOME) default to no, so --yes will NOT delete
# data. To force-delete data without prompts, run interactively and answer y.
#
# Steps (each prompted independently):
#   1. Stop the running dolt server, if any
#   2. Remove the bd binary
#   3. Remove the dolt binary (brew uninstall on macOS when applicable)
#   4. Remove bdx-managed Claude/Codex permissions
#   5. Remove $AGENT_HOME (DESTRUCTIVE — all plans, contexts, summaries)
#
# Per-project Beads databases are user project data and are never removed.

set -eu

main() {
  local script_source="${BASH_SOURCE[0]:-}" script_dir=""
  # Only trust a sibling helper when Bash is executing a real on-disk script.
  # For `curl ... | bash` and process substitution, use the embedded validator;
  # never reinterpret the caller's current directory as the script directory.
  if [ -n "$script_source" ] && [ -f "$script_source" ]; then
    case "$script_source" in /dev/fd/*|/proc/self/fd/*) ;; *)
      script_dir=$(CDPATH= cd -- "$(dirname -- "$script_source")" && pwd)
      ;;
    esac
  fi
  if [ -n "$script_dir" ] && [ -r "$script_dir/bdx-validate-agent-home-delete" ]; then
    # shellcheck source=./bdx-validate-agent-home-delete
    . "$script_dir/bdx-validate-agent-home-delete"
  else
    # `curl .../uninstall.sh | bash` has no sibling scripts. Keep the same
    # safety boundary inline so the advertised standalone path stays safe.
    bdx_validate_agent_home_delete() {
      local target="${1:-}" canonical_target canonical_home
      [ -n "$target" ] && [ -d "$target" ] || return 1
      canonical_target=$(CDPATH= cd -- "$target" && pwd -P)
      canonical_home=$(CDPATH= cd -- "$HOME" && pwd -P)
      case "$canonical_target" in
        /|/Applications|/Library|/System|/Users|/bin|/etc|/home|/opt|/private|/root|/sbin|/tmp|/usr|/var) return 1 ;;
      esac
      [ "$canonical_target" != "$canonical_home" ] || return 1
      case "$canonical_home/" in "$canonical_target/"*) return 1 ;; esac
      printf '%s\n' "$canonical_target"
    }
  fi
  local YES=0 DRY=0
  for arg in "$@"; do
    case "$arg" in
      --yes|-y)     YES=1 ;;
      --dry-run|-n) DRY=1 ;;
      --help|-h)    sed -n '2,25p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null | sed 's/^# \{0,1\}//' || true; return 0 ;;
      *) printf 'unknown flag: %s (try --help)\n' "$arg" >&2; return 2 ;;
    esac
  done

  local warn_no_tty=0
  if [ ! -t 0 ]; then
    if (exec </dev/tty) 2>/dev/null; then
      exec </dev/tty
    else
      YES=1
      warn_no_tty=1
    fi
  fi

  bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
  info() { printf '  %s\n' "$*"; }
  ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
  warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
  danger() { printf '  \033[31m!!\033[0m %s\n' "$*"; }

  ask_yn() {
    local q="$1" d="${2:-N}" prompt ans
    case "$d" in Y|y) prompt="[Y/n]" ;; *) prompt="[y/N]" ;; esac
    if [ "$YES" = 1 ]; then case "$d" in Y|y) return 0 ;; *) return 1 ;; esac; fi
    printf '  %s %s ' "$q" "$prompt" >&2
    read -r ans || ans=""
    ans="${ans:-$d}"
    case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
  }

  run() {
    if [ "$DRY" = 1 ]; then
      info "[dry-run] would run: $*"
      return 0
    fi
    "$@"
  }

  bold "bdx uninstaller"
  if [ "$warn_no_tty" = 1 ]; then
    warn "no controlling terminal — running non-interactive (--yes implied)"
  fi
  if [ "$DRY" = 1 ]; then
    info "dry-run mode: nothing will be removed"
  fi
  if [ "$YES" = 1 ] && [ "$DRY" = 0 ]; then
    info "--yes accepts defaults at every prompt (data deletion still defaults to no)"
  fi

  # --- 1. dolt server -----------------------------------------------------
  bold "1/5  stop dolt server"
  local dolt_running=0
  if command -v bd >/dev/null 2>&1 && bd dolt status 2>/dev/null | grep -q 'running'; then
    dolt_running=1
  elif pgrep -f 'dolt sql-server' >/dev/null 2>&1; then
    dolt_running=1
  fi
  if [ "$dolt_running" = 0 ]; then
    info "no dolt server running"
  elif ask_yn "Stop the running dolt server?" Y; then
    if command -v bd >/dev/null 2>&1; then
      run bd dolt stop || warn "bd dolt stop failed; trying pkill"
    fi
    pgrep -f 'dolt sql-server' >/dev/null 2>&1 && run pkill -f 'dolt sql-server' || true
    ok "dolt server stopped"
  else
    info "skipped — left running"
  fi

  # --- 2. bd binary -------------------------------------------------------
  bold "2/5  bd binary"
  local bd_path
  bd_path=$(command -v bd 2>/dev/null || true)
  if [ -z "$bd_path" ]; then
    info "bd not on PATH — nothing to remove"
  else
    info "found: $bd_path"
    if ask_yn "Remove the bd binary?" Y; then
      run rm -f "$bd_path" && ok "removed $bd_path"
    else
      info "skipped"
    fi
  fi

  # --- 3. dolt binary -----------------------------------------------------
  bold "3/5  dolt binary"
  local dolt_path
  dolt_path=$(command -v dolt 2>/dev/null || true)
  if [ -z "$dolt_path" ]; then
    info "dolt not on PATH — nothing to remove"
  else
    info "found: $dolt_path"
    # Detect homebrew install — uninstall properly to avoid leaving a brew stub
    local via_brew=0
    if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx dolt; then
      via_brew=1
    fi
    if [ "$via_brew" = 1 ]; then
      if ask_yn "Run 'brew uninstall dolt'?" Y; then
        run brew uninstall dolt && ok "brew uninstalled dolt"
      else
        info "skipped"
      fi
    else
      if ask_yn "Remove the dolt binary?" Y; then
        run rm -f "$dolt_path" && ok "removed $dolt_path"
      else
        info "skipped"
      fi
    fi
  fi

  # --- 4. agent permissions ----------------------------------------------
  bold "4/5  agent permissions (Claude Code + Codex)"
  local agent_home="${AGENT_HOME:-$HOME/.bdx-agent}"
  local settings_file="$HOME/.claude/settings.json"
  local claude_provenance_file="$HOME/.claude/bdx-managed-permissions.json"
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local codex_rules_file="$codex_home/rules/bdx.rules"
  if ask_yn "Remove bdx-managed Claude and Codex permissions?" Y; then
    if [ "$DRY" = 1 ]; then
      info "[dry-run] would remove bdx entries from $settings_file and $codex_rules_file"
    else
      if [ -f "$settings_file" ] && [ -f "$claude_provenance_file" ] && command -v jq >/dev/null 2>&1; then
        local remove_jq='.permissions.allow = ((.permissions.allow // []) - ($managed[0] // []))'
        if jq --slurpfile managed "$claude_provenance_file" "$remove_jq" \
          "$settings_file" > "$settings_file.tmp"; then
          mv -f "$settings_file.tmp" "$settings_file"
          rm -f "$claude_provenance_file"
          ok "removed installer-owned bdx entries from $settings_file"
        else
          rm -f "$settings_file.tmp"
          warn "couldn't update $settings_file — left untouched"
        fi
      elif [ -f "$settings_file" ] && [ ! -f "$claude_provenance_file" ]; then
        info "no Claude permission provenance — preserved existing entries"
      elif [ -f "$settings_file" ]; then
        warn "jq not on PATH — left Claude permissions untouched"
      else
        rm -f "$claude_provenance_file"
        info "no Claude settings file"
      fi

      if [ -f "$codex_rules_file" ]; then
        local codex_rules_tmp="$codex_rules_file.tmp"
        awk '
          $0 == "# BEGIN bdx managed rule" { managed=1; next }
          managed && $0 == "# END bdx managed rule" { managed=0; next }
          !managed { lines[++count]=$0 }
          END {
            while (count > 0 && lines[count] == "") count--
            for (i=1; i<=count; i++) print lines[i]
          }
        ' "$codex_rules_file" > "$codex_rules_tmp"
        mv -f "$codex_rules_tmp" "$codex_rules_file"
        ok "removed bdx managed block from $codex_rules_file"
      else
        info "no Codex bdx rules file"
      fi
    fi
  else
    info "skipped — permissions left installed"
  fi

  # --- 5. $AGENT_HOME (DESTRUCTIVE) --------------------------------------
  bold "5/5  remove \$AGENT_HOME (plans, contexts, summaries, inbox)"
  if [ ! -d "$agent_home" ]; then
    info "$agent_home does not exist — nothing to remove"
  else
    local canonical_agent_home
    if ! canonical_agent_home=$(bdx_validate_agent_home_delete "$agent_home"); then
      danger "refusing unsafe AGENT_HOME deletion target: $agent_home"
      info "choose a dedicated bdx data directory before uninstalling data"
    else
      danger "this will permanently delete: $canonical_agent_home"
      danger "contents include all plan/, context/, summary/, inbox/ markdown files"
      if [ "$canonical_agent_home" = "$HOME/Dropbox/Notes/agent" ] || [[ "$canonical_agent_home" == *"Dropbox"* ]] || [[ "$canonical_agent_home" == *"iCloud"* ]]; then
        danger "this path looks synced (Dropbox/iCloud) — deletion will propagate to other machines"
      fi
      if ask_yn "Delete $canonical_agent_home?" N; then
        run rm -rf "$canonical_agent_home" && ok "removed $canonical_agent_home"
      else
        info "skipped — left intact at $canonical_agent_home"
      fi
    fi
  fi

  # --- manual cleanup reminder -------------------------------------------
  bold "manual cleanup"
  info "shell profile: remove the AGENT_HOME export from your shell rc by hand"
  info "project .beads databases are intentionally left untouched"
  info "claude plugin: 'claude plugin remove bdx' if you installed it via a marketplace"
  info "launchd agent (macOS): 'launchctl unload ~/Library/LaunchAgents/com.<you>.beads.dolt.plist' + delete the plist if you set one up"

  bold "done"
}

main "$@"
exit $?
