# =============================================================================
# Status line Claude Code - variante PowerShell (Windows natif)
# Equivalent de statusline.sh : 2 lignes, texte colore, sans Nerd Font.
#   Ligne 1 : user@host:dir | modele.effort | branche@worktree filesChanges | PR
#   Ligne 2 : barre de contexte + tokens | cout | timer temps reel | lignes | 5h/7j
# Entree = JSON Claude Code sur stdin. Sortie = 2 lignes.
# PowerShell 5.1+ ou 7+. Terminal recommande : Windows Terminal (ANSI + emojis).
# =============================================================================

$ErrorActionPreference = 'SilentlyContinue'
$raw = [Console]::In.ReadToEnd()
try { $j = $raw | ConvertFrom-Json } catch { $j = $null }

# --- Couleurs ANSI -----------------------------------------------------------
$ESC = [char]27
function C([int]$n) { "$ESC[${n}m" }
$RESET=C 0; $BLUE=C 34; $GREEN=C 32; $CYAN=C 36; $MAGENTA=C 35; $YELLOW=C 33; $RED=C 31; $GREY=C 90

# --- Glyphes (Unicode standard, pas de Nerd Font) ----------------------------
$LEAF  = [char]::ConvertFromUtf32(0x1F33F)   # 🌿
$MONEY = [char]::ConvertFromUtf32(0x1F4B0)   # 💰
$DOT   = [char]0x00B7                         # ·
$DOTF  = [char]0x25CF                         # ●
$CLOCK = [char]0x23F1                         # ⏱
$DELTA = [char]0x0394                         # Δ

# --- Helpers -----------------------------------------------------------------
function ToInt($v) {
  if ($null -eq $v -or "$v" -eq '') { return $null }
  try { return [int][math]::Floor([double]("$v")) } catch { return $null }
}
function IsPos($v) { $n = ToInt $v; return ($null -ne $n -and $n -gt 0) }
function PctColor($v) {
  $n = ToInt $v; if ($null -eq $n) { $n = 0 }
  if ($n -ge 90) { $RED } elseif ($n -ge 70) { $YELLOW } else { $GREEN }
}
function FmtK($v) {
  $n = ToInt $v; if ($null -eq $n) { return '' }
  if ($n -ge 1000000) { '{0}M' -f [math]::Round($n/1000000) }
  elseif ($n -ge 1000) { '{0}k' -f [math]::Round($n/1000) }
  else { "$n" }
}
function FmtTtl($target) {
  $t = ToInt $target; if ($null -eq $t) { return '' }
  if ($t -ge 100000000000) { $t = [math]::Floor($t/1000) }   # ms -> s
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $diff = $t - $now; if ($diff -lt 0) { $diff = 0 }
  $h = [math]::Floor($diff/3600); $m = [math]::Floor(($diff%3600)/60)
  if ($h -gt 0) { '{0}h{1:D2}m' -f $h,$m } else { '{0}m' -f $m }
}

# --- Champs natifs -----------------------------------------------------------
$model   = $j.model.display_name
$effort  = $j.effort.level
$sid     = if ($j.session_id) { $j.session_id } else { 'default' }
$cwd     = if ($j.workspace.current_dir) { $j.workspace.current_dir } elseif ($j.cwd) { $j.cwd } else { (Get-Location).Path }
$usedPct = $j.context_window.used_percentage
$ctxSize = $j.context_window.context_window_size
$inTok   = $j.context_window.total_input_tokens
$cost    = $j.cost.total_cost_usd
$durMs   = $j.cost.total_duration_ms
$added   = $j.cost.total_lines_added
$removed = $j.cost.total_lines_removed
$wtName  = if ($j.worktree.name) { $j.worktree.name } else { $j.workspace.git_worktree }
$prNum   = $j.pr.number
$prState = $j.pr.review_state
$rl5p    = $j.rate_limits.five_hour.used_percentage
$rl5r    = $j.rate_limits.five_hour.resets_at
$rl7p    = $j.rate_limits.seven_day.used_percentage
$rl7r    = $j.rate_limits.seven_day.resets_at

$dir = Split-Path -Leaf $cwd
$user = $env:USERNAME
$hostName = $env:COMPUTERNAME
$cacheDir = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }

# --- Git avec cache par session ---------------------------------------------
$gBranch=''; $gFiles=0; $gAdd=0; $gDel=0
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
if ($hasGit) {
  git -C "$cwd" rev-parse --is-inside-work-tree 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    $cacheFile = Join-Path $cacheDir "claude-statusline-git-$sid"
    $fresh = $false
    if (Test-Path $cacheFile) {
      $age = (New-TimeSpan -Start (Get-Item $cacheFile).LastWriteTime -End (Get-Date)).TotalSeconds
      if ($age -lt 3) { $fresh = $true }
    }
    if ($fresh) {
      $c = @(Get-Content $cacheFile)
      $gBranch = $c[0]; $gFiles = [int]($c[1]); $gAdd = [int]($c[2]); $gDel = [int]($c[3])
    } else {
      $gBranch = (git -C "$cwd" branch --show-current 2>$null)
      if (-not $gBranch) { $gBranch = (git -C "$cwd" rev-parse --short HEAD 2>$null) }
      $gFiles = @(git -C "$cwd" status --porcelain 2>$null).Count
      foreach ($line in @(git -C "$cwd" diff --numstat HEAD 2>$null)) {
        $p = $line -split "`t"
        if ($p.Count -ge 2) {
          if ($p[0] -match '^\d+$') { $gAdd += [int]$p[0] }
          if ($p[1] -match '^\d+$') { $gDel += [int]$p[1] }
        }
      }
      "$gBranch`n$gFiles`n$gAdd`n$gDel" | Set-Content $cacheFile
    }
  }
}

# =============================================================================
# LIGNE 1 : texte colore, sans fond, separateur | (identique a la ligne 2)
# =============================================================================
$SEP = " $GREY|$RESET "
$l1 = "$BLUE$user@$hostName$RESET" + ":" + "$GREEN$dir$RESET"
if ($model) {
  $m = "$CYAN$model$RESET"
  if ($effort) { $m += "$GREY$DOT$effort$RESET" }
  $l1 += "$SEP$m"
}
if ($gBranch) {
  $g = "$MAGENTA$LEAF $gBranch$RESET"
  if ($wtName) { $g += "$GREY@$wtName$RESET" }
  $chg = ''
  if (IsPos $gFiles) { $chg = "$YELLOW$DOTF$gFiles$RESET" }
  if ((IsPos $gAdd) -or (IsPos $gDel)) {
    $chg += " $GREEN+$gAdd$RESET$GREY/$RESET$RED-$gDel$RESET"
  }
  if ($chg) { $g += " $chg" }
  $l1 += "$SEP$g"
}
if ($prNum) {
  switch ("$prState") {
    'approved'          { $pc = $GREEN }
    'changes_requested' { $pc = $RED }
    'draft'             { $pc = $GREY }
    default             { $pc = $YELLOW }
  }
  $l1 += "$SEP${pc}PR#$prNum$RESET"
}

# =============================================================================
# LIGNE 2 : metriques de session
# =============================================================================
$p2 = @()

# barre de contexte + tokens
if ($null -ne $usedPct -and "$usedPct" -ne '') {
  $pi = ToInt $usedPct; if ($null -eq $pi) { $pi = 0 }
  $filled = [int][math]::Floor(($pi + 5) / 10); if ($filled -gt 10) { $filled = 10 }; if ($filled -lt 0) { $filled = 0 }
  $empty = 10 - $filled
  $cc = PctColor $pi
  $bar = $cc + ('#' * $filled) + $GREY + ('.' * $empty) + $RESET
  $toks = ''
  if ($null -ne $inTok) { $toks = "$GREY(" + (FmtK $inTok) + '/' + (FmtK $ctxSize) + ")$RESET" }
  $p2 += "${GREY}ctx$RESET $bar $cc$pi%$RESET $toks"
}
# cout session
if ($null -ne $cost -and "$cost" -ne '') {
  try { $cs = ([double]("$cost")).ToString('0.00',[System.Globalization.CultureInfo]::InvariantCulture) } catch { $cs = "$cost" }
  $p2 += ($GREEN + $MONEY + ' $' + $cs + $RESET)
}
# timer temps reel (refreshInterval=1 dans settings.json)
if ($null -ne $durMs -and "$durMs" -ne '') {
  $startFile = Join-Path $cacheDir "claude-statusline-start-$sid"
  $tnow = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $dnat = ToInt $durMs; if ($null -eq $dnat) { $dnat = 0 }; $dnat = [int][math]::Floor($dnat / 1000)
  $start = $null
  if (Test-Path $startFile) { $start = ToInt ((Get-Content $startFile -TotalCount 1)) }
  if ($null -eq $start) { $start = $tnow - $dnat; "$start" | Set-Content $startFile }
  $secs = [int]($tnow - $start); if ($secs -lt 0) { $secs = 0 }
  if ($dnat -gt $secs) { $secs = $dnat; "$($tnow - $dnat)" | Set-Content $startFile }
  $h = [math]::Floor($secs/3600); $m = [math]::Floor(($secs%3600)/60); $s = $secs%60
  if ($h -gt 0) { $d = "${h}h${m}m${s}s" } elseif ($m -gt 0) { $d = "${m}m${s}s" } else { $d = "${s}s" }
  $p2 += "$GREY$CLOCK $d$RESET"
}
# lignes editees par Claude
if ((IsPos $added) -or (IsPos $removed)) {
  $a = ToInt $added; if ($null -eq $a) { $a = 0 }
  $r = ToInt $removed; if ($null -eq $r) { $r = 0 }
  $p2 += "$GREY$DELTA$RESET $GREEN+$a$RESET$GREY/$RESET$RED-$r$RESET"
}
# rate limits 5h / 7j (Pro/Max, apres 1er appel API)
if ($null -ne $rl5p -and "$rl5p" -ne '') {
  $seg = "${GREY}5h$RESET " + (PctColor $rl5p) + (ToInt $rl5p) + "%$RESET"
  $ttl = FmtTtl $rl5r; if ($ttl) { $seg += "$GREY$DOT$ttl$RESET" }
  $p2 += $seg
}
if ($null -ne $rl7p -and "$rl7p" -ne '') {
  $seg = "${GREY}7j$RESET " + (PctColor $rl7p) + (ToInt $rl7p) + "%$RESET"
  $ttl = FmtTtl $rl7r; if ($ttl) { $seg += "$GREY$DOT$ttl$RESET" }
  $p2 += $seg
}

# --- Sortie ------------------------------------------------------------------
$out = $l1
if ($p2.Count -gt 0) { $out += "`n" + ($p2 -join $SEP) }
[Console]::Out.Write($out + "`n")
