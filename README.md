# Claude Code Status Line

Une status line maison pour **Claude Code CLI**, en texte coloré sur 2 lignes, **sans police Nerd Font**.

- **Ligne 1** : `user@host:dossier | modèle·effort | 🌿 branche@worktree ●fichiers +ajouts/-suppr | PR#n`
- **Ligne 2** : barre de contexte colorée + tokens · 💰 coût session · ⏱ timer temps réel · Δ lignes éditées · quotas 5h / 7j avec compte à rebours

![Aperçu du rendu de la status line](preview.svg)

<sub>Version texte (mêmes données) :</sub>

```
jeremy@host:mon-projet | Opus 4.8·high | 🌿 main ●2 +2/-1
ctx ####...... 42% (85k/200k) | 💰 $1.23 | ⏱ 14m5s | Δ +128/-17 | 5h 34%·2h00m | 7j 12%·72h00m
```

Couleurs ANSI + emojis/symboles Unicode standard. Tout est calculé **en local** : aucune donnée envoyée, aucun token consommé.

## Deux variantes

| Ton environnement | Fichier à utiliser |
|---|---|
| macOS | `statusline.sh` |
| Linux | `statusline.sh` |
| Windows + WSL | `statusline.sh` (recommandé) |
| Windows + Git Bash | `statusline.sh` |
| Windows natif (PowerShell) | `statusline.ps1` |

> Sur Windows, le plus fiable est de lancer Claude Code dans **WSL** ou **Git Bash** et d'utiliser `statusline.sh`. La variante `statusline.ps1` est fournie pour PowerShell natif, mais reste **moins éprouvée** (retours bienvenus via les issues).

## Prérequis

- Claude Code CLI
- **Version Bash** (`statusline.sh`) : `bash`, `git`, `jq`
  - macOS : `brew install jq`
  - Debian / Ubuntu / WSL : `sudo apt install jq`
  - Fedora : `sudo dnf install jq`
  - Windows (Git Bash) : `jq` via `winget install jqlang.jq` ou `scoop install jq`
- **Version PowerShell** (`statusline.ps1`) : PowerShell 5.1+ (7+ conseillé), `git` dans le PATH. Pas besoin de `jq`. **Windows Terminal** recommandé (gère ANSI + emojis ; l'ancienne console `conhost` peut mal rendre les emojis).

Compatible macOS et Linux (le cache git utilise `stat -f` ou `stat -c` selon l'OS).

## Installation — version Bash (macOS / Linux / WSL / Git Bash)

### Option rapide : one-liner

Une seule commande télécharge le script au bon endroit et le rend exécutable :

```bash
mkdir -p ~/.claude && curl -fsSL https://raw.githubusercontent.com/occirank/claude-code-statusline/main/statusline.sh -o ~/.claude/statusline.sh && chmod +x ~/.claude/statusline.sh
```

**Ce que fait cette commande, étape par étape :**

- `mkdir -p ~/.claude` : crée le dossier de configuration de Claude Code s'il n'existe pas déjà (`-p` = aucune erreur s'il existe).
- `curl -fsSL <url> -o ~/.claude/statusline.sh` : télécharge le script depuis GitHub (le « raw », c'est-à-dire le fichier brut) vers le bon emplacement. Les options : `-f` échoue proprement si le serveur renvoie une erreur, `-s` rend `curl` silencieux, `-S` réaffiche quand même les messages d'erreur, `-L` suit les redirections.
- `chmod +x ...` : rend le script exécutable.
- Les `&&` enchaînent les commandes : chacune ne s'exécute que si la précédente a réussi (si le téléchargement échoue, on ne lance pas `chmod`).

> Ce one-liner installe **seulement le script**. Il te reste ensuite à ajouter le bloc `statusLine` (étape 2 ci-dessous) dans ton `settings.json`, puis à relancer Claude Code.

> Bonne pratique : ne lance jamais une commande `curl ... | bash` sans regarder ce qu'elle fait. Ici, le script est simplement téléchargé dans un fichier (jamais exécuté directement depuis le réseau) ; tu peux l'ouvrir et l'inspecter avant de t'en servir.

### Option manuelle (depuis le dépôt cloné)

1. Copie le script et rends-le exécutable :
   ```bash
   mkdir -p ~/.claude
   cp statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

2. Ajoute ce bloc dans `~/.claude/settings.json` (au premier niveau de l'objet) :
   ```json
   "statusLine": {
     "type": "command",
     "command": "~/.claude/statusline.sh",
     "padding": 0,
     "refreshInterval": 1
   }
   ```

3. Relance Claude Code (ou tape `/statusline`).

## Installation — version PowerShell (Windows natif)

### Option rapide : one-liner

Dans une fenêtre **PowerShell**, une seule commande crée le dossier et télécharge le script :

```powershell
$d="$HOME\.claude"; New-Item -ItemType Directory -Force -Path $d | Out-Null; Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/occirank/claude-code-statusline/main/statusline.ps1 -OutFile "$d\statusline.ps1"
```

**Ce que fait cette commande, étape par étape :**

- `$d="$HOME\.claude"` : mémorise le chemin du dossier de configuration de Claude Code (`$HOME` = ton profil utilisateur, ex. `C:\Users\TonNom`).
- `New-Item -ItemType Directory -Force -Path $d | Out-Null` : crée ce dossier s'il n'existe pas (`-Force` = aucune erreur s'il existe déjà) ; `| Out-Null` masque l'affichage.
- `Invoke-WebRequest -UseBasicParsing <url> -OutFile "$d\statusline.ps1"` : télécharge le script depuis le « raw » GitHub vers le bon emplacement. `-UseBasicParsing` assure la compatibilité avec PowerShell 5.1.
- Le `;` sépare les commandes exécutées l'une après l'autre.

> Pas de `chmod` sous Windows : PowerShell exécute le script via `-File`. Il te reste ensuite à ajouter le bloc `statusLine` (étape 2 ci-dessous) dans ton `settings.json`, puis à relancer Claude Code.

> Astuce : sous PowerShell, `curl` est en réalité un alias d'`Invoke-WebRequest` (ce n'est pas le vrai `curl`) ; on utilise donc `Invoke-WebRequest` explicitement pour éviter toute ambiguïté.

### Option manuelle

1. Copie `statusline.ps1` dans `%USERPROFILE%\.claude\statusline.ps1`.

2. Ajoute ce bloc dans `%USERPROFILE%\.claude\settings.json`, en remplaçant `<TOI>` par ton nom d'utilisateur Windows et en utilisant le chemin **absolu** (l'expansion de `~` n'est pas garantie sur Windows) :
   ```json
   "statusLine": {
     "type": "command",
     "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File C:/Users/<TOI>/.claude/statusline.ps1",
     "padding": 0,
     "refreshInterval": 1
   }
   ```
   - PowerShell 7+ : `pwsh`. PowerShell 5.1 : remplace `pwsh` par `powershell`.
   - Les `/` fonctionnent dans le chemin `-File`.

3. Relance Claude Code.

## ⚠️ Sécurité

N'ajoute **que** le bloc `statusLine` dans **ton** `settings.json`. Ne copie **jamais** le `settings.json` de quelqu'un d'autre : ce fichier contient ses clés API et mots de passe. Les scripts `statusline.sh` / `statusline.ps1`, eux, ne contiennent aucun secret.

## Personnalisation

- **Timer temps réel** : `refreshInterval` (secondes). `1` = à la seconde ; `5` = toutes les 5 s ; retire la clé pour ne rafraîchir qu'aux messages.
- **Seuils de couleur** (contexte et quotas) : fonction `pct_color` (`.sh`) / `PctColor` (`.ps1`) — vert < 70, jaune 70-89, rouge ≥ 90.
- **Durée du cache git** : `CACHE_TTL` (`.sh`) / le `-lt 3` dans le bloc git (`.ps1`).
- **Retirer un segment** : supprime son bloc conditionnel (ex. `# badge PR`, `# rate limits`).

## Bon à savoir

- Les segments `5h` / `7j` (quotas d'abonnement) n'apparaissent que pour les comptes **Pro / Max**, après le 1er appel API.
- Le cache git et le timer écrivent de petits fichiers dans le dossier temporaire (`/tmp` ou `%TEMP%`), nettoyés au redémarrage.
- Champs lus depuis le JSON fourni par Claude Code sur stdin (modèle, contexte, coût, rate limits, worktree, PR, etc.).

## Dépannage (Windows)

- **Emojis en `??` ou `?`, point médian `·` en `�`** : utilise la dernière version de `statusline.ps1` (elle force la sortie en UTF-8) et lance Claude Code dans **Windows Terminal**. L'ancienne console `conhost.exe` peut ne pas afficher les emojis, même avec un encodage correct.
- **Rien ne s'affiche** : vérifie le chemin absolu dans `settings.json` et que `pwsh` (ou `powershell`) est bien dans le PATH.

## Licence

MIT.
