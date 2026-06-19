#!/bin/bash
# =============================================================================
# Claude Code - status line personnalisee
# Reprend les fonctionnalites existantes :
#   - ancien statusline-command.sh : user@host:dir, modele, contexte %
#   - ccstatusline                 : modele, context-length, git-branch, git-changes
# Ajoute : barre de contexte coloree, cout session, duree, lignes editees,
#          worktree, badge PR, rate limits 5h/7j avec compte a rebours de reset.
# Perf : cache git cle par session_id (recommandation doc Anthropic, debounce 300ms).
# Compatible bash 3.2 (macOS) + jq. Entree = JSON sur stdin. Sortie = 2 lignes.
# =============================================================================

input=$(cat)
export LC_NUMERIC=C   # point decimal pour printf (sinon $1,23 en locale FR)

# --- Couleurs ANSI (via printf pour compat /bin/sh comme /bin/bash) ---
esc=$(printf '\033')
RESET="${esc}[0m"; BOLD="${esc}[1m"
BLUE="${esc}[34m"; GREEN="${esc}[32m"; CYAN="${esc}[36m"
MAGENTA="${esc}[35m"; YELLOW="${esc}[33m"; RED="${esc}[31m"; GREY="${esc}[90m"

# --- Repli si jq absent : on garde au moins l'esprit de l'ancien script ---
if ! command -v jq >/dev/null 2>&1; then
  printf '%s@%s%s' "$(whoami)" "$(hostname -s)" " (jq manquant)"
  exit 0
fi

# --- Extraction de tous les champs natifs en UN seul appel jq -------------
# Une valeur par ligne, lue dans un tableau indexe : robuste aux champs vides
# (un IFS=tab fusionnerait les champs vides successifs et decalerait tout).
i=0
while IFS= read -r __l; do F[$i]="$__l"; i=$((i+1)); done <<EOF
$(printf '%s' "$input" | jq -r '[
  .model.display_name, .effort.level, .session_id,
  .workspace.current_dir, .cwd,
  .context_window.used_percentage, .context_window.context_window_size,
  .context_window.total_input_tokens,
  .cost.total_cost_usd, .cost.total_duration_ms,
  .cost.total_lines_added, .cost.total_lines_removed,
  .worktree.name, .workspace.git_worktree, .worktree.branch,
  .pr.number, .pr.review_state,
  .rate_limits.five_hour.used_percentage, .rate_limits.five_hour.resets_at,
  .rate_limits.seven_day.used_percentage, .rate_limits.seven_day.resets_at,
  .workspace.project_dir
] | map(if . == null then "" else tostring end) | .[]' 2>/dev/null)
EOF

model=${F[0]};    effort=${F[1]};      session_id=${F[2]}
cwd=${F[3]};      cwd_alt=${F[4]};     used_pct=${F[5]}
ctx_size=${F[6]}; in_tok=${F[7]}
cost=${F[8]};     dur_ms=${F[9]};      added=${F[10]};   removed=${F[11]}
wt_name=${F[12]}; wt_gw=${F[13]};      wt_branch=${F[14]}
pr_num=${F[15]};  pr_state=${F[16]}
rl5_pct=${F[17]}; rl5_reset=${F[18]};  rl7_pct=${F[19]};  rl7_reset=${F[20]}
project_dir=${F[21]}

[ -z "$cwd" ] && cwd="$cwd_alt"
[ -z "$cwd" ] && cwd=$(pwd)
[ -z "$session_id" ] && session_id="default"
dir=$(basename "$cwd")
user=$(whoami)
host=$(hostname -s)

# --- Helpers ---------------------------------------------------------------
# Formate un nombre en k / M
fmt_k() {
  local n=${1%.*}
  case "$n" in ''|*[!0-9]*) return ;; esac
  if   [ "$n" -ge 1000000 ]; then printf '%dM' $(( (n + 500000) / 1000000 ))
  elif [ "$n" -ge 1000 ];    then printf '%dk' $(( (n + 500) / 1000 ))
  else printf '%d' "$n"; fi
}
# Compte a rebours "XhYYm" depuis un epoch (secondes ou ms) ; vide si non numerique
fmt_ttl() {
  local target=${1%.*} now diff h m
  case "$target" in ''|*[!0-9]*) return ;; esac
  [ "$target" -ge 100000000000 ] && target=$(( target / 1000 ))   # ms -> s
  now=$(date +%s)
  diff=$(( target - now )); [ "$diff" -lt 0 ] && diff=0
  h=$(( diff / 3600 )); m=$(( (diff % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"; else printf '%dm' "$m"; fi
}
# Couleur selon un pourcentage (vert < 70, jaune 70-89, rouge >= 90)
pct_color() {
  local p=${1%.*}; case "$p" in ''|*[!0-9]*) p=0 ;; esac
  if   [ "$p" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$p" -ge 70 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}
repeat() { local n=$1 c=$2 i=0 out=""; while [ "$i" -lt "$n" ]; do out="$out$c"; i=$((i+1)); done; printf '%s' "$out"; }
# Vrai si l'argument est un entier strictement positif (tolere un suffixe decimal)
is_pos() { local v=${1%.*}; case "$v" in ''|*[!0-9]*) return 1 ;; *) [ "$v" -gt 0 ] ;; esac; }
# mtime d'un fichier en epoch — compatible macOS/BSD (stat -f) ET Linux/GNU (stat -c)
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
# Formate une taille (entree en Ko) en K / M / G
fmt_size() {
  local kb=${1%.*}; case "$kb" in ''|*[!0-9]*) return ;; esac
  if   [ "$kb" -ge 1048576 ]; then awk "BEGIN{printf \"%.1fG\", $kb/1048576}"
  elif [ "$kb" -ge 1024 ];    then awk "BEGIN{printf \"%.0fM\", $kb/1024}"
  else printf '%dK' "$kb"; fi
}

now=$(date +%s)

# --- Git avec cache par session (evite git status a chaque tick) -----------
CACHE_TTL=3
cache_file="${TMPDIR:-/tmp}/claude-statusline-git-${session_id}"
g_branch=""; g_files=""; g_add=""; g_del=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  now=$(date +%s); fresh=0
  if [ -f "$cache_file" ]; then
    mtime=$(file_mtime "$cache_file")
    [ $(( now - mtime )) -lt "$CACHE_TTL" ] && fresh=1
  fi
  if [ "$fresh" = "1" ]; then
    g_branch=$(sed -n '1p' "$cache_file"); g_files=$(sed -n '2p' "$cache_file")
    g_add=$(sed -n '3p' "$cache_file");    g_del=$(sed -n '4p' "$cache_file")
  else
    g_branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    [ -z "$g_branch" ] && g_branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    g_files=$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c .)
    read -r g_add g_del <<NUM
$(git -C "$cwd" diff --numstat HEAD 2>/dev/null | awk '{a+=$1; d+=$2} END{printf "%d %d", a+0, d+0}')
NUM
    printf '%s\n%s\n%s\n%s\n' "$g_branch" "$g_files" "$g_add" "$g_del" > "$cache_file" 2>/dev/null
  fi
fi

# --- Espace disque du projet (du en arriere-plan, non bloquant + cache) ------
# Affiche la derniere taille connue ; recalcule en tache de fond (TTL 60s) sans
# jamais bloquer le rendu. Verrou anti-stampede pour ne pas lancer 'du' en boucle.
SIZE_TTL=60
proj="${project_dir:-$cwd}"
disk=""
if [ -n "$proj" ] && [ -d "$proj" ]; then
  key=$(printf '%s' "$proj" | cksum | awk '{print $1}')
  size_cache="${TMPDIR:-/tmp}/claude-statusline-size-${key}"
  size_lock="${size_cache}.lock"
  [ -f "$size_cache" ] && disk=$(sed -n '1p' "$size_cache" 2>/dev/null)
  need=0
  if [ ! -f "$size_cache" ]; then need=1
  elif [ $(( now - $(file_mtime "$size_cache") )) -ge "$SIZE_TTL" ]; then need=1; fi
  if [ "$need" = "1" ]; then
    if [ ! -f "$size_lock" ] || [ $(( now - $(file_mtime "$size_lock") )) -gt 300 ]; then
      : > "$size_lock"
      ( du -sk "$proj" 2>/dev/null | awk '{print $1}' > "${size_cache}.tmp" 2>/dev/null \
        && mv "${size_cache}.tmp" "$size_cache" 2>/dev/null; rm -f "$size_lock" 2>/dev/null ) >/dev/null 2>&1 &
    fi
  fi
fi

# ===========================================================================
# LIGNE 1 : texte colore, SANS fond, separateur | (identique a la ligne 2)
# ===========================================================================
ARW=" ${GREY}|${RESET} "   # meme separateur que la ligne 2
l1="${BLUE}${user}@${host}${RESET}:${GREEN}${dir}${RESET}"

# modele (+ effort)
if [ -n "$model" ]; then
  m="${CYAN}${model}${RESET}"
  [ -n "$effort" ] && m="${m}${GREY}·${effort}${RESET}"
  l1="${l1}${ARW}${m}"
fi

# branche git (+ worktree) + changements working tree
if [ -n "$g_branch" ]; then
  gseg="${MAGENTA}\xf0\x9f\x8c\xbf ${g_branch}${RESET}"
  wt="$wt_name"; [ -z "$wt" ] && wt="$wt_gw"
  [ -n "$wt" ] && gseg="${gseg}${GREY}@${wt}${RESET}"
  chg=""
  is_pos "$g_files" && chg="${YELLOW}\xe2\x97\x8f${g_files}${RESET}"
  if is_pos "$g_add" || is_pos "$g_del"; then
    chg="${chg} ${GREEN}+${g_add}${RESET}${GREY}/${RESET}${RED}-${g_del}${RESET}"
  fi
  [ -n "$chg" ] && gseg="${gseg} ${chg}"
  l1="${l1}${ARW}${gseg}"
fi

# badge PR
if [ -n "$pr_num" ]; then
  case "$pr_state" in
    approved) pc=$GREEN ;; changes_requested) pc=$RED ;;
    draft) pc=$GREY ;; *) pc=$YELLOW ;;
  esac
  l1="${l1}${ARW}${pc}PR#${pr_num}${RESET}"
fi

# ===========================================================================
# LIGNE 2 : metriques de session (style leger, separateur |)
# ===========================================================================
SEP=" ${GREY}|${RESET} "
l2=""
add2() { [ -n "$1" ] && { [ -n "$l2" ] && l2="${l2}${SEP}"; l2="${l2}$1"; }; }

# barre de contexte coloree + tokens
if [ -n "$used_pct" ]; then
  pi=${used_pct%.*}; case "$pi" in ''|*[!0-9]*) pi=0 ;; esac
  filled=$(( (pi + 5) / 10 )); [ "$filled" -gt 10 ] && filled=10; [ "$filled" -lt 0 ] && filled=0
  empty=$(( 10 - filled )); cc=$(pct_color "$pi")
  bar="${cc}$(repeat "$filled" '#')${GREY}$(repeat "$empty" '.')${RESET}"
  toks=""
  [ -n "$in_tok" ] && toks="${GREY}($(fmt_k "$in_tok")/$(fmt_k "$ctx_size"))${RESET}"
  add2 "${GREY}ctx${RESET} ${bar} ${cc}${pi}%${RESET} ${toks}"
fi

# cout session
if [ -n "$cost" ]; then
  add2 "$(printf "${GREEN}\xf0\x9f\x92\xb0 \$%.2f${RESET}" "$cost" 2>/dev/null)"
fi

# espace disque occupe par le projet (💾)
[ -n "$disk" ] && add2 "${GREY}\xf0\x9f\x92\xbe $(fmt_size "$disk")${RESET}"

# duree de session — timer TEMPS REEL (s'egrene a la seconde si refreshInterval=1).
# Ancre le debut sur la duree native au 1er rendu, puis l'horloge avance ; on
# resynchronise vers le haut si la valeur native depasse (ex. apres un long appel).
if [ -n "$dur_ms" ]; then
  start_file="${TMPDIR:-/tmp}/claude-statusline-start-${session_id}"
  tnow=$(date +%s)
  dnat=${dur_ms%.*}; case "$dnat" in ''|*[!0-9]*) dnat=0 ;; esac; dnat=$(( dnat / 1000 ))
  if [ -f "$start_file" ]; then start=$(sed -n '1p' "$start_file" 2>/dev/null); else start=""; fi
  case "$start" in ''|*[!0-9]*) start=$(( tnow - dnat )); printf '%s\n' "$start" > "$start_file" 2>/dev/null ;; esac
  secs=$(( tnow - start )); [ "$secs" -lt 0 ] && secs=0
  if [ "$dnat" -gt "$secs" ]; then secs=$dnat; printf '%s\n' "$(( tnow - dnat ))" > "$start_file" 2>/dev/null; fi
  h=$(( secs / 3600 )); m=$(( (secs % 3600) / 60 )); s=$(( secs % 60 ))
  if   [ "$h" -gt 0 ]; then d="${h}h${m}m${s}s"
  elif [ "$m" -gt 0 ]; then d="${m}m${s}s"
  else d="${s}s"; fi
  add2 "${GREY}\xe2\x8f\xb1 ${d}${RESET}"
fi

# lignes editees par Claude dans la session (distinct du diff git working tree)
if is_pos "$added" || is_pos "$removed"; then
  add2 "${GREY}\xce\x94${RESET} ${GREEN}+${added}${RESET}${GREY}/${RESET}${RED}-${removed}${RESET}"
fi

# rate limits 5h / 7j (Pro/Max, apres 1er appel API)
if [ -n "$rl5_pct" ]; then
  c5=$(pct_color "$rl5_pct"); ttl5=$(fmt_ttl "$rl5_reset")
  seg="${GREY}5h${RESET} ${c5}${rl5_pct%.*}%${RESET}"; [ -n "$ttl5" ] && seg="${seg}${GREY}·${ttl5}${RESET}"
  add2 "$seg"
fi
if [ -n "$rl7_pct" ]; then
  c7=$(pct_color "$rl7_pct"); ttl7=$(fmt_ttl "$rl7_reset")
  seg="${GREY}7j${RESET} ${c7}${rl7_pct%.*}%${RESET}"; [ -n "$ttl7" ] && seg="${seg}${GREY}·${ttl7}${RESET}"
  add2 "$seg"
fi

# ===========================================================================
# SORTIE (printf %b pour interpreter les \xNN des emojis/symboles)
# ===========================================================================
printf '%b' "$l1"
[ -n "$l2" ] && printf '\n%b' "$l2"
printf '\n'
