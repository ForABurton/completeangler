# completeangler

`completeangler` is a naturally & ironically very incomplete tool for exploring, diagnosing, and developing those mysterious shell-varying, implementation-varying, time-of-existence-varying tab-completions, with a current focus on running in `bash` (*COMP_WORDS/COMP_CWORD* modeled; `Zsh` and `fish` support are ~~planned~~ contemplated). It currently works best when completions have already been loaded in your session (in the wild, many completion systems lazy-load their definitions, and they may not be around for long).



    Status: Only the very basic paths work, not so much of the development features and live testing.

### What It Does

* Helps you see why a completion did or did not trigger

* Identifies how a command is being completed (function, wrapper, framework, etc.)

* Suggests completion patterns and opportunities

* Supports early-stage scaffolding and exporting of completions

* Provides groundwork for profiling, tracing, and UI picker modes or terminal hotkey bound completions (future)

### "Installation"
```bash
source completeangler.sh
```


Usage
completeangler <verb> [options]


Example:

```
completeangler why "git che"
completeangler detect kubectl
completeangler niche mycli
completeangler export docker
```
Makes a home for its development-related stuff and config at `$COMPLETEANGLER_HOME`: e.g. current settings at `~/.completeangler/config`

## Verbs by Stability

### Core (basic functionality)

| Verb | Description |
|------|-------------|
| `why <input>` | Explain why completion happened or failed |
| `detect <command>` | Identify the completion mechanism for a command |
| `search <pattern>` | Search across known completions |
| `niche <command>` | Identify potential opportunities to add completion coverage |
| `implementation <cmd>` | Suggest possible completion pattern(s) |
| `validate <command>` | Check whether a completion appears to function |
| `repl` | Interactive exploratory shell with completion inspection commands available |
| `record <action>` | Enable/disable usage logging |
| `report <type>` | Generate slow/unused/conflict reports |
| `diff <cmd1> <cmd2>` | Compare how two commands are completed |
| `export <command>` | Export completion definition(s) |
| `whoami` | Identify shell context |
| `doctor` | Attempt to explain shell environment issues |

---

### Partial / Experimental (incomplete)

| Verb | Status | Description |
|------|--------|-------------|
| `extract` | Partial | Limited automated generation from help text |
| `fishfishing` | Partial | Placeholder toolkit for fish conversion/explanation |

---

### Planned / Future Work

| Verb | Purpose |
|------|---------|
| `test <input>` | Simulate completion without full shell state |
| `inspect <command>` | Show full breakdown of completion logic |
| `trace <command>` | Live execution tracing of completion functions |
| `list` | List installed or discovered completions |
| `scaffold <command>` | Generate boilerplate completion definitions |
| `watch <file>` | Hot-reload during development |
| `snippet <type>` | Emit reusable completion patterns |
| `profile <command>` | Measure completion performance cost |
| `lint <command>` | Check style / correctness issues |
| `stats [command]` | Analyze logged completion usage behavior |
| `import <file>` | Import exported completion definitions |
| `ui <input>` | Fuzzy UI interface (requires fzf for most enjoyment) |
| `shell-init` | UI integration bootstrap (i.e. Ctrl-G terminal hotkey bind plugin) |
| `fishfishing subcommands` | fish scaffolding, explain, convert, diff |
