# Muse Stream Audio

> Un lecteur audio YouTube léger et rapide avec VLC via yt-dlp en PowerShell

## ⚡ Pourquoi Muse Stream Audio ?

- **Léger** : utilise moins de RAM qu'un onglet de navigateur avec YouTube (~80 MB vs 500+ MB)
- **Rapide** : charge une piste en moins de 2 secondes
- **Simple** : interface en ligne de commande, sans prise de tête
- **Efficace** : cache intelligent des URLs, préchargement des pistes

## 🚀 Fonctionnalités

| Fonction | Description |
|----------|-------------|
| ⚡ Lecture instantanée | Résolution d'URL < 2s |
| 💾 Cache intelligent | URLs mises en cache pour un accès immédiat |
| 📋 Playlist | Navigation N/P/R avec préchargement |
| 🔍 Recherche | Recherche YouTube directement dans le terminal |
| 🔄 Autoplay | Mode mains libres avec boucle infinie |
| 📥 Téléchargement | Export M4A/MP3 (FFmpeg requis) |

## 📦 Prérequis

- [VLC Media Player](https://www.videolan.org/vlc/) (lecteur audio)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) (extraction YouTube)
- PowerShell 5.0+ (Windows)

## 🔧 Installation

```powershell
# Télécharger le script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/votre-utilisateur/muse-stream-audio/main/muse-stream-audio.ps1" -OutFile "muse-stream-audio.ps1"

# Lancer
.\muse-stream-audio.ps1
📖 Utilisation
text
  ==================================================
           M U S E   S T R E A M   A U D I O
  ==================================================

  [VLC: PRET] Cache: 5 URLs

  [1] Lecture simple (URL)
  [2] Playlist (N/P/R)
  [3] Telecharger (M4A)
  [4] Rechercher
  [5] Autoplay (mains libres)
  [C] Vider cache
  [Q] Quitter
Mode Turbo (direct sans menu)
powershell
.\muse-stream-audio.ps1 -Turbo -Url "https://youtube.com/watch?v=..."
💚 Licence
MIT License - voir le fichier LICENSE
