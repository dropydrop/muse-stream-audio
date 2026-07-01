# Muse Stream Audio - Version COMPLETE V7.1
# Ajouts: Interface amelioree, Recherche, Autoplay
# Conserve: Vitesse < 2s, Cache intelligent, VLC persistant
# SANS ACCENTS POUR LA CONSOLE - Performance maximale

param(
    [string]$Url = "",
    [switch]$Turbo,
    [switch]$Direct
)

[Console]::TreatControlCAsInput = $false

# ============ CONFIGURATION ULTRA-RAPIDE ============
$script:rcPort = 4212
$script:rcHost = "127.0.0.1"
$script:downloadPath = "$env:USERPROFILE\Downloads"
$script:vlcPath = ""
$script:ffmpegPath = ""
$script:appDir = "$env:LOCALAPPDATA\muse-stream-audio"
$script:cacheFile = "$env:TEMP\muse_url_cache.json"
$script:urlCache = @{}
$script:ffmpegChecked = $false
$script:vlcReady = $false
$script:startTime = Get-Date
$script:autoplayRunning = $false

# ============ FONCTIONS DE BASE ULTRA-LEGERES ============

function Write-Success { 
    param([string]$Message) 
    Write-Host "[OK] $Message" -ForegroundColor Green 
}

function Write-Error { 
    param([string]$Message) 
    Write-Host "[!] $Message" -ForegroundColor Red 
}

function Write-Info { 
    param([string]$Message) 
    Write-Host "[>] $Message" -ForegroundColor Yellow 
}

function Write-Debug { 
    param([string]$Message) 
    if ($env:MUSE_DEBUG) { 
        Write-Host "[DEBUG] $Message" -ForegroundColor Gray 
    } 
}

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ==================================================" -ForegroundColor Red
    Write-Host "           M U S E   S T R E A M   A U D I O          " -ForegroundColor Green
    Write-Host "  ==================================================" -ForegroundColor Red
    Write-Host ""
}

function Show-NowPlaying {
    param([string]$Titre, [int]$Current = 0, [int]$Total = 0, [int]$Progress = 0)
    
    if ($Total -gt 0) {
        Write-Host "  === PLAYLIST $Current/$Total ===" -ForegroundColor Gray
    }
    
    if ($Progress -gt 0 -and $Progress -lt 100) {
        $barLength = 40
        $filled = [int]($Progress * $barLength / 100)
        $bar = "█" * $filled + "░" * ($barLength - $filled)
        Write-Host "  [$bar] $Progress%" -ForegroundColor Green
    }
    
    Write-Host "  ♫ $Titre" -ForegroundColor Green
    
    if ($Total -gt 0) {
        Write-Host "  --------------------------------------------------" -ForegroundColor Gray
        Write-Host "  [N] Suivant  [P] Precedent  [R] Rejouer  [Q] Quitter" -ForegroundColor White
        Write-Host "  [Space] Pause" -ForegroundColor White
    }
    Write-Host ""
}

# ============ GESTION VLC PERSISTANT ============

function Get-VLCPath {
    if ($script:vlcPath) { 
        return $script:vlcPath 
    }
    
    $chemins = @(
        "${env:ProgramFiles}\VideoLAN\VLC\vlc.exe",
        "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe",
        "$env:LOCALAPPDATA\Programs\VideoLAN\VLC\vlc.exe"
    )
    
    foreach ($c in $chemins) {
        if (Test-Path $c) { 
            $script:vlcPath = $c
            return $c 
        }
    }
    
    $c = Get-Command vlc -ErrorAction SilentlyContinue
    if ($c) { 
        $script:vlcPath = $c.Source
        return $c.Source 
    }
    return $null
}

function Test-VLCProcess {
    $vlcProcess = Get-Process -Name "vlc" -ErrorAction SilentlyContinue
    return ($vlcProcess -ne $null)
}

function Ensure-VLCReady {
    if ($script:vlcReady) { 
        return $true 
    }
    
    # 1. Verifier si le port RC est deja disponible
    try {
        $client = New-Object System.Net.Sockets.TcpClient($script:rcHost, $script:rcPort)
        $client.Close()
        $script:vlcReady = $true
        Write-Debug "VLC deja actif avec RC"
        return $true
    } catch {
        # Port RC non disponible
    }
    
    # 2. Verifier si VLC est deja ouvert (sans RC)
    if (Test-VLCProcess) {
        Write-Info "VLC deja ouvert. Redemarrage avec controle distant..."
        Stop-Process -Name "vlc" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
    
    # 3. Demarrer VLC avec RC
    Write-Info "Demarrage de VLC (une fois)..."
    $vlc = Get-VLCPath
    if (-not $vlc) { 
        Write-Error "VLC introuvable"
        return $false 
    }
    
    Start-Process $vlc -ArgumentList "--extraintf", "rc", "--rc-host", "$($script:rcHost):$($script:rcPort)", "--one-instance", "--no-random", "--no-loop", "--qt-start-minimized" -WindowStyle Minimized
    
    # Attendre le port (max 5s)
    $timeout = 0
    while ($timeout -lt 50) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient($script:rcHost, $script:rcPort)
            $client.Close()
            $script:vlcReady = $true
            Write-Debug "VLC pret en $($timeout * 100)ms"
            return $true
        } catch { 
            Start-Sleep -Milliseconds 100
            $timeout++ 
        }
    }
    
    Write-Error "Impossible de demarrer VLC avec controle distant"
    return $false
}

function Send-To-VLC {
    param([string]$Url)
    
    $vlc = Get-VLCPath
    if (-not $vlc) { 
        return 
    }
    
    Start-Process $vlc -ArgumentList "--one-instance", "--qt-start-minimized", "`"$Url`"" -WindowStyle Minimized
}

function Send-RCCommand {
    param([string]$Command)
    
    try {
        $client = New-Object System.Net.Sockets.TcpClient($script:rcHost, $script:rcPort)
        $ns = $client.GetStream()
        $data = [System.Text.Encoding]::UTF8.GetBytes("$Command`n")
        $ns.Write($data, 0, $data.Length)
        $client.Close()
    } catch { 
        # Silencieux
    }
}

# ============ CACHE D'URLS INTELLIGENT ============

function Load-UrlCache {
    if (Test-Path $script:cacheFile) {
        try {
            $content = Get-Content $script:cacheFile -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $cache = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($cache -and $cache.PSObject.Properties) {
                    $script:urlCache = @{}
                    foreach ($prop in $cache.PSObject.Properties) {
                        $script:urlCache[$prop.Name] = $prop.Value
                    }
                    Write-Debug "Cache charge: $($script:urlCache.Count) URLs"
                }
            }
        } catch {
            Write-Debug "Erreur chargement cache"
        }
    }
}

function Save-UrlCache {
    if ($script:urlCache.Count -gt 0) {
        try {
            $json = $script:urlCache | ConvertTo-Json -Compress -ErrorAction SilentlyContinue
            Set-Content -Path $script:cacheFile -Value $json -ErrorAction SilentlyContinue
        } catch {
            # Silencieux
        }
    }
}

function Get-CachedUrl {
    param([string]$VideoId)
    
    if (-not $VideoId) { 
        return $null 
    }
    
    if ($script:urlCache.ContainsKey($VideoId)) {
        Write-Debug "Cache hit: $VideoId"
        return $script:urlCache[$VideoId]
    }
    return $null
}

function Extract-VideoId {
    param([string]$Url)
    
    if ($Url -match 'v=([a-zA-Z0-9_-]{11})') {
        return $Matches[1]
    }
    if ($Url -match 'youtu\.be/([a-zA-Z0-9_-]{11})') {
        return $Matches[1]
    }
    return $null
}

# ============ RESOLUTION ULTRA-RAPIDE ============

function Get-StreamUrlUltraFast {
    param([string]$Url, [switch]$NoCache)
    
    $videoId = Extract-VideoId $Url
    
    if (-not $NoCache -and $videoId) {
        $cached = Get-CachedUrl $videoId
        if ($cached) { 
            Write-Debug "URL cachee utilisee"
            return $cached 
        }
    }
    
    Write-Debug "Resolution yt-dlp..."
    $startResolve = Get-Date
    
    $args = @(
        "-f", "bestaudio[ext=m4a]/bestaudio",
        "-g",
        "--no-warnings",
        "--no-playlist",
        "--quiet",
        $Url
    )
    
    $streamUrl = & $ytdlpPath @args 2>$null
    
    if ($streamUrl) {
        $streamUrl = $streamUrl.Trim()
        $elapsed = [int]((Get-Date).Subtract($startResolve).TotalMilliseconds)
        Write-Debug "Resolu en ${elapsed}ms"
        
        if ($videoId) {
            $script:urlCache[$videoId] = $streamUrl
            Save-UrlCache
        }
        return $streamUrl
    }
    
    return $null
}

# ============ DETECTION FIN DE PISTE ============

function Get-QuickStatus {
    try {
        $client = New-Object System.Net.Sockets.TcpClient($script:rcHost, $script:rcPort)
        $ns = $client.GetStream()
        $data = [System.Text.Encoding]::UTF8.GetBytes("status`n")
        $ns.Write($data, 0, $data.Length)
        
        $response = ""
        $buffer = New-Object byte[] 512
        $timeout = 0
        
        while ($timeout -lt 20 -and $ns.DataAvailable) {
            $bytes = $ns.Read($buffer, 0, $buffer.Length)
            $response += [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytes)
            $timeout++
        }
        $client.Close()
        
        if ($response -match "state=playing") { return "playing" }
        if ($response -match "state=stopped") { return "stopped" }
        if ($response -match "state=paused") { return "paused" }
        return "unknown"
    } catch { 
        return "unknown" 
    }
}

# ============ PLAYER PRINCIPAL ULTRA-RAPIDE ============

function Play-Instant {
    param([string]$Url, [string]$Title = "")
    
    if (-not (Ensure-VLCReady)) {
        Write-Error "VLC non disponible"
        return $false
    }
    
    $streamUrl = Get-StreamUrlUltraFast $Url
    if (-not $streamUrl) {
        Write-Error "Impossible de resoudre l'URL"
        return $false
    }
    
    Send-To-VLC $streamUrl
    
    if ($Title) {
        Show-NowPlaying -Titre $Title
    }
    
    return $true
}

function Play-PlaylistTurbo {
    param([array]$PlaylistUrls, [array]$PlaylistTitles)
    
    if ($PlaylistUrls.Count -eq 0) { 
        return 
    }
    
    if (-not (Ensure-VLCReady)) {
        Write-Error "VLC non disponible"
        return
    }
    
    $currentIndex = 0
    $preloadJob = $null
    
    Write-Debug "Chargement piste 1..."
    $currentUrl = Get-StreamUrlUltraFast $PlaylistUrls[0]
    if ($currentUrl) {
        Send-To-VLC $currentUrl
        Show-NowPlaying -Titre $PlaylistTitles[0] -Current 1 -Total $PlaylistUrls.Count
    }
    
    if ($PlaylistUrls.Count -gt 1) {
        Write-Debug "Prechargement piste 2..."
        $preloadJob = Start-Job -Name "Preload" -ScriptBlock {
            param($p, $u)
            & $p -f "bestaudio[ext=m4a]/bestaudio" -g --no-warnings --no-playlist --quiet $u 2>$null
        } -ArgumentList $ytdlpPath, $PlaylistUrls[1]
    }
    
    while ($currentIndex -lt $PlaylistUrls.Count) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).Key.ToString()
            
            switch ($key) {
                "N" {
                    $nextIndex = $currentIndex + 1
                    if ($nextIndex -lt $PlaylistUrls.Count) {
                        $nextUrl = $null
                        if ($preloadJob -and $preloadJob.State -eq "Completed") {
                            $nextUrl = Receive-Job $preloadJob
                            Remove-Job $preloadJob -Force
                            $preloadJob = $null
                            Write-Debug "Piste prechargee utilisee"
                        }
                        
                        if (-not $nextUrl) {
                            Write-Debug "Chargement direct piste $($nextIndex+1)"
                            $nextUrl = Get-StreamUrlUltraFast $PlaylistUrls[$nextIndex]
                        }
                        
                        if ($nextUrl) {
                            $currentIndex = $nextIndex
                            Send-To-VLC $nextUrl
                            Show-NowPlaying -Titre $PlaylistTitles[$currentIndex] -Current ($currentIndex+1) -Total $PlaylistUrls.Count
                            
                            $nextNext = $currentIndex + 1
                            if ($nextNext -lt $PlaylistUrls.Count) {
                                Write-Debug "Prechargement piste $($nextNext+1)..."
                                $preloadJob = Start-Job -Name "Preload" -ScriptBlock {
                                    param($p, $u)
                                    & $p -f "bestaudio[ext=m4a]/bestaudio" -g --no-warnings --no-playlist --quiet $u 2>$null
                                } -ArgumentList $ytdlpPath, $PlaylistUrls[$nextNext]
                            }
                        }
                    }
                }
                "P" {
                    $prevIndex = $currentIndex - 1
                    if ($prevIndex -ge 0) {
                        $prevUrl = Get-StreamUrlUltraFast $PlaylistUrls[$prevIndex]
                        if ($prevUrl) {
                            $currentIndex = $prevIndex
                            Send-To-VLC $prevUrl
                            Show-NowPlaying -Titre $PlaylistTitles[$currentIndex] -Current ($currentIndex+1) -Total $PlaylistUrls.Count
                        }
                    }
                }
                "R" {
                    Send-RCCommand "seek 0"
                }
                "Q" { 
                    if ($preloadJob) { Remove-Job $preloadJob -Force }
                    return 
                }
                "Space" {
                    Send-RCCommand "pause"
                }
            }
        }
        Start-Sleep -Milliseconds 50
    }
    
    if ($preloadJob) { Remove-Job $preloadJob -Force }
}

# ============ GESTION PLAYLIST RAPIDE ============

function Get-PlaylistInfoFast {
    param([string]$Url)
    
    if ($Url -notlike "*list=*") {
        $title = & $ytdlpPath --get-title --no-warnings --quiet $Url 2>$null
        return @($Url), @($title)
    }
    
    Write-Info "Scan playlist..."
    $startScan = Get-Date
    
    $data = & $ytdlpPath --flat-playlist --print "%(title)s|%(id)s" --ignore-errors --no-warnings --quiet $Url 2>$null
    
    $urls = @()
    $titles = @()
    
    foreach ($line in $data) {
        if ($line -match '(.+)\|(.+)') {
            $titles += $Matches[1].Trim()
            $urls += "https://www.youtube.com/watch?v=$($Matches[2])"
        }
    }
    
    $elapsed = [int]((Get-Date).Subtract($startScan).TotalMilliseconds)
    Write-Debug "Playlist scannee en ${elapsed}ms ($($urls.Count) pistes)"
    
    return $urls, $titles
}

# ============ RECHERCHE INTEGREE ============

function Search-YouTube {
    param([string]$Query, [int]$Limit = 10)
    
    if ([string]::IsNullOrWhiteSpace($Query)) {
        Write-Host "  Recherche: " -NoNewline -ForegroundColor White
        $Query = Read-Host
        if ([string]::IsNullOrWhiteSpace($Query)) { 
            return @() 
        }
    }
    
    Write-Info "Recherche: '$Query'..."
    
    $searchQuery = "ytsearch${Limit}:$Query"
    $results = & $ytdlpPath $searchQuery --flat-playlist --print "%(title)s|%(url)s|%(duration)s" --no-warnings --quiet 2>$null
    
    $songs = @()
    $i = 1
    Write-Host ""
    Write-Host "  Resultats:" -ForegroundColor Yellow
    Write-Host "  --------------------------------------------------" -ForegroundColor Gray
    
    foreach ($result in $results) {
        if ($result -match '(.+)\|(.+)\|(.+)') {
            $title = $Matches[1].Trim()
            $url = $Matches[2].Trim()
            $duration = $Matches[3].Trim()
            
            if ($duration -match '(\d+):(\d+)') {
                $duration = "$([int]$Matches[1])min $([int]$Matches[2])s"
            }
            
            Write-Host "  [$i] $title" -ForegroundColor White
            Write-Host "      Duration: $duration" -ForegroundColor Gray
            $songs += @{ Title = $title; Url = $url }
            $i++
        }
    }
    
    Write-Host "  --------------------------------------------------" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Selection (1-$($songs.Count)) ou [A] Ajouter tout: " -NoNewline -ForegroundColor Yellow
    
    $choice = Read-Host
    if ($choice -eq "a" -or $choice -eq "A") {
        return $songs
    }
    
    $index = [int]$choice - 1
    if ($index -ge 0 -and $index -lt $songs.Count) {
        return @($songs[$index])
    }
    
    return @()
}

# ============ AUTOPLAY (MAINS LIBRES) ============

function Start-AutoPlay {
    param([string]$SearchQuery, [int]$MaxSongs = 20)
    
    if (-not (Ensure-VLCReady)) {
        Write-Error "VLC non disponible"
        return
    }
    
    Write-Info "Mode Autoplay: '$SearchQuery'..."
    
    $searchQuery = "ytsearch${MaxSongs}:$SearchQuery"
    $searchResults = & $ytdlpPath $searchQuery --flat-playlist --print "%(title)s|%(url)s" --no-warnings --quiet 2>$null
    
    $playQueue = @()
    foreach ($result in $searchResults) {
        if ($result -match '(.+)\|(.+)') {
            $playQueue += @{
                Title = $Matches[1].Trim()
                Url = $Matches[2].Trim()
            }
        }
    }
    
    if ($playQueue.Count -eq 0) {
        Write-Error "Aucun resultat"
        return
    }
    
    Write-Success "$($playQueue.Count) pistes trouvees"
    $script:autoplayRunning = $true
    
    $currentIndex = 0
    $preloadJob = $null
    
    while ($script:autoplayRunning -and $currentIndex -lt $playQueue.Count) {
        $song = $playQueue[$currentIndex]
        
        $streamUrl = Get-StreamUrlUltraFast $song.Url
        if ($streamUrl) {
            Send-To-VLC $streamUrl
            Show-NowPlaying -Titre $song.Title -Current ($currentIndex + 1) -Total $playQueue.Count
        }
        
        $nextIndex = $currentIndex + 1
        if ($nextIndex -lt $playQueue.Count) {
            $preloadJob = Start-Job -Name "Preload" -ScriptBlock {
                param($p, $u)
                & $p -f "bestaudio[ext=m4a]/bestaudio" -g --no-warnings --no-playlist --quiet $u 2>$null
            } -ArgumentList $ytdlpPath, $playQueue[$nextIndex].Url
        }
        
        $timeout = 0
        $maxTimeout = 300
        
        while ($script:autoplayRunning -and $timeout -lt $maxTimeout) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true).Key.ToString()
                if ($key -eq "Q" -or $key -eq "M") {
                    $script:autoplayRunning = $false
                    break
                }
                if ($key -eq "N") {
                    break
                }
                if ($key -eq "Space") {
                    Send-RCCommand "pause"
                }
            }
            
            $status = Get-QuickStatus
            if ($status -eq "stopped") {
                break
            }
            
            Start-Sleep -Milliseconds 200
            $timeout++
        }
        
        if ($preloadJob) {
            Remove-Job $preloadJob -Force
            $preloadJob = $null
        }
        
        $currentIndex++
        if ($currentIndex -ge $playQueue.Count -and $script:autoplayRunning) {
            Write-Info "Fin de playlist - boucle"
            $currentIndex = 0
        }
    }
    
    $script:autoplayRunning = $false
    Write-Info "Autoplay arrete"
}

# ============ FFMPEG OPTIMISE ============

function Quick-FFmpegCheck {
    if ($script:ffmpegChecked) { 
        return $true 
    }
    
    $c = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($c) { 
        $script:ffmpegPath = $c.Source
        $script:ffmpegChecked = $true
        return $true 
    }
    
    $known = @(
        "C:\Program Files\DownloadHelper CoApp\ffmpeg.exe",
        "$script:appDir\ffmpeg.exe"
    )
    foreach ($k in $known) {
        if (Test-Path $k) {
            $script:ffmpegPath = $k
            $script:ffmpegChecked = $true
            return $true
        }
    }
    
    Write-Info "FFmpeg non trouve. DL desactive."
    $script:ffmpegChecked = $true
    return $false
}

function Download-AudioTurbo {
    param([string]$Url)
    
    if (-not (Quick-FFmpegCheck)) {
        Write-Error "FFmpeg requis pour DL"
        Read-Host "Appuyez sur Entree"
        return
    }
    
    Write-Info "DL M4A max..."
    $args = @(
        "-x", "--audio-format", "m4a",
        "--output", "$script:downloadPath\%(title)s.%(ext)s",
        "--no-warnings",
        "--quiet",
        "--ffmpeg-location", $script:ffmpegPath
    )
    & $ytdlpPath @args $Url
    
    if ($LASTEXITCODE -eq 0) { 
        Write-Success "DL termine !"
    } else {
        Write-Error "Echec DL"
    }
    Read-Host "Appuyez sur Entree"
}

# ============ MENU PRINCIPAL ULTRA-RAPIDE ============

# Initialisation
$ytdlpPath = "yt-dlp"
$null = Get-VLCPath

Load-UrlCache

if (-not (Ensure-VLCReady)) {
    Write-Error "VLC non disponible - installation recommandee"
}

if ($Turbo -or $Direct) {
    if ($Url) {
        Write-Info "Mode Turbo: $Url"
        $success = Play-Instant $Url
        if ($success) {
            Write-Success "Lecture lancee"
        }
        Start-Sleep -Seconds 2
        exit
    }
}

while ($true) {
    Show-Header
    
    if ($script:vlcReady) { 
        Write-Host "  [VLC: PRET] " -NoNewline -ForegroundColor Green
    } else { 
        Write-Host "  [VLC: ...] " -NoNewline -ForegroundColor Yellow 
    }
    Write-Host "Cache: $($script:urlCache.Count) URLs" -ForegroundColor Gray
    if ($script:autoplayRunning) {
        Write-Host "  [AUTOPLAY ACTIF] " -ForegroundColor Magenta
    }
    Write-Host ""
    
    Write-Host "  [1] Lecture simple (URL)" -ForegroundColor White
    Write-Host "  [2] Playlist (N/P/R)" -ForegroundColor White
    Write-Host "  [3] Telecharger (M4A)" -ForegroundColor White
    Write-Host "  [4] Rechercher" -ForegroundColor White
    Write-Host "  [5] Autoplay (mains libres)" -ForegroundColor White
    Write-Host "  [C] Vider cache" -ForegroundColor White
    Write-Host "  [Q] Quitter" -ForegroundColor White
    Write-Host ""
    Write-Host "  > " -NoNewline -ForegroundColor Red
    
    $input = Read-Host
    
    switch ($input.ToLower()) {
        "q" { 
            Save-UrlCache
            break 
        }
        "c" {
            $script:urlCache = @{}
            if (Test-Path $script:cacheFile) { 
                Remove-Item $script:cacheFile -Force 
            }
            Write-Success "Cache vide"
            Start-Sleep -Milliseconds 500
            continue
        }
        "1" {
            Write-Host "  URL: " -NoNewline -ForegroundColor White
            $url = Read-Host
            if ($url) {
                Play-Instant $url
                Start-Sleep -Seconds 2
            }
        }
        "2" {
            Write-Host "  URL (playlist): " -NoNewline -ForegroundColor White
            $url = Read-Host
            if ($url) {
                $urls, $titles = Get-PlaylistInfoFast $url
                if ($urls.Count -gt 0) {
                    Play-PlaylistTurbo $urls $titles
                } else {
                    Write-Error "Aucune piste trouvee"
                    Start-Sleep -Seconds 1
                }
            }
        }
        "3" {
            Write-Host "  URL: " -NoNewline -ForegroundColor White
            $url = Read-Host
            if ($url) {
                Download-AudioTurbo $url
            }
        }
        "4" {
            $songs = Search-YouTube
            if ($songs.Count -gt 0) {
                if ($songs.Count -eq 1) {
                    Play-Instant $songs[0].Url $songs[0].Title
                } else {
                    $urls = @()
                    $titles = @()
                    foreach ($s in $songs) {
                        $urls += $s.Url
                        $titles += $s.Title
                    }
                    Play-PlaylistTurbo $urls $titles
                }
            }
        }
        "5" {
            if ($script:autoplayRunning) {
                Write-Info "Arret de l'autoplay..."
                $script:autoplayRunning = $false
                Start-Sleep -Seconds 1
            } else {
                Write-Host "  Recherche autoplay: " -NoNewline -ForegroundColor White
                $query = Read-Host
                if ($query) {
                    Start-AutoPlay $query
                }
            }
        }
        default {
            if ($input -match '^https?://') {
                Play-Instant $input
                Start-Sleep -Seconds 2
            }
        }
    }
}

Save-UrlCache
Write-Info "Au revoir !"