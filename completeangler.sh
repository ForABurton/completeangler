completeangler() (
    set -euo pipefail
    
    local COMPLETEANGLER_SHELL="bash"
    [ -n "${ZSH_VERSION:-}" ] && COMPLETEANGLER_SHELL="zsh"


    # All globals become *local* here
    local COMPLETEANGLER_VERSION="1.0.0"
    local COMPLETEANGLER_HOME="${COMPLETEANGLER_HOME:-$HOME/.completeangler}"
    local COMPLETEANGLER_CONFIG="$COMPLETEANGLER_HOME/config"

    # Colors (also local to subshell)
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local BLUE='\033[0;34m'
    local NC='\033[0m'

# Initialize directories
completeangler_init() {
    mkdir -p "$COMPLETEANGLER_HOME"/{cache,logs,disabled,mocks,state}
    
    if [ ! -f "$COMPLETEANGLER_CONFIG" ]; then
        cat > "$COMPLETEANGLER_CONFIG" <<'EOF'
# completeangler configuration
UI_BACKEND=auto
AUTO_LOGGING=false
PERF_THRESHOLD=150
CI_STRICT=false
CACHE_DIR=$COMPLETEANGLER_HOME/cache
LOG_FILE=$COMPLETEANGLER_HOME/logs/completions.log
EOF
    fi
}

# Load configuration
completeangler_load_config() {
    [ -f "$COMPLETEANGLER_CONFIG" ] && source "$COMPLETEANGLER_CONFIG"
}

# ============================================================================
# CORE VERBS
# ============================================================================

# why - Explain why completion happened/failed
completeangler_why() {
    local cmdline="$1"
    local verbose="${2:-}"
    
    local words=($cmdline)
    local cmd="${words[0]}"
    local current="${words[-1]}"
    
    echo "Analyzing: $cmdline"
    echo ""
    
    # Check for completion depending on shell
    local spec=""
    if [ "$COMPLETEANGLER_SHELL" = "bash" ]; then
        spec=$(complete -p "$cmd" 2>/dev/null || true)
    else
        # In Zsh, completion is a function named "_$cmd" or a dispatcher
        if whence -w "_$cmd" >/dev/null 2>&1; then
            spec="_$cmd (zsh)"
        fi
    fi
    if [ -z "$spec" ]; then
        echo -e "${RED}✗${NC} No completion registered for '$cmd'"
        echo ""
        echo "Suggestions:"
        echo "  - If using Zsh: ensure compinit is loaded"
        echo "  - If using Bash: install bash-completion"
        echo "  - Or create custom completion: completeangler scaffold $cmd"
        return 1
    fi

    
    echo -e "${GREEN}✓${NC} Completion found for '$cmd'"
    echo ""
    
    # Parse completion spec
    local comp_type=""
    local handler=""
    
    if [[ $spec =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        comp_type="Function"
        handler="${BASH_REMATCH[1]}"
    elif [[ $spec =~ -W[[:space:]]+\'([^\']+)\' ]]; then
        comp_type="Wordlist"
        handler="${BASH_REMATCH[1]}"

    elif [[ $spec =~ -C[[:space:]]+([^[:space:]]+) ]]; then
        comp_type="Command"
        handler="${BASH_REMATCH[1]}"
    fi
    
    echo "Completion Type: $comp_type"
    echo "Handler: $handler"
    
    # Get handler location
    if [ "$comp_type" = "Function" ] && declare -f "$handler" >/dev/null 2>&1; then
        shopt -s extdebug
        local func_info=($(declare -F "$handler" 2>/dev/null || echo "" 0 "unknown"))
        shopt -u extdebug
        if [ -n "${func_info[2]}" ] && [ "${func_info[2]}" != "unknown" ]; then
            echo "Location: ${func_info[2]}:${func_info[1]}"
        fi
        echo ""
    fi
    
    # Simulate completion
    echo "Simulating completion..."

    if [ "$COMPLETEANGLER_SHELL" = "bash" ]; then
        COMP_WORDS=($cmdline)
        COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
        COMP_LINE="$cmdline"
        COMP_POINT=${#COMP_LINE}
        COMPREPLY=()

        if [ "$comp_type" = "Function" ]; then
            $handler "$cmd" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]:-}" 2>/dev/null || true
        fi

    else
        # Zsh backend via `_complete_debug`
        local debug_file="$(mktemp)"
        COMPLETEANGLER_DEBUG_FILE="$debug_file"
        autoload -Uz _complete_debug 2>/dev/null || true

        # Run Zsh completion trace
        ZLE_LINE_TEXT="$cmdline" \
        BUFFER="$cmdline" \
        COMP_LINE="$cmdline" \
        compstate= \
        _complete_debug >/dev/null 2>&1

        # Extract suggested completions
        COMPREPLY=($(grep -A999 '^matches:' "$debug_file" | sed '1d' | sed '/^$/q'))


        # no force
        rm "$debug_file"
    fi

    
    if [ "$COMPLETEANGLER_SHELL" = "bash" ] && [ "$comp_type" = "Function" ]; then
        $handler "$cmd" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]:-}" 2>/dev/null || true
    fi

    
    echo ""
    if [ ${#COMPREPLY[@]} -eq 0 ]; then
        echo -e "${RED}✗${NC} No matches found for '$current'"
        echo ""
        echo "Why this might happen:"
        echo "  - Current word doesn't match any completions"
        echo "  - Completion function has a bug"
        echo "  - Context doesn't allow completions here"
        
        if [ -n "$verbose" ]; then
            echo ""
            echo "Running with tracing enabled..."
            set -x
            COMPREPLY=()
            $handler "$cmd" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]:-}" 2>&1 || true
            set +x
        fi
    else
        echo -e "${GREEN}✓${NC} Found ${#COMPREPLY[@]} matches:"
        printf '  - %s\n' "${COMPREPLY[@]}" | head -20
        [ ${#COMPREPLY[@]} -gt 20 ] && echo "  ... and $((${#COMPREPLY[@]} - 20)) more"
        
        echo ""
        echo "Matching Logic:"
        if [[ "$current" == "" ]]; then
            echo "  - All completions shown (no filter)"
        else
            echo "  - Prefix match on '$current'"
        fi
    fi
}

# test - Simulate completion without shell context
completeangler_test() {
    local cmdline="$1"
    local format="${2:-text}"
    
    local words=($cmdline)
    local cmd="${words[0]}"
    
    # Try bash completion first
    local spec=$(complete -p "$cmd" 2>/dev/null || true)
    
    if [ -n "$spec" ]; then
        COMP_WORDS=($cmdline)
        COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
        COMP_LINE="$cmdline"
        COMP_POINT=${#COMP_LINE}
        COMPREPLY=()
        
        if [[ $spec =~ -F[[:space:]]+([^[:space:]]+) ]]; then
            local func="${BASH_REMATCH[1]}"
            $func "$cmd" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]:-}" 2>/dev/null || true
        fi
        
        case "$format" in
            json)
                echo -n '{"completions":['
                local first=true
                for item in "${COMPREPLY[@]}"; do
                    $first || echo -n ','
                    echo -n "\"$item\""
                    first=false
                done
                echo ']}'
                ;;
            count)
                echo "${#COMPREPLY[@]}"
                ;;
            *)
                printf '%s\n' "${COMPREPLY[@]}"
                ;;
        esac
        return 0
    fi
    
    # Try self-completion protocols
    detect_and_test_protocol "$cmd" "$cmdline"
}

detect_and_test_protocol() {
    local cmd="$1"
    local cmdline="$2"
    local binary=$(which "$cmd" 2>/dev/null || true)
    
    [ -z "$binary" ] && return 1
    
    # Try argcomplete
    if grep -q "PYTHON_ARGCOMPLETE_OK" "$binary" 2>/dev/null; then
        _ARGCOMPLETE=1 \
        _ARGCOMPLETE_COMP_WORDBREAKS=$' \t\n' \
        COMP_LINE="$cmdline" \
        COMP_POINT=${#cmdline} \
        "$cmd" 8>&1 9>&2 1>/dev/null 2>&1 || true
        return 0
    fi
    
    # Try Cobra
    if "$cmd" __complete "${words[@]:1}" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# detect - Identify completion mechanism
completeangler_detect() {
    local cmd="$1"
    local test_mode="${2:-}"
    
    local binary=$(which "$cmd" 2>/dev/null || true)
    if [ -z "$binary" ]; then
        echo "Command not found: $cmd"
        return 1
    fi
    
    echo "Command: $cmd"
    echo "Binary: $binary"
    
    local filetype=$(file "$binary" 2>/dev/null || echo "unknown")
    echo "Type: $filetype"
    echo ""
    
    echo "Shell Completion Check:"
    if complete -p "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Bash completion registered"
        local spec=$(complete -p "$cmd")
        echo "  Spec: $spec"
    else
        echo -e "  ${RED}✗${NC} No bash completion"
    fi
    echo ""
    
    echo "Self-Completion Detection:"
    
    # Python argcomplete
    if grep -q "PYTHON_ARGCOMPLETE_OK" "$binary" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ARGCOMPLETE detected"
        echo "    Marker: PYTHON_ARGCOMPLETE_OK found"
        
        if [ -n "$test_mode" ]; then
            echo "    Testing..."
            if _ARGCOMPLETE=1 COMP_LINE="$cmd " COMP_POINT=$((${#cmd}+1)) "$cmd" 2>/dev/null | head -5; then
                echo -e "    ${GREEN}✓${NC} Responds to argcomplete protocol"
            fi
        fi
        
        echo ""
        echo "  Setup Required:"
        echo "    1. pip install argcomplete"
        echo "    2. activate-global-python-argcomplete --user"
        echo "    3. exec bash"
        return 0
    fi
    
    # Python Click
    if _"${cmd^^}"_COMPLETE=bash_source "$cmd" 2>&1 | grep -q "complete"; then
        echo -e "  ${GREEN}✓${NC} CLICK detected"
        echo "    Environment: _${cmd^^}_COMPLETE"
        echo ""
        echo "  Setup Required:"
        echo "    eval \"\$(_${cmd^^}_COMPLETE=bash_source $cmd)\""
        return 0
    fi
    
    # Go Cobra
    if "$cmd" completion bash --help &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} COBRA detected"
        echo "    Subcommand: completion bash"
        echo ""
        echo "  Setup Required:"
        echo "    source <($cmd completion bash)"
        return 0
    fi
    
    # Go urfave/cli
    if timeout 1 "$cmd" --generate-bash-completion &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} URFAVE/CLI detected"
        echo "    Flag: --generate-bash-completion"
        return 0
    fi
    
    echo -e "  ${RED}✗${NC} No self-completion detected"
    echo ""
    echo "Recommendation:"
    echo "  This command would benefit from custom completion."
    echo "  Run: completeangler niche $cmd"
}

# Load completion definitions for a given command if not already loaded
ca_load_completion() {
    local cmd="$1"

    # Already has a rule?
    complete -p "$cmd" >/dev/null 2>&1 && return

    # If bash-completion provides its loader, use it
    if declare -F _completion_loader >/dev/null 2>&1; then
        _completion_loader "$cmd" 2>/dev/null && return
    fi

    # Fallback: try standard completion directories
    if [ -f "/usr/share/bash-completion/completions/$cmd" ]; then
        source "/usr/share/bash-completion/completions/$cmd" && return
    fi
    if [ -f "$HOME/.local/share/bash-completion/completions/$cmd" ]; then
        source "$HOME/.local/share/bash-completion/completions/$cmd" && return
    fi

    # Docker provides built-in self-generated completion
    if command -v "$cmd" >/dev/null 2>&1 && "$cmd" completion bash >/dev/null 2>&1; then
        "$cmd" completion bash | source /dev/stdin && return
    fi
}



ui_completion() {
    local cmdline="$1"
    local backend="${2:-${UI_BACKEND:-auto}}"

    printf "\n[ui] >>> ENTER ui_completion('%s')\n" "$cmdline" >&2

    if [ "$backend" = "auto" ]; then
        backend=$(command -v fzf >/dev/null 2>&1 && echo fzf || echo native)
    fi
    printf "[ui] backend=%s\n" "$backend" >&2

    if ! declare -F _completion_loader >/dev/null 2>&1; then
        printf "[ui] loading bash-completion\n" >&2
        source /usr/share/bash-completion/bash_completion 2>/dev/null || true
    fi

    COMP_LINE="$cmdline"
    COMP_POINT=${#cmdline}

    local saveIFS="$IFS"
    IFS=$' \t\n'
    read -r -a COMP_WORDS <<<"$cmdline"
    IFS="$saveIFS"

    if [[ "$cmdline" =~ [[:space:]]$ ]]; then
        COMP_WORDS+=("")
    fi

    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))

    printf "[ui] COMP_WORDS(%d):" "${#COMP_WORDS[@]}" >&2
    for w in "${COMP_WORDS[@]}"; do printf " «%s»" "$w" >&2; done
    printf "\n[ui] COMP_CWORD=%d\n" "$COMP_CWORD" >&2

    #
    # Load completion rule (make the latter use the former)
    #
    local target="${COMP_WORDS[0]}"
    ca_load_completion "$target"

    local spec handler prog
    spec=$(complete -p "$target" 2>/dev/null || true)
    printf "[ui] complete spec: %s\n" "$spec" >&2

    COMPREPLY=()

    if [[ $spec =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        handler="${BASH_REMATCH[1]}"
        printf "[ui] calling handler via wrapper: %s\n" "$handler" >&2
        __ca_call_handler() { "$handler"; }
        __ca_call_handler 2>/dev/null || true

    elif [[ $spec =~ -C[[:space:]]+([^[:space:]]+) ]]; then
        prog="${BASH_REMATCH[1]}"
        printf "[ui] calling external generator via wrapper: %s\n" "$prog" >&2
        __ca_call_prog() { "$prog"; }
        __ca_call_prog 2>/dev/null || true

    else
        printf "[ui] no completion handler found\n" >&2
    fi

    local items=("${COMPREPLY[@]}")
    printf "[ui] COMPREPLY -> %d entries\n" "${#items[@]}" >&2

    if [ ${#items[@]} -eq 0 ]; then
        printf "[ui] inserting (none)\n" >&2
        items=("(none)")
    fi

    printf "[ui] items:" >&2
    for w in "${items[@]}"; do printf " «%s»" "$w" >&2; done
    printf "\n" >&2

    case "$backend" in
        fzf)
            printf "[ui] invoking fzf\n" >&2
            local selection
            selection=$(printf '%s\n' "${items[@]}" | fzf --prompt="$cmdline > ")
            printf "[ui] fzf selected: «%s»\n" "$selection" >&2
            [ -n "$selection" ] && [ "$selection" != "(none)" ] && printf '%s\n' "$selection"
            ;;
        native)
            local i idx
            printf "[ui] native menu:\n" >&2
            for ((i=0;i<${#items[@]};i++)); do
                printf " [%d] %s\n" "$i" "${items[$i]}" >&2
            done
            printf "> " >&2
            read -r idx
            [ "$idx" -ge 0 ] && [ "$idx" -lt ${#items[@]} ] && [ "${items[$idx]}" != "(none)" ] && printf '%s\n' "${items[$idx]}"
            ;;
    esac

    printf "[ui] <<< EXIT ui_completion\n\n" >&2
}






# inspect - Show detailed completion information
completeangler_inspect() {
    local cmd="$1"
    local verbose="${2:-}"
    
    local spec=$(complete -p "$cmd" 2>/dev/null || true)
    
    if [ -z "$spec" ]; then
        echo "No completion found for: $cmd"
        return 1
    fi
    
    echo "Command: $cmd"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    local comp_type=""
    local handler=""
    
    if [[ $spec =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        handler="${BASH_REMATCH[1]}"
        printf "[ui] calling handler in subshell: %s\n" "$handler" >&2
        (
            "$handler" 2>/dev/null || true
        )
    elif [[ $spec =~ -C[[:space:]]+([^[:space:]]+) ]]; then
        prog="${BASH_REMATCH[1]}"
        printf "[ui] calling external generator in subshell: %s\n" "$prog" >&2
        (
            "$prog" 2>/dev/null || true
        )
    else
        printf "[ui] no completion handler found\n" >&2
    fi


    echo "Type: $comp_type"

    if [ "$comp_type" = "function" ]; then
        shopt -s extdebug
        local func_info=($(declare -F "$handler" 2>/dev/null || echo "" 0 "unknown"))
        shopt -u extdebug
        if [ -n "${func_info[2]}" ] && [ "${func_info[2]}" != "unknown" ]; then
            echo "Location: ${func_info[2]}:${func_info[1]}"
        fi
        
        if [ -n "$verbose" ]; then
            echo ""
            echo "Function Body:"
            echo "───────────────────────────────────────────────"
            declare -f "$handler" 2>/dev/null || echo "Function not available"
            echo "───────────────────────────────────────────────"
        fi
    fi
    
    echo ""
    echo "Full Specification:"
    echo "  $spec"
    
    echo ""
    echo "Sample Completions:"
    completeangler_test "$cmd " text 2>/dev/null | head -5 | sed 's/^/  /'
}

# trace - Live trace completion execution
completeangler_trace() {
    local cmd="$1"
    
    echo "Tracing completions for: $cmd"
    echo "Use the command normally. Press Ctrl-C to stop."
    echo ""
    
    local spec=$(complete -p "$cmd" 2>/dev/null || true)
    if [[ ! $spec =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        echo "Not a function-based completion"
        return 1
    fi
    
    local handler="${BASH_REMATCH[1]}"
    
    # This is a simplified trace - full implementation would wrap the function
    echo "Completion function: $handler"
    echo "Enable bash debugging with: set -x"
    echo "Then use $cmd and tab-complete to see execution"
}

# search - Search across completions
completeangler_search() {
    local pattern="$1"
    
    echo "Searching for: $pattern"
    echo ""
    
    while read -r line; do
        local cmd=$(echo "$line" | awk '{print $NF}')
        
        # Search in completion results
        local results=$(completeangler_test "$cmd " text 2>/dev/null || true)
        
        if echo "$results" | grep -qi "$pattern"; then
            echo "$cmd:"
            echo "$results" | grep -i "$pattern" | sed 's/^/  /'
            echo ""
        fi
    done < <(complete -p)
}

# list - List all completions
completeangler_list() {
    local filter="${1:-}"
    
    echo "Registered Completions:"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    printf "%-20s %-15s %s\n" "COMMAND" "TYPE" "HANDLER"
    printf "%-20s %-15s %s\n" "-------" "----" "-------"
    
    while read -r line; do
        local cmd=$(echo "$line" | awk '{print $NF}')
        local type="unknown"
        local handler=""
        
        if [[ $line =~ -F[[:space:]]+([^[:space:]]+) ]]; then
            type="function"
            handler="${BASH_REMATCH[1]}"
        elif [[ $line =~ -W ]]; then
            type="wordlist"
            handler="(inline)"
        fi
        
        if [ -z "$filter" ] || [[ "$type" == *"$filter"* ]]; then
            printf "%-20s %-15s %s\n" "$cmd" "$type" "$handler"
        fi
    done < <(complete -p | sort -k3)
}

# ============================================================================
# ANALYSIS VERBS
# ============================================================================

# niche - Identify completion opportunities
completeangler_niche() {
    local cmd="$1"
    
    echo "Analyzing: $cmd"
    echo ""
    
    # Check if command exists
    if ! command -v "$cmd" &>/dev/null; then
        echo "Command not found: $cmd"
        return 1
    fi
    
    # Check for existing completion
    echo "Completion Status:"
    if complete -p "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Shell completion exists"
        echo ""
        echo "Recommendation: LOW - Already has completion"
        return 0
    fi
    
    # Check for self-completion
    local has_self_completion=$(completeangler_detect "$cmd" 2>/dev/null | grep -c "detected" || echo 0)
    if [ "$has_self_completion" -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} Self-completing"
        echo ""
        echo "Recommendation: ACTIVATION_ONLY"
        echo "This command already supports completions!"
        return 0
    fi
    
    echo -e "  ${RED}✗${NC} No existing completion"
    echo ""
    
    # Analyze help output
    echo "Analyzing help output..."
    local help_output=$("$cmd" --help 2>&1 || "$cmd" -h 2>&1 || true)
    
    local flag_count=$(echo "$help_output" | grep -cE '^\s*-' || echo 0)
    local has_subcommands=$(echo "$help_output" | grep -ciE '(commands:|subcommands:)' || echo 0)
    
    echo "  Flags detected: $flag_count"
    echo "  Subcommands: $([ $has_subcommands -gt 0 ] && echo 'Yes' || echo 'No')"
    echo ""
    
    # Make recommendation
    echo "Completion Opportunities:"
    if [ "$flag_count" -gt 10 ] || [ "$has_subcommands" -gt 0 ]; then
        echo -e "  ${GREEN}Recommendation: HIGH${NC}"
        echo "  This command would benefit significantly from completions"
        echo ""
        echo "Next steps:"
        echo "  1. completeangler implementation $cmd"
        echo "  2. completeangler scaffold $cmd"
    elif [ "$flag_count" -gt 3 ]; then
        echo -e "  ${YELLOW}Recommendation: MEDIUM${NC}"
        echo "  This command could benefit from completions"
    else
        echo -e "  Recommendation: LOW"
        echo "  Simple command, completion may not add much value"
    fi
}

# implementation - Suggest completion patterns
completeangler_implementation() {
    local cmd="$1"
    
    echo "Analyzing: $cmd"
    echo ""
    
    local help_output=$("$cmd" --help 2>&1 || "$cmd" -h 2>&1 || true)
    
    local has_subcommands=$(echo "$help_output" | grep -ciE '(commands:|subcommands:)' || echo 0)
    local flag_count=$(echo "$help_output" | grep -cE '^\s*-' || echo 0)
    
    echo "Command Structure:"
    echo "  Subcommands: $([ $has_subcommands -gt 0 ] && echo 'Yes' || echo 'No')"
    echo "  Flags: $flag_count"
    echo ""
    
    local pattern="SIMPLE_FLAGS"
    local complexity="Low"
    
    if [ "$has_subcommands" -gt 0 ]; then
        pattern="SUBCOMMAND_DISPATCHER"
        complexity="Medium"
    elif [ "$flag_count" -gt 20 ]; then
        pattern="STATE_MACHINE"
        complexity="Medium"
    fi
    
    echo "Recommended Pattern: $pattern"
    echo "Complexity: $complexity"
    echo ""
    
    case "$pattern" in
        SIMPLE_FLAGS)
            cat <<'EOF'
Implementation: Simple flag completion
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_mycommand() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "--help --version --verbose" -- "$cur"))
}
complete -F _mycommand mycommand

Estimated time: 30 minutes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
            ;;
        SUBCOMMAND_DISPATCHER)
            cat <<'EOF'
Implementation: Subcommand dispatcher (Git-style)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_mycommand() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"
  
  case "$prev" in
    mycommand)
      COMPREPLY=($(compgen -W "start stop restart status" -- "$cur"))
      ;;
    *)
      COMPREPLY=($(compgen -W "--help --verbose" -- "$cur"))
      ;;
  esac
}
complete -F _mycommand mycommand

Estimated time: 2-3 hours
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
            ;;
    esac
    
    echo ""
    echo "Next Steps:"
    echo "  completeangler scaffold $cmd --pattern $pattern"
}

# ============================================================================
# DEVELOPMENT VERBS
# ============================================================================

# extract - Auto-generate from help
completeangler_extract() {
    local cmd="$1"
    
    echo "Extracting completion from help for: $cmd"
    echo ""
    
    local help_output=$("$cmd" --help 2>&1 || "$cmd" -h 2>&1 || true)
    
    echo "Detected Flags:"
    local flags=$(echo "$help_output" | grep -oE '\-\-[a-z0-9-]+' | sort -u)
    echo "$flags" | sed 's/^/  /'
    
    echo ""
    echo "Generated Completion:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cat <<EOF
_${cmd}() {
    local cur="\${COMP_WORDS[COMP_CWORD]}"
    local flags="$flags"
    COMPREPLY=(\$(compgen -W "\$flags" -- "\$cur"))
}
complete -F _${cmd} $cmd
EOF
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# scaffold - Generate boilerplate
completeangler_scaffold() {
    local cmd="$1"
    local pattern="${2:-simple}"
    local output="${3:-$cmd-completion.sh}"
    
    echo "Scaffolding completion for: $cmd"
    echo "Pattern: $pattern"
    echo "Output: $output"
    echo ""
    
    case "$pattern" in
        simple)
            cat > "$output" <<EOF
# Bash completion for $cmd
# Generated by completeangler

_${cmd}() {
    local cur="\${COMP_WORDS[COMP_CWORD]}"
    local prev="\${COMP_WORDS[COMP_CWORD-1]}"
    
    # TODO: Add your flags here
    local flags="--help --version --verbose --quiet"
    
    case "\$prev" in
        --config|-c)
            COMPREPLY=(\$(compgen -f -- "\$cur"))
            return 0
            ;;
    esac
    
    if [[ "\$cur" == -* ]]; then
        COMPREPLY=(\$(compgen -W "\$flags" -- "\$cur"))
    else
        COMPREPLY=(\$(compgen -f -- "\$cur"))
    fi
}

complete -F _${cmd} $cmd
EOF
            ;;
        subcommand)
            cat > "$output" <<EOF
# Bash completion for $cmd
# Generated by completeangler

_${cmd}() {
    local cur="\${COMP_WORDS[COMP_CWORD]}"
    local prev="\${COMP_WORDS[COMP_CWORD-1]}"
    
    # TODO: Add your subcommands
    local subcommands="start stop restart status"
    local global_flags="--help --verbose"
    
    # Find subcommand
    local subcommand=""
    local i
    for ((i=1; i < COMP_CWORD; i++)); do
        if [[ " \$subcommands " =~ " \${COMP_WORDS[i]} " ]]; then
            subcommand="\${COMP_WORDS[i]}"
            break
        fi
    done
    
    if [ -z "\$subcommand" ]; then
        COMPREPLY=(\$(compgen -W "\$subcommands \$global_flags" -- "\$cur"))
        return 0
    fi
    
    # Subcommand-specific completion
    case "\$subcommand" in
        start|stop|restart)
            COMPREPLY=(\$(compgen -W "--force --timeout" -- "\$cur"))
            ;;
        *)
            COMPREPLY=(\$(compgen -W "\$global_flags" -- "\$cur"))
            ;;
    esac
}

complete -F _${cmd} $cmd
EOF
            ;;
    esac
    
    echo -e "${GREEN}✓${NC} Created: $output"
    echo ""
    echo "Next steps:"
    echo "  1. Edit: \$EDITOR $output"
    echo "  2. Test: completeangler test '$cmd '"
    echo "  3. Load: source $output"
}

# watch - Live reload during development
completeangler_watch() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo "File not found: $file"
        return 1
    fi
    
    echo "Watching: $file"
    echo "Press Ctrl-C to stop"
    echo ""
    
    # Load initially
    echo "Loading completion..."
    if source "$file" 2>&1; then
        echo -e "${GREEN}✓${NC} Loaded successfully"
    else
        echo -e "${RED}✗${NC} Error loading completion"
    fi
    echo ""
    
    # Watch for changes (simplified - real implementation would use inotify)
    local last_modified=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file")
    
    while true; do
        sleep 2
        
        local current_modified=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file")
        
        if [ "$current_modified" != "$last_modified" ]; then
            echo "[$(date '+%H:%M:%S')] File changed, reloading..."
            
            if bash -n "$file" 2>&1; then
                if source "$file" 2>&1; then
                    echo -e "${GREEN}✓${NC} Reloaded successfully"
                else
                    echo -e "${RED}✗${NC} Error reloading"
                fi
            else
                echo -e "${RED}✗${NC} Syntax error"
            fi
            
            echo ""
            last_modified="$current_modified"
        fi
    done
}

# snippet - Show code patterns
completeangler_snippet() {
    local type="$1"
    shift
    
    case "$type" in
        files)
            cat <<'EOF'
# Complete files with specific extension
COMPREPLY=($(compgen -f -X '!*.json' -- "$cur"))

# Complete only directories
COMPREPLY=($(compgen -d -- "$cur"))
EOF
            ;;
        flags)
            local flags="$*"
            cat <<EOF
# Complete flags
local flags="$flags"
COMPREPLY=(\$(compgen -W "\$flags" -- "\$cur"))
EOF
            ;;
        subcommands)
            local subcommands="$*"
            cat <<EOF
# Complete subcommands
local subcommands="$subcommands"
COMPREPLY=(\$(compgen -W "\$subcommands" -- "\$cur"))
EOF
            ;;
        dynamic)
            cat <<'EOF'
# Dynamic completion from command output
local items=$(mycommand list 2>/dev/null)
COMPREPLY=($(compgen -W "$items" -- "$cur"))
EOF
            ;;
        hosts)
            cat <<'EOF'
# Complete hostnames from known_hosts
local hosts=$(awk '{print $1}' ~/.ssh/known_hosts 2>/dev/null | cut -d, -f1)
COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
EOF
            ;;
        users)
            cat <<'EOF'
# Complete usernames
COMPREPLY=($(compgen -u -- "$cur"))
EOF
            ;;
        git-branches)
            cat <<'EOF'
# Complete git branches
local branches=$(git branch --format='%(refname:short)' 2>/dev/null)
COMPREPLY=($(compgen -W "$branches" -- "$cur"))
EOF
            ;;
        *)
            echo "Unknown snippet type: $type"
            echo ""
            echo "Available snippets:"
            echo "  files flags subcommands dynamic hosts users git-branches"
            return 1
            ;;
    esac
}

# ============================================================================
# QUALITY VERBS
# ============================================================================

# profile - Performance analysis
completeangler_profile() {
    local cmd="$1"
    local iterations="${2:-100}"
    
    echo "Profiling completion for: $cmd"
    echo "Iterations: $iterations"
    echo ""
    
    local spec=$(complete -p "$cmd" 2>/dev/null || true)
    if [[ ! $spec =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        echo "Not a function-based completion"
        return 1
    fi
    
    local handler="${BASH_REMATCH[1]}"
    
    echo "Running benchmark..."
    local start=$(date +%s%N)
    
    for ((i=0; i<iterations; i++)); do
        COMP_WORDS=($cmd "")
        COMP_CWORD=1
        COMP_LINE="$cmd "
        COMP_POINT=${#COMP_LINE}
        COMPREPLY=()
        $handler "$cmd" "" "" 2>/dev/null || true
    done
    
    local end=$(date +%s%N)
    local total_ms=$(( (end - start) / 1000000 ))
    local avg_ms=$(( total_ms / iterations ))
    
    echo ""
    echo "Performance Results:"
    echo "═══════════════════════════════════════════════"
    echo "Total time: ${total_ms}ms"
    echo "Average per completion: ${avg_ms}ms"
    [ $avg_ms -gt 0 ] && echo "Completions per second: $(( 1000 / avg_ms ))"
    echo ""
    
    echo "Performance Rating:"
    if [ "$avg_ms" -lt 50 ]; then
        echo -e "  ${GREEN}✓ EXCELLENT${NC} (< 50ms) - Users won't notice delay"
    elif [ "$avg_ms" -lt 150 ]; then
        echo -e "  ${GREEN}✓ GOOD${NC} (50-150ms) - Acceptable"
    elif [ "$avg_ms" -lt 300 ]; then
        echo -e "  ${YELLOW}⚠ FAIR${NC} (150-300ms) - Noticeable delay"
    else
        echo -e "  ${RED}✗ POOR${NC} (> 300ms) - Needs optimization"
    fi
    
    # Check for external commands
    echo ""
    echo "Bottleneck Analysis:"
    local func_body=$(declare -f "$handler")
    local external_cmds=$(echo "$func_body" | grep -oE '\$\([^)]+\)' | sed 's/\$(\|)//g' || true)
    
    if [ -n "$external_cmds" ]; then
        echo -e "  ${YELLOW}⚠${NC} External commands detected (may be slow):"
        echo "$external_cmds" | sed 's/^/    /'
        echo ""
        echo "  Suggestion: Cache these results"
    else
        echo -e "  ${GREEN}✓${NC} No external commands detected"
    fi
}

# lint - Check for issues
completeangler_lint() {
    local cmd="$1"
    
    echo "Linting completion for: $cmd"
    echo ""
    
    local spec=$(complete -p "$cmd" 2>/dev/null || true)
    
    if [ -z "$spec" ]; then
        echo -e "${RED}ERROR${NC}: No completion registered"
        return 1
    fi
    
    local issues=0
    local warnings=0
    
    if [[ $spec =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        local handler="${BASH_REMATCH[1]}"
        
        # Check if function exists
        if ! declare -f "$handler" &>/dev/null; then
            echo -e "${RED}ERROR${NC}: Completion function '$handler' not defined"
            ((issues++))
        else
            local func_body=$(declare -f "$handler")
            
            # Check for syntax errors
            if ! bash -n <(echo "$func_body") 2>/dev/null; then
                echo -e "${RED}ERROR${NC}: Syntax error in function"
                ((issues++))
            fi
            
            # Check for unquoted variables
            if echo "$func_body" | grep -q '\$COMP_WORDS\[' && \
               ! echo "$func_body" | grep -q '"\${COMP_WORDS\['; then
                echo -e "${YELLOW}WARNING${NC}: Unquoted COMP_WORDS array access"
                ((warnings++))
            fi
            
            # Check for missing local declarations
            if echo "$func_body" | grep -q 'cur=' && \
               ! echo "$func_body" | grep -q 'local cur'; then
                echo -e "${YELLOW}WARNING${NC}: Variable 'cur' not declared as local"
                ((warnings++))
            fi
            
            # Check for expensive operations
            if echo "$func_body" | grep -qE '\$\((find|locate|grep -r)'; then
                echo -e "${YELLOW}WARNING${NC}: Expensive operation detected"
                echo "  Consider caching or optimizing"
                ((warnings++))
            fi
            
            # Function size
            local line_count=$(echo "$func_body" | wc -l)
            if [ "$line_count" -gt 100 ]; then
                echo -e "${YELLOW}WARNING${NC}: Large function ($line_count lines)"
                echo "  Consider breaking into smaller functions"
                ((warnings++))
            fi
        fi
    fi
    
    echo ""
    echo "Summary:"
    echo "  Errors: $issues"
    echo "  Warnings: $warnings"
    
    if [ "$issues" -eq 0 ] && [ "$warnings" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} No issues found"
        return 0
    else
        [ "$issues" -gt 0 ] && return 1
        return 0
    fi
}

# validate - Verify completions work
completeangler_validate() {
    local cmd="$1"
    
    echo "Validating completion for: $cmd"
    echo ""
    
    local passed=0
    local failed=0
    
    # Test 1: Completion exists
    echo -n "Test: Completion registered ... "
    if complete -p "$cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((passed++))
    else
        echo -e "${RED}✗${NC}"
        ((failed++))
    fi
    
    # Test 2: Function is defined
    local spec=$(complete -p "$cmd" 2>/dev/null || true)
    if [[ $spec =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        local handler="${BASH_REMATCH[1]}"
        
        echo -n "Test: Function defined ... "
        if declare -f "$handler" &>/dev/null; then
            echo -e "${GREEN}✓${NC}"
            ((passed++))
        else
            echo -e "${RED}✗${NC}"
            ((failed++))
        fi
        
        # Test 3: No syntax errors
        echo -n "Test: Syntax check ... "
        if bash -n <(declare -f "$handler") 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
            ((passed++))
        else
            echo -e "${RED}✗${NC}"
            ((failed++))
        fi
    fi
    
    # Test 4: Basic completion works
    echo -n "Test: Basic completion ... "
    if completeangler_test "$cmd " >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        ((passed++))
    else
        echo -e "${RED}✗${NC}"
        ((failed++))
    fi
    
    echo ""
    echo "Results: $passed passed, $failed failed"
    
    [ "$failed" -eq 0 ] && return 0 || return 1
}

# ============================================================================
# UTILITY VERBS
# ============================================================================

# repl - Interactive shell
completeangler_repl() {
    echo "completeangler REPL"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "Commands: test, why, inspect, detect, profile, help, exit"
    echo ""
    
    while true; do
        read -p "completeangler> " repl_input || break
        
        [ -z "$repl_input" ] && continue
        
        local cmd_verb=$(echo "$repl_input" | awk '{print $1}')
        local cmd_args=$(echo "$repl_input" | cut -d' ' -f2-)
        
        case "$cmd_verb" in
            test)
                completeangler_test "$cmd_args"
                ;;
            why)
                completeangler_why "$cmd_args"
                ;;
            inspect)
                completeangler_inspect "$cmd_args"
                ;;
            detect)
                completeangler_detect "$cmd_args"
                ;;
            profile)
                completeangler_profile "$cmd_args"
                ;;
            help)
                echo "Available: test, why, inspect, detect, profile, help, exit"
                ;;
            exit|quit)
                break
                ;;
            *)
                echo "Unknown command: $cmd_verb"
                ;;
        esac
        
        echo ""
    done
}

# record - Log completion usage
completeangler_record() {
    local action="$1"
    local log_file="${LOG_FILE:-$COMPLETEANGLER_HOME/logs/completions.log}"
    
    case "$action" in
        start)
            echo "Starting completion logging..."
            mkdir -p "$(dirname "$log_file")"
            echo "Log file: $log_file"
            echo ""
            echo "Note: Full logging requires function wrapping"
            echo "This is a simplified version that logs to: $log_file"
            ;;
        stop)
            echo "Stopping completion logging..."
            echo "Log preserved at: $log_file"
            ;;
        status)
            if [ -f "$log_file" ]; then
                echo "Logging: active"
                echo "Log file: $log_file"
                echo "Log size: $(du -h "$log_file" 2>/dev/null | cut -f1)"
                echo "Entries: $(wc -l < "$log_file" 2>/dev/null || echo 0)"
            else
                echo "Logging: inactive"
            fi
            ;;
    esac
}

# stats - Usage analytics
completeangler_stats() {
    local cmd="$1"
    local log_file="${LOG_FILE:-$COMPLETEANGLER_HOME/logs/completions.log}"
    
    if [ ! -f "$log_file" ]; then
        echo "No log file found. Start recording with: completeangler record start"
        return 1
    fi
    
    echo "Completion Statistics"
    echo "═══════════════════════════════════════════════"
    echo ""
    
    if [ -n "$cmd" ]; then
        echo "Command: $cmd"
        local count=$(grep -c "|$cmd|" "$log_file" 2>/dev/null || echo 0)
        echo "Total completions: $count"
    else
        echo "Most completed commands:"
        cut -d'|' -f2 "$log_file" 2>/dev/null | sort | uniq -c | sort -rn | head -10 || echo "No data"
    fi
}

# report - Generate reports
completeangler_report() {
    local report_type="$1"
    
    case "$report_type" in
        slow)
            echo "Slow Completions Report"
            echo "═══════════════════════════════════════════════"
            echo ""
            echo "Testing completions for performance..."
            echo "(This may take a while)"
            echo ""
            
            while read -r line; do
                local cmd=$(echo "$line" | awk '{print $NF}')
                # Simplified - would need full profiling
                echo "$cmd: (use 'completeangler profile $cmd' for details)"
            done < <(complete -p | head -5)
            ;;
        unused)
            echo "Unused Completions Report"
            echo "═══════════════════════════════════════════════"
            echo ""
            echo "Note: Requires logging to be enabled"
            ;;
        conflicts)
            echo "Completion Conflicts Report"
            echo "═══════════════════════════════════════════════"
            echo ""
            complete -p | awk '{print $NF}' | sort | uniq -d | while read cmd; do
                echo "⚠ Multiple completions for: $cmd"
            done || echo "No conflicts found"
            ;;
        *)
            echo "Unknown report type: $report_type"
            echo ""
            echo "Available reports:"
            echo "  slow       - Completions slower than 150ms"
            echo "  unused     - Completions never used"
            echo "  conflicts  - Multiple definitions"
            ;;
    esac
}

# diff - Compare completions
completeangler_diff() {
    local cmd1="$1"
    local cmd2="$2"
    
    echo "Comparing completions:"
    echo "  Command 1: $cmd1"
    echo "  Command 2: $cmd2"
    echo ""
    
    local spec1=$(complete -p "$cmd1" 2>/dev/null || true)
    local spec2=$(complete -p "$cmd2" 2>/dev/null || true)
    
    echo "Specification Difference:"
    echo "───────────────────────────────────────────────"
    diff <(echo "$spec1") <(echo "$spec2") 2>/dev/null || echo "No difference or commands not found"
    
    echo ""
    echo "Result Difference:"
    echo "───────────────────────────────────────────────"
    
    local result1=$(completeangler_test "$cmd1 " 2>/dev/null | sort)
    local result2=$(completeangler_test "$cmd2 " 2>/dev/null | sort)
    
    local only_in_1=$(comm -23 <(echo "$result1") <(echo "$result2") 2>/dev/null || true)
    local only_in_2=$(comm -13 <(echo "$result1") <(echo "$result2") 2>/dev/null || true)
    
    if [ -n "$only_in_1" ]; then
        echo "Only in $cmd1:"
        echo "$only_in_1" | sed 's/^/  /'
    fi
    
    if [ -n "$only_in_2" ]; then
        echo "Only in $cmd2:"
        echo "$only_in_2" | sed 's/^/  /'
    fi
    
    if [ -z "$only_in_1" ] && [ -z "$only_in_2" ]; then
        echo "✓ Identical results"
    fi
}

# export - Export completion
completeangler_export() {
    local cmd="$1"
    local output="${2:-${cmd}-completion.sh}"
    
    echo "Exporting completion for: $cmd"
    
    local spec=$(complete -p "$cmd" 2>/dev/null || true)
    
    if [ -z "$spec" ]; then
        echo "ERROR: No completion found for $cmd"
        return 1
    fi
    
    {
        echo "# Bash completion for $cmd"
        echo "# Exported by completeangler"
        echo "# Date: $(date)"
        echo ""
        
        if [[ $spec =~ -F[[:space:]]+([^[:space:]]+) ]]; then
            local handler="${BASH_REMATCH[1]}"
            declare -f "$handler" 2>/dev/null || echo "# Function not available"
            echo ""
        fi
        
        echo "$spec"
    } > "$output"
    
    echo -e "${GREEN}✓${NC} Exported to: $output"
}

# whoami - Explain the current shell + completion context
completeangler_whoami() {
    echo "completeangler environment:"
    echo ""

    # Local shell (where user typed)
    local local_shell="${SHELL##*/}"
    echo "Local Shell (where you typed):"
    echo "  $local_shell"
    [ -n "${ZSH_VERSION:-}" ] && echo "  Detected: zsh (interactive)"
    [ -n "${BASH_VERSION:-}" ] && echo "  Detected: bash (interactive)"
    echo ""

    # Remote shell (where completeangler actually executes)
    echo "Remote Shell (where completions run):"
    if [ -n "${COMPLETEANGLER_SHELL:-}" ]; then
        echo "  $COMPLETEANGLER_SHELL (detected)"
    else
        echo "  Unknown (fallback: $local_shell)"
    fi
    echo ""

    # Completion system availability
    echo "Completion Providers:"
    if [ "$COMPLETEANGLER_SHELL" = "bash" ]; then
        if declare -F _init_completion >/dev/null 2>&1; then
            echo "  bash-completion: active"
        else
            echo "  bash-completion: not loaded"
        fi
    else
        if typeset -f compinit >/dev/null 2>&1; then
            echo "  zsh compinit: active"
        else
            echo "  zsh compinit: not loaded"
        fi
    fi
    echo ""

    # OS check (useful for macOS→linux SSH confusion)
    echo "Remote OS:"
    uname -a 2>/dev/null || echo "  unknown"

    echo ""
    echo "Interpretation:"
    if [ "$local_shell" = "zsh" ] && [ "$COMPLETEANGLER_SHELL" = "bash" ]; then
        echo "You are using Zsh locally, but completions being analyzed are from Bash on the remote host."
        echo "This means 'why' will NOT see completions provided by your local zsh."
    elif [ "$local_shell" = "$COMPLETEANGLER_SHELL" ]; then
        echo "Your local and remote shells match — completion behavior should match."
    else
        echo "Mixed shell situation detected."
    fi
}

completeangler_doctor_shells() {
    echo "completeangler doctor shells"
    echo "═══════════════════════════════════════════════"
    echo ""

    # Local vs remote shell mismatch
    local local_shell="${SHELL##*/}"
    local remote_shell="${COMPLETEANGLER_SHELL:-unknown}"

    echo "Local Shell:  $local_shell"
    echo "Remote Shell: $remote_shell"
    echo ""

    # Detect local completion frameworks
    if [ -n "${ZSH_VERSION:-}" ]; then
        if typeset -f compinit >/dev/null 2>&1; then
            echo "Local zsh completion: enabled (compinit loaded)"
        else
            echo "Local zsh completion: NOT loaded"
        fi
    fi

    if [ -n "${BASH_VERSION:-}" ]; then
        if declare -F _init_completion >/dev/null 2>&1; then
            echo "Local bash-completion: enabled"
        else
            echo "Local bash-completion: NOT loaded"
        fi
    fi

    echo ""

    # Detect remote completion
    if [ "$remote_shell" = "bash" ]; then
        if declare -F _init_completion >/dev/null 2>&1; then
            echo "Remote bash-completion: enabled"
        else
            echo "Remote bash-completion: NOT loaded"
        fi
    fi

    echo ""

    # If mismatch detected, explain it
    if [ "$local_shell" = "zsh" ] && [ "$remote_shell" = "bash" ]; then
        echo "Diagnosis:"
        echo "  Your Tab key triggers zsh completion locally."
        echo "  completeangler analyzes completions on the remote bash shell."
        echo "  Therefore, 'why' may not see completions that already happened locally."
        echo ""
        echo "Suggested Action:"
        echo "  Run completeangler locally as well to inspect zsh completions."
        echo "  Or switch to remote completion mode (ask: 'how do I use remote mode?')."
    else
        echo "No issues detected. Local and remote completion layers align."
    fi
}

completeangler_doctor_explain() {
    local cmd="$1"

    echo "Completion Context Report for: $cmd"
    echo "=========================================="
    echo ""

    # Detect local shell
    local local_shell="unknown"
    [ -n "${ZSH_VERSION:-}" ] && local_shell="zsh"
    [ -n "${BASH_VERSION:-}" ] && local_shell="bash"

    # Detect remote shell if SSH
    local remote_shell="none"
    if [ -n "${SSH_CONNECTION:-}" ]; then
        remote_shell=$(ps -p $$ -o comm= 2>/dev/null || echo "unknown")
    fi

    echo "Local Shell: $local_shell"
    if [ "$remote_shell" != "none" ]; then
        echo "Remote Shell (via SSH): $remote_shell"
    fi
    echo ""

    # Determine where Tab completion is actually happening
    if [ "$remote_shell" = "none" ]; then
        echo "Tab completion is happening LOCALLY."
    else
        echo "Tab completion is happening LOCALLY (even though you are SSH'd)."
        echo "This is because the editor line is handled before network transport."
    fi
    echo ""

    # Detect LOCAL completion provider
    if [ "$local_shell" = "zsh" ]; then
        if whence -w "_${cmd}" >/dev/null 2>&1; then
            echo "Local Completion Provider:"
            echo "  zsh function: _${cmd}"
        else
            echo "Local Completion Provider:"
            echo "  No zsh completion found for $cmd"
        fi
    else
        local spec_local
        spec_local=$(complete -p "$cmd" 2>/dev/null || true)
        if [ -n "$spec_local" ]; then
            echo "Local Completion Provider:"
            echo "  $spec_local"
        else
            echo "Local Completion Provider:"
            echo "  No bash completion found locally for $cmd"
        fi
    fi
    echo ""

    # Detect REMOTE completion (only if SSH)
    if [ "$remote_shell" != "none" ]; then
        local spec_remote
        spec_remote=$(complete -p "$cmd" 2>/dev/null || true)
        echo "Remote Completion Provider (as inspected by completeangler):"
        if [ -n "$spec_remote" ]; then
            echo "  $spec_remote"
        else
            echo "  No registered remote completion"
        fi
        echo ""
    fi

    echo "Conclusion:"
    if [ "$remote_shell" != "none" ]; then
        echo "  The completions you *experience* when pressing Tab are provided by the LOCAL shell."
        echo "  The completions completeangler reports are from the REMOTE shell."
        echo "  Both are correct; they are simply different completion engines."
    else
        echo "  The completion you see matches the one completeangler is inspecting."
    fi
}




# import - Import completion
completeangler_import() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo "ERROR: File not found: $file"
        return 1
    fi
    
    echo "Importing completion from: $file"
    
    if ! bash -n "$file" 2>/dev/null; then
        echo "ERROR: Syntax error in file"
        return 1
    fi
    
    if source "$file" 2>&1; then
        echo -e "${GREEN}✓${NC} Imported successfully"
    else
        echo "ERROR: Failed to import"
        return 1
    fi
}

# lazy-report - Identify lazy-loaded completion candidates
completeangler_lazy_report() {
    echo "Lazy Completion Report"
    echo "══════════════════════════════════════════════"
    echo ""

    if [ -n "$ZSH_VERSION" ]; then
        # Zsh
        autoload -Uz compinit 2>/dev/null
        compinit -i 2>/dev/null

        # Completion functions in $fpath but not currently loaded
        local lazy
        lazy=$(for f in $fpath/_*; do
            local fn=${f:t}
            if ! typeset -f "$fn" >/dev/null 2>&1; then
                echo "$fn"
            fi
        done | sort)

        if [ -z "$lazy" ]; then
            echo "No lazy completions. All completions already loaded."
            return 0
        fi

        echo "Zsh autoloadable completions not yet loaded:"
        echo ""
        echo "$lazy" | sed 's/^/  - /'
        return 0
    fi

    # Bash
    local compdir="/usr/share/bash-completion/completions"
    if [ ! -d "$compdir" ]; then
        echo "No bash-completion directory found at $compdir"
        return 1
    fi

    local available active lazy
    available=$(ls "$compdir" 2>/dev/null | sort)
    active=$(complete -p 2>/dev/null | awk '{print $NF}' | sort)
    lazy=$(comm -23 <(echo "$available") <(echo "$active"))

    if [ -z "$lazy" ]; then
        echo "No lazy completions. All completions already loaded."
        return 0
    fi

    echo "Bash autoloadable completions not yet loaded:"
    echo ""
    echo "$lazy" | sed 's/^/  - /'
}


# preload - Preload all lazy-loaded completion scripts
completeangler_preload() {
    echo "Preloading completions..."
    echo ""

    if [ -n "$ZSH_VERSION" ]; then
        # Zsh: load every autoloadable completion function in fpath
        autoload -Uz compinit 2>/dev/null
        compinit -i 2>/dev/null

        local loaded=0 skipped=0

        for f in $fpath/_*; do
            local fn=${f:t}
            if typeset -f "$fn" >/dev/null 2>&1; then
                ((skipped++))
                continue
            fi
            autoload -Uz "$fn" 2>/dev/null && ((loaded++))
        done

        echo "Loaded:  $loaded"
        echo "Skipped: $skipped (already active)"
        echo ""
        return 0
    fi

    # Bash
    local compdir="/usr/share/bash-completion/completions"
    if [ ! -d "$compdir" ]; then
        echo "No bash-completion directory found at $compdir"
        return 1
    fi

    local loaded=0 skipped=0 failed=0

    for f in "$compdir"/*; do
        local cmd="${f##*/}"
        if complete -p "$cmd" >/dev/null 2>&1; then
            ((skipped++))
            continue
        fi

        if declare -F _completion_loader >/dev/null 2>&1; then
            _completion_loader "$cmd" >/dev/null 2>&1 && { ((loaded++)); continue; }
        fi

        source "$f" >/dev/null 2>&1 && ((loaded++)) || ((failed++))
    done

    echo "Loaded:  $loaded"
    echo "Skipped: $skipped"
    echo "Failed:  $failed"
    echo ""
}


completeangler_fishfishing_list() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        printf "usage: completeangler fishfishing list <command>\n" >&2
        return 1
    fi

    # Search standard fish completion directories
    local dirs=(
        "$HOME/.config/fish/completions"
        "/usr/share/fish/completions"
        "/usr/share/fish/vendor_completions.d"
        "/usr/local/share/fish/completions"
        "/usr/local/share/fish/vendor_completions.d"
    )

    local file
    for d in "${dirs[@]}"; do
        file="$d/$cmd.fish"
        if [[ -f "$file" ]]; then
            printf "COMMAND: %s\nSOURCE:  %s\n\n" "$cmd" "$file"
            sed 's/^/  /' "$file"
            return 0
        fi
    done

    printf "No fish completion rules found for: %s\n" "$cmd"
    return 1
}

completeangler_fishfishing_paths() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        printf "usage: completeangler fishfishing paths <command>\n" >&2
        return 1
    fi

    local dirs=(
        "$HOME/.config/fish/completions"
        "/usr/share/fish/completions"
        "/usr/share/fish/vendor_completions.d"
        "/usr/local/share/fish/completions"
        "/usr/local/share/fish/vendor_completions.d"
    )

    local d file
    for d in "${dirs[@]}"; do
        file="$d/$cmd.fish"
        if [[ -f "$file" ]]; then
            printf "[FOUND] %s\n" "$file"
        else
            printf "[MISSING] %s\n" "$file"
        fi
    done
}

completeangler_fishfishing_scaffold() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        printf "usage: completeangler fishfishing scaffold <command>\n" >&2
        return 1
    fi

    local out="$HOME/.config/fish/completions/$cmd.fish"
    mkdir -p "$HOME/.config/fish/completions"

    if [[ -f "$out" ]]; then
        printf "Refusing to overwrite existing file: %s\n" "$out" >&2
        return 1
    fi

    cat > "$out" <<EOF
# Fish completion scaffold for: $cmd
# Add subcommands or flags below.

# Example:
# complete --command $cmd --arguments "start stop status" --description "Subcommands"

EOF

    printf "Created scaffold: %s\n" "$out"
}


completeangler_fishfishing_explain() {
    local input="$*"
    if [[ -z "$input" ]]; then
        printf "usage: completeangler fishfishing explain <partial command line>\n" >&2
        return 1
    fi

    # Split into words
    local cmd
    cmd="${input%% *}"

    if [[ -z "$cmd" ]]; then
        printf "cannot determine command from input\n" >&2
        return 1
    fi

    # Locate the fish completion file
    local dirs=(
        "$HOME/.config/fish/completions"
        "/usr/share/fish/completions"
        "/usr/share/fish/vendor_completions.d"
        "/usr/local/share/fish/completions"
        "/usr/local/share/fish/vendor_completions.d"
    )

    local file
    for d in "${dirs[@]}"; do
        file="$d/$cmd.fish"
        if [[ -f "$file" ]]; then
            printf "COMMAND: %s\nSOURCE:  %s\n\n" "$cmd" "$file"
            printf "Relevant completion rules:\n\n"
            grep -n "complete" "$file" | sed 's/^/  /'
            return 0
        fi
    done

    printf "No fish completion rules found for: %s\n" "$cmd"
    return 1
}


completeangler_fishfishing_extract() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        printf "usage: completeangler fishfishing extract <command>\n" >&2
        return 1
    fi

    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf "command not found: %s\n" "$cmd" >&2
        return 1
    fi

    # Capture help text
    local help
    help="$("$cmd" --help 2>/dev/null || true)"

    printf "# Generated fish completions for %s\n" "$cmd"
    printf "# Edit as needed.\n\n"

    # Extract one-word tokens before descriptions (typical subcommand pattern)
    printf "%s" "$help" |
        awk '
            # match e.g. "  deploy   Create ..." or "  build  ... "
            /^[[:space:]]+[a-zA-Z0-9_-]+[[:space:]]/ {
                sub(/^[ \t]+/, "", $0)
                sub(/[ \t].*$/, "", $0)
                print $0
            }
        ' |
        sort -u |
        while read -r sub; do
            printf "complete --command %s --arguments \"%s\" --description \"%s subcommand\"\n" "$cmd" "$sub" "$sub"
        done
}


completeangler_fishfishing_convert() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        printf "usage: completeangler fishfishing convert <command>\n" >&2
        return 1
    fi

    # First check if bash has a registered completion
    local bash_def
    bash_def="$(complete -p "$cmd" 2>/dev/null || true)"

    if [[ -z "$bash_def" ]]; then
        # no bash completion: fallback to extract
        completeangler_fishfishing_extract "$cmd"
        return $?
    fi

    printf "# Converted from bash completion for %s\n" "$cmd"
    printf "# Further refinement is recommended.\n\n"

    # Extract likely subcommands using the help backoff
    completeangler_fishfishing_extract "$cmd"
}


completeangler_fishfishing_diff() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        printf "usage: completeangler fishfishing diff <command>\n" >&2
        return 1
    fi

    local user="$HOME/.config/fish/completions/$cmd.fish"
    local vendor=""

    for d in \
        "/usr/share/fish/vendor_completions.d" \
        "/usr/share/fish/completions" \
        "/usr/local/share/fish/vendor_completions.d" \
        "/usr/local/share/fish/completions"
    do
        if [[ -f "$d/$cmd.fish" ]]; then
            vendor="$d/$cmd.fish"
            break
        fi
    done

    if [[ ! -f "$user" && -z "$vendor" ]]; then
        printf "No fish completion files found for: %s\n" "$cmd"
        return 1
    fi

    if [[ ! -f "$user" ]]; then
        printf "Only vendor completion exists: %s\n" "$vendor"
        return 0
    fi

    if [[ -z "$vendor" ]]; then
        printf "Only user completion exists: %s\n" "$user"
        return 0
    fi

    diff -u "$vendor" "$user"
}




completeangler_fishfishing_dispatch() {
    local cmd="$1"
    shift || true

    case "$cmd" in
        list)
            completeangler_fishfishing_list "$@"
            ;;
        paths)
            completeangler_fishfishing_paths "$@"
            ;;
        scaffold)
            completeangler_fishfishing_scaffold "$@"
            ;;
        explain)
        completeangler_fishfishing_explain "$@"
            ;;
        extract)
            completeangler_fishfishing_extract "$@"
            ;;
        convert)
            completeangler_fishfishing_convert "$@"
            ;;
        diff)
            completeangler_fishfishing_diff "$@"
            ;;

        *)
            printf "fishfishing: unknown subcommand: %s\n" "$cmd" >&2
            return 1
            ;;
    esac
}




# shell-init - Generate shell integration
completeangler_shell_init() {
    local shell="${1:-bash}"
    
    case "$shell" in
        bash)
            cat <<'EOF'
# completeangler shell integration for bash

_completeangler_widget() {
    local result
    result=$(completeangler ui -- "$COMP_LINE" 2>/dev/null)
   
    if [ -n "$result" ]; then
        printf "\r[completeangler] → %s\n" "$result" >&2
        READLINE_LINE="${READLINE_LINE:0:COMP_POINT}$result ${READLINE_LINE:COMP_POINT}"
        READLINE_POINT=$((COMP_POINT + ${#result} + 1))
    else
        printf "\r[completeangler] (no completion)\n" >&2
    fi
}

bind '"\C-g": ""'
bind -x '"\C-g": _completeangler_widget'



EOF
            ;;
        zsh)
            cat <<'EOF'
# completeangler shell integration for zsh

_completeangler_ui() {
    local -a words
    words=(${=BUFFER})  # convert BUFFER into array of words the bash way

    local result
    result=$(completeangler ui "${(q)words[@]}" --return 2>/dev/null)

    if [ -n "$result" ]; then
        BUFFER="${BUFFER% *} $result"
        CURSOR=$#BUFFER
    fi
    zle reset-prompt
}


zle -N _completeangler_ui
bindkey '^ ' _completeangler_ui  # Ctrl-Space

EOF
            ;;
        *)
            echo "Unknown shell: $shell"
            echo "Supported: bash, zsh"
            return 1
            ;;
    esac
}

# ============================================================================
# HELP & MAIN
# ============================================================================

show_help() {
    cat <<'EOF'
completeangler - Shell completion toolkit (incomplete)
Remember to actually try to use the completion in this session before using this tool for best results.
Many completions are sneaky & lazy-loaded ;)

USAGE:
    completeangler <VERB> [OPTIONS]

CORE VERBS:
    why <input>           Explain why completion happened/failed
    test <input>          Simulate completion without shell context [FUTURE]
    detect <command>      Identify completion mechanism
    inspect <command>     Show detailed completion information [FUTURE]
    trace <command>       Live trace completion execution [FUTURE]
    search <pattern>      Search across all completions
    list [filter]         List all completions [FUTURE]

ANALYSIS VERBS:
    niche <command>       Identify completion opportunities
    implementation <cmd>  Suggest completion patterns

DEVELOPMENT VERBS:
    extract <command>     Auto-generate from help text [PARTIAL]
    scaffold <command>    Generate boilerplate completion [FUTURE]
    watch <file>          Live reload during development [FUTURE]
    snippet <type>        Show code patterns [FUTURE]

QUALITY VERBS:
    profile <command>     Performance analysis [FUTURE]
    lint <command>        Check for issues [FUTURE]
    validate <command>    Verify completions work

UTILITY VERBS:
    repl                  Interactive shell
    record <action>       Log completion usage (start|stop|status) 
    stats [command]       Show usage analytics [FUTURE]
    report <type>         Generate reports (slow|unused|conflicts)
    diff <cmd1> <cmd2>    Compare completions
    export <command>      Export completion
    import <file>         Import completion [FUTURE]
    whoami                Deduce shell (remote & local)
    doctor <verb>         Try to figure out shell situation (explain|shells)
    
UI (fuzzy finder) VERBs [future]:
    ui <input>            Interactive completion UI (requires fzf)
    shell-init [shell]    Generate shell integration code you can source for a Ctrl-G plugin
    
OTHER SHELLS:
    fishfinding           For fish (behaves less like zsh or bash): list|paths|scaffold|explain|extract|convert|diff [FUTURE]

EXAMPLES:
    completeangler why "git che"
    completeangler test "docker run --"
    completeangler detect kubectl
    completeangler niche mycli
    completeangler scaffold mynewcmd
    completeangler profile git
    completeangler list

SHELL INTEGRATION (bash shown):
    # Add to ~/.bashrc:
    eval "$(completeangler shell-init bash)"
    
    # Then use Ctrl-G (overrides BEL) for interactive UI on bash

VERSION: $COMPLETEANGLER_VERSION
EOF
}

show_version() {
    echo "completeangler version $COMPLETEANGLER_VERSION"
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

completeangler_dispatch() {
    completeangler_init
    completeangler_load_config
    
    local verb="${1:-help}"
    shift || true
    
    case "$verb" in
        # Core verbs
        why)
            completeangler_why "$@"
            ;;
        test)
            completeangler_test "$@"
            ;;
        detect)
            completeangler_detect "$@"
            ;;
        ui)
            ui_completion "$@"
            ;;
        inspect)
            completeangler_inspect "$@"
            ;;
        trace)
            completeangler_trace "$@"
            ;;
        search)
            completeangler_search "$@"
            ;;
        list)
            completeangler_list "$@"
            ;;
        
        # Analysis verbs
        niche)
            completeangler_niche "$@"
            ;;
        implementation)
            completeangler_implementation "$@"
            ;;
        
        # Development verbs
        extract)
            completeangler_extract "$@"
            ;;
        scaffold)
            completeangler_scaffold "$@"
            ;;
        watch)
            completeangler_watch "$@"
            ;;
        snippet)
            completeangler_snippet "$@"
            ;;
        
        # Quality verbs
        profile)
            completeangler_profile "$@"
            ;;
        lint)
            completeangler_lint "$@"
            ;;
        validate)
            completeangler_validate "$@"
            ;;
        
        # Utility verbs
        repl)
            completeangler_repl "$@"
            ;;
        record)
            completeangler_record "$@"
            ;;
        stats)
            completeangler_stats "$@"
            ;;
        report)
            completeangler_report "$@"
            ;;
        diff)
            completeangler_diff "$@"
            ;;
        export)
            completeangler_export "$@"
            ;;
        import)
            completeangler_import "$@"
            ;;
        shell-init)
            completeangler_shell_init "$@"
            ;;
        whoami)
            completeangler_whoami "$@"
            ;;
        doctor)
            local sub="${1:-help}"
            shift || true

            case "$sub" in
                explain)
                    completeangler_doctor_explain "$@"
                    ;;
                shells)
                    completeangler_doctor_shells "$@"
                    ;;
                help|--help|-h)
                    echo "doctor subcommands:"
                    echo "  explain <cmd>   Explain which completion system is actually active"
                    echo "  shells          Show local vs remote shell context"
                    ;;
                *)
                    echo "Unknown doctor subcommand: $sub"
                    echo "Try: completeangler doctor help"
                    return 1
                    ;;
            esac
            ;;
        lazy-report)
            completeangler_lazy_report "$@"
            ;;
        preload)
            completeangler_preload "$@"
            ;;
        fishfishing)
            shift
            completeangler_fishfishing_dispatch "$@"
            return $?
            ;;

        # Meta
        version|--version|-v)
            show_version
            ;;
        help|--help|-h|"")
            show_help
            ;;
        *)
            echo "Unknown verb: $verb"
            echo "Run 'completeangler help' for usage"
            return 1
            ;;
    esac
}

    # End of definitions — dispatch
    completeangler_dispatch "$@"
)

