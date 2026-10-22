# Tests for install/suji.ps1, without Pester (as the hikari installer's). Run
# from anywhere:
#   pwsh -NoProfile -File tests/install.Tests.ps1
# Exit code 0 when everything passes. Windows paths are simulated with temporary
# folders and an injected environment; nothing is downloaded: the downloads are
# local files. Runs on Windows and Linux.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$env:SUJI_INSTALL_TEST = '1'
$env:SUJI_LANG = 'en'
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$InstallScript = [System.IO.Path]::Combine($RepoRoot, 'install', 'suji.ps1')
$IexHarness = [System.IO.Path]::Combine($PSScriptRoot, 'iex-harness.ps1')

# The installer keeps everything inside one script block run in a scope of its
# own (so that iex leaves nothing behind). The tests need its functions and
# $script: variables here, so they take that script block from the file and
# dot-source it; with SUJI_INSTALL_TEST set it stops before running anything.
function Get-InstallerBody {
    param([string]$Path)
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw ('parse errors in ' + $Path) }
    $found = $ast.Find({
            param($n)
            $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
            $n.Parent -is [System.Management.Automation.Language.CommandAst] -and
            $n.Parent.CommandElements.Count -ge 2 -and
            $n.Parent.CommandElements[0] -is [System.Management.Automation.Language.ParenExpressionAst] -and
            [object]::ReferenceEquals($n.Parent.CommandElements[1], $n)
        }, $true)
    if ($null -eq $found) { throw ('installer body not found in ' + $Path) }
    return $found.ScriptBlock.GetScriptBlock()
}
. (Get-InstallerBody $InstallScript)
$script:SujiQuiet = $true
$OriginalThumbSha = $script:ThumbfastSha256

$script:Passed = 0
$script:Failed = 0
$TestRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'suji-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TestRoot | Out-Null

# Typed answers for the questions, in order; $null (no more input) when they run out.
$script:Answers = New-Object System.Collections.Generic.Queue[string]
# The questions asked, in order.
$script:Prompts = New-Object System.Collections.Generic.List[string]
$script:SujiReadLine = {
    param([string]$Prompt)
    $script:Prompts.Add($Prompt)
    if ($script:Answers.Count -gt 0) { return $script:Answers.Dequeue() }
    return $null
}

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    $script:NonInteractive = $true
    $script:Answers.Clear()
    $script:Prompts.Clear()
    try {
        & $Body
        $script:Passed++
        Write-Host ('ok   ' + $Name)
    }
    catch {
        $script:Failed++
        Write-Host ('FAIL ' + $Name) -ForegroundColor Red
        Write-Host ('     ' + $_.Exception.Message + ' (line ' + $_.InvocationInfo.ScriptLineNumber + ')') -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$What = 'value')
    if (-not [object]::Equals($Actual, $Expected)) {
        throw ("{0}: expected [{1}], got [{2}]" -f $What, $Expected, $Actual)
    }
}

function Assert-True {
    param($Condition, [string]$What)
    if (-not $Condition) { throw ('expected true: ' + $What) }
}

function Assert-Throws {
    param([scriptblock]$Body, [string]$Like = '*', [string]$What = 'call')
    $threw = $false
    try { & $Body } catch {
        $threw = $true
        if ($_.Exception.Message -notlike $Like) { throw ("{0} threw [{1}], expected like [{2}]" -f $What, $_.Exception.Message, $Like) }
    }
    if (-not $threw) { throw ($What + ' did not throw') }
}

function P {
    param([string[]]$Parts)
    $r = $Parts[0]
    for ($i = 1; $i -lt $Parts.Count; $i++) { $r = [System.IO.Path]::Combine($r, $Parts[$i]) }
    return $r
}

function New-TestDir {
    param([string]$Name)
    $d = P @($TestRoot, $Name)
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

function Set-TestFile {
    param([string]$Path, [string]$Content = 'x')
    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-TestText {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path)
}

function Test-Exists {
    param([string]$Path)
    return (Test-Path -LiteralPath $Path)
}

# Every file under $Dir as "relative/path=sha256", sorted: to compare two trees.
function Get-TreeState {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return '' }
    $full = (Get-Item -LiteralPath $Dir).FullName
    $out = @(Get-ChildItem -LiteralPath $Dir -Recurse -Force | ForEach-Object {
            $rel = $_.FullName.Substring($full.Length + 1).Replace('\', '/')
            if ($_.PSIsContainer) { $rel + '/' } else { $rel + '=' + (Get-SujiFileSha256 $_.FullName) }
        } | Sort-Object)
    return [string]::Join("`n", $out)
}

# Fake Windows environment rooted in a temp folder.
function New-FakeEnv {
    param([string]$Base)
    return @{
        LocalAppData    = (P @($Base, 'Local'))
        AppData         = (P @($Base, 'Roaming'))
        UserProfile     = (P @($Base, 'User'))
        ProgramFiles    = (P @($Base, 'Program Files'))
        ProgramFilesX86 = $null
        ProgramData     = (P @($Base, 'ProgramData'))
        MpvHome         = $null
        IsAdmin         = $false
        FindCommand     = { param([string]$Name) return $null }
        TestWritable    = { param([string]$Path) return $true }
    }
}

# Fake downloads: URL -> local file. The fake thumbfast's hash replaces the
# pinned one while the tests run.
$script:FakeDownloads = @{}
$script:DownloadLog = New-Object System.Collections.Generic.List[string]
$script:SujiDownloader = {
    param([string]$Url, [string]$OutFile)
    $script:DownloadLog.Add($Url)
    if (-not $script:FakeDownloads.ContainsKey($Url)) { throw ('unexpected download ' + $Url) }
    Copy-Item -LiteralPath $script:FakeDownloads[$Url] -Destination $OutFile -Force
}
$FakeThumb = P @($TestRoot, 'thumbfast-src.lua')
Set-TestFile $FakeThumb "-- fake thumbfast`n"
$script:ThumbfastSha256 = Get-SujiFileSha256 $FakeThumb
$script:FakeDownloads[$script:ThumbfastUrl] = $FakeThumb

$Source = [pscustomobject]@{ SujiDir = (P @($RepoRoot, 'suji')); Version = '9.9.9' }
$SujiFiles = @(Get-ChildItem -LiteralPath $Source.SujiDir -Recurse -File).Count

function Install-Test {
    param([string]$Config, [string]$Kind = 'mpv', [string]$Exe = '', [string]$Stamp = '20260101-000000', [string]$Thumb = $FakeThumb)
    $c = [pscustomobject]@{ Kind = $Kind; Exe = $Exe; ConfigDir = $Config }
    Install-SujiTarget -Candidate $c -Source $Source -ThumbfastFile $Thumb -Stamp $Stamp
}

function Uninstall-Test {
    param([string]$Config, [string]$Stamp = '20260102-000000', [string]$StateDir = '')
    Uninstall-SujiTarget -Candidate ([pscustomobject]@{ Kind = 'mpv'; Exe = ''; ConfigDir = $Config }) -Stamp $Stamp -StateDir $StateDir
}

# What the installer writes to the console while $Body runs.
function Get-ShownText {
    param([scriptblock]$Body)
    $script:SujiQuiet = $false
    try { $out = & $Body 6>&1 | ForEach-Object { [string]$_ } }
    finally { $script:SujiQuiet = $true }
    return [string]::Join("`n", @($out))
}

# The suji.zip of a release: LICENSE and suji\.
function New-TestReleaseZip {
    param([string]$Dir)
    $src = P @($Dir, 'zip-src')
    New-Item -ItemType Directory -Path $src -Force | Out-Null
    Copy-Item -LiteralPath $Source.SujiDir -Destination (P @($src, 'suji')) -Recurse
    Copy-Item -LiteralPath (P @($RepoRoot, 'LICENSE')) -Destination (P @($src, 'LICENSE'))
    $zip = P @($Dir, 'suji.zip')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $zip)
    return $zip
}

$TestReleaseUrl = 'https://github.com/SCEPTICG/suji/releases/download/v9.9.9/suji.zip'

# ---------------------------------------------------------------------------
# The file itself
# ---------------------------------------------------------------------------

Test-Case 'the installer parses without errors and is pure ASCII' {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($InstallScript, [ref]$null, [ref]$errors)
    Assert-Equal @($errors).Count 0 'parse errors'
    $bytes = [System.IO.File]::ReadAllBytes($InstallScript)
    Assert-Equal @($bytes | Where-Object { $_ -gt 127 }).Count 0 'non-ASCII bytes'
}

Test-Case 'the release markers are whole lines, each exactly once, with the development values' {
    $lines = [System.IO.File]::ReadAllText($InstallScript) -split "`r?`n"
    foreach ($m in @("`$script:SujiVersion = 'dev'", "`$script:SujiUrl = ''", "`$script:SujiSha256 = ''")) {
        Assert-Equal @($lines | Where-Object { $_ -ceq $m }).Count 1 $m
    }
    Assert-Equal $OriginalThumbSha 'a3d08e71eae8b892f6cd39f9593ea219768e709312d176bca883841b156448bf' 'thumbfast hash'
    Assert-True ($script:ThumbfastUrl -like '*/po5/thumbfast/0f711de3138c9bd6718209d819ac54022c23ded2/thumbfast.lua') 'thumbfast URL'
}

Test-Case 'Spanish messages decode, English ones stay as they are' {
    try {
        Set-SujiLanguage 'es'
        Assert-True ((T 'invalid') -ceq ('Opci' + [char]0xF3 + 'n no v' + [char]0xE1 + 'lida.')) 'Spanish'
        Assert-True ((T 'release_unpublished').Contains('install\suji.ps1')) 'one backslash'
        Set-SujiLanguage 'en'
        Assert-True ((T 'release_unpublished').Contains('install\suji.ps1')) 'English backslash'
        Assert-Equal @($script:SujiStringsEn.Keys | Where-Object { -not $script:SujiStringsEs.ContainsKey($_) }).Count 0 'every message in both'
    }
    finally { Set-SujiLanguage 'en' }
}

# ---------------------------------------------------------------------------
# The mpv.conf block
# ---------------------------------------------------------------------------

$Block = "# >>> suji (managed block, do not edit) >>>`nosc=no`n# <<< suji (managed block, do not edit) <<<"

Test-Case 'mpv.conf: new file, CRLF, only osc=no' {
    $d = New-TestDir 'block-new'
    Update-SujiMpvConf $d
    Assert-Equal (Get-TestText (P @($d, 'mpv.conf'))) ($Block.Replace("`n", "`r`n") + "`r`n") 'mpv.conf'
}

Test-Case 'mpv.conf: an existing LF file gets the block at the start, the rest unchanged; again, no change' {
    $d = New-TestDir 'block-lf'
    $mine = "# mine`nvolume=50`n[anime]`nsub-auto=fuzzy`n"
    Set-TestFile (P @($d, 'mpv.conf')) $mine
    Update-SujiMpvConf $d
    Assert-Equal (Get-TestText (P @($d, 'mpv.conf'))) ($Block + "`n" + $mine) 'block first'
    Update-SujiMpvConf $d
    Assert-Equal (Get-TestText (P @($d, 'mpv.conf'))) ($Block + "`n" + $mine) 'idempotent'
    Remove-SujiMpvConf -ConfigDir $d -CreatedBySuji $false
    Assert-Equal (Get-TestText (P @($d, 'mpv.conf'))) $mine 'removed, as it was'
}

Test-Case 'mpv.conf: CRLF and a BOM are kept' {
    $d = New-TestDir 'block-crlf'
    $mine = "volume=50`r`nosd-bar=no"
    $p = P @($d, 'mpv.conf')
    [System.IO.File]::WriteAllText($p, $mine, (New-Object System.Text.UTF8Encoding($true)))
    Update-SujiMpvConf $d
    $bytes = [System.IO.File]::ReadAllBytes($p)
    Assert-True ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'BOM kept'
    $text = (Read-SujiText $p).Text
    Assert-Equal $text ($Block.Replace("`n", "`r`n") + "`r`n" + $mine) 'CRLF block'
    Assert-True (-not ($text -match "[^`r]`n")) 'no bare LF'
    Remove-SujiMpvConf -ConfigDir $d -CreatedBySuji $false
    Assert-Equal (Read-SujiText $p).Text $mine 'removed'
}

Test-Case 'mpv.conf: an old block is replaced where it is' {
    $d = New-TestDir 'block-old'
    Set-TestFile (P @($d, 'mpv.conf')) "volume=50`n# >>> suji (managed block, do not edit) >>>`nosc=no`nborder=no`n# <<< suji (managed block, do not edit) <<<`nmute=yes`n"
    Update-SujiMpvConf $d
    Assert-Equal (Get-TestText (P @($d, 'mpv.conf'))) ("volume=50`n" + $Block + "`nmute=yes`n") 'replaced in place'
}

Test-Case 'mpv.conf: a broken or repeated block is refused' {
    $cases = @(
        "# >>> suji (managed block, do not edit) >>>`nosc=no`n",
        "osc=no`n# <<< suji (managed block, do not edit) <<<`n",
        ($Block + "`n" + $Block + "`n"),
        "# <<< suji (managed block, do not edit) <<<`n# >>> suji (managed block, do not edit) >>>`n"
    )
    $i = 0
    foreach ($text in $cases) {
        $d = New-TestDir ('block-bad-' + $i)
        Set-TestFile (P @($d, 'mpv.conf')) $text
        Assert-Throws { Update-SujiMpvConf $d } -Like '*incomplete or repeated suji block*' -What ('case ' + $i)
        Assert-Throws { Remove-SujiMpvConf -ConfigDir $d -CreatedBySuji $false } -Like '*incomplete or repeated*' -What ('remove ' + $i)
        Assert-Equal (Get-TestText (P @($d, 'mpv.conf'))) $text ('untouched ' + $i)
        $i++
    }
}

Test-Case 'install with a broken block: error, nothing changed, no backup' {
    $d = New-TestDir 'block-bad-install'
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'mpv.conf')) "# >>> suji (managed block, do not edit) >>>`nosc=no`n"
    Set-TestFile (P @($cfg, 'scripts', 'osc.lua')) '-- other osc'
    $before = Get-TreeState $cfg
    Assert-Throws { Install-Test $cfg } -Like '*incomplete or repeated*' -What 'install'
    Assert-Equal (Get-TreeState $cfg) $before 'folder unchanged'
    Assert-Equal @(Get-ChildItem -LiteralPath $d).Count 1 'no backup'
}

# ---------------------------------------------------------------------------
# Install, update, uninstall
# ---------------------------------------------------------------------------

Test-Case 'install into a new folder: suji, thumbfast, thumbfast.conf, mpv.conf and the record' {
    $d = New-TestDir 'fresh'
    $cfg = P @($d, 'mpv')
    Install-Test $cfg
    Assert-Equal @(Get-ChildItem -LiteralPath (P @($cfg, 'scripts', 'suji')) -Recurse -File).Count $SujiFiles 'suji files'
    Assert-Equal (Get-TestText (P @($cfg, 'scripts', 'suji', 'main.lua'))) (Get-TestText (P @($Source.SujiDir, 'main.lua'))) 'main.lua'
    Assert-Equal (Get-TestText (P @($cfg, 'scripts', 'thumbfast.lua'))) "-- fake thumbfast`n" 'thumbfast'
    $conf = Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))
    foreach ($l in @('network=yes', 'hwdec=yes', 'spawn_first=no', 'max_height=200', 'max_width=200')) {
        Assert-True ($conf -match ('(?m)^' + [regex]::Escape($l) + "`r?$")) $l
    }
    Assert-True ($conf.StartsWith('# suji settings for thumbfast')) 'header'
    Assert-True ($conf -notmatch 'mpv_path') 'no mpv_path for mpv'
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) ($Block.Replace("`n", "`r`n") + "`r`n") 'mpv.conf'
    $rec = Read-SujiRecord $cfg
    Assert-Equal $rec.Values['suji_version'] '9.9.9' 'version'
    Assert-Equal $rec.Values['thumbfast_preexisting'] 'no' 'thumbfast before'
    Assert-Equal $rec.Values['thumbfast_conf_preexisting'] 'no' 'thumbfast.conf before'
    Assert-Equal $rec.Values['mpv_conf_preexisting'] 'no' 'mpv.conf before'
    Assert-Equal @(Get-ChildItem -LiteralPath $d).Count 1 'nothing to back up: no backup'
}

Test-Case 'update: suji replaced, thumbfast kept as it is, what was there before kept in the record' {
    $d = New-TestDir 'update'
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`n"
    Install-Test $cfg -Stamp '20260101-000000'
    Set-TestFile (P @($cfg, 'scripts', 'suji', 'old-module.lua')) '-- from an older suji'
    Set-TestFile (P @($cfg, 'script-opts', 'suji.conf')) "scale=1.5`n"
    # No thumbfast download needed: the one there is the pinned one.
    Install-Test $cfg -Stamp '20260101-000001' -Thumb ''
    Assert-True (-not (Test-Exists (P @($cfg, 'scripts', 'suji', 'old-module.lua')))) 'old file gone'
    Assert-Equal @(Get-ChildItem -LiteralPath (P @($cfg, 'scripts', 'suji')) -Recurse -File).Count $SujiFiles 'suji files'
    Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'suji.conf'))) "scale=1.5`n" 'suji.conf untouched'
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) ($Block + "`nvolume=50`n") 'one block'
    $rec = Read-SujiRecord $cfg
    Assert-Equal $rec.Values['mpv_conf_preexisting'] 'yes' 'mpv.conf was there'
    Assert-Equal $rec.Values['thumbfast_preexisting'] 'no' 'thumbfast was not, still says so'
    Assert-True (Test-Exists (P @($d, 'mpv-respaldo-suji-20260101-000001', 'scripts', 'suji', 'old-module.lua'))) 'the update backed up the old suji'
}

Test-Case 'a changed thumbfast is replaced on update; without the download that is an error' {
    $d = New-TestDir 'thumb-changed'
    $cfg = P @($d, 'mpv')
    Install-Test $cfg
    Set-TestFile (P @($cfg, 'scripts', 'thumbfast.lua')) '-- changed'
    Assert-Throws { Install-Test $cfg -Stamp '20260101-000001' -Thumb '' } -Like '*thumbfast*' -What 'no download'
    Install-Test $cfg -Stamp '20260101-000002'
    Assert-Equal (Get-TestText (P @($cfg, 'scripts', 'thumbfast.lua'))) "-- fake thumbfast`n" 'pinned again'
}

Test-Case 'uninstall: removes what suji added and puts the rest back as it was' {
    $d = New-TestDir 'uninstall'
    $cfg = P @($d, 'mpv')
    $mine = "volume=50`r`n"
    Set-TestFile (P @($cfg, 'mpv.conf')) $mine
    Set-TestFile (P @($cfg, 'input.conf')) "a cycle pause`n"
    Install-Test $cfg
    Set-TestFile (P @($cfg, 'script-opts', 'suji.conf')) "scale=1.5`n"
    Set-TestFile (P @($cfg, 'suji-size')) "125`n"
    Uninstall-Test $cfg
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) $mine 'mpv.conf as it was'
    foreach ($gone in @(@('scripts', 'suji'), @('scripts', 'thumbfast.lua'), @('script-opts', 'thumbfast.conf'), @('suji-installed.txt'))) {
        Assert-True (-not (Test-Exists (P (@($cfg) + $gone)))) ([string]::Join('/', $gone) + ' removed')
    }
    # With -Yes the user's settings stay.
    Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'suji.conf'))) "scale=1.5`n" 'suji.conf kept'
    Assert-Equal (Get-TestText (P @($cfg, 'suji-size'))) "125`n" 'suji-size kept'
    Assert-True (-not (Test-Exists (P @($cfg, 'scripts')))) 'empty scripts removed'
    Assert-Equal (Get-TestText (P @($cfg, 'input.conf'))) "a cycle pause`n" 'input.conf untouched'
}

Test-Case 'uninstall: an mpv.conf suji created goes; asked, the user files go too' {
    $d = New-TestDir 'uninstall-ask'
    $cfg = P @($d, 'mpv')
    Install-Test $cfg
    Set-TestFile (P @($cfg, 'script-opts', 'suji.conf')) "scale=1.5`n"
    Set-TestFile (P @($cfg, 'suji-size')) "125`n"
    $script:NonInteractive = $false
    # Remove thumbfast? yes. Delete settings? yes.
    foreach ($a in @('y', 's')) { $script:Answers.Enqueue($a) }
    Uninstall-Test $cfg
    Assert-Equal $script:Answers.Count 0 'two questions'
    Assert-Equal (Get-TreeState $cfg) '' 'nothing left'
}

Test-Case 'thumbfast that was there before is kept on uninstall (default), with its conf' {
    $d = New-TestDir 'thumb-before'
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'scripts', 'thumbfast.lua')) '-- my thumbfast'
    Set-TestFile (P @($cfg, 'script-opts', 'thumbfast.conf')) "network=no`n"
    Install-Test $cfg
    Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))) "network=no`n" 'existing conf untouched (mpv: no mpv_path)'
    Uninstall-Test $cfg
    Assert-Equal (Get-TestText (P @($cfg, 'scripts', 'thumbfast.lua'))) "-- fake thumbfast`n" 'thumbfast kept'
    Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))) "network=no`n" 'conf kept'
}

Test-Case 'uninstall: the settings question names only what it deletes; a suji-size in the state folder stays and is named' {
    $d = New-TestDir 'size-state'
    $cfg = P @($d, 'mpv')
    $state = P @($d, 'Local', 'mpv')
    Install-Test $cfg
    Set-TestFile (P @($cfg, 'suji-size')) "125`n"
    Set-TestFile (P @($state, 'suji-size')) "110`n"
    $script:NonInteractive = $false
    foreach ($a in @('y', 'y')) { $script:Answers.Enqueue($a) }
    $shown = Get-ShownText { Uninstall-Test $cfg -StateDir $state }
    Assert-True ($script:Prompts[1].StartsWith('Delete suji-size too')) ('question: ' + $script:Prompts[1])
    Assert-True (-not $script:Prompts[1].Contains('suji.conf')) 'no suji.conf in it: there is none'
    Assert-True (-not (Test-Exists (P @($cfg, 'suji-size')))) 'the one in the config folder deleted'
    Assert-Equal (Get-TestText (P @($state, 'suji-size'))) "110`n" 'the state one stays'
    Assert-True ($shown.Contains('This file stays: ' + (P @($state, 'suji-size')))) ('named; shown: ' + $shown)
    # A portable_config is its own state folder: nothing else is named.
    $c = [pscustomobject]@{ Kind = 'AnimeJaNai'; Exe = 'x'; ConfigDir = $cfg; Portable = $true }
    Assert-Equal (Get-SujiStateDir -Env (New-FakeEnv $d) -Candidate $c) '' 'portable'
    $c.Portable = $false
    Assert-Equal (Get-SujiStateDir -Env (New-FakeEnv $d) -Candidate $c) (P @($d, 'Local', 'mpv')) '%LOCALAPPDATA%\mpv'
}

# ---------------------------------------------------------------------------
# thumbfast.conf and mpv_path
# ---------------------------------------------------------------------------

Test-Case 'thumbfast.conf: new for AnimeJaNai, with mpv_path to its mpvnet.exe' {
    $d = New-TestDir 'mpvpath-new'
    $exe = P @($d, 'mpv-AnimeJaNai', 'mpvnet.exe')
    Set-TestFile $exe 'exe'
    $cfg = P @($d, 'mpv-AnimeJaNai', 'portable_config')
    Install-Test $cfg -Kind 'AnimeJaNai' -Exe $exe
    $conf = Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))
    Assert-True ($conf.EndsWith("max_width=200`r`n`r`n" + $script:MpvPathComment + "`r`nmpv_path=" + $exe + "`r`n")) ('mpv_path; got ' + $conf)
    Assert-True ($conf.Contains("network=yes`r`n")) 'settings too'
    Install-Test $cfg -Kind 'AnimeJaNai' -Exe $exe -Stamp '20260101-000001'
    Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))) $conf 'unchanged on update'
}

Test-Case 'thumbfast.conf: an existing one only gets mpv_path, and only when it has none' {
    $d = New-TestDir 'mpvpath-existing'
    $exe = P @($d, 'mpv.net', 'mpvnet.exe')
    Set-TestFile $exe 'exe'
    $cfg = P @($d, 'cfg1')
    Set-TestFile (P @($cfg, 'script-opts', 'thumbfast.conf')) "network=no`nmax_height=300"
    Install-Test $cfg -Kind 'mpv.net' -Exe $exe
    Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))) ("network=no`nmax_height=300`n`n" + $script:MpvPathComment + "`nmpv_path=" + $exe + "`n") 'added, LF kept'
    $cfg2 = P @($d, 'cfg2')
    Set-TestFile (P @($cfg2, 'script-opts', 'thumbfast.conf')) "mpv_path=C:\other\mpv.exe`r`n"
    Install-Test $cfg2 -Kind 'mpv.net' -Exe $exe
    Assert-Equal (Get-TestText (P @($cfg2, 'script-opts', 'thumbfast.conf'))) "mpv_path=C:\other\mpv.exe`r`n" 'own mpv_path kept'
    $cfg3 = P @($d, 'cfg3')
    Install-Test $cfg3 -Kind 'mpv.net' -Exe ''
    Assert-True ((Get-TestText (P @($cfg3, 'script-opts', 'thumbfast.conf'))) -notmatch 'mpv_path') 'mpv.net without its exe: none'
}

Test-Case 'thumbfast.conf of the user: the mpv_path lines suji added go on uninstall, byte for byte back' {
    $d = New-TestDir 'mark'
    $exe = P @($d, 'mpv.net', 'mpvnet.exe')
    $cases = @("network=no`nmax_height=300", "network=no`r`nmax_height=300`r`n", "", "# mine`n`n")
    $i = 0
    foreach ($text in $cases) {
        $cfg = P @($d, ('cfg' + $i))
        Set-TestFile (P @($cfg, 'script-opts', 'thumbfast.conf')) $text
        Install-Test $cfg -Kind 'mpv.net' -Exe $exe
        Assert-True ((Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))).Contains($script:MpvPathComment)) ('marked ' + $i)
        Install-Test $cfg -Kind 'mpv.net' -Exe $exe -Stamp '20260101-000001'
        Uninstall-Test $cfg
        Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))) $text ('as it was ' + $i)
        $i++
    }
    # The mark taken out by the user: the mpv_path line is theirs now.
    $cfg = P @($d, 'cfg-nomark')
    Set-TestFile (P @($cfg, 'script-opts', 'thumbfast.conf')) "network=no`n"
    Install-Test $cfg -Kind 'mpv.net' -Exe $exe
    $p = P @($cfg, 'script-opts', 'thumbfast.conf')
    Set-TestFile $p ((Get-TestText $p).Replace($script:MpvPathComment + "`n", ''))
    $now = Get-TestText $p
    Uninstall-Test $cfg
    Assert-Equal (Get-TestText $p) $now 'left alone'
    Assert-Equal (Read-SujiRecord (P @($d, 'cfg0'))) $null 'record gone'
    # A thumbfast.conf suji made stays whole when thumbfast stays.
    $cfg = P @($d, 'cfg-made')
    Install-Test $cfg -Kind 'mpv.net' -Exe $exe
    $made = Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))
    $script:NonInteractive = $false
    $script:Answers.Enqueue('n')
    Uninstall-Test $cfg
    Assert-Equal (Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))) $made 'whole, with its mpv_path'
}

# ---------------------------------------------------------------------------
# Backups
# ---------------------------------------------------------------------------

Test-Case 'backup: only what suji may touch, at its relative path' {
    $d = New-TestDir 'backup'
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`n"
    Set-TestFile (P @($cfg, 'input.conf')) "a cycle pause`n"
    Set-TestFile (P @($cfg, 'watch_later', 'ABC')) 'pos'
    Set-TestFile (P @($cfg, 'scripts', 'other.lua')) '-- other script'
    Set-TestFile (P @($cfg, 'scripts', 'modernz.lua')) '-- modernz'
    Set-TestFile (P @($cfg, 'script-opts', 'thumbfast.conf')) "network=no`n"
    Set-TestFile (P @($cfg, 'script-opts', 'modernz.conf')) "x=1`n"
    Install-Test $cfg -Stamp '20260101-120000'
    $b = P @($d, 'mpv-respaldo-suji-20260101-120000')
    $expected = [string]::Join("`n", @(@(
                ('mpv.conf=' + (Get-SujiFileSha256 (P @($b, 'mpv.conf')))),
                'script-opts/',
                ('script-opts/modernz.conf=' + (Get-SujiFileSha256 (P @($b, 'script-opts', 'modernz.conf')))),
                ('script-opts/thumbfast.conf=' + (Get-SujiFileSha256 (P @($b, 'script-opts', 'thumbfast.conf')))),
                'scripts/',
                ('scripts/modernz.lua=' + (Get-SujiFileSha256 (P @($b, 'scripts', 'modernz.lua'))))
            ) | Sort-Object))
    Assert-Equal (Get-TreeState $b) $expected 'backup contents'
    Assert-Equal (Get-TestText (P @($b, 'mpv.conf'))) "volume=50`n" 'mpv.conf as before'
    Assert-Equal (Get-TestText (P @($b, 'scripts', 'modernz.lua'))) '-- modernz' 'set-aside script as before'
}

Test-Case 'backups: the three newest stay, others and look-alikes are left alone' {
    $d = New-TestDir 'rotate'
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`n"
    foreach ($s in @('20250101-000000', '20250102-000000', '20250103-000000', '20250104-000000')) {
        Set-TestFile (P @($d, ('mpv-respaldo-suji-' + $s), 'mpv.conf')) 'old'
    }
    Set-TestFile (P @($d, 'mpv-respaldo-hikari-20240101-000000', 'mpv.conf')) 'hikari backup'
    Set-TestFile (P @($d, 'mpv2-respaldo-suji-20240101-000000', 'mpv.conf')) 'another folder'
    Set-TestFile (P @($d, 'mpv-respaldo-suji-mine', 'mpv.conf')) 'not a stamp'
    Install-Test $cfg -Stamp '20260101-000000'
    Install-Test $cfg -Stamp '20260101-000000'
    $left = @(Get-ChildItem -LiteralPath $d -Directory | ForEach-Object { $_.Name } | Sort-Object)
    Assert-Equal ([string]::Join(' ', $left)) ([string]::Join(' ', @('mpv', 'mpv-respaldo-hikari-20240101-000000', 'mpv-respaldo-suji-20250104-000000',
                'mpv-respaldo-suji-20260101-000000', 'mpv-respaldo-suji-20260101-000000-2', 'mpv-respaldo-suji-mine', 'mpv2-respaldo-suji-20240101-000000'))) 'folders left'
}

Test-Case 'a link inside the folder is not followed by the backup' {
    $d = New-TestDir 'backup-link'
    $cfg = P @($d, 'mpv')
    $outside = P @($d, 'outside')
    Set-TestFile (P @($outside, 'secret.txt')) 'secret'
    Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`n"
    New-Item -ItemType Directory -Path (P @($cfg, 'scripts')) -Force | Out-Null
    try { New-Item -ItemType SymbolicLink -Path (P @($cfg, 'scripts', 'suji')) -Target $outside | Out-Null }
    catch { Write-Host '     (symlinks not available, skipped)'; return }
    $b = New-SujiBackup -ConfigDir $cfg -Stamp '20260101-000000'
    Assert-True (-not (Test-Exists (P @($b, 'scripts')))) 'link not copied'
    # An update replaces the link with a real folder; what it pointed at stays.
    Install-Test $cfg -Stamp '20260101-000001'
    Assert-Equal (Get-TreeState $outside) ('secret.txt=' + (Get-SujiFileSha256 (P @($outside, 'secret.txt')))) 'target untouched'
    Assert-True (-not ((Get-Item -LiteralPath (P @($cfg, 'scripts', 'suji')) -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) 'a real folder now'
}

# ---------------------------------------------------------------------------
# Interfaces set aside
# ---------------------------------------------------------------------------

Test-Case 'conflicting interfaces are set aside, recorded, and come back on uninstall' {
    $d = New-TestDir 'aside'
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'scripts', 'osc.lua')) '-- an osc'
    Set-TestFile (P @($cfg, 'scripts', 'modernz.lua')) '-- modernz'
    Set-TestFile (P @($cfg, 'script-opts', 'modernz.conf')) "a=1`n"
    Set-TestFile (P @($cfg, 'fonts', 'modernz-icons.ttf')) 'font'
    Set-TestFile (P @($cfg, 'fonts', 'other.ttf')) 'font'
    Set-TestFile (P @($cfg, 'scripts', 'uosc', 'main.lua')) '-- uosc'
    Set-TestFile (P @($cfg, 'script-opts', 'uosc.conf')) "b=2`n"
    Set-TestFile (P @($cfg, 'fonts', 'uosc_icons.otf')) 'icons'
    Set-TestFile (P @($cfg, 'scripts', 'mine.lua')) '-- mine'
    $before = Get-TreeState $cfg
    Install-Test $cfg
    $moved = [ordered]@{
        'scripts/osc.lua' = 'osc.lua'; 'scripts/modernz.lua' = 'modernz.lua'; 'script-opts/modernz.conf' = 'script-opts/modernz.conf'
        'fonts/modernz-icons.ttf' = 'fonts/modernz-icons.ttf'; 'scripts/uosc' = 'uosc'; 'script-opts/uosc.conf' = 'script-opts/uosc.conf'
    }
    foreach ($rel in $moved.Keys) {
        Assert-True (-not (Test-Exists (Join-SujiRel $cfg $rel))) ($rel + ' moved')
        Assert-True (Test-Exists (Join-SujiRel $cfg ('scripts-apartados-suji/' + $moved[$rel]))) ($rel + ' set aside')
    }
    Assert-True (Test-Exists (P @($cfg, 'scripts', 'mine.lua'))) 'other scripts stay'
    Assert-True (Test-Exists (P @($cfg, 'fonts', 'other.ttf'))) 'other fonts stay'
    Assert-True (Test-Exists (P @($cfg, 'fonts', 'uosc_icons.otf'))) 'uosc fonts stay, as in the hikari installer'
    $rec = Read-SujiRecord $cfg
    Assert-Equal @($rec.Aside).Count 6 'recorded'
    Assert-True (@($rec.Aside) -contains 'scripts-apartados-suji/uosc|scripts/uosc') 'uosc entry'
    Assert-True (@($rec.Aside) -contains 'scripts-apartados-suji/script-opts/uosc.conf|script-opts/uosc.conf') 'uosc.conf entry'
    Uninstall-Test $cfg
    Assert-Equal (Get-TreeState $cfg) $before 'all back, nothing else left'
}

Test-Case 'conflicts kept when the user says no; a second install keeps the first record' {
    $d = New-TestDir 'aside-no'
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'scripts', 'osc.lua')) '-- an osc'
    $script:NonInteractive = $false
    $script:Answers.Enqueue('n')
    Install-Test $cfg
    Assert-True (Test-Exists (P @($cfg, 'scripts', 'osc.lua'))) 'left in place'
    Assert-Equal @((Read-SujiRecord $cfg).Aside).Count 0 'nothing recorded'
    $script:NonInteractive = $true
    Install-Test $cfg -Stamp '20260101-000001'
    Set-TestFile (P @($cfg, 'scripts', 'osc.lua')) '-- a new one'
    Install-Test $cfg -Stamp '20260101-000002'
    $aside = @((Read-SujiRecord $cfg).Aside)
    Assert-Equal $aside.Count 2 'both recorded'
    Assert-Equal $aside[1] 'scripts-apartados-suji/osc-20260101-000002.lua|scripts/osc.lua' 'renamed, not overwritten'
}

Test-Case 'a tampered record cannot move things outside the folder' {
    $d = New-TestDir 'record-bad'
    $cfg = P @($d, 'mpv')
    Install-Test $cfg
    Set-TestFile (P @($d, 'victim.txt')) 'victim'
    $rec = P @($cfg, 'suji-installed.txt')
    $text = Get-TestText $rec
    $text += "disabled=../victim.txt|scripts/x.lua`r`ndisabled=scripts-apartados-suji/a|../../x`r`ndisabled=scripts-apartados-suji/a|mpv.conf`r`n"
    Set-TestFile $rec $text
    Assert-Equal @((Read-SujiRecord $cfg -NoWarn).Aside).Count 0 'all three refused'
    Uninstall-Test $cfg
    Assert-Equal (Get-TestText (P @($d, 'victim.txt'))) 'victim' 'untouched'
}

# ---------------------------------------------------------------------------
# Links (junctions, symbolic links) where the installer writes
# ---------------------------------------------------------------------------

# A config folder with a link at $Rel to a file or folder outside it. $null
# when this system cannot make symbolic links.
function New-LinkedConfig {
    param([string]$Name, [string]$Rel, [switch]$Folder)
    $d = New-TestDir $Name
    $cfg = P @($d, 'mpv')
    $outside = P @($d, 'outside')
    Set-TestFile (P @($cfg, 'input.conf')) "a cycle pause`n"
    if ($Folder) { Set-TestFile (P @($outside, 'thumbfast.conf')) "network=no`n"; $target = $outside }
    else { Set-TestFile (P @($outside, 'file.conf')) "volume=50`n"; $target = P @($outside, 'file.conf') }
    $link = Join-SujiRel $cfg $Rel
    New-Item -ItemType Directory -Path (Split-Path -Path $link -Parent) -Force | Out-Null
    try { New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null }
    catch { return $null }
    return [pscustomobject]@{ Dir = $d; Config = $cfg; Outside = $outside }
}

Test-Case 'a linked mpv.conf is written through and stays a link, also on uninstall' {
    $t = New-LinkedConfig 'link-mpvconf' 'mpv.conf'
    if ($null -eq $t) { Write-Host '     (symlinks not available, skipped)'; return }
    $link = P @($t.Config, 'mpv.conf')
    Install-Test $t.Config
    Assert-True (((Get-Item -LiteralPath $link -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) 'still a link'
    Assert-Equal (Get-TestText (P @($t.Outside, 'file.conf'))) ($Block + "`nvolume=50`n") 'written through'
    Uninstall-Test $t.Config
    Assert-True (((Get-Item -LiteralPath $link -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) 'still a link after'
    Assert-Equal (Get-TestText (P @($t.Outside, 'file.conf'))) "volume=50`n" 'block taken out through it'
}

Test-Case 'a linked thumbfast.conf only gets mpv_path, through the link' {
    $t = New-LinkedConfig 'link-tconf' 'script-opts/thumbfast.conf'
    if ($null -eq $t) { Write-Host '     (symlinks not available, skipped)'; return }
    $exe = P @($t.Dir, 'mpv.net', 'mpvnet.exe')
    Install-Test $t.Config -Kind 'mpv.net' -Exe $exe
    Assert-True (((Get-Item -LiteralPath (P @($t.Config, 'script-opts', 'thumbfast.conf')) -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) 'still a link'
    Assert-Equal (Get-TestText (P @($t.Outside, 'file.conf'))) ("volume=50`n`n" + $script:MpvPathComment + "`nmpv_path=" + $exe + "`n") 'mpv_path added in the target'
}

Test-Case 'a linked script-opts: thumbfast.conf is made in the folder it points at, and the link stays' {
    $t = New-LinkedConfig 'link-opts' 'script-opts' -Folder
    if ($null -eq $t) { Write-Host '     (symlinks not available, skipped)'; return }
    Remove-Item -LiteralPath (P @($t.Outside, 'thumbfast.conf'))
    Install-Test $t.Config
    Assert-True ((Get-TestText (P @($t.Outside, 'thumbfast.conf'))).StartsWith('# suji settings for thumbfast')) 'in the target'
    Uninstall-Test $t.Config
    Assert-True (Test-Exists (P @($t.Config, 'script-opts'))) 'link kept'
    Assert-True (((Get-Item -LiteralPath (P @($t.Config, 'script-opts')) -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) 'still a link'
    Assert-True (Test-Exists $t.Outside) 'target folder kept'
    Assert-True (-not (Test-Exists (P @($t.Outside, 'thumbfast.conf')))) 'suji''s thumbfast.conf removed from it'
}

Test-Case 'a linked scripts folder: suji and thumbfast go in the folder it points at, and the link stays' {
    $t = New-LinkedConfig 'link-scripts' 'scripts' -Folder
    if ($null -eq $t) { Write-Host '     (symlinks not available, skipped)'; return }
    Install-Test $t.Config
    Assert-True (Test-Exists (P @($t.Outside, 'suji', 'main.lua'))) 'suji in the target'
    Assert-True (Test-Exists (P @($t.Outside, 'thumbfast.lua'))) 'thumbfast in the target'
    Uninstall-Test $t.Config
    Assert-True (((Get-Item -LiteralPath (P @($t.Config, 'scripts')) -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) 'still a link'
    Assert-Equal (Get-TreeState $t.Outside) ('thumbfast.conf=' + (Get-SujiFileSha256 (P @($t.Outside, 'thumbfast.conf')))) 'only what was there before'
}

Test-Case 'uninstall with scripts\suji or thumbfast.lua as links: the links go, what they point at stays' {
    $d = New-TestDir 'link-suji-uninstall'
    $cfg = P @($d, 'mpv')
    Install-Test $cfg
    $other = P @($d, 'other-suji')
    Set-TestFile (P @($other, 'main.lua')) '-- my own suji'
    $otherThumb = P @($d, 'my-thumbfast.lua')
    Set-TestFile $otherThumb '-- my thumbfast'
    Remove-SujiItem -Path (P @($cfg, 'scripts', 'suji')) -Root $cfg
    Remove-SujiItem -Path (P @($cfg, 'scripts', 'thumbfast.lua')) -Root $cfg
    try {
        New-Item -ItemType SymbolicLink -Path (P @($cfg, 'scripts', 'suji')) -Target $other | Out-Null
        New-Item -ItemType SymbolicLink -Path (P @($cfg, 'scripts', 'thumbfast.lua')) -Target $otherThumb | Out-Null
    }
    catch { Write-Host '     (symlinks not available, skipped)'; return }
    $script:NonInteractive = $false
    $script:Answers.Enqueue('y')
    Uninstall-Test $cfg
    Assert-True (-not (Test-Exists (P @($cfg, 'scripts', 'suji')))) 'suji link gone'
    Assert-True (-not (Test-Exists (P @($cfg, 'scripts', 'thumbfast.lua')))) 'thumbfast link gone'
    Assert-Equal (Get-TestText (P @($other, 'main.lua'))) '-- my own suji' 'other folder intact'
    Assert-Equal (Get-TestText $otherThumb) '-- my thumbfast' 'other thumbfast intact'
}

Test-Case 'backup: a linked mpv.conf is copied with its contents' {
    $t = New-LinkedConfig 'backup-linked-mpvconf' 'mpv.conf'
    if ($null -eq $t) { Write-Host '     (symlinks not available, skipped)'; return }
    Install-Test $t.Config -Stamp '20260101-000000'
    $b = P @($t.Dir, 'mpv-respaldo-suji-20260101-000000', 'mpv.conf')
    $item = Get-Item -LiteralPath $b -Force
    Assert-True (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) 'a real file in the backup'
    Assert-Equal (Get-TestText $b) "volume=50`n" 'its contents'
}

Test-Case 'backup: through linked scripts and script-opts folders, what suji will change is copied' {
    $d = New-TestDir 'backup-linked-dirs'
    $cfg = P @($d, 'mpv')
    $scripts = P @($d, 'dot-scripts')
    $opts = P @($d, 'dot-opts')
    Set-TestFile (P @($scripts, 'suji', 'main.lua')) '-- an older suji'
    Set-TestFile (P @($scripts, 'thumbfast.lua')) '-- an older thumbfast'
    Set-TestFile (P @($opts, 'suji.conf')) "scale=2`n"
    Set-TestFile (P @($opts, 'thumbfast.conf')) "network=no`n"
    New-Item -ItemType Directory -Path $cfg -Force | Out-Null
    try {
        New-Item -ItemType SymbolicLink -Path (P @($cfg, 'scripts')) -Target $scripts | Out-Null
        New-Item -ItemType SymbolicLink -Path (P @($cfg, 'script-opts')) -Target $opts | Out-Null
    }
    catch { Write-Host '     (symlinks not available, skipped)'; return }
    Install-Test $cfg -Stamp '20260101-000000'
    $b = P @($d, 'mpv-respaldo-suji-20260101-000000')
    Assert-Equal (Get-TestText (P @($b, 'scripts', 'suji', 'main.lua'))) '-- an older suji' 'scripts\suji'
    Assert-Equal (Get-TestText (P @($b, 'scripts', 'thumbfast.lua'))) '-- an older thumbfast' 'thumbfast.lua'
    Assert-Equal (Get-TestText (P @($b, 'script-opts', 'suji.conf'))) "scale=2`n" 'suji.conf'
    Assert-Equal (Get-TestText (P @($b, 'script-opts', 'thumbfast.conf'))) "network=no`n" 'thumbfast.conf'
    Assert-Equal (Get-TestText (P @($scripts, 'suji', 'main.lua'))) (Get-TestText (P @($Source.SujiDir, 'main.lua'))) 'and then updated through the link'
}

Test-Case 'writes leave no temporary file behind' {
    $d = New-TestDir 'no-tmp'
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`n"
    Install-Test $cfg
    Install-Test $cfg -Stamp '20260101-000001'
    Uninstall-Test $cfg
    Assert-Equal @(Get-ChildItem -LiteralPath $cfg -Recurse -Force | Where-Object { $_.Name -like '*.tmp' -or $_.Name -like '.suji-new-*' }).Count 0 'no leftovers'
}

# ---------------------------------------------------------------------------
# hikari
# ---------------------------------------------------------------------------

Test-Case 'a folder with hikari is not touched, on install or uninstall' {
    foreach ($sign in @('record', 'sosc', 'scripts')) {
        $d = New-TestDir ('hikari-' + $sign)
        $cfg = P @($d, 'mpv')
        if ($sign -eq 'record') { Set-TestFile (P @($cfg, 'hikari-installed.txt')) "hikari_version=1.0.0`n" }
        elseif ($sign -eq 'sosc') { Set-TestFile (P @($cfg, 'sosc-installed.txt')) "sosc_version=0.3.0`n" }
        else { Set-TestFile (P @($cfg, 'scripts', 'hikari-palettes.lua')) '-- hikari' }
        Set-TestFile (P @($cfg, 'scripts', 'osc.lua')) '-- an osc'
        Set-TestFile (P @($cfg, 'scripts', 'suji', 'main.lua')) '-- suji installed by hikari'
        $before = Get-TreeState $cfg
        Assert-Throws { Install-Test $cfg } -Like '*has hikari: nothing is changed there*-Interface suji*' -What ('install ' + $sign)
        Assert-Throws { Uninstall-Test $cfg } -Like '*has hikari*' -What ('uninstall ' + $sign)
        foreach ($action in @('install', 'uninstall')) {
            Assert-Equal (Invoke-SujiMain -Action $action -Target @($cfg) -Yes $true -Environment (New-FakeEnv $d)) 2 ('-Yes ' + $action + ' ' + $sign)
        }
        Assert-Equal (Get-TreeState $cfg) $before ('untouched ' + $sign)
        Assert-Equal @(Get-ChildItem -LiteralPath $d).Count 1 ('no backup ' + $sign)
        $c = New-SujiCandidate -Env (New-FakeEnv $d) -Kind 'folder' -Exe '' -ConfigDir $cfg -Portable $false
        Assert-True $c.Hikari ('tagged ' + $sign)
        Assert-True ((Get-SujiCandidateTags $c).Contains('[hikari: use its installer]')) 'tag text'
    }
}

# ---------------------------------------------------------------------------
# The whole run (Invoke-SujiMain), with a fake machine
# ---------------------------------------------------------------------------

# A release build in this session: its zip, and that zip's hash (or another).
function Use-TestRelease {
    param([string]$Dir, [string]$Sha256 = '')
    $zip = New-TestReleaseZip $Dir
    if (-not $Sha256) { $Sha256 = Get-SujiFileSha256 $zip }
    $script:SujiUrl = $TestReleaseUrl
    $script:SujiSha256 = $Sha256
    $script:SujiVersion = '9.9.9'
    $script:FakeDownloads[$TestReleaseUrl] = $zip
}

function Reset-TestRelease {
    $script:SujiUrl = ''
    $script:SujiSha256 = ''
    $script:SujiVersion = 'dev'
    $script:ThumbfastSha256 = Get-SujiFileSha256 $FakeThumb
}

function Get-TempLeftovers {
    return @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Force -Filter 'suji-install-*')
}

Test-Case 'main: a release installs from its checked zip into an AnimeJaNai portable_config' {
    $d = New-TestDir 'main-release'
    try {
        Use-TestRelease $d
        $fake = New-FakeEnv $d
        $exe = P @($fake.LocalAppData, 'Programs', 'mpv-AnimeJaNai', 'mpvnet.exe')
        Set-TestFile $exe 'exe'
        $cfg = P @($fake.LocalAppData, 'Programs', 'mpv-AnimeJaNai', 'portable_config')
        Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`n"
        $script:DownloadLog.Clear()
        $tempBefore = @(Get-TempLeftovers).Count
        $code = Invoke-SujiMain -Action 'install' -Target @() -Yes $true -Environment $fake
        Assert-Equal $code 0 'exit code'
        Assert-Equal ([string]::Join(' ', $script:DownloadLog)) ($TestReleaseUrl + ' ' + $script:ThumbfastUrl) 'downloads'
        Assert-Equal (Get-TestText (P @($cfg, 'scripts', 'suji', 'main.lua'))) (Get-TestText (P @($Source.SujiDir, 'main.lua'))) 'from the zip'
        Assert-True ((Get-TestText (P @($cfg, 'script-opts', 'thumbfast.conf'))).Contains('mpv_path=' + $exe)) 'mpv_path'
        Assert-Equal (Read-SujiRecord $cfg).Values['player'] 'AnimeJaNai' 'player'
        Assert-Equal @(Get-TempLeftovers).Count $tempBefore 'temp removed'
        # Again: thumbfast is up to date, only the zip is downloaded.
        $script:DownloadLog.Clear()
        Assert-Equal (Invoke-SujiMain -Action 'install' -Target @() -Yes $true -Environment $fake) 0 'update'
        Assert-Equal ([string]::Join(' ', $script:DownloadLog)) $TestReleaseUrl 'only the zip'
        Assert-Equal (Invoke-SujiMain -Action 'uninstall' -Target @() -Yes $true -Environment $fake) 0 'uninstall'
        Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) "volume=50`n" 'as before'
    }
    finally { Reset-TestRelease }
}

Test-Case 'main: a zip or thumbfast with the wrong hash installs nothing, anywhere' {
    $d = New-TestDir 'main-badhash'
    try {
        $fake = New-FakeEnv $d
        $cfg = P @($d, 'cfg')
        Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`n"
        Set-TestFile (P @($cfg, 'scripts', 'osc.lua')) '-- an osc'
        $before = Get-TreeState $d
        $tempBefore = @(Get-TempLeftovers).Count
        Use-TestRelease (New-TestDir 'main-badhash-zip') -Sha256 ('b' * 64)
        Assert-Equal (Invoke-SujiMain -Action 'install' -Target @($cfg) -Yes $true -Environment $fake) 1 'bad zip'
        Assert-Equal (Get-TreeState $d) $before 'nothing changed, no backup'
        Reset-TestRelease
        Use-TestRelease (New-TestDir 'main-badhash-zip2')
        $script:ThumbfastSha256 = 'c' * 64
        Assert-Equal (Invoke-SujiMain -Action 'install' -Target @($cfg) -Yes $true -Environment $fake) 1 'bad thumbfast'
        Assert-Equal (Get-TreeState $d) $before 'nothing changed either'
        Assert-Equal @(Get-TempLeftovers).Count $tempBefore 'temp removed'
    }
    finally { Reset-TestRelease }
}

Test-Case 'main: the repository version installs from its own suji folder; run on its own it cannot' {
    $d = New-TestDir 'main-dev'
    $cfg = P @($d, 'cfg')
    $saved = $script:SujiScriptRoot
    try {
        $script:SujiScriptRoot = P @($RepoRoot, 'install')
        Assert-Equal (Invoke-SujiMain -Action 'install' -Target @($cfg) -Yes $true -Environment (New-FakeEnv $d)) 0 'dev install'
        Assert-Equal (Read-SujiRecord $cfg).Values['suji_version'] 'dev' 'version dev'
        $script:SujiScriptRoot = ''
        $cfg2 = P @($d, 'cfg2')
        Assert-Equal (Invoke-SujiMain -Action 'install' -Target @($cfg2) -Yes $true -Environment (New-FakeEnv $d)) 1 'no release'
        Assert-True (-not (Test-Exists $cfg2)) 'nothing made'
    }
    finally { $script:SujiScriptRoot = $saved }
}

Test-Case 'main: exit codes for wrong usage and for a failed folder' {
    $d = New-TestDir 'main-codes'
    $fake = New-FakeEnv $d
    Assert-Equal (Invoke-SujiMain -Action '' -Target @() -Yes $true -Environment $fake) 2 '-Yes without -Action'
    Assert-Equal (Invoke-SujiMain -Action 'install' -Target @() -Yes $true -Environment $fake) 2 'nothing found'
    Assert-Equal (Invoke-SujiMain -Action 'uninstall' -Target @() -Yes $true -Environment $fake) 2 'nothing to uninstall'
    New-Item -ItemType Directory -Path (P @($fake.AppData, 'mpv')) -Force | Out-Null
    New-Item -ItemType Directory -Path (P @($fake.AppData, 'mpv.net')) -Force | Out-Null
    Assert-Equal (Invoke-SujiMain -Action 'install' -Target @() -Yes $true -Environment $fake) 2 'two folders, no -Target'
    Assert-Equal (Invoke-SujiMain -Action 'install' -Target @([System.IO.Path]::GetPathRoot($d)) -Yes $true -Environment $fake) 2 'a drive root'
    $odd = P @($d, 'odd')
    Set-TestFile (P @($odd, 'notes.txt')) 'notes'
    Assert-Equal (Invoke-SujiMain -Action 'install' -Target @($odd) -Yes $true -Environment $fake) 2 'not an mpv folder'
    $hk = P @($d, 'hk')
    Set-TestFile (P @($hk, 'hikari-installed.txt')) "hikari_version=1.0.0`n"
    $saved = $script:SujiScriptRoot
    try {
        $script:SujiScriptRoot = P @($RepoRoot, 'install')
        Assert-Equal (Invoke-SujiMain -Action 'install' -Target @($hk) -Yes $true -Environment $fake) 2 'hikari folder: refused'
        $one = P @($d, 'one')
        Assert-Equal (Invoke-SujiMain -Action 'install' -Target @(($one + ';' + $hk)) -Yes $true -Environment $fake) 2 'with -Yes, one refused: nothing done'
        Assert-True (-not (Test-Exists $one)) 'the other one not installed either'
        # Interactive: the hikari folder is left out, the other one installed.
        $script:NonInteractive = $false
        Assert-Equal (Invoke-SujiMain -Action 'install' -Target @(($one + ';' + $hk)) -Yes $false -Environment $fake) 0 'interactive'
        Assert-True (Test-Exists (P @($one, 'scripts', 'suji', 'main.lua'))) 'the other one installed'
        # A folder that fails: exit code 1.
        $bad = P @($d, 'bad')
        Set-TestFile (P @($bad, 'mpv.conf')) "# >>> suji (managed block, do not edit) >>>`n"
        Assert-Equal (Invoke-SujiMain -Action 'install' -Target @(($one + ';' + $bad)) -Yes $true -Environment $fake) 1 'one of two failed'
    }
    finally { $script:SujiScriptRoot = $saved }
    $script:NonInteractive = $false
    $script:Answers.Enqueue('0')
    Assert-Equal (Invoke-SujiMain -Action '' -Target @() -Yes $false -Environment $fake) 0 'menu: exit'
    Assert-Equal (Invoke-SujiMain -Action '' -Target @() -Yes $false -Environment $fake) 0 'menu: no more input'
}

Test-Case 'main: as administrator it does not run: exit code 2, the folder exactly as it was' {
    $d = New-TestDir 'main-admin'
    $fake = New-FakeEnv $d
    $fake.IsAdmin = $true
    $cfg = P @($d, 'cfg')
    Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`n"
    Set-TestFile (P @($cfg, 'scripts', 'osc.lua')) '-- an osc'
    $before = Get-TreeState $d
    $saved = $script:SujiScriptRoot
    try {
        $script:SujiScriptRoot = P @($RepoRoot, 'install')
        foreach ($action in @('install', 'uninstall')) {
            Assert-Equal (Invoke-SujiMain -Action $action -Target @($cfg) -Yes $true -Environment $fake) 2 ('-Yes ' + $action)
        }
        $script:NonInteractive = $false
        $script:Answers.Enqueue('1')
        Assert-Equal (Invoke-SujiMain -Action '' -Target @() -Yes $false -Environment $fake) 2 'menu'
        Assert-Equal $script:Answers.Count 1 'asked nothing'
    }
    finally { $script:SujiScriptRoot = $saved }
    Assert-Equal (Get-TreeState $d) $before 'nothing changed, no backup'
    try {
        Set-SujiLanguage 'es'
        Assert-Equal (T 'admin_refused') ('Ejec' + [char]0xFA + 'talo desde una ventana normal de PowerShell, no como administrador.') 'Spanish'
    }
    finally { Set-SujiLanguage 'en' }
    Assert-Equal (T 'admin_refused') 'Run it from a normal PowerShell window, not as administrator.' 'English'
}

Test-Case 'detection: AnimeJaNai and its portable_config, mpv.net, MPV_HOME' {
    $d = New-TestDir 'detect'
    $fake = New-FakeEnv $d
    Set-TestFile (P @($fake.LocalAppData, 'Programs', 'mpv-AnimeJaNai', 'mpvnet.exe')) 'exe'
    New-Item -ItemType Directory -Path (P @($fake.LocalAppData, 'Programs', 'mpv-AnimeJaNai', 'portable_config')) -Force | Out-Null
    Set-TestFile (P @($fake.ProgramFiles, 'mpv.net', 'mpvnet.exe')) 'exe'
    $mpvHome = P @($d, 'home')
    $fake.MpvHome = $mpvHome
    New-Item -ItemType Directory -Path $mpvHome -Force | Out-Null
    $found = @(Find-SujiPlayers -Env $fake)
    Assert-Equal $found.Count 3 'three'
    Assert-Equal $found[0].Kind 'AnimeJaNai' 'AnimeJaNai first'
    Assert-True $found[0].Portable 'portable'
    Assert-Equal $found[1].Kind 'mpv.net' 'mpv.net'
    Assert-Equal $found[1].ConfigDir (Get-SujiFullPath (P @($fake.AppData, 'mpv.net'))) 'its folder'
    Assert-Equal $found[2].ConfigDir (Get-SujiFullPath $mpvHome) 'MPV_HOME'
    # Typed: the player's own folder means its portable_config.
    $c = Resolve-SujiManualTarget -Env $fake -Path (P @($fake.LocalAppData, 'Programs', 'mpv-AnimeJaNai')) -Candidates $found
    Assert-Equal $c.Kind 'AnimeJaNai' 'typed folder'
}

# ---------------------------------------------------------------------------
# Run without a file: irm | iex, and [scriptblock]::Create for options. Each of
# these starts a real pwsh and dot-sources tests/iex-harness.ps1 from -Command,
# so the installer runs in the global scope of a fresh session, as at a prompt.
# ---------------------------------------------------------------------------

$script:Pwsh = (Get-Process -Id $PID).Path

# A release copy of the installer, its markers replaced as tools/make-release.sh
# does (whole lines, each exactly once), with the fake thumbfast's hash.
function New-ReleaseScript {
    param([string]$Dir, [string]$Zip, [string]$ZipSha256 = '')
    if (-not $ZipSha256) { $ZipSha256 = Get-SujiFileSha256 $Zip }
    $replace = [ordered]@{}
    $replace["`$script:SujiVersion = 'dev'"] = "`$script:SujiVersion = '9.9.9'"
    $replace["`$script:SujiUrl = ''"] = "`$script:SujiUrl = '" + $TestReleaseUrl + "'"
    $replace["`$script:SujiSha256 = ''"] = "`$script:SujiSha256 = '" + $ZipSha256 + "'"
    $replace["`$script:ThumbfastSha256 = '" + $OriginalThumbSha + "'"] = "`$script:ThumbfastSha256 = '" + (Get-SujiFileSha256 $FakeThumb) + "'"
    $lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllText($InstallScript) -split "`n")
    foreach ($old in $replace.Keys) {
        $at = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].TrimEnd("`r") -ceq $old) { $i } })
        if ($at.Count -ne 1) { throw ('marker found ' + $at.Count + ' times: ' + $old) }
        $lines[$at[0]] = $replace[$old]
    }
    $path = P @($Dir, 'suji.ps1')
    [System.IO.File]::WriteAllText($path, [string]::Join("`n", $lines), (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Invoke-IexHarness {
    param([string]$Script, [hashtable]$Downloads = @{}, [string]$Mode = 'iex', [string[]]$Stdin = @(),
        [string]$Action = '', [string]$Target = '', [string]$YesValue = '', [switch]$StrictLatest, [string]$TempDir = '')
    $id = [guid]::NewGuid().ToString('N')
    $report = P @($TestRoot, ('harness-' + $id + '.json'))
    $dl = P @($TestRoot, ('harness-' + $id + '-downloads.json'))
    [System.IO.File]::WriteAllText($dl, ($Downloads | ConvertTo-Json))
    $q = { param([string]$v) "'" + $v.Replace("'", "''") + "'" }
    $cmd = '. ' + (& $q $IexHarness) + ' -Script ' + (& $q $Script) + ' -Report ' + (& $q $report) + ' -Downloads ' + (& $q $dl) + ' -Mode ' + $Mode
    if ($Action) { $cmd += ' -Action ' + (& $q $Action) }
    if ($Target) { $cmd += ' -Target ' + (& $q $Target) }
    if ($YesValue) { $cmd += ' -YesValue ' + $YesValue }
    if ($StrictLatest) { $cmd += ' -StrictLatest' }
    $ErrorActionPreference = 'Continue'
    $saved = @($env:TMPDIR, $env:TEMP, $env:TMP)
    if ($TempDir) { $env:TMPDIR = $TempDir; $env:TEMP = $TempDir; $env:TMP = $TempDir }
    try {
        $stdinLines = @($Stdin) + @('')
        $out = @($stdinLines | & $script:Pwsh -NoProfile -Command $cmd 2>&1 | ForEach-Object { [string]$_ })
    }
    finally { $env:TMPDIR = $saved[0]; $env:TEMP = $saved[1]; $env:TMP = $saved[2] }
    $r = $null
    if (Test-Path -LiteralPath $report) { $r = Get-Content -Raw -LiteralPath $report | ConvertFrom-Json }
    return [pscustomobject]@{ Report = $r; Text = [string]::Join("`n", $out) }
}

function Assert-SessionClean {
    param($Run, [int]$ExitCode)
    $r = $Run.Report
    Assert-True ($null -ne $r) ('the session survived (no exit); output: ' + $Run.Text)
    Assert-Equal ([int]$r.ExitCode) $ExitCode ('$LASTEXITCODE; output: ' + $Run.Text)
    Assert-Equal @($r.NewVariables).Count 0 ('variables left: ' + [string]::Join(',', @($r.NewVariables)))
    Assert-Equal @($r.NewFunctions).Count 0 ('functions left: ' + [string]::Join(',', @($r.NewFunctions)))
    Assert-Equal @($r.NewModules).Count 0 ('modules left: ' + [string]::Join(',', @($r.NewModules)))
    Assert-Equal @($r.Output).Count 0 ('pipeline output: ' + [string]::Join(',', @($r.Output)))
    Assert-True $r.TlsSame 'SecurityProtocol put back'
}

Test-Case 'iex at a prompt, no options: no exit, nothing left in the session' {
    $run = Invoke-IexHarness -Script $InstallScript -Stdin @('0')
    Assert-SessionClean $run 0
    Assert-Equal $run.Report.Eap 'Continue' 'ErrorActionPreference kept'
    Assert-Equal $run.Report.Strict 'off' 'StrictMode stays off'
    Assert-True ($run.Text.Contains('Cancelled.')) ('menu answered; output: ' + $run.Text)
}

Test-Case 'iex in a session with StrictMode Latest and ErrorActionPreference Stop: runs, both kept' {
    $run = Invoke-IexHarness -Script $InstallScript -Stdin @('0') -StrictLatest
    Assert-SessionClean $run 0
    Assert-Equal $run.Report.Eap 'Stop' 'ErrorActionPreference kept'
    Assert-Equal $run.Report.Strict 'on' 'StrictMode Latest kept'
}

Test-Case 'iex of the repository version: no release, nothing downloaded or installed' {
    $d = New-TestDir 'iex-dev'
    $tmp = New-TestDir 'iex-dev-tmp'
    $cfg = P @($d, 'mpv')
    # Install, other folder, the folder.
    $run = Invoke-IexHarness -Script $InstallScript -Stdin @('1', 'o', $cfg) -TempDir $tmp
    Assert-SessionClean $run 1
    Assert-True ($run.Text.Contains('has no suji release')) ('message; output: ' + $run.Text)
    Assert-Equal @($run.Report.Downloads).Count 0 'no download'
    Assert-Equal @(Get-ChildItem -LiteralPath $tmp -Force).Count 0 'temp folder removed'
    Assert-True (-not (Test-Exists $cfg)) 'nothing installed'
}

Test-Case 'release through iex and through [scriptblock]::Create: install, update, uninstall' {
    $d = New-TestDir 'iex-release'
    $tmp = New-TestDir 'iex-release-tmp'
    $zip = New-TestReleaseZip $d
    $script = New-ReleaseScript -Dir $d -Zip $zip
    $downloads = @{ $TestReleaseUrl = $zip; $script:ThumbfastUrl = $FakeThumb }
    $cfg = P @($d, 'mpv')
    Set-TestFile (P @($cfg, 'mpv.conf')) "volume=50`r`n"
    Set-TestFile (P @($cfg, 'scripts', 'osc.lua')) '-- an osc'
    # Install, other folder, the folder, set the osc aside (default).
    $run = Invoke-IexHarness -Script $script -Downloads $downloads -Stdin @('1', 'o', $cfg, '') -TempDir $tmp
    Assert-SessionClean $run 0
    Assert-True $run.Report.TlsTouched 'the downloader changed SecurityProtocol, so putting it back was tested'
    Assert-Equal ([string]::Join(' ', @($run.Report.Downloads))) ($TestReleaseUrl + ' ' + $script:ThumbfastUrl) 'downloads'
    Assert-True ($run.Text.TrimEnd().EndsWith('Restart the player to see the changes.') -and -not $run.Text.Contains('Done: ')) ('last line, one folder; output: ' + $run.Text)
    Assert-Equal (Get-TestText (P @($cfg, 'scripts', 'suji', 'main.lua'))) (Get-TestText (P @($Source.SujiDir, 'main.lua'))) 'installed'
    Assert-True (Test-Exists (P @($cfg, 'scripts-apartados-suji', 'osc.lua'))) 'osc set aside'
    Assert-Equal (Read-SujiRecord $cfg).Values['suji_version'] '9.9.9' 'record'
    Assert-Equal @(Get-ChildItem -LiteralPath $tmp -Force).Count 0 'temp folder removed'

    $run = Invoke-IexHarness -Script $script -Downloads $downloads -Mode create -Action 'install' -Target $cfg -YesValue 'true' -TempDir $tmp
    Assert-SessionClean $run 0
    Assert-Equal ([string]::Join(' ', @($run.Report.Downloads))) $TestReleaseUrl 'update: only the zip'

    $run = Invoke-IexHarness -Script $script -Downloads $downloads -Mode create -Action 'uninstall' -Target $cfg -YesValue 'true' -TempDir $tmp
    Assert-SessionClean $run 0
    Assert-Equal @($run.Report.Downloads).Count 0 'uninstall downloads nothing'
    Assert-Equal (Get-TestText (P @($cfg, 'mpv.conf'))) "volume=50`r`n" 'mpv.conf as before'
    Assert-True (Test-Exists (P @($cfg, 'scripts', 'osc.lua'))) 'osc back'
    Assert-True (-not (Test-Exists (P @($cfg, 'scripts', 'suji')))) 'suji gone'
    Assert-Equal @(Get-ChildItem -LiteralPath $d -Directory -Filter 'mpv-respaldo-suji-*').Count 3 'three backups kept'
}

Test-Case 'release with a wrong hash through [scriptblock]::Create: nothing installed, temp removed' {
    $d = New-TestDir 'iex-badhash'
    $tmp = New-TestDir 'iex-badhash-tmp'
    $zip = New-TestReleaseZip $d
    $script = New-ReleaseScript -Dir $d -Zip $zip -ZipSha256 ('b' * 64)
    $cfg = P @($d, 'mpv')
    $run = Invoke-IexHarness -Script $script -Downloads @{ $TestReleaseUrl = $zip; $script:ThumbfastUrl = $FakeThumb } -Mode create -Action 'install' -Target $cfg -YesValue 'true' -TempDir $tmp
    Assert-SessionClean $run 1
    Assert-True ($run.Text.Contains('does not match its expected SHA256')) ('message; output: ' + $run.Text)
    Assert-Equal ([string]::Join(' ', @($run.Report.Downloads))) $TestReleaseUrl 'only the zip was fetched'
    Assert-True (-not (Test-Exists $cfg)) 'nothing installed'
    Assert-Equal @(Get-ChildItem -LiteralPath $tmp -Force).Count 0 'temp folder removed'
}

Test-Case 'Spanish through iex' {
    $saved = $env:SUJI_LANG
    try {
        $env:SUJI_LANG = 'es'
        $run = Invoke-IexHarness -Script $InstallScript -Stdin @('0')
    }
    finally { $env:SUJI_LANG = $saved }
    Assert-SessionClean $run 0
    Assert-True ($run.Text.Contains('1) Instalar o actualizar') -and $run.Text.Contains('Cancelado.')) ('Spanish; output: ' + $run.Text)
}

# ---------------------------------------------------------------------------

Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
