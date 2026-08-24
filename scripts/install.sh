#!/usr/bin/env bash
# bdx installer — one-shot bootstrap for the bdx workflow.
#
#   1. bd          (beads CLI, via gastownhall/beads)
#   2. dolt        (homebrew on macOS when available, official installer otherwise)
#   3. env         (AGENT_HOME export in your shell rc, with prompt)
#   4. bd setup    (explain per-project `bd init`; no global database)
#   5. templates   (seed example manifest + DHH/Linus personas into $AGENT_HOME)
#   6. perms       (Claude allowlist + Codex exec-policy rule)
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/zeejers/bdx/refs/heads/development/scripts/install.sh)
#   curl -fsSL https://raw.githubusercontent.com/zeejers/bdx/refs/heads/development/scripts/install.sh | bash
#   ./install.sh                  # interactive
#   ./install.sh --yes            # non-interactive, accept defaults
#   ./install.sh --skip-env       # skip the shell-profile prompts
#   ./install.sh --skip-bd        # skip bd install
#   ./install.sh --skip-dolt      # skip dolt install
#   ./install.sh --skip-init      # skip the bd init step
#   ./install.sh --skip-templates # skip the manifest/personas seeding
#   ./install.sh --skip-perms     # skip Claude Code + Codex permission setup
#
# Safe to re-run; everything is idempotent.

set -eu

# Everything lives inside main() so bash buffers the entire script while
# parsing — necessary so `curl ... | bash` doesn't hang when prompts redirect
# stdin to /dev/tty mid-execution. Same trick rustup / nvm / homebrew use.
main() {
  local YES=0 SKIP_ENV=0 SKIP_BD=0 SKIP_DOLT=0 SKIP_INIT=0 SKIP_TEMPLATES=0 SKIP_PERMS=0
  for arg in "$@"; do
    case "$arg" in
      --yes|-y)         YES=1 ;;
      --skip-env)       SKIP_ENV=1 ;;
      --skip-bd)        SKIP_BD=1 ;;
      --skip-dolt)      SKIP_DOLT=1 ;;
      --skip-init)      SKIP_INIT=1 ;;
      --skip-templates) SKIP_TEMPLATES=1 ;;
      --skip-perms)     SKIP_PERMS=1 ;;
      --help|-h)        sed -n '2,23p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null | sed 's/^# \{0,1\}//' || true; return 0 ;;
      *) printf 'unknown flag: %s (try --help)\n' "$arg" >&2; return 2 ;;
    esac
  done

  # Re-attach stdin to the terminal when piped via `curl | bash`.
  # Guarded: if /dev/tty isn't openable (CI, sandbox, no controlling tty),
  # fall through to non-interactive mode.
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
  die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

  # with_spinner "label" cmd args... — runs the command silently with a
  # rotating spinner; on failure, dumps the captured output indented under
  # the row so the user can see what broke. Falls back to plain "label …
  # done/fail" when stdout isn't a TTY (CI, piped install).
  with_spinner() {
    local label="$1"; shift
    if [ ! -t 1 ]; then
      printf '  %s ... ' "$label"
      if "$@" >/dev/null 2>&1; then
        printf 'done\n'; return 0
      else
        printf 'fail\n'; return 1
      fi
    fi
    local logfile
    logfile=$(mktemp -t bdx-install.XXXXXX 2>/dev/null || mktemp)
    ( "$@" >"$logfile" 2>&1 ) &
    local cmd_pid=$!
    local chars='|/-\'
    local i=0
    while kill -0 "$cmd_pid" 2>/dev/null; do
      printf '\r  \033[36m%s\033[0m %s' "${chars:$i:1}" "$label"
      i=$(( (i+1) % 4 ))
      sleep 0.08
    done
    wait "$cmd_pid"
    local rc=$?
    printf '\r\033[K'
    if [ "$rc" = 0 ]; then
      printf '  \033[32m✓\033[0m %s\n' "$label"
    else
      printf '  \033[31m✗\033[0m %s\n' "$label"
      [ -s "$logfile" ] && sed 's/^/      /' "$logfile" >&2
    fi
    rm -f "$logfile"
    return "$rc"
  }

  ask_yn() {
    # ask_yn "question" default(Y|N) -> 0 yes, 1 no
    local q="$1" d="${2:-Y}" prompt ans
    case "$d" in Y|y) prompt="[Y/n]" ;; *) prompt="[y/N]" ;; esac
    if [ "$YES" = 1 ]; then case "$d" in Y|y) return 0 ;; *) return 1 ;; esac; fi
    printf '  %s %s ' "$q" "$prompt" >&2
    read -r ans || ans=""
    ans="${ans:-$d}"
    case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
  }

  ask_value() {
    # ask_value "label" "default" -> echoes chosen value
    local label="$1" def="$2" ans
    if [ "$YES" = 1 ]; then printf '%s' "$def"; return; fi
    printf '  %s [%s]: ' "$label" "$def" >&2
    read -r ans || ans=""
    printf '%s' "${ans:-$def}"
  }

  # --- platform ----------------------------------------------------------
  local OS ARCH PLATFORM
  OS=$(uname -s)
  ARCH=$(uname -m)
  case "$OS" in
    Darwin) PLATFORM=macos ;;
    Linux)  PLATFORM=linux ;;
    *) die "unsupported OS: $OS (macOS and Linux only)" ;;
  esac

  bold "bdx installer — $PLATFORM/$ARCH"
  if [ "$warn_no_tty" = 1 ]; then
    warn "no controlling terminal — running non-interactive (defaults accepted)"
  fi

  # --- 1. bd (beads) -----------------------------------------------------
  bold "1/6  beads (bd)"
  if [ "$SKIP_BD" = 1 ]; then
    info "skipped (--skip-bd)"
  elif command -v bd >/dev/null 2>&1; then
    ok "bd already installed: $(bd --version 2>/dev/null | head -1 || echo 'present')"
  else
    info "installing via gastownhall/beads installer..."
    curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash
    if command -v bd >/dev/null 2>&1; then
      ok "bd installed: $(bd --version 2>/dev/null | head -1 || echo 'ok')"
    else
      # Try the conventional install path so step 4 still works in this shell.
      if [ -x "$HOME/.local/bin/bd" ]; then
        export PATH="$HOME/.local/bin:$PATH"
        ok "bd installed: $(bd --version 2>/dev/null | head -1 || echo 'ok') (added ~/.local/bin to PATH for this run)"
      else
        warn "bd installer ran but 'bd' is not on PATH yet — open a new shell, or check ~/.local/bin"
      fi
    fi
  fi

  # --- 2. dolt -----------------------------------------------------------
  bold "2/6  dolt"
  if [ "$SKIP_DOLT" = 1 ]; then
    info "skipped (--skip-dolt)"
  elif command -v dolt >/dev/null 2>&1; then
    ok "dolt already installed: $(dolt version 2>/dev/null | head -1)"
  else
    case "$PLATFORM" in
      macos)
        if command -v brew >/dev/null 2>&1; then
          info "installing via homebrew..."
          brew install dolt
        else
          info "homebrew not found — using the official dolt installer (sudo required)..."
          curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | sudo bash
        fi
        ;;
      linux)
        info "installing via the official dolt installer (sudo required)..."
        curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | sudo bash
        ;;
    esac
    command -v dolt >/dev/null 2>&1 && ok "dolt installed: $(dolt version 2>/dev/null | head -1)"
  fi

  # --- 3. shell profile env vars ----------------------------------------
  bold "3/6  shell profile (AGENT_HOME)"
  local rc shell_name chosen_agent_home=""
  if [ "$SKIP_ENV" = 1 ]; then
    info "skipped (--skip-env)"
  else
    shell_name=$(basename "${SHELL:-/bin/bash}")
    case "$shell_name" in
      zsh)  rc="$HOME/.zshrc" ;;
      bash) if [ "$PLATFORM" = macos ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
      fish) rc="$HOME/.config/fish/config.fish" ;;
      *)    rc="$HOME/.profile" ;;
    esac
    info "shell rc: $rc"

    add_export() {
      local var="$1" val="$2" line
      if [ "$shell_name" = "fish" ]; then
        line="set -gx $var \"$val\""
      else
        line="export $var=\"$val\""
      fi
      if [ -f "$rc" ] && grep -qE "^[[:space:]]*(export[[:space:]]+|set[[:space:]]+-gx[[:space:]]+)?$var(=|[[:space:]])" "$rc"; then
        warn "$var already set in $rc — leaving untouched"
        return
      fi
      mkdir -p "$(dirname "$rc")"
      printf '\n# bdx installer\n%s\n' "$line" >> "$rc"
      ok "added $var=\"$val\" to $rc"
    }

    # AGENT_HOME — same detection. If the user has it set (commonly to a
    # synced path like ~/Dropbox/Notes/agent), honor that and skip the prompt.
    if [ -n "${AGENT_HOME:-}" ]; then
      ok "AGENT_HOME already set in env: $AGENT_HOME — using existing"
      chosen_agent_home="$AGENT_HOME"
    elif ask_yn "Add AGENT_HOME to your shell profile?" Y; then
      chosen_agent_home=$(ask_value "AGENT_HOME" "$HOME/.bdx-agent")
      add_export AGENT_HOME "$chosen_agent_home"
    fi
  fi

  # --- 4. per-project bd setup ------------------------------------------
  # bdx uses the manifest to route across repositories; it does not own or
  # initialize a global task database. Native Beads remains authoritative in
  # each project and therefore keeps provider sync configuration project-local.
  bold "4/6  beads databases (per-project)"
  if [ "$SKIP_INIT" = 1 ]; then
    info "skipped (--skip-init)"
  elif ! command -v bd >/dev/null 2>&1; then
    warn "bd not on PATH — initialize each project after opening a new shell"
  else
    ok "bdx will use each repository's native Beads database"
    info "for a new repo: cd <repo> && bd init"
    info "then add it to \$AGENT_HOME/manifest.md with /bdx:manifest"
    if [ -n "${BEADS_DIR:-}" ]; then
      warn "BEADS_DIR is currently exported; unset it for per-project routing"
    fi
  fi

  # --- 5. seed example templates ----------------------------------------
  # Pull the manifest + persona examples from the repo into $AGENT_HOME so
  # /bdx:plan, /bdx:scope, and /bdx:summarize have starter content. Each
  # file is fetched independently and skipped if it already exists, so this
  # is safe to re-run and won't clobber user customizations.
  bold "5/6  example manifest + personas (optional starter content)"
  if [ "$SKIP_TEMPLATES" = 1 ]; then
    info "skipped (--skip-templates)"
  else
    local target_ah="${AGENT_HOME:-${chosen_agent_home:-$HOME/.bdx-agent}}"
    local templates_branch="${BDX_TEMPLATES_BRANCH:-development}"
    local base_url="https://raw.githubusercontent.com/zeejers/bdx/refs/heads/${templates_branch}/examples"
    local has_manifest=0 has_personas=0
    [ -f "$target_ah/manifest.md" ] && has_manifest=1
    [ -d "$target_ah/personas" ] && ls "$target_ah/personas"/*.md >/dev/null 2>&1 && has_personas=1
    if [ "$has_manifest" = 1 ] && [ "$has_personas" = 1 ]; then
      ok "$target_ah already has manifest + personas — leaving untouched"
    else
      info "target:         $target_ah"
      info "from branch:    $templates_branch (override with BDX_TEMPLATES_BRANCH=...)"
      info "(existing files are never overwritten)"
      fetch_template() {
        local url="$1" dest="$2" label="$3"
        if [ -f "$dest" ]; then
          info "$label already exists — skipped"
          return 0
        fi
        if with_spinner "$label" curl -fsSL "$url" -o "$dest"; then
          return 0
        else
          rm -f "$dest"
          return 1
        fi
      }
      if [ "$has_manifest" = 0 ]; then
        if ask_yn "Seed example manifest.md into $target_ah?" Y; then
          mkdir -p "$target_ah"
          fetch_template "$base_url/manifest.md" "$target_ah/manifest.md" "manifest.md"
        else
          info "manifest skipped — copy from examples/ in the repo when ready"
        fi
      fi
      # Personas default to N: seeding them auto-enables persona reviews in
      # /bdx:summarize (the skill no-ops when $AGENT_HOME/personas is empty).
      # Opt-in keeps a fresh install quiet by default.
      if [ "$has_personas" = 0 ]; then
        info "personas: dhh.md, linus.md — enables per-persona reviews on /bdx:summarize"
        if ask_yn "Seed example personas into $target_ah/personas/?" N; then
          mkdir -p "$target_ah/personas"
          fetch_template "$base_url/personas/dhh.md"   "$target_ah/personas/dhh.md"   "personas/dhh.md"
          fetch_template "$base_url/personas/linus.md" "$target_ah/personas/linus.md" "personas/linus.md"
        else
          info "personas skipped — copy from examples/personas/ when ready"
        fi
      fi
    fi
  fi

  # --- 6. Agent permission setup -----------------------------------------
  # Claude Code: merge the bdx allowlist into ~/.claude/settings.json.
  # Codex: append a managed block to a dedicated exec-policy rules file under
  # $CODEX_HOME/rules/. Existing settings, rules, and user additions to the
  # dedicated file are preserved; reruns do not duplicate the managed block.
  bold "6/6  agent permissions (Claude Code + Codex)"
  if [ "$SKIP_PERMS" = 1 ]; then
    info "skipped (--skip-perms)"
  else
    local target_ah="${AGENT_HOME:-${chosen_agent_home:-$HOME/.bdx-agent}}"
    local ah_pattern="$target_ah"
    # Rewrite $HOME prefix to ~ so the config doesn't bake in absolute paths.
    if [[ "$target_ah" == "$HOME"/* ]] || [[ "$target_ah" == "$HOME" ]]; then
      ah_pattern="~${target_ah#$HOME}"
    fi
    local settings_file="$HOME/.claude/settings.json"
    local claude_provenance_file="$HOME/.claude/bdx-managed-permissions.json"
    local codex_home="${CODEX_HOME:-$HOME/.codex}"
    local codex_rules_file="$codex_home/rules/bdx.rules"
    info "Claude: $settings_file"
    info "Codex:  $codex_rules_file"
    info "adds:    Claude bd/bdx wrapper access + AGENT_HOME; matching Codex allow rules"
    info "(existing settings and rules are preserved; managed entries are idempotent)"
    if ask_yn "Install bdx permissions for Claude Code and Codex?" Y; then
      if ! command -v jq >/dev/null 2>&1; then
        warn "jq not on PATH — skipped Claude Code settings merge"
      else
        mkdir -p "$HOME/.claude"
        local requested_permissions current_permissions added_permissions prior_managed_permissions
        requested_permissions=$(jq -cn --arg ah "$ah_pattern" '[
          "Bash(bd:*)",
          "Bash(bdx-resolve-project:*)",
          "Bash(bdx-plan-frontmatter:*)",
          "Bash(bdx-sync-status:*)",
          "Read(\($ah)/**)",
          "Write(\($ah)/**)",
          "Edit(\($ah)/**)"
        ]')
        if [ -f "$settings_file" ]; then
          current_permissions=$(jq -ce '.permissions.allow // []' "$settings_file" 2>/dev/null || printf '[]')
        else
          current_permissions='[]'
        fi
        added_permissions=$(jq -cn --argjson requested "$requested_permissions" \
          --argjson current "$current_permissions" '$requested - $current')
        if [ -f "$claude_provenance_file" ]; then
          prior_managed_permissions=$(jq -ce 'if type == "array" then . else error("not an array") end' \
            "$claude_provenance_file" 2>/dev/null || printf '[]')
        else
          prior_managed_permissions='[]'
        fi
        local merge_jq='.permissions.allow = ((.permissions.allow // []) + [
          "Bash(bd:*)",
          "Bash(bdx-resolve-project:*)",
          "Bash(bdx-plan-frontmatter:*)",
          "Bash(bdx-sync-status:*)",
          "Read(\($ah)/**)",
          "Write(\($ah)/**)",
          "Edit(\($ah)/**)"
        ] | unique)'
        local claude_merge_ok=0
        if [ -f "$settings_file" ]; then
          if jq --arg ah "$ah_pattern" "$merge_jq" "$settings_file" > "$settings_file.tmp" 2>/dev/null; then
            mv -f "$settings_file.tmp" "$settings_file"
            claude_merge_ok=1
            ok "merged bdx allowlist into $settings_file"
          else
            rm -f "$settings_file.tmp"
            warn "couldn't merge into $settings_file (invalid JSON?) — left untouched"
          fi
        else
          if jq --arg ah "$ah_pattern" "$merge_jq" <<<'{}' > "$settings_file"; then
            claude_merge_ok=1
            ok "wrote $settings_file with bdx allowlist"
          else
            warn "failed to write $settings_file"
          fi
        fi
        if [ "$claude_merge_ok" = 1 ]; then
          jq -cn --argjson prior "$prior_managed_permissions" --argjson added "$added_permissions" \
            '$prior + $added | unique' > "$claude_provenance_file.tmp"
          mv -f "$claude_provenance_file.tmp" "$claude_provenance_file"
          ok "recorded installer-owned Claude entries in $claude_provenance_file"
        fi
      fi

      local codex_marker="# BEGIN bdx managed rule"
      local codex_end_marker="# END bdx managed rule"
      mkdir -p "$(dirname "$codex_rules_file")"
      local codex_rules_tmp="$codex_rules_file.tmp"
      if [ -f "$codex_rules_file" ]; then
        awk -v begin="$codex_marker" -v end="$codex_end_marker" '
          $0 == begin { managed=1; next }
          managed && $0 == end { managed=0; next }
          !managed { lines[++count]=$0 }
          END {
            while (count > 0 && lines[count] == "") count--
            for (i=1; i<=count; i++) print lines[i]
          }
        ' "$codex_rules_file" > "$codex_rules_tmp"
      else
        : > "$codex_rules_tmp"
      fi
      if [ -s "$codex_rules_tmp" ]; then
        printf '\n' >> "$codex_rules_tmp"
      fi
      cat >> "$codex_rules_tmp" <<'BDX_CODEX_RULE'
# BEGIN bdx managed rule
# Pre-approves host execution when a bdx skill explicitly requests it so bd can
# reach its configured Dolt store. An allow rule does not itself move a default
# call outside the workspace sandbox; Codex-only instructions in each bd-using
# skill require that request. The exact-token prefix does not match `bdx`.
prefix_rule(
    pattern = ["bd"],
    decision = "allow",
    justification = "bdx skills use Beads task tracking and its configured Dolt store",
    match = [
        "bd ready",
        "bd show bd-123",
        "bd dolt push",
    ],
    not_match = [
        "bdx ready",
    ],
)
prefix_rule(
    pattern = ["bdx-resolve-project"],
    decision = "allow",
    justification = "bdx resolves a Bead to its owning per-project database",
)
prefix_rule(
    pattern = ["bdx-plan-frontmatter"],
    decision = "allow",
    justification = "bdx atomically updates managed live-plan frontmatter",
)
prefix_rule(
    pattern = ["bdx-sync-status"],
    decision = "allow",
    justification = "bdx projects authoritative Beads status into live plan frontmatter",
)
# END bdx managed rule
BDX_CODEX_RULE
      mv -f "$codex_rules_tmp" "$codex_rules_file"
      ok "installed current Codex bdx rules in $codex_rules_file"
    else
      info "skipped — copy the Claude and Codex snippets from the README when ready"
    fi
  fi

  # --- next steps card --------------------------------------------------
  # Build the list dynamically so SKIP_ENV cleanly drops the "open a new
  # shell" step. Each row is rendered into a unicode-box card sized to the
  # longest line, capped at 76 cols for terminal-friendly width.
  local steps=()
  if [ "$SKIP_ENV" = 0 ]; then
    steps+=("open a new shell (or: source ${rc:-<your shell rc>})")
  fi
  steps+=("claude plugin marketplace add zeejers/bdx")
  steps+=("claude plugin install bdx@bdx-marketplace")
  steps+=("")
  steps+=("then in any project:")
  steps+=("  /bdx:plan \"<your first task>\"   # creates a bd issue + plan")
  steps+=("  bd ready                        # find unblocked work")

  local title="✨ all set — next steps"
  local inner_w=${#title}
  local s
  for s in "${steps[@]}"; do
    [ ${#s} -gt "$inner_w" ] && inner_w=${#s}
  done
  inner_w=$(( inner_w + 4 ))
  [ "$inner_w" -gt 76 ] && inner_w=76

  local hbar=""
  local _n=$inner_w
  while [ "$_n" -gt 0 ]; do hbar="${hbar}─"; _n=$((_n - 1)); done

  printf '\n'
  printf '  \033[36m╭%s╮\033[0m\n' "$hbar"
  printf '  \033[36m│\033[0m \033[1m%-*s\033[0m \033[36m│\033[0m\n' $((inner_w - 2)) "$title"
  printf '  \033[36m├%s┤\033[0m\n' "$hbar"
  local idx=1
  for s in "${steps[@]}"; do
    if [ -z "$s" ]; then
      printf '  \033[36m│\033[0m %-*s \033[36m│\033[0m\n' $((inner_w - 2)) ""
    elif [[ "$s" == "  "* ]] || [[ "$s" == "then "* ]]; then
      printf '  \033[36m│\033[0m %-*s \033[36m│\033[0m\n' $((inner_w - 2)) "$s"
    else
      printf '  \033[36m│\033[0m %-*s \033[36m│\033[0m\n' $((inner_w - 2)) "$(printf '%d. %s' "$idx" "$s")"
      idx=$((idx + 1))
    fi
  done
  printf '  \033[36m╰%s╯\033[0m\n\n' "$hbar"
}

main "$@"
exit $?
