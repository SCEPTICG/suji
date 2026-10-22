<#
.SYNOPSIS
    suji installer for Windows: mpv, mpv.net and AnimeJaNai.

.DESCRIPTION
    Installs, updates or removes suji (https://github.com/SCEPTICG/suji), together
    with thumbfast, in one or more mpv config folders.

    From a published release (the release's suji.ps1 downloads that release's
    suji.zip and checks its SHA256 before using it):
        irm https://github.com/SCEPTICG/suji/releases/latest/download/suji.ps1 | iex
    With options (iex cannot pass them):
        & ([scriptblock]::Create((irm https://github.com/SCEPTICG/suji/releases/latest/download/suji.ps1))) -Action uninstall
    From a copy of the repository:
        powershell -ExecutionPolicy Bypass -File install\suji.ps1

    No administrator rights, no registry, no PATH changes. Before touching a
    folder it copies the files it may change to a sibling folder named
    <config>-respaldo-suji-<date>, and keeps the three newest of those.

    A folder where hikari is installed is left alone: hikari installs suji
    itself (its installer's -Interface suji).

    Works with Windows PowerShell 5.1 and PowerShell 7. This file is pure ASCII on
    purpose: Windows PowerShell 5.1 reads BOM-less scripts as ANSI, so the Spanish
    messages are written with \uXXXX escapes and decoded at start-up.

    Everything runs inside one script block, invoked in a scope of its own (a
    throw-away dynamic module), so that run through iex it leaves nothing behind
    in the session: no variables, functions, StrictMode or ErrorActionPreference
    changes. It only calls exit when it runs from a file (-File, or .\suji.ps1);
    through iex it returns and leaves its exit code in $LASTEXITCODE.

.PARAMETER SujiAction
    Use it as -Action (alias). install or uninstall. Without it a menu is shown.

.PARAMETER SujiTarget
    Use it as -Target (alias). mpv config folder(s) to work on (the folder that
    holds mpv.conf, e.g. ...\mpv-AnimeJaNai\portable_config or %APPDATA%\mpv).
    Several folders go separated by ';'. Without it the detected players are
    listed.

.PARAMETER SujiYes
    Use it as -Yes (alias). Do not ask: take the default answer to every
    question. Needs -Action, and -Target when more than one folder is found.

.PARAMETER SujiNoMenu
    Use it as -NoMenu (alias). Accepted for the same options as the hikari
    installer: this installer always asks with numbers and typed answers.

.NOTES
    Exit codes: 0 done (or cancelled by the user), 1 at least one folder failed,
    2 wrong usage or nothing to work on.
#>
# The parameters are named Suji* on purpose: run through iex, a param block
# creates its variables in the caller's session, so they get names nobody else
# uses and are removed again at the end (see the finally below). The aliases
# keep the public names: -Action, -Target, -Yes, -NoMenu.
[CmdletBinding()]
param(
    [Alias('Action')]
    [ValidateSet('', 'install', 'uninstall')]
    [string]$SujiAction = '',
    [Alias('Target')]
    [string[]]$SujiTarget = @(),
    [Alias('Yes')]
    [switch]$SujiYes,
    [Alias('NoMenu')]
    [switch]$SujiNoMenu
)

try {
# A dynamic module gives the script block its own script: scope, so the
# $script: variables below never land in the caller's session. New-Module with
# an empty body exports nothing and is not added to the session's module list.
# The parameters are passed by name (not with @args, which turns -Yes:$false
# into -Yes).
& (New-Module -ScriptBlock { }) {
param(
    [string]$Action = '',
    [string[]]$Target = @(),
    [switch]$Yes
)

# All three are local to this script block: the caller's session keeps its own.
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Release markers. tools/make-release.sh replaces these three lines, matched
# whole and exactly once each, with the version, the URL of that release's
# suji.zip and its SHA256. Keep them exactly as they are. In the repository they
# stay as they are: the suji files then come from the repository copy the script
# sits in, and run on its own (irm | iex) it explains that there is no release.
$script:SujiVersion = 'dev'
$script:SujiUrl = ''
$script:SujiSha256 = ''

# thumbfast: fixed commit, verified by SHA256 (the same one hikari installs).
$script:ThumbfastUrl = 'https://raw.githubusercontent.com/po5/thumbfast/0f711de3138c9bd6718209d819ac54022c23ded2/thumbfast.lua'
$script:ThumbfastSha256 = 'a3d08e71eae8b892f6cd39f9593ea219768e709312d176bca883841b156448bf'

# Downloads are only allowed over HTTPS from these hosts. Redirects (GitHub
# serves release files from release-assets.githubusercontent.com) may only go
# to HTTPS on these hosts or on a host right under githubusercontent.com, at
# most $script:MaxRedirects times. A larger download is cut and refused.
$script:AllowedHosts = @('github.com', 'raw.githubusercontent.com')
$script:RedirectHostPattern = '\A[a-z0-9-]+\.githubusercontent\.com\z'
$script:MaxRedirects = 5
$script:MaxDownloadBytes = 50MB

$script:BlockBegin = '# >>> suji (managed block, do not edit) >>>'
$script:BlockEnd = '# <<< suji (managed block, do not edit) <<<'
$script:MpvConfLines = @('osc=no')

# thumbfast.conf as suji writes it when there is none (the same as install/suji.sh).
$script:ThumbfastConfLines = @(
    '# suji settings for thumbfast (https://github.com/po5/thumbfast), which makes the',
    '# timeline thumbnails suji shows. thumbfast itself is not part of suji: the',
    '# installer downloads it. Anything not set here keeps thumbfast''s default.',
    '',
    '# Thumbnails on network streams too. thumbfast opens a second, hidden mpv with',
    '# its own connection to the stream, so it uses some extra bandwidth.',
    'network=yes',
    '',
    '# Decode thumbnails on the GPU instead of the CPU.',
    'hwdec=yes',
    '',
    '# Only start the thumbnailer when the timeline is first hovered.',
    'spawn_first=no',
    '',
    '# Maximum thumbnail size in pixels (scaled down to fit, scaled up with hidpi).',
    'max_height=200',
    'max_width=200'
)
# Above the mpv_path line the installer adds.
$script:MpvPathComment = '# Added by the suji installer: mpv started from another app may not find mpv in its PATH.'

$script:RecordName = 'suji-installed.txt'
# Interfaces set aside go here: scripts\ ones straight in, the others in their
# sub-folder (script-opts\, fonts\).
$script:AsideDir = 'scripts-apartados-suji'
$script:BackupKeep = 3
# suji's own settings and the size it remembers: only removed when the user says so.
$script:UserFiles = @('script-opts/suji.conf', 'suji-size')
# What a backup copies when it is there: what the installer may change.
$script:BackupItems = @('mpv.conf', 'suji-installed.txt', 'scripts/suji', 'scripts/thumbfast.lua',
    'script-opts/thumbfast.conf', 'script-opts/suji.conf', 'suji-size', 'scripts-apartados-suji')

# Signs that a folder belongs to mpv (any of them is enough).
$script:MpvConfigFiles = @('mpv.conf', 'input.conf', 'suji-installed.txt')
$script:MpvConfigDirs = @('scripts', 'script-opts')
$script:PlayerExes = @('mpvnet.exe', 'mpv.exe')

# On-screen controllers that clash with suji, the ones hikari sets aside plus
# uosc (scripts/uosc or scripts/uosc.lua). Matched against names in scripts/
# (wildcards, case-insensitive); each one's script-opts/<name>.conf goes with
# it, and the fonts that clearly belong to one of them.
$script:ConflictPatterns = @(
    'osc.lua', 'osc_*.lua', 'osc-*.lua', 'oscc.lua', 'oscc_*.lua', 'oscc-*.lua',
    'modernx*.lua', 'modernz*.lua', 'mordenx*.lua', 'mpv-osc-*.lua',
    'mfpbar.lua', 'mpv_thumbnail_script_client_osc*.lua', 'uosc.lua'
)
$script:ConflictDirs = @('uosc')
$script:ConflictFontPatterns = @('modernx*', 'modernz*', 'mordenx*')

# Folder of this file; empty when run through iex or [scriptblock]::Create.
$script:SujiScriptRoot = $PSScriptRoot
$script:SujiQuiet = $false
$script:NonInteractive = $false
# Set when running as administrator: deleting or moving then refuses paths that
# go through a link (junction or symbolic link) inside the config folder.
$script:SujiElevated = $false

# Download function, replaceable in tests: param($Url, $OutFile).
$script:SujiDownloader = {
    param([string]$Url, [string]$OutFile)
    Invoke-SujiHttpDownload -Url $Url -OutFile $OutFile
}

# ---------------------------------------------------------------------------
# Messages (English and Spanish). Spanish strings use \uXXXX escapes.
# ---------------------------------------------------------------------------

$script:SujiStringsEn = @{
    title                = 'suji installer {0}'
    menu                 = "1) Install or update`n2) Uninstall`n0) Exit"
    menu_prompt          = 'Choose an option'
    invalid              = 'Invalid option.'
    found_header         = 'Players and config folders found:'
    found_header_uninst  = 'Folders with suji:'
    cand_exe             = '     Player: {0}'
    cand_config          = '     Config: {0}'
    kind_folder          = 'config folder'
    tag_installed        = '[suji {0} installed]'
    tag_manual           = '[suji files present, no installer record]'
    tag_hikari           = '[hikari: use its installer]'
    tag_readonly         = '[no write permission]'
    tag_new              = '[will be created]'
    opt_other            = 'O) Other folder'
    opt_quit             = '0) Exit'
    select_prompt        = 'Choose one or more, separated by commas (e.g. 1,3)'
    ask_folder           = 'Full path of the mpv config folder (where mpv.conf is or should go)'
    folder_missing       = 'The folder {0} does not exist and neither does its parent.'
    readonly_warn        = 'Cannot write to {0}.'
    readonly_offer       = 'Use {0} instead?'
    readonly_portable    = 'Careful: while {0} exists, this player only reads that folder and will not see suji in {1}.'
    readonly_skip        = 'Skipping {0}.'
    none_found           = 'No mpv player was found (mpv, mpv.net or AnimeJaNai). Install one first (https://mpv.io/installation/), or type its config folder with O.'
    yes_no_default_yes   = ' [Y/n] '
    yes_no_default_no    = ' [y/N] '
    backup_done          = 'Backup: {0}'
    backup_failed        = 'Could not back up {0}: {1}. Nothing was changed in that folder.'
    backup_prune_failed  = 'Could not delete the old backup {0}: {1}'
    conflicts_found      = 'These scripts replace the mpv controls and clash with suji:'
    conflicts_confirm    = 'Move them to {0}? Nothing is deleted, and they come back when you uninstall.'
    conflicts_kept       = 'Left in place: suji and that interface will both draw controls.'
    moved                = 'Moved {0} -> {1}'
    hash_bad             = 'The download of {0} does not match its expected SHA256 (expected {1}, got {2}). Nothing was installed from it.'
    url_bad              = 'Refusing to download {0}: only HTTPS from GitHub is allowed.'
    release_unpublished  = 'This copy of the installer has no suji release to install. Use the one of a release (irm https://github.com/SCEPTICG/suji/releases/latest/download/suji.ps1 | iex), or run install\suji.ps1 from a copy of the repository.'
    source_missing       = 'suji files not found in {0}.'
    download_failed      = 'Could not download {0}: {1}'
    download_redirects   = 'too many redirects'
    download_too_big     = 'larger than {0} MB'
    download_status      = 'the server answered {0}'
    installing_to        = 'Installing suji into {0}'
    uninstalling_from    = 'Removing suji from {0}'
    thumbfast_uptodate   = 'thumbfast is already installed, unchanged: not copied again.'
    mpvpath_set          = 'thumbfast.conf: mpv_path={0}'
    malformed_block      = '{0} has an incomplete or repeated suji block (a start or end marker is missing or twice). Fix it by hand and run the installer again. Nothing was changed in that folder.'
    hikari_present       = '{0} has hikari: nothing is changed there. hikari installs suji itself: use the hikari installer with -Interface suji.'
    install_ok           = 'suji {0} installed in {1}.'
    uninstall_ok         = 'suji removed from {0}.'
    target_failed        = '{0}: {1}'
    restore_hint         = 'Your previous config is in {0}.'
    summary              = 'Done: {0} of {1} folders.'
    restart              = 'Restart the player to see the changes.'
    ask_remove_thumbfast = 'Remove thumbfast too?'
    ask_delete_user      = 'Delete your suji settings and saved size (suji.conf, suji-size)?'
    ask_restore          = 'Move back the interfaces suji set aside ({0})?'
    restore_skipped      = '{0} not moved back: {1} already exists.'
    nothing_to_uninstall = 'suji does not seem to be installed in any detected folder.'
    usage_yes_action     = '-Yes needs -Action install or -Action uninstall.'
    usage_many           = 'Several folders found; with -Yes, choose with -Target:'
    usage_none           = 'Nothing to work on.'
    error_generic        = 'Error: {0}'
    outside_target       = 'Refusing to delete or move {0}: it is outside {1}.'
    old_ps               = 'Windows PowerShell 5.1 or newer is needed.'
    cancelled            = 'Cancelled.'
    link_skipped         = 'Not copied to the backup: {0} is a link (junction or symbolic link), or inside one.'
    path_bad             = '{0} is not a valid folder path.'
    target_root          = 'Refusing {0}: a drive root or your user folder is not an mpv config folder.'
    not_mpv_folder       = '{0} does not look like an mpv config folder: no mpv.conf, input.conf, scripts or script-opts in it, and no mpv next to it.'
    not_mpv_confirm      = 'Use it anyway?'
    not_mpv_yes          = 'With -Yes such a folder is refused: run without -Yes to confirm it.'
    exe_folder           = '{0} is the folder of {1}, not its config folder.'
    exe_portable         = 'Using {0}, the portable_config next to it.'
    exe_offer            = 'Use {0}, the config folder that player reads?'
    mpv_home_note        = 'MPV_HOME is set: mpv reads its config from {0}, not from {1}.'
    admin_warn           = 'The installer is running as administrator. It does not need it, and what it creates may end up belonging to the administrator.'
    admin_confirm        = 'Continue as administrator?'
    admin_refused        = 'As administrator with -Yes, only folders under Program Files or ProgramData are allowed: {0}. Run it without administrator rights.'
    link_in_path         = 'Refusing to delete or move {0}: {1} is a link (junction or symbolic link) and the installer is running as administrator.'
    link_write           = 'Refusing to write {0}: {1} is a link (junction or symbolic link), and the installer never writes through one. Nothing was changed in that folder.'
    record_bad           = 'Ignored an invalid entry in suji-installed.txt: {0}'
}

$script:SujiStringsEs = @{
    title                = 'Instalador de suji {0}'
    menu                 = '1) Instalar o actualizar\n2) Desinstalar\n0) Salir'
    menu_prompt          = 'Elige una opci\u00f3n'
    invalid              = 'Opci\u00f3n no v\u00e1lida.'
    found_header         = 'Reproductores y carpetas de configuraci\u00f3n encontrados:'
    found_header_uninst  = 'Carpetas con suji:'
    cand_exe             = '     Reproductor: {0}'
    cand_config          = '     Configuraci\u00f3n: {0}'
    kind_folder          = 'carpeta de configuraci\u00f3n'
    tag_installed        = '[suji {0} instalado]'
    tag_manual           = '[hay ficheros de suji, sin registro del instalador]'
    tag_hikari           = '[hikari: usa su instalador]'
    tag_readonly         = '[sin permiso de escritura]'
    tag_new              = '[se crear\u00e1]'
    opt_other            = 'O) Otra carpeta'
    opt_quit             = '0) Salir'
    select_prompt        = 'Elige uno o varios separados por comas (p. ej. 1,3)'
    ask_folder           = 'Ruta completa de la carpeta de configuraci\u00f3n de mpv (donde est\u00e1 o ir\u00e1 mpv.conf)'
    folder_missing       = 'No existe la carpeta {0} ni la que la contiene.'
    readonly_warn        = 'No se puede escribir en {0}.'
    readonly_offer       = '\u00bfUsar {0} en su lugar?'
    readonly_portable    = 'Ojo: mientras exista {0}, este reproductor solo lee esa carpeta y no ver\u00e1 suji en {1}.'
    readonly_skip        = 'Se omite {0}.'
    none_found           = 'No se ha encontrado ning\u00fan reproductor de mpv (mpv, mpv.net o AnimeJaNai). Instala uno antes (https://mpv.io/installation/) o escribe su carpeta de configuraci\u00f3n con O.'
    yes_no_default_yes   = ' [S/n] '
    yes_no_default_no    = ' [s/N] '
    backup_done          = 'Copia de seguridad: {0}'
    backup_failed        = 'No se ha podido hacer la copia de seguridad de {0}: {1}. No se ha cambiado nada en esa carpeta.'
    backup_prune_failed  = 'No se ha podido borrar la copia de seguridad antigua {0}: {1}'
    conflicts_found      = 'Estos scripts sustituyen los controles de mpv y chocan con suji:'
    conflicts_confirm    = '\u00bfMoverlos a {0}? No se borra nada y vuelven a su sitio al desinstalar.'
    conflicts_kept       = 'Se quedan donde est\u00e1n: suji y esa interfaz dibujar\u00e1n controles a la vez.'
    moved                = 'Movido {0} -> {1}'
    hash_bad             = 'La descarga de {0} no coincide con su SHA256 esperado (esperado {1}, obtenido {2}). No se ha instalado nada de ella.'
    url_bad              = 'No se descarga {0}: solo se admite HTTPS desde GitHub.'
    release_unpublished  = 'Esta copia del instalador no trae ninguna versi\u00f3n de suji que instalar. Usa la de una versi\u00f3n publicada (irm https://github.com/SCEPTICG/suji/releases/latest/download/suji.ps1 | iex) o ejecuta install\\suji.ps1 desde una copia del repositorio.'
    source_missing       = 'No se encuentran los ficheros de suji en {0}.'
    download_failed      = 'No se ha podido descargar {0}: {1}'
    download_redirects   = 'demasiadas redirecciones'
    download_too_big     = 'ocupa m\u00e1s de {0} MB'
    download_status      = 'el servidor ha respondido {0}'
    installing_to        = 'Instalando suji en {0}'
    uninstalling_from    = 'Quitando suji de {0}'
    thumbfast_uptodate   = 'thumbfast ya est\u00e1 instalado y sin cambios: no se vuelve a copiar.'
    mpvpath_set          = 'thumbfast.conf: mpv_path={0}'
    malformed_block      = '{0} tiene un bloque de suji incompleto o repetido (falta una marca de inicio o de fin, o est\u00e1 dos veces). Arr\u00e9glalo a mano y vuelve a ejecutar el instalador. No se ha cambiado nada en esa carpeta.'
    hikari_present       = '{0} tiene hikari: no se cambia nada ah\u00ed. hikari ya instala suji: usa el instalador de hikari con -Interface suji.'
    install_ok           = 'suji {0} instalado en {1}.'
    uninstall_ok         = 'suji quitado de {0}.'
    target_failed        = '{0}: {1}'
    restore_hint         = 'Tu configuraci\u00f3n anterior est\u00e1 en {0}.'
    summary              = 'Hecho: {0} de {1} carpetas.'
    restart              = 'Reinicia el reproductor para ver los cambios.'
    ask_remove_thumbfast = '\u00bfQuitar tambi\u00e9n thumbfast?'
    ask_delete_user      = '\u00bfBorrar tus ajustes de suji y el tama\u00f1o guardado (suji.conf, suji-size)?'
    ask_restore          = '\u00bfDevolver a su sitio las interfaces que suji apart\u00f3 ({0})?'
    restore_skipped      = '{0} no se devuelve: ya existe {1}.'
    nothing_to_uninstall = 'No parece que suji est\u00e9 instalado en ninguna de las carpetas encontradas.'
    usage_yes_action     = '-Yes necesita -Action install o -Action uninstall.'
    usage_many           = 'Hay varias carpetas; con -Yes, elige con -Target:'
    usage_none           = 'No hay nada sobre lo que trabajar.'
    error_generic        = 'Error: {0}'
    outside_target       = 'No se borra ni se mueve {0}: est\u00e1 fuera de {1}.'
    old_ps               = 'Hace falta Windows PowerShell 5.1 o posterior.'
    cancelled            = 'Cancelado.'
    link_skipped         = 'No se copia a la copia de seguridad: {0} es un enlace (uni\u00f3n o enlace simb\u00f3lico) o est\u00e1 dentro de uno.'
    path_bad             = '{0} no es una ruta de carpeta v\u00e1lida.'
    target_root          = 'No se usa {0}: la ra\u00edz de una unidad o tu carpeta de usuario no son una carpeta de configuraci\u00f3n de mpv.'
    not_mpv_folder       = '{0} no parece una carpeta de configuraci\u00f3n de mpv: no tiene mpv.conf, input.conf, scripts ni script-opts, ni hay un mpv al lado.'
    not_mpv_confirm      = '\u00bfUsarla de todos modos?'
    not_mpv_yes          = 'Con -Yes se rechaza una carpeta as\u00ed: ejecuta sin -Yes para confirmarla.'
    exe_folder           = '{0} es la carpeta de {1}, no su carpeta de configuraci\u00f3n.'
    exe_portable         = 'Se usa {0}, la portable_config que tiene al lado.'
    exe_offer            = '\u00bfUsar {0}, la carpeta de configuraci\u00f3n que lee ese reproductor?'
    mpv_home_note        = 'MPV_HOME est\u00e1 definida: mpv lee su configuraci\u00f3n de {0}, no de {1}.'
    admin_warn           = 'El instalador se est\u00e1 ejecutando como administrador. No le hace falta, y lo que cree puede acabar perteneciendo al administrador.'
    admin_confirm        = '\u00bfSeguir como administrador?'
    admin_refused        = 'Como administrador y con -Yes solo se admiten carpetas dentro de Program Files o ProgramData: {0}. Ejec\u00fatalo sin permisos de administrador.'
    link_in_path         = 'No se borra ni se mueve {0}: {1} es un enlace (uni\u00f3n o enlace simb\u00f3lico) y el instalador se est\u00e1 ejecutando como administrador.'
    link_write           = 'No se escribe {0}: {1} es un enlace (uni\u00f3n o enlace simb\u00f3lico) y el instalador nunca escribe a trav\u00e9s de uno. No se ha cambiado nada en esa carpeta.'
    record_bad           = 'Se ignora una entrada no v\u00e1lida de suji-installed.txt: {0}'
}

# The Windows display language; the regional format only when it is unknown.
# SUJI_LANG (es or en) wins over both.
function Get-SujiLanguage {
    if ($env:SUJI_LANG -eq 'es' -or $env:SUJI_LANG -eq 'en') { return $env:SUJI_LANG }
    $culture = $null
    try { $culture = Get-UICulture } catch { }
    if ($null -eq $culture -or -not $culture.Name) { try { $culture = Get-Culture } catch { } }
    if ($null -ne $culture -and $culture.TwoLetterISOLanguageName -eq 'es') { return 'es' }
    return 'en'
}

function Set-SujiLanguage {
    param([string]$Language)
    $script:SujiStrings = @{}
    if ($Language -eq 'es') {
        foreach ($key in $script:SujiStringsEs.Keys) {
            $script:SujiStrings[$key] = [regex]::Unescape($script:SujiStringsEs[$key])
        }
    }
    else {
        # English strings hold real backslashes (install\suji.ps1) that
        # [regex]::Unescape would reject, and no \uXXXX.
        foreach ($key in $script:SujiStringsEn.Keys) { $script:SujiStrings[$key] = $script:SujiStringsEn[$key] }
    }
}

# Text arguments go in without control characters (C0, DEL and C1: \p{Cc}):
# a folder (from MPV_HOME, typed or found) or what an error says must not send
# escape sequences to the console.
function T {
    param([string]$Key, [object[]]$FormatArgs = @())
    $text = $script:SujiStrings[$Key]
    if ($null -eq $text) { $text = $Key }
    if (@($FormatArgs).Count -gt 0) {
        $shown = [object[]]$FormatArgs.Clone()
        for ($i = 0; $i -lt $shown.Length; $i++) {
            if ($shown[$i] -is [string]) { $shown[$i] = [regex]::Replace($shown[$i], '\p{Cc}', '') }
        }
        return ($text -f $shown)
    }
    return $text
}

Set-SujiLanguage (Get-SujiLanguage)

# ---------------------------------------------------------------------------
# Output and input
# ---------------------------------------------------------------------------

function Write-SujiInfo {
    param([string]$Message)
    if (-not $script:SujiQuiet) { Write-Host $Message }
}

function Write-SujiOk {
    param([string]$Message)
    if (-not $script:SujiQuiet) { Write-Host $Message -ForegroundColor Green }
}

function Write-SujiWarn {
    param([string]$Message)
    if (-not $script:SujiQuiet) { Write-Host $Message -ForegroundColor Yellow }
}

function Write-SujiError {
    param([string]$Message)
    if (-not $script:SujiQuiet) { Write-Host $Message -ForegroundColor Red }
}

# Replaceable in tests. $null when the input has ended.
$script:SujiReadLine = { param([string]$Prompt) Read-Host -Prompt $Prompt }

function Read-SujiLine {
    param([string]$Prompt)
    return (& $script:SujiReadLine $Prompt)
}

# A yes/no question; with -Yes (or no more input) the default answer.
function Confirm-Suji {
    param([string]$Question, [bool]$Default)
    if ($script:NonInteractive) { return $Default }
    $suffix = T 'yes_no_default_no'
    if ($Default) { $suffix = T 'yes_no_default_yes' }
    while ($true) {
        $answer = Read-SujiLine ($Question + $suffix)
        if ($null -eq $answer) { return $Default }
        $answer = $answer.Trim().ToLowerInvariant()
        if ($answer -eq '') { return $Default }
        if (@('s', 'si', 'y', 'yes') -contains $answer -or $answer -eq ('s' + [char]0x00ED)) { return $true }
        if (@('n', 'no') -contains $answer) { return $false }
        Write-SujiWarn (T 'invalid')
    }
}

# ---------------------------------------------------------------------------
# Paths and files
# ---------------------------------------------------------------------------

function Join-SujiPath {
    param([string]$Base, [string[]]$Child)
    $result = $Base
    foreach ($part in $Child) { $result = [System.IO.Path]::Combine($result, $part) }
    return $result
}

# A '/'-separated path relative to $Root, as the record and the lists name them.
function Join-SujiRel {
    param([string]$Root, [string]$Rel)
    return (Join-SujiPath $Root ($Rel -split '/'))
}

function Get-SujiFullPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $trim = $full.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    if ($trim -eq '' -or $trim -match '^[A-Za-z]:$') { return $full }
    return $trim
}

function Test-SujiSamePath {
    param([string]$A, [string]$B)
    return [string]::Equals((Get-SujiFullPath $A), (Get-SujiFullPath $B), [System.StringComparison]::OrdinalIgnoreCase)
}

# True when $Path is strictly inside $Root (never $Root itself).
function Test-SujiInside {
    param([string]$Path, [string]$Root)
    if ([string]::IsNullOrEmpty($Path) -or [string]::IsNullOrEmpty($Root)) { return $false }
    $full = Get-SujiFullPath $Path
    $rootFull = (Get-SujiFullPath $Root).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if ($full.Length -le $prefix.Length) { return $false }
    return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-SujiInside {
    param([string]$Path, [string]$Root)
    if (-not (Test-SujiInside -Path $Path -Root $Root)) { throw (T 'outside_target' @($Path, $Root)) }
}

# True for junctions, symbolic links and other reparse points.
function Test-SujiLink {
    param($Item)
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

# The first folder between $Root (excluded) and $Path (excluded) that is a
# link, or $null.
function Find-SujiLinkInPath {
    param([string]$Path, [string]$Root)
    $rootFull = Get-SujiFullPath $Root
    $p = Split-Path -Path (Get-SujiFullPath $Path) -Parent
    while ($p -and (Test-SujiInside -Path $p -Root $rootFull)) {
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and (Test-SujiLink $item)) { return $p }
        $p = Split-Path -Path $p -Parent
    }
    return $null
}

# Running as administrator, a link inside the config folder (scripts\ ->
# C:\Windows, say) would let a delete or move land outside it with full rights.
# So, only when elevated, every folder between the two must be a real folder.
function Assert-SujiNoLink {
    param([string]$Path, [string]$Root)
    if (-not $script:SujiElevated) { return }
    $link = Find-SujiLinkInPath -Path $Path -Root $Root
    if ($link) { throw (T 'link_in_path' @($Path, $link)) }
}

# Before writing to $Path, or making a folder there, inside $Root: neither
# $Path itself nor a folder between it and $Root may be a link (junction or
# symbolic link), so nothing is ever written outside the config folder.
function Assert-SujiWriteTarget {
    param([string]$Path, [string]$Root)
    $link = Find-SujiLinkInPath -Path $Path -Root $Root
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and (Test-SujiLink $item)) { $link = $Path }
    if ($link) { throw (T 'link_write' @($Path, $link)) }
}

# Deletes a file or folder inside $Root. Links (junctions, symlinks) are removed
# as links: their target is never followed.
function Remove-SujiItem {
    param([string]$Path, [string]$Root)
    Assert-SujiInside -Path $Path -Root $Root
    Assert-SujiNoLink -Path $Path -Root $Root
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }
    $isLink = Test-SujiLink $item
    if ($item.PSIsContainer) {
        if ($isLink) {
            [System.IO.Directory]::Delete($item.FullName, $false)
            return
        }
        foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force)) {
            Remove-SujiItem -Path $child.FullName -Root $Root
        }
        $item.Attributes = [System.IO.FileAttributes]::Directory
        [System.IO.Directory]::Delete($item.FullName, $false)
    }
    else {
        if (-not $isLink) { $item.Attributes = [System.IO.FileAttributes]::Normal }
        [System.IO.File]::Delete($item.FullName)
    }
}

# Copies a folder tree. Links inside it are skipped (with a warning), never
# followed: a junction could point anywhere, even back up the tree.
function Copy-SujiTree {
    param([string]$From, [string]$To)
    New-SujiDirectory $To
    foreach ($child in @(Get-ChildItem -LiteralPath $From -Force)) {
        if (Test-SujiLink $child) { Write-SujiWarn (T 'link_skipped' @($child.FullName)); continue }
        $dest = Join-SujiPath $To $child.Name
        if ($child.PSIsContainer) { Copy-SujiTree -From $child.FullName -To $dest }
        else { Copy-Item -LiteralPath $child.FullName -Destination $dest -Force }
    }
}

# $Root: the config folder $Path is in (checked with Assert-SujiWriteTarget).
function New-SujiDirectory {
    param([string]$Path, [string]$Root = '')
    if ($Root) { Assert-SujiWriteTarget -Path $Path -Root $Root }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# A path typed by the user (or given with -Target): quotes stripped, %VARS%
# expanded and a relative path resolved against PowerShell's current folder.
# Throws when it is not a file system path.
function ConvertTo-SujiTypedPath {
    param([string]$Path)
    if ($null -eq $Path) { $Path = '' }
    $p = $Path.Trim().Trim('"').Trim("'").Trim()
    if ($p -eq '') { throw (T 'path_bad' @($Path)) }
    $p = [Environment]::ExpandEnvironmentVariables($p)
    $provider = $null
    $drive = $null
    try { $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p, [ref]$provider, [ref]$drive) }
    catch { throw (T 'path_bad' @($Path)) }
    if ($null -eq $provider -or $provider.Name -ne 'FileSystem') { throw (T 'path_bad' @($Path)) }
    return (Get-SujiFullPath $resolved)
}

# Reads a text file keeping what is needed to write it back unchanged: UTF-8 (with
# or without BOM) or, when the bytes are not valid UTF-8, Latin-1, which maps
# every byte to one character and back, so nothing of the user's file is lost.
function Read-SujiText {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset = 0
    if ($bom) { $offset = 3 }
    $encoding = 'utf8'
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        $text = $strict.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        $encoding = 'latin1'
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes, $offset, $bytes.Length - $offset)
    }
    return [pscustomobject]@{ Text = $text; Encoding = $encoding; Bom = $bom }
}

# Writes text without BOM unless $Bom is set (only to keep a BOM the file already
# had), into $Path inside the config folder $Root. The text goes to a temporary
# file next to it that then replaces it, so a failed write never leaves half a
# file.
function Write-SujiText {
    param([string]$Path, [string]$Text, [Parameter(Mandatory = $true)][string]$Root, [string]$Encoding = 'utf8', [bool]$Bom = $false)
    Assert-SujiInside -Path $Path -Root $Root
    Assert-SujiWriteTarget -Path $Path -Root $Root
    if ($Encoding -eq 'latin1') { $enc = [System.Text.Encoding]::GetEncoding(28591) }
    else { $enc = New-Object System.Text.UTF8Encoding($false) }
    $body = $enc.GetBytes($Text)
    if ($Bom) { $body = [byte[]](@(0xEF, 0xBB, 0xBF) + $body) }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $tmp = $Path + '.suji-' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [System.IO.File]::WriteAllBytes($tmp, $body)
        if ($null -ne $item) { [System.IO.File]::Replace($tmp, $Path, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $Path) }
    }
    finally { if ([System.IO.File]::Exists($tmp)) { [System.IO.File]::Delete($tmp) } }
}

function Test-SujiDirWritable {
    param([string]$Path)
    $probe = $Path
    while ($probe -and -not (Test-Path -LiteralPath $probe -PathType Container)) {
        $parent = Split-Path -Path $probe -Parent
        if ($parent -eq $probe) { break }
        $probe = $parent
    }
    if (-not $probe -or -not (Test-Path -LiteralPath $probe -PathType Container)) { return $false }
    $file = Join-SujiPath $probe ('.suji-write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($file, 'suji')
        [System.IO.File]::Delete($file)
        return $true
    }
    catch {
        return $false
    }
}

function Get-SujiFileSha256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try { $hash = $sha.ComputeHash($stream) }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

function Test-SujiAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        return [bool]$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

# Everything detection needs from the machine, so tests can fake a Windows box.
function New-SujiEnvironment {
    return @{
        IsAdmin         = (Test-SujiAdmin)
        LocalAppData    = $env:LOCALAPPDATA
        AppData         = $env:APPDATA
        UserProfile     = $env:USERPROFILE
        ProgramFiles    = $env:ProgramFiles
        ProgramFilesX86 = ${env:ProgramFiles(x86)}
        ProgramData     = $env:ProgramData
        MpvHome         = $env:MPV_HOME
        FindCommand     = {
            param([string]$Name)
            $cmd = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmd) { return $cmd.Path }
            return $null
        }
        TestWritable    = { param([string]$Path) Test-SujiDirWritable $Path }
    }
}

function Get-SujiUserConfigDir {
    param([hashtable]$Env, [string]$Kind)
    if ($Kind -eq 'mpv') {
        if ($Env.MpvHome) { return $Env.MpvHome }
        if (-not $Env.AppData) { return $null }
        return (Join-SujiPath $Env.AppData 'mpv')
    }
    if (-not $Env.AppData) { return $null }
    return (Join-SujiPath $Env.AppData 'mpv.net')
}

function Get-SujiPlayerKind {
    param([string]$Exe)
    $name = [System.IO.Path]::GetFileName($Exe)
    if ($name -ieq 'mpvnet.exe') {
        if ($Exe -match '(?i)animejanai') { return 'AnimeJaNai' }
        return 'mpv.net'
    }
    return 'mpv'
}

# Scoop puts a small launcher in PATH (shims\mpv.exe) with a mpv.shim text file
# next to it that says where the real exe is.
function Resolve-SujiShim {
    param([string]$Exe)
    $shim = [System.IO.Path]::ChangeExtension($Exe, '.shim')
    if (Test-Path -LiteralPath $shim -PathType Leaf) {
        foreach ($line in [System.IO.File]::ReadAllLines($shim)) {
            if ($line -match '^\s*path\s*=\s*"?([^"]+?)"?\s*$') { return $Matches[1] }
        }
    }
    if ($Exe -match '(?i)[\\/]chocolatey[\\/]bin[\\/]') { return $null }
    return $Exe
}

# hikari (or sosc, its name before v0.3.0) in the folder, as the hikari
# installer itself recognises it: its record, or its scripts (hikari-*.lua).
function Test-SujiHikariPresent {
    param([string]$ConfigDir)
    foreach ($name in @('hikari-installed.txt', 'sosc-installed.txt')) {
        if ($null -ne (Get-Item -LiteralPath (Join-SujiPath $ConfigDir $name) -Force -ErrorAction SilentlyContinue)) { return $true }
    }
    $scripts = Join-SujiPath $ConfigDir 'scripts'
    return ((Test-Path -LiteralPath $scripts -PathType Container) -and
        @(Get-ChildItem -LiteralPath $scripts -Filter 'hikari-*.lua' -File -Force).Count -gt 0)
}

# A version as the record or this installer may say it: X.Y.Z or dev. Anything
# else is never shown: the record can be edited by anyone.
function Test-SujiVersionText {
    param([string]$Text)
    return ($Text -cmatch '\A[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}\z' -or $Text -ceq 'dev')
}

function New-SujiCandidate {
    param([hashtable]$Env, [string]$Kind, [string]$Exe, [string]$ConfigDir, [bool]$Portable)
    $exists = Test-Path -LiteralPath $ConfigDir -PathType Container
    $installed = $false
    $manual = $false
    $version = ''
    $hikari = $false
    if ($exists) {
        $record = Read-SujiRecord $ConfigDir -NoWarn
        if ($null -ne $record) {
            $installed = $true
            $version = [string]$record.Values['suji_version']
            if (-not (Test-SujiVersionText $version)) { $version = '?' }
        }
        elseif (Test-Path -LiteralPath (Join-SujiPath $ConfigDir @('scripts', 'suji')) -PathType Container) {
            $installed = $true
            $manual = $true
        }
        $hikari = Test-SujiHikariPresent $ConfigDir
    }
    $fallback = $null
    if ($Portable) { $fallback = Get-SujiUserConfigDir -Env $Env -Kind $Kind }
    return [pscustomobject]@{
        Kind             = $Kind
        Exe              = $Exe
        ConfigDir        = $ConfigDir
        Portable         = $Portable
        Exists           = $exists
        Writable         = [bool](& $Env.TestWritable $ConfigDir)
        Installed        = $installed
        InstalledVersion = $version
        Manual           = $manual
        Hikari           = $hikari
        UserConfigDir    = $fallback
    }
}

# Finds mpv, mpv.net and AnimeJaNai, plus mpv config folders that exist without
# a player. Pure apart from the file system: everything else comes from $Env.
function Find-SujiPlayers {
    param([Parameter(Mandatory = $true)][hashtable]$Env)

    $exePaths = New-Object System.Collections.Generic.List[string]
    $addExe = {
        param([string]$Path)
        if (-not [string]::IsNullOrEmpty($Path)) { $exePaths.Add($Path) }
    }

    if ($Env.LocalAppData) {
        & $addExe (Join-SujiPath $Env.LocalAppData @('Programs', 'mpv-AnimeJaNai', 'mpvnet.exe'))
        & $addExe (Join-SujiPath $Env.LocalAppData @('Programs', 'mpv.net', 'mpvnet.exe'))
    }
    foreach ($pf in @($Env.ProgramFiles, $Env.ProgramFilesX86)) {
        if ($pf) { & $addExe (Join-SujiPath $pf @('mpv.net', 'mpvnet.exe')) }
    }
    if ($Env.UserProfile) {
        & $addExe (Join-SujiPath $Env.UserProfile @('scoop', 'apps', 'mpv.net', 'current', 'mpvnet.exe'))
    }
    $found = & $Env.FindCommand 'mpvnet.exe'
    if ($found) { & $addExe (Resolve-SujiShim $found) }

    $found = & $Env.FindCommand 'mpv.exe'
    if ($found) { & $addExe (Resolve-SujiShim $found) }
    if ($Env.UserProfile) {
        & $addExe (Join-SujiPath $Env.UserProfile @('scoop', 'apps', 'mpv', 'current', 'mpv.exe'))
        & $addExe (Join-SujiPath $Env.UserProfile @('scoop', 'apps', 'mpv-git', 'current', 'mpv.exe'))
    }
    foreach ($pf in @($Env.ProgramFiles, $Env.ProgramFilesX86)) {
        if ($pf) {
            & $addExe (Join-SujiPath $pf @('mpv', 'mpv.exe'))
            & $addExe (Join-SujiPath $pf @('MPV Player', 'mpv.exe'))
        }
    }
    if ($Env.ProgramData) {
        $chocoLib = Join-SujiPath $Env.ProgramData @('chocolatey', 'lib')
        if (Test-Path -LiteralPath $chocoLib -PathType Container) {
            foreach ($pkg in @(Get-ChildItem -LiteralPath $chocoLib -Directory -Filter 'mpv*' -Force)) {
                foreach ($exe in @(Get-ChildItem -LiteralPath $pkg.FullName -Recurse -Depth 3 -File -Filter 'mpv.exe' -Force -ErrorAction SilentlyContinue)) {
                    & $addExe $exe.FullName
                }
            }
        }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $seenExe = New-Object System.Collections.Generic.List[string]
    $seenConfig = New-Object System.Collections.Generic.List[string]
    $isSeen = {
        param($List, [string]$Path)
        foreach ($p in $List) { if (Test-SujiSamePath $p $Path) { return $true } }
        return $false
    }

    foreach ($exe in $exePaths) {
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
        $exeFull = Get-SujiFullPath $exe
        if (& $isSeen $seenExe $exeFull) { continue }
        $seenExe.Add($exeFull)
        $kind = Get-SujiPlayerKind $exeFull
        $portableDir = Join-SujiPath (Split-Path -Path $exeFull -Parent) 'portable_config'
        # mpv itself gives MPV_HOME priority over portable_config. mpv.net (and
        # AnimeJaNai) set their own config-dir, which beats both.
        $portable = (Test-Path -LiteralPath $portableDir -PathType Container) -and -not ($kind -eq 'mpv' -and $Env.MpvHome)
        if ($portable) { $config = $portableDir } else { $config = Get-SujiUserConfigDir -Env $Env -Kind $kind }
        if (-not $config) { continue }
        $config = Get-SujiFullPath $config
        if (& $isSeen $seenConfig $config) { continue }
        $seenConfig.Add($config)
        $candidates.Add((New-SujiCandidate -Env $Env -Kind $kind -Exe $exeFull -ConfigDir $config -Portable $portable))
    }

    foreach ($kind in @('mpv', 'mpv.net')) {
        $config = Get-SujiUserConfigDir -Env $Env -Kind $kind
        if (-not $config -or -not (Test-Path -LiteralPath $config -PathType Container)) { continue }
        $config = Get-SujiFullPath $config
        if (& $isSeen $seenConfig $config) { continue }
        $seenConfig.Add($config)
        $candidates.Add((New-SujiCandidate -Env $Env -Kind 'folder' -Exe '' -ConfigDir $config -Portable $false))
    }

    return $candidates.ToArray()
}

# A folder typed by the user (or given with -Target): reuse the detected entry
# when it is one, otherwise guess the player from an exe next to it. A folder
# that holds the player itself is not a config folder: its portable_config is
# used, or the user folder that player reads is offered. Returns $null when the
# user turns that down.
function Resolve-SujiManualTarget {
    param([hashtable]$Env, [string]$Path, [object[]]$Candidates)
    $full = ConvertTo-SujiTypedPath $Path
    foreach ($c in $Candidates) {
        if (Test-SujiSamePath $c.ConfigDir $full) { return $c }
    }

    foreach ($name in $script:PlayerExes) {
        $probe = Join-SujiPath $full $name
        if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { continue }
        $kind = Get-SujiPlayerKind $probe
        Write-SujiWarn (T 'exe_folder' @($full, $name))
        $portableDir = Join-SujiPath $full 'portable_config'
        if ((Test-Path -LiteralPath $portableDir -PathType Container) -and -not ($kind -eq 'mpv' -and $Env.MpvHome)) {
            Write-SujiInfo (T 'exe_portable' @($portableDir))
            return (Resolve-SujiManualTarget -Env $Env -Path $portableDir -Candidates $Candidates)
        }
        $user = Get-SujiUserConfigDir -Env $Env -Kind $kind
        if (-not $user) { return $null }
        $user = Get-SujiFullPath $user
        if (-not (Confirm-Suji -Question (T 'exe_offer' @($user)) -Default $true)) { return $null }
        foreach ($c in $Candidates) {
            if (Test-SujiSamePath $c.ConfigDir $user) { return $c }
        }
        return (New-SujiCandidate -Env $Env -Kind $kind -Exe $probe -ConfigDir $user -Portable $false)
    }

    $kind = 'folder'
    $exe = ''
    $portable = $false
    if ((Split-Path -Path $full -Leaf) -ieq 'portable_config') {
        $parent = Split-Path -Path $full -Parent
        foreach ($name in $script:PlayerExes) {
            $probe = Join-SujiPath $parent $name
            if (Test-Path -LiteralPath $probe -PathType Leaf) {
                $exe = $probe
                $kind = Get-SujiPlayerKind $probe
                $portable = $true
                if ($kind -eq 'mpv' -and $Env.MpvHome) { Write-SujiWarn (T 'mpv_home_note' @($Env.MpvHome, $full)) }
                break
            }
        }
    }
    return (New-SujiCandidate -Env $Env -Kind $kind -Exe $exe -ConfigDir $full -Portable $portable)
}

# A drive root (C:\, \\server\share, /) or the bare user profile is never a
# config folder.
function Test-SujiForbiddenTarget {
    param([hashtable]$Env, [string]$Path)
    $full = Get-SujiFullPath $Path
    $seps = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($null -eq $root -or $full.TrimEnd($seps) -eq $root.TrimEnd($seps)) { return $true }
    if ($Env.UserProfile -and (Test-SujiSamePath $full $Env.UserProfile)) { return $true }
    return $false
}

# False only for a folder that exists, is not empty and shows no sign of mpv.
function Test-SujiLooksLikeMpvConfig {
    param([hashtable]$Env, $Candidate)
    $dir = Get-SujiFullPath $Candidate.ConfigDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $true }
    if (@(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) { return $true }
    if ($Candidate.Exe) { return $true }
    foreach ($n in $script:MpvConfigFiles) { if (Test-Path -LiteralPath (Join-SujiPath $dir $n) -PathType Leaf) { return $true } }
    foreach ($n in $script:MpvConfigDirs) { if (Test-Path -LiteralPath (Join-SujiPath $dir $n) -PathType Container) { return $true } }
    foreach ($kind in @('mpv', 'mpv.net')) {
        $user = Get-SujiUserConfigDir -Env $Env -Kind $kind
        if ($user -and (Test-SujiSamePath $user $dir)) { return $true }
    }
    $parent = Split-Path -Path $dir -Parent
    foreach ($d in @($dir, $parent)) {
        if (-not $d) { continue }
        foreach ($n in $script:PlayerExes) { if (Test-Path -LiteralPath (Join-SujiPath $d $n) -PathType Leaf) { return $true } }
    }
    return $false
}

# "1,3" / "o" / "0" -> what the user picked. Returns $null when the text is not valid.
function ConvertFrom-SujiSelection {
    param([string]$Text, [int]$Count)
    $result = [pscustomobject]@{ Indexes = @(); Other = $false; Quit = $false }
    if ($null -eq $Text) { return $null }
    $parts = @($Text -split '[,;\s]+' | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) { return $null }
    $indexes = New-Object System.Collections.Generic.List[int]
    foreach ($part in $parts) {
        $p = $part.ToLowerInvariant()
        if ($p -eq '0' -or $p -eq 'q' -or $p -eq 'x') { $result.Quit = $true; continue }
        if ($p -eq 'o') { $result.Other = $true; continue }
        $n = 0
        if (-not [int]::TryParse($p, [ref]$n)) { return $null }
        if ($n -lt 1 -or $n -gt $Count) { return $null }
        if (-not $indexes.Contains($n - 1)) { $indexes.Add($n - 1) }
    }
    $result.Indexes = $indexes.ToArray()
    return $result
}

# ---------------------------------------------------------------------------
# The suji block in mpv.conf
# ---------------------------------------------------------------------------

# Splits text into lines, keeping each line's own terminator and offset.
function Split-SujiLines {
    param([string]$Text)
    $lines = New-Object System.Collections.Generic.List[object]
    $pos = 0
    while ($pos -lt $Text.Length) {
        $nl = $Text.IndexOf("`n", $pos)
        if ($nl -lt 0) {
            $lines.Add([pscustomobject]@{ Start = $pos; Content = $Text.Substring($pos); Eol = '' })
            break
        }
        $end = $nl
        $eol = "`n"
        if ($nl -gt $pos -and $Text[$nl - 1] -eq "`r") { $end = $nl - 1; $eol = "`r`n" }
        $lines.Add([pscustomobject]@{ Start = $pos; Content = $Text.Substring($pos, $end - $pos); Eol = $eol })
        $pos = $nl + 1
    }
    return $lines.ToArray()
}

# The file's own line ending; CRLF for a file without any.
function Get-SujiEol {
    param([string]$Text)
    if ($Text.Contains("`r`n")) { return "`r`n" }
    if ($Text.Contains("`n")) { return "`n" }
    return "`r`n"
}

# Returns $null when there is no block, or the index of its first and last line.
# Throws when the markers do not pair up (missing, repeated or out of order).
function Find-SujiBlock {
    param([object[]]$Lines, [string]$Name)
    $begin = -1
    $end = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $content = $Lines[$i].Content.Trim()
        if ($content -eq $script:BlockBegin) {
            if ($begin -ge 0) { throw (T 'malformed_block' @($Name)) }
            $begin = $i
        }
        elseif ($content -eq $script:BlockEnd) {
            if ($begin -lt 0 -or $end -ge 0) { throw (T 'malformed_block' @($Name)) }
            $end = $i
        }
    }
    if ($begin -ge 0 -and $end -lt 0) { throw (T 'malformed_block' @($Name)) }
    if ($begin -lt 0) { return $null }
    return [pscustomobject]@{ Begin = $begin; End = $end }
}

# Puts the block in place of the old one, or at the start of the file: there,
# before any [profile], its options apply to every file.
function Set-SujiBlockText {
    param([string]$Text, [string]$Name)
    $eol = Get-SujiEol $Text
    $body = [string]::Join($eol, @(@($script:BlockBegin) + $script:MpvConfLines + @($script:BlockEnd)))
    $lines = @(Split-SujiLines $Text)
    $block = Find-SujiBlock -Lines $lines -Name $Name
    if ($null -ne $block) {
        $first = $lines[$block.Begin]
        $last = $lines[$block.End]
        return $Text.Substring(0, $first.Start) + $body + $Text.Substring($last.Start + $last.Content.Length)
    }
    return $body + $eol + $Text
}

function Remove-SujiBlockText {
    param([string]$Text, [string]$Name)
    $lines = @(Split-SujiLines $Text)
    $block = Find-SujiBlock -Lines $lines -Name $Name
    if ($null -eq $block) { return $Text }
    $first = $lines[$block.Begin]
    $last = $lines[$block.End]
    return $Text.Substring(0, $first.Start) + $Text.Substring($last.Start + $last.Content.Length + $last.Eol.Length)
}

# Throws when mpv.conf has a broken block; called before anything changes.
function Assert-SujiMpvConf {
    param([string]$ConfigDir)
    $path = Join-SujiPath $ConfigDir 'mpv.conf'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    [void](Find-SujiBlock -Lines @(Split-SujiLines (Read-SujiText $path).Text) -Name $path)
}

# Writes the block into mpv.conf (created when missing), keeping its encoding,
# BOM and line endings.
function Update-SujiMpvConf {
    param([string]$ConfigDir)
    $path = Join-SujiPath $ConfigDir 'mpv.conf'
    $existed = Test-Path -LiteralPath $path -PathType Leaf
    if ($existed) { $file = Read-SujiText $path }
    else { $file = [pscustomobject]@{ Text = ''; Encoding = 'utf8'; Bom = $false } }
    $newText = Set-SujiBlockText -Text $file.Text -Name $path
    if (-not $existed -or $newText -cne $file.Text) {
        Write-SujiText -Path $path -Text $newText -Root $ConfigDir -Encoding $file.Encoding -Bom $file.Bom
    }
}

# Takes the block out. A file suji created that is left with nothing in it goes.
function Remove-SujiMpvConf {
    param([string]$ConfigDir, [bool]$CreatedBySuji)
    $path = Join-SujiPath $ConfigDir 'mpv.conf'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $file = Read-SujiText $path
    $newText = Remove-SujiBlockText -Text $file.Text -Name $path
    if ($newText -ceq $file.Text) { return }
    if ($CreatedBySuji -and $newText.Trim() -eq '') { Remove-SujiItem -Path $path -Root $ConfigDir; return }
    Write-SujiText -Path $path -Text $newText -Root $ConfigDir -Encoding $file.Encoding -Bom $file.Bom
}

# thumbfast.conf: created with suji's settings when missing; an existing one is
# only given mpv_path, when it needs one and has none.
function Update-SujiThumbfastConf {
    param([string]$ConfigDir, [string]$MpvPath)
    $opts = Join-SujiPath $ConfigDir 'script-opts'
    $path = Join-SujiPath $opts 'thumbfast.conf'
    # The lines added for mpv_path: a blank line, why, and the line itself.
    $added = { param([string]$Eol) $Eol + $script:MpvPathComment + $Eol + 'mpv_path=' + $MpvPath + $Eol }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        New-SujiDirectory $opts -Root $ConfigDir
        $text = [string]::Join("`r`n", $script:ThumbfastConfLines) + "`r`n"
        if ($MpvPath) { $text += & $added "`r`n" }
        Write-SujiText -Path $path -Text $text -Root $ConfigDir
    }
    else {
        if (-not $MpvPath -or $item.PSIsContainer -or (Test-SujiLink $item)) { return }
        $file = Read-SujiText $path
        if ($file.Text -match '(?m)^\s*mpv_path\s*=') { return }
        $eol = Get-SujiEol $file.Text
        $text = $file.Text
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += $eol }
        Write-SujiText -Path $path -Text ($text + (& $added $eol)) -Root $ConfigDir -Encoding $file.Encoding -Bom $file.Bom
    }
    if ($MpvPath) { Write-SujiInfo (T 'mpvpath_set' @($MpvPath)) }
}

# ---------------------------------------------------------------------------
# Installer record (suji-installed.txt)
# ---------------------------------------------------------------------------

# The record can be edited by anyone, so its paths are checked before use: they
# must be relative, '/'-separated, with no '..', '.', empty segment, drive,
# backslash or characters Windows does not allow, and no segment ending in a dot
# or a space (Windows drops those, so "..." could act as "..").
function Test-SujiRecordPath {
    param([string]$Rel)
    if ([string]::IsNullOrEmpty($Rel)) { return $false }
    if ($Rel -match '[\\:*?"<>|\x00-\x1f]') { return $false }
    foreach ($seg in ($Rel -split '/')) {
        if ($seg -eq '' -or $seg -match '^\.+\z' -or $seg -match '[. ]\z') { return $false }
    }
    return $true
}

# "aside|original": something set aside, so in the folder of set-aside things
# (never another file of the folder), from scripts, script-opts or fonts.
function Test-SujiAsidePair {
    param([string]$Value)
    $pair = $Value -split '\|'
    return ($pair.Count -eq 2 -and (Test-SujiRecordPath $pair[0]) -and (Test-SujiRecordPath $pair[1]) -and
        $pair[0].StartsWith($script:AsideDir + '/') -and $pair[1] -match '^(scripts|script-opts|fonts)/')
}

function Read-SujiRecord {
    param([string]$ConfigDir, [switch]$NoWarn)
    $path = Join-SujiPath $ConfigDir $script:RecordName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $values = @{}
    $aside = New-Object System.Collections.Generic.List[string]
    foreach ($line in ((Read-SujiText $path).Text -split "`r?`n")) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $idx = $line.IndexOf('=')
        $key = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim()
        if ($key -eq 'disabled') {
            if (Test-SujiAsidePair $value) { $aside.Add($value) }
            elseif (-not $NoWarn) { Write-SujiWarn (T 'record_bad' @($line)) }
        }
        else { $values[$key] = $value }
    }
    return [pscustomobject]@{ Values = $values; Aside = $aside.ToArray() }
}

function Write-SujiRecord {
    param([string]$ConfigDir, [System.Collections.Specialized.OrderedDictionary]$Values, [string[]]$Aside)
    $eol = "`r`n"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('# Written by the suji installer. Used to update and uninstall; do not edit.' + $eol)
    foreach ($key in $Values.Keys) { [void]$sb.Append($key + '=' + [regex]::Replace([string]$Values[$key], '\p{Cc}', '') + $eol) }
    foreach ($a in $Aside) { [void]$sb.Append('disabled=' + $a + $eol) }
    Write-SujiText -Path (Join-SujiPath $ConfigDir $script:RecordName) -Text $sb.ToString() -Root $ConfigDir
}

function ConvertTo-SujiYesNo { param([bool]$Value) if ($Value) { return 'yes' } return 'no' }

# ---------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------

function Assert-SujiDownloadUrl {
    param([string]$Url)
    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or $script:AllowedHosts -notcontains $uri.Host.ToLowerInvariant()) {
        throw (T 'url_bad' @($Url))
    }
}

# $Text without control characters, cut to $Max characters: what a server
# sent, ready to be shown.
function Get-SujiCleanText {
    param([string]$Text, [int]$Max = 200)
    $t = [regex]::Replace([string]$Text, '\p{Cc}', '')
    if ($Max -gt 0 -and $t.Length -gt $Max) { $t = $t.Substring(0, $Max) + '...' }
    return $t
}

# Where a redirect from $From to $Location leads; throws unless it is HTTPS on
# GitHub, on the usual port and with no user name.
function Get-SujiRedirectUri {
    param([System.Uri]$From, [string]$Location)
    $to = $null
    if ([string]::IsNullOrEmpty($Location) -or -not [System.Uri]::TryCreate($From, $Location, [ref]$to)) {
        throw (T 'url_bad' @((Get-SujiCleanText $Location)))
    }
    $hostName = $to.Host.ToLowerInvariant()
    $ok = $to.Scheme -eq 'https' -and $to.IsDefaultPort -and -not $to.UserInfo -and
        ($script:AllowedHosts -contains $hostName -or $hostName -cmatch $script:RedirectHostPattern)
    if (-not $ok) { throw (T 'url_bad' @((Get-SujiCleanText $to.AbsoluteUri))) }
    return $to
}

# The exception behind PowerShell's "Exception calling ..." wrappers.
function Get-SujiInnerException {
    param([System.Exception]$Exception)
    $e = $Exception
    while ($null -ne $e.InnerException -and $e -is [System.Management.Automation.RuntimeException]) { $e = $e.InnerException }
    return $e
}

# The real download: HttpWebRequest, the same in Windows PowerShell 5.1 and
# PowerShell 7. Redirects are followed here, one by one, each checked by
# Get-SujiRedirectUri. The file is only used after its SHA256 is checked
# (Invoke-SujiVerifiedDownload).
function Invoke-SujiHttpDownload {
    param([string]$Url, [string]$OutFile)
    Assert-SujiDownloadUrl $Url
    $uri = New-Object System.Uri($Url)
    for ($hop = 0; $hop -le $script:MaxRedirects; $hop++) {
        $request = [System.Net.HttpWebRequest]([System.Net.WebRequest]::Create($uri))
        $request.AllowAutoRedirect = $false
        $request.Method = 'GET'
        $request.Timeout = 30000
        $request.ReadWriteTimeout = 30000
        $request.UserAgent = 'suji-installer'
        $response = $null
        try { $response = [System.Net.HttpWebResponse]$request.GetResponse() }
        catch {
            $web = Get-SujiInnerException $_.Exception
            if ($web -is [System.Net.WebException] -and $null -ne $web.Response) { try { $web.Response.Close() } catch { } }
            throw (T 'download_failed' @($Url, (Get-SujiCleanText $web.Message 300)))
        }
        try {
            $code = [int]$response.StatusCode
            if ($code -ge 300 -and $code -lt 400) {
                $uri = Get-SujiRedirectUri -From $uri -Location ([string]$response.Headers['Location'])
                continue
            }
            if ($code -ne 200) { throw (T 'download_failed' @($Url, (T 'download_status' @($code)))) }
            $in = $response.GetResponseStream()
            $out = [System.IO.File]::Create($OutFile)
            try {
                $buffer = New-Object byte[] 65536
                $done = [long]0
                while (($n = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $done += $n
                    if ($done -gt $script:MaxDownloadBytes) {
                        throw (T 'download_failed' @($Url, (T 'download_too_big' @([long]($script:MaxDownloadBytes / 1MB)))))
                    }
                    $out.Write($buffer, 0, $n)
                }
            }
            catch {
                # A connection cut or a timeout half-way; the messages of this
                # file (thrown as text: no inner exception) pass as they are.
                $e = $_.Exception
                if ($e -is [System.Management.Automation.RuntimeException] -and $null -eq $e.InnerException) { throw }
                throw (T 'download_failed' @($Url, (Get-SujiCleanText (Get-SujiInnerException $e).Message 300)))
            }
            finally { $out.Dispose(); $in.Dispose() }
            return
        }
        finally { $response.Close() }
    }
    throw (T 'download_failed' @($Url, (T 'download_redirects')))
}

# Downloads $Url to $OutFile and checks its SHA256. On mismatch, or when the
# download fails half-way, the file is deleted and an error is thrown, so
# nothing unverified is ever used.
function Invoke-SujiVerifiedDownload {
    param([string]$Url, [string]$Sha256, [string]$OutFile)
    Assert-SujiDownloadUrl $Url
    if ([string]::IsNullOrEmpty($Sha256)) { throw (T 'hash_bad' @($Url, '?', '?')) }
    try {
        # Anything the downloader prints must not end up in the caller's return value.
        & $script:SujiDownloader $Url $OutFile | Out-Null
    }
    catch {
        if (Test-Path -LiteralPath $OutFile -PathType Leaf) { [System.IO.File]::Delete($OutFile) }
        throw
    }
    if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf)) { throw (T 'hash_bad' @($Url, $Sha256, '-')) }
    $actual = Get-SujiFileSha256 $OutFile
    if ($actual -ne $Sha256.ToLowerInvariant()) {
        [System.IO.File]::Delete($OutFile)
        throw (T 'hash_bad' @($Url, $Sha256.ToLowerInvariant(), $actual))
    }
}

function New-SujiTempDir {
    $dir = Join-SujiPath ([System.IO.Path]::GetTempPath()) ('suji-install-' + [guid]::NewGuid().ToString('N'))
    New-SujiDirectory $dir
    return $dir
}

# Where the suji files come from: SujiDir, the folder that goes to scripts\suji.
# A release build (the markers filled in by tools/make-release.sh) always uses
# its own suji.zip, downloaded into $TempDir and checked against its SHA256
# before it is opened. The repository version uses the suji folder of the
# repository copy it sits in; run on its own (iex) it has nothing to install.
function Get-SujiSource {
    param([string]$TempDir)
    if (-not [string]::IsNullOrEmpty($script:SujiUrl)) {
        $zip = Join-SujiPath $TempDir 'suji.zip'
        Write-SujiInfo ('suji ' + $script:SujiVersion + ': ' + $script:SujiUrl)
        Invoke-SujiVerifiedDownload -Url $script:SujiUrl -Sha256 $script:SujiSha256 -OutFile $zip
        $dest = Join-SujiPath $TempDir 'suji-zip'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        New-SujiDirectory $dest
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
        $dir = Join-SujiPath $dest 'suji'
        if (-not (Test-Path -LiteralPath (Join-SujiPath $dir 'main.lua') -PathType Leaf)) { throw (T 'source_missing' @($script:SujiUrl)) }
        return [pscustomobject]@{ SujiDir = $dir; Version = $script:SujiVersion }
    }
    if ($script:SujiScriptRoot) {
        $dir = Join-SujiPath (Split-Path -Path $script:SujiScriptRoot -Parent) 'suji'
        if (Test-Path -LiteralPath (Join-SujiPath $dir 'main.lua') -PathType Leaf) {
            return [pscustomobject]@{ SujiDir = $dir; Version = $script:SujiVersion }
        }
    }
    throw (T 'release_unpublished')
}

# Is the thumbfast of the folder the pinned file, byte for byte?
function Test-SujiThumbfastUpToDate {
    param([string]$ConfigDir)
    $p = Join-SujiPath $ConfigDir @('scripts', 'thumbfast.lua')
    $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSIsContainer -or (Test-SujiLink $item)) { return $false }
    return ((Get-SujiFileSha256 $p) -ceq $script:ThumbfastSha256.ToLowerInvariant())
}

# ---------------------------------------------------------------------------
# Backups and set-aside interfaces
# ---------------------------------------------------------------------------

# Copies what the installer may change ($script:BackupItems and $Extra, paths
# relative to the folder) to <config>-respaldo-suji-<stamp>, each at its own
# relative path. Links, and anything inside one, are skipped. Returns the
# backup folder, or '' when there was nothing to copy.
function New-SujiBackup {
    param([string]$ConfigDir, [string]$Stamp, [string[]]$Extra = @())
    $full = Get-SujiFullPath $ConfigDir
    $parent = Split-Path -Path $full -Parent
    if (-not $parent) { throw (T 'target_root' @($full)) }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($rel in (@($script:BackupItems) + @($Extra) | Select-Object -Unique)) {
        $p = Join-SujiRel $full $rel
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        if ((Test-SujiLink $item) -or (Find-SujiLinkInPath -Path $p -Root $full)) { Write-SujiWarn (T 'link_skipped' @($p)); continue }
        $items.Add([pscustomobject]@{ Rel = $rel; Item = $item })
    }
    if ($items.Count -eq 0) { return '' }

    $base = $full + '-respaldo-suji-' + $Stamp
    $backup = $base
    $n = 2
    while (Test-Path -LiteralPath $backup) { $backup = $base + '-' + $n; $n++ }
    New-SujiDirectory $backup
    try {
        foreach ($i in $items) {
            $dest = Join-SujiRel $backup $i.Rel
            if ($i.Item.PSIsContainer) { Copy-SujiTree -From $i.Item.FullName -To $dest }
            else {
                New-SujiDirectory (Split-Path -Path $dest -Parent)
                Copy-Item -LiteralPath $i.Item.FullName -Destination $dest -Force
            }
        }
    }
    catch {
        $failure = $_
        try { Remove-SujiItem -Path $backup -Root $parent } catch { }
        throw $failure
    }
    return $backup
}

# The backup as a step: throws, saying nothing was changed, when it cannot.
function New-SujiBackupStep {
    param([string]$ConfigDir, [string]$Stamp, [string[]]$Extra = @())
    try { $backup = New-SujiBackup -ConfigDir $ConfigDir -Stamp $Stamp -Extra $Extra }
    catch { throw (T 'backup_failed' @($ConfigDir, $_.Exception.Message)) }
    if ($backup) { Write-SujiInfo (T 'backup_done' @($backup)) }
    return $backup
}

# Keeps the newest $Keep backups of this folder (<config>-respaldo-suji-<stamp>,
# siblings of it) and deletes the older ones. Only folders whose name is
# exactly that pattern for this folder are considered; links are never touched.
function Remove-SujiOldBackups {
    param([string]$ConfigDir, [int]$Keep = $script:BackupKeep)
    $full = Get-SujiFullPath $ConfigDir
    $parent = Split-Path -Path $full -Parent
    if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { return }
    $re = '^' + [regex]::Escape((Split-Path -Path $full -Leaf)) + '-respaldo-suji-(\d{8}-\d{6})(?:-(\d+))?\z'
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($d in @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue)) {
        $m = [regex]::Match($d.Name, $re, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $m.Success -or (Test-SujiLink $d)) { continue }
        $n = 1
        if ($m.Groups[2].Success) { $n = [int]$m.Groups[2].Value }
        $found.Add([pscustomobject]@{ Path = $d.FullName; Stamp = $m.Groups[1].Value; N = $n })
    }
    $sorted = @($found | Sort-Object -Property @{ Expression = 'Stamp'; Descending = $true }, @{ Expression = 'N'; Descending = $true })
    for ($i = $Keep; $i -lt $sorted.Count; $i++) {
        try { Remove-SujiItem -Path $sorted[$i].Path -Root $parent }
        catch { Write-SujiWarn (T 'backup_prune_failed' @($sorted[$i].Path, $_.Exception.Message)) }
    }
}

# Interfaces in the folder that clash with suji, as paths relative to it: the
# scripts (and uosc's folders), each one's script-opts/<name>.conf, and the
# fonts that clearly belong to one of them.
function Find-SujiConflicts {
    param([string]$ConfigDir)
    $found = New-Object System.Collections.Generic.List[string]
    $scripts = Join-SujiPath $ConfigDir 'scripts'
    if (-not (Test-Path -LiteralPath $scripts -PathType Container)) { return @() }
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(Get-ChildItem -LiteralPath $scripts -Force)) {
        $hit = $false
        if ($item.PSIsContainer) { $hit = $script:ConflictDirs -contains $item.Name }
        else { foreach ($pattern in $script:ConflictPatterns) { if ($item.Name -like $pattern) { $hit = $true; break } } }
        if (-not $hit) { continue }
        $found.Add('scripts/' + $item.Name)
        $names.Add(($item.Name -replace '\.lua$', ''))
    }
    foreach ($n in @($names | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-SujiPath $ConfigDir @('script-opts', ($n + '.conf'))) -PathType Leaf) { $found.Add('script-opts/' + $n + '.conf') }
    }
    $fonts = Join-SujiPath $ConfigDir 'fonts'
    if ($names.Count -gt 0 -and (Test-Path -LiteralPath $fonts -PathType Container)) {
        foreach ($item in @(Get-ChildItem -LiteralPath $fonts -File -Force)) {
            $owned = $false
            foreach ($pattern in $script:ConflictFontPatterns) {
                if ($item.Name -like $pattern -and @($names | Where-Object { $_ -like $pattern }).Count -gt 0) { $owned = $true }
            }
            if ($owned) { $found.Add('fonts/' + $item.Name) }
        }
    }
    return $found.ToArray()
}

# Moves an item of the folder (relative path) into the folder of set-aside
# things: from scripts/ straight in, from script-opts/ and fonts/ into that
# sub-folder. Returns "aside|original" (relative).
function Move-SujiAside {
    param([string]$ConfigDir, [string]$Rel, [string]$Stamp)
    $path = Join-SujiRel $ConfigDir $Rel
    $dest = Join-SujiRel $ConfigDir ($script:AsideDir + '/' + ($Rel -replace '^scripts/', ''))
    if (Test-Path -LiteralPath $dest) {
        $name = Split-Path -Path $dest -Leaf
        $ext = [System.IO.Path]::GetExtension($name)
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
        if ((Get-Item -LiteralPath $path -Force).PSIsContainer) { $ext = ''; $stem = $name }
        $dest = Join-SujiPath (Split-Path -Path $dest -Parent) ($stem + '-' + $Stamp + $ext)
    }
    Assert-SujiInside -Path $path -Root $ConfigDir
    Assert-SujiInside -Path $dest -Root $ConfigDir
    Assert-SujiNoLink -Path $path -Root $ConfigDir
    Assert-SujiNoLink -Path $dest -Root $ConfigDir
    New-SujiDirectory (Split-Path -Path $dest -Parent) -Root $ConfigDir
    Move-Item -LiteralPath $path -Destination $dest
    $destRel = (Get-SujiFullPath $dest).Substring((Get-SujiFullPath $ConfigDir).Length + 1).Replace('\', '/')
    Write-SujiInfo (T 'moved' @($Rel, $destRel))
    return ($destRel + '|' + $Rel)
}

# Moves set-aside items back. The entries come from the record, which is not
# trusted: both ends must be clean paths inside the folder, nothing is
# overwritten and links are not followed when running as administrator.
function Restore-SujiAside {
    param([string]$ConfigDir, [string[]]$Pairs)
    foreach ($entry in $Pairs) {
        if (-not (Test-SujiAsidePair $entry)) { Write-SujiWarn (T 'record_bad' @($entry)); continue }
        $pair = $entry -split '\|'
        $from = Join-SujiRel $ConfigDir $pair[0]
        $to = Join-SujiRel $ConfigDir $pair[1]
        if (-not (Test-SujiInside -Path $from -Root $ConfigDir) -or -not (Test-SujiInside -Path $to -Root $ConfigDir)) {
            Write-SujiWarn (T 'record_bad' @($entry)); continue
        }
        if ($null -eq (Get-Item -LiteralPath $from -Force -ErrorAction SilentlyContinue)) { continue }
        if ($null -ne (Get-Item -LiteralPath $to -Force -ErrorAction SilentlyContinue)) { Write-SujiWarn (T 'restore_skipped' @($pair[0], $pair[1])); continue }
        Assert-SujiNoLink -Path $from -Root $ConfigDir
        Assert-SujiNoLink -Path $to -Root $ConfigDir
        New-SujiDirectory (Split-Path -Path $to -Parent) -Root $ConfigDir
        Move-Item -LiteralPath $from -Destination $to
        Write-SujiInfo (T 'moved' @($pair[0], $pair[1]))
    }
}

# Removes the folder when it is a real folder with no files left in it
# (-Strict: with nothing at all in it).
function Remove-SujiEmptyDir {
    param([string]$ConfigDir, [string]$Rel, [switch]$Strict)
    $dir = Join-SujiRel $ConfigDir $Rel
    $item = Get-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or -not $item.PSIsContainer -or (Test-SujiLink $item)) { return }
    if ($Strict) { $left = @(Get-ChildItem -LiteralPath $dir -Force) }
    else { $left = @(Get-ChildItem -LiteralPath $dir -Recurse -Force | Where-Object { -not $_.PSIsContainer }) }
    if ($left.Count -eq 0) {
        Remove-SujiItem -Path $dir -Root $ConfigDir
    }
}

function Get-SujiRestoreMessage {
    param([string]$Message, [string]$Backup)
    if ($Backup) { $Message += ' ' + (T 'restore_hint' @($Backup)) }
    return $Message
}

# Every place the installer writes to in the folder is checked for links before
# anything changes, as a broken block is (and again at each write).
function Assert-SujiWriteTargets {
    param([string]$ConfigDir)
    foreach ($rel in @('mpv.conf', $script:RecordName, 'scripts/suji', 'scripts/thumbfast.lua', 'script-opts/thumbfast.conf', $script:AsideDir)) {
        Assert-SujiWriteTarget -Path (Join-SujiRel $ConfigDir $rel) -Root $ConfigDir
    }
}

# ---------------------------------------------------------------------------
# Install and uninstall
# ---------------------------------------------------------------------------

# Installs into one folder. $ThumbfastFile: the checked download ('' when every
# folder already had it).
function Install-SujiTarget {
    param([Parameter(Mandatory = $true)]$Candidate, [Parameter(Mandatory = $true)]$Source, [string]$ThumbfastFile = '',
        [string]$Stamp = '')
    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    $config = Get-SujiFullPath $Candidate.ConfigDir
    Write-SujiInfo ''
    Write-SujiInfo (T 'installing_to' @($config))
    # Checked before anything changes, the backup too.
    if (Test-SujiHikariPresent $config) { throw (T 'hikari_present' @($config)) }
    Assert-SujiMpvConf $config
    Assert-SujiWriteTargets $config

    # Interfaces that clash with suji: asked first, so the backup has them.
    $moving = @()
    $conflicts = @()
    if (Test-Path -LiteralPath $config -PathType Container) { $conflicts = @(Find-SujiConflicts $config) }
    if ($conflicts.Count -gt 0) {
        Write-SujiWarn (T 'conflicts_found')
        foreach ($c in $conflicts) { Write-SujiWarn ('  - ' + $c) }
        if (Confirm-Suji -Question (T 'conflicts_confirm' @($script:AsideDir)) -Default $true) { $moving = $conflicts }
        else { Write-SujiWarn (T 'conflicts_kept') }
    }
    $backup = ''
    if (Test-Path -LiteralPath $config -PathType Container) {
        $backup = New-SujiBackupStep -ConfigDir $config -Stamp $Stamp -Extra $moving
    }
    else { New-SujiDirectory $config }

    try {
        if ($backup) { Remove-SujiOldBackups $config }
        $old = Read-SujiRecord $config
        $scripts = Join-SujiPath $config 'scripts'
        $thumb = Join-SujiPath $scripts 'thumbfast.lua'
        # What was there before suji: from the record once suji is installed.
        $prev = {
            param([string]$Key, [bool]$Now)
            if ($null -ne $old -and $old.Values.ContainsKey($Key)) { return ($old.Values[$Key] -eq 'yes') }
            return $Now
        }
        $values = [ordered]@{}
        $values['suji_version'] = $Source.Version
        $values['installed_at'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        $values['player'] = $Candidate.Kind
        $values['thumbfast_preexisting'] = ConvertTo-SujiYesNo (& $prev 'thumbfast_preexisting' (Test-Path -LiteralPath $thumb -PathType Leaf))
        $values['thumbfast_conf_preexisting'] = ConvertTo-SujiYesNo (& $prev 'thumbfast_conf_preexisting' `
            (Test-Path -LiteralPath (Join-SujiPath $config @('script-opts', 'thumbfast.conf')) -PathType Leaf))
        $values['mpv_conf_preexisting'] = ConvertTo-SujiYesNo (& $prev 'mpv_conf_preexisting' `
            (Test-Path -LiteralPath (Join-SujiPath $config 'mpv.conf') -PathType Leaf))
        $aside = New-Object System.Collections.Generic.List[string]
        if ($null -ne $old) { foreach ($a in $old.Aside) { $aside.Add($a) } }

        # Set aside, never deleted, and recorded as soon as each one moves, so a
        # failure later never leaves one unrecorded.
        Write-SujiRecord -ConfigDir $config -Values $values -Aside $aside.ToArray()
        foreach ($c in $moving) {
            $aside.Add((Move-SujiAside -ConfigDir $config -Rel $c -Stamp $Stamp))
            Write-SujiRecord -ConfigDir $config -Values $values -Aside $aside.ToArray()
        }

        # thumbfast: not copied again when it is exactly as pinned.
        New-SujiDirectory $scripts -Root $config
        if (Test-SujiThumbfastUpToDate $config) { Write-SujiInfo (T 'thumbfast_uptodate') }
        else {
            if (-not $ThumbfastFile) { throw (T 'source_missing' @($script:ThumbfastUrl)) }
            Remove-SujiItem -Path $thumb -Root $config
            Assert-SujiWriteTarget -Path $thumb -Root $config
            Copy-Item -LiteralPath $ThumbfastFile -Destination $thumb -Force
        }

        # suji: copied next to the old one first, so a failed copy leaves the
        # old one in place.
        $dest = Join-SujiPath $scripts 'suji'
        $tmp = Join-SujiPath $scripts ('.suji-new-' + [guid]::NewGuid().ToString('N'))
        try {
            Assert-SujiWriteTarget -Path $tmp -Root $config
            Copy-SujiTree -From $Source.SujiDir -To $tmp
            Remove-SujiItem -Path $dest -Root $config
            Move-Item -LiteralPath $tmp -Destination $dest
        }
        catch {
            $failure = $_
            try { Remove-SujiItem -Path $tmp -Root $config } catch { }
            throw $failure
        }

        # mpv.net (and AnimeJaNai) do not always tell thumbfast where they are.
        $mpvPath = ''
        if (($Candidate.Kind -eq 'mpv.net' -or $Candidate.Kind -eq 'AnimeJaNai') -and $Candidate.Exe) { $mpvPath = $Candidate.Exe }
        Update-SujiThumbfastConf -ConfigDir $config -MpvPath $mpvPath
        Update-SujiMpvConf $config
        Write-SujiRecord -ConfigDir $config -Values $values -Aside $aside.ToArray()
    }
    catch { throw (Get-SujiRestoreMessage -Message $_.Exception.Message -Backup $backup) }
    Write-SujiOk (T 'install_ok' @($Source.Version, $config))
}

function Uninstall-SujiTarget {
    param([Parameter(Mandatory = $true)]$Candidate, [string]$Stamp = '')
    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss') }
    $config = Get-SujiFullPath $Candidate.ConfigDir
    Write-SujiInfo ''
    Write-SujiInfo (T 'uninstalling_from' @($config))
    if (Test-SujiHikariPresent $config) { throw (T 'hikari_present' @($config)) }
    Assert-SujiMpvConf $config
    Assert-SujiWriteTargets $config
    $backup = New-SujiBackupStep -ConfigDir $config -Stamp $Stamp

    try {
        if ($backup) { Remove-SujiOldBackups $config }
        $record = Read-SujiRecord $config
        $values = @{}
        $aside = @()
        if ($null -ne $record) { $values = $record.Values; $aside = @($record.Aside) }
        $wasNot = { param([string]$Key) $values.ContainsKey($Key) -and $values[$Key] -eq 'no' }

        Remove-SujiItem -Path (Join-SujiPath $config @('scripts', 'suji')) -Root $config
        Remove-SujiMpvConf -ConfigDir $config -CreatedBySuji (& $wasNot 'mpv_conf_preexisting')

        $thumb = Join-SujiPath $config @('scripts', 'thumbfast.lua')
        if (Test-Path -LiteralPath $thumb -PathType Leaf) {
            if (Confirm-Suji -Question (T 'ask_remove_thumbfast') -Default (& $wasNot 'thumbfast_preexisting')) {
                Remove-SujiItem -Path $thumb -Root $config
                if (& $wasNot 'thumbfast_conf_preexisting') {
                    Remove-SujiItem -Path (Join-SujiPath $config @('script-opts', 'thumbfast.conf')) -Root $config
                }
            }
        }
        if (@($script:UserFiles | Where-Object { Test-Path -LiteralPath (Join-SujiRel $config $_) -PathType Leaf }).Count -gt 0) {
            if (Confirm-Suji -Question (T 'ask_delete_user') -Default $false) {
                foreach ($f in $script:UserFiles) { Remove-SujiItem -Path (Join-SujiRel $config $f) -Root $config }
            }
        }
        if ($aside.Count -gt 0) {
            $names = [string]::Join(', ', @($aside | ForEach-Object { ($_ -split '\|')[1] }))
            if (Confirm-Suji -Question (T 'ask_restore' @($names)) -Default $true) { Restore-SujiAside -ConfigDir $config -Pairs $aside }
        }

        Remove-SujiItem -Path (Join-SujiPath $config $script:RecordName) -Root $config
        # Folders left empty go too: the set-aside one when no file is left in
        # it, scripts and script-opts when suji may have created them.
        Remove-SujiEmptyDir -ConfigDir $config -Rel $script:AsideDir
        Remove-SujiEmptyDir -ConfigDir $config -Rel 'script-opts' -Strict
        Remove-SujiEmptyDir -ConfigDir $config -Rel 'scripts' -Strict
    }
    catch { throw (Get-SujiRestoreMessage -Message $_.Exception.Message -Backup $backup) }
    Write-SujiOk (T 'uninstall_ok' @($config))
}

# ---------------------------------------------------------------------------
# Interactive flow
# ---------------------------------------------------------------------------

function Get-SujiCandidateTags {
    param($Candidate)
    $tags = @()
    if ($Candidate.Hikari) { $tags += (T 'tag_hikari') }
    elseif ($Candidate.Manual) { $tags += (T 'tag_manual') }
    elseif ($Candidate.Installed) { $tags += (T 'tag_installed' @($Candidate.InstalledVersion)) }
    if (-not $Candidate.Writable) { $tags += (T 'tag_readonly') }
    if (-not $Candidate.Exists) { $tags += (T 'tag_new') }
    return [string]::Join(' ', $tags)
}

function Show-SujiCandidates {
    param([object[]]$Candidates)
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $c = $Candidates[$i]
        $kind = $c.Kind
        if ($kind -eq 'folder') { $kind = T 'kind_folder' }
        Write-SujiInfo (' {0}) {1}  {2}' -f ($i + 1), $kind, (Get-SujiCandidateTags $c))
        if ($c.Exe) { Write-SujiInfo (T 'cand_exe' @($c.Exe)) }
        Write-SujiInfo (T 'cand_config' @($c.ConfigDir))
    }
}

# Which folders to work on, as ConvertFrom-SujiSelection returns them; $null
# when the input ends.
function Read-SujiTargetChoice {
    param([object[]]$List, [string]$Mode)
    while ($true) {
        if (@($List).Count -gt 0) {
            if ($Mode -eq 'uninstall') { Write-SujiInfo (T 'found_header_uninst') } else { Write-SujiInfo (T 'found_header') }
            Show-SujiCandidates $List
        }
        Write-SujiInfo (' ' + (T 'opt_other'))
        Write-SujiInfo (' ' + (T 'opt_quit'))
        $text = Read-SujiLine (T 'select_prompt')
        if ($null -eq $text) { return $null }
        $sel = ConvertFrom-SujiSelection -Text $text -Count @($List).Count
        if ($null -ne $sel) { return $sel }
        Write-SujiWarn (T 'invalid')
    }
}

function Read-SujiFolder {
    param([hashtable]$Env, [object[]]$Candidates)
    while ($true) {
        $answer = Read-SujiLine (T 'ask_folder')
        if ($null -eq $answer -or $answer.Trim() -eq '' -or $answer.Trim() -eq '0') { return $null }
        try { $path = ConvertTo-SujiTypedPath $answer }
        catch { Write-SujiWarn $_.Exception.Message; continue }
        $parent = Split-Path -Path $path -Parent
        if ((Test-Path -LiteralPath $path -PathType Container) -or ($parent -and (Test-Path -LiteralPath $parent -PathType Container))) {
            $c = Resolve-SujiManualTarget -Env $Env -Path $path -Candidates $Candidates
            if ($null -ne $c) { return $c }
            continue
        }
        Write-SujiWarn (T 'folder_missing' @($path))
    }
}

# Checks write access and offers the user folder when a portable one is read-only.
function Resolve-SujiWritable {
    param([hashtable]$Env, $Candidate)
    if ($Candidate.Writable) { return $Candidate }
    Write-SujiWarn (T 'readonly_warn' @($Candidate.ConfigDir))
    if ($Candidate.UserConfigDir) {
        if ($Candidate.Portable) { Write-SujiWarn (T 'readonly_portable' @($Candidate.ConfigDir, $Candidate.UserConfigDir)) }
        if (-not $script:NonInteractive -and (Confirm-Suji -Question (T 'readonly_offer' @($Candidate.UserConfigDir)) -Default $false)) {
            $alt = New-SujiCandidate -Env $Env -Kind $Candidate.Kind -Exe $Candidate.Exe -ConfigDir (Get-SujiFullPath $Candidate.UserConfigDir) -Portable $false
            if ($alt.Writable) { return $alt }
            Write-SujiWarn (T 'readonly_warn' @($alt.ConfigDir))
        }
    }
    Write-SujiWarn (T 'readonly_skip' @($Candidate.ConfigDir))
    return $null
}

# Returns Ok (false: wrong usage with -Yes) and the targets (empty: cancelled).
function Select-SujiTargets {
    param([hashtable]$Env, [string]$Mode, [string[]]$Paths)
    $all = @(Find-SujiPlayers -Env $Env)
    $chosen = New-Object System.Collections.Generic.List[object]
    $refused = $false
    if (@($Paths).Count -gt 0) {
        foreach ($p in $Paths) {
            $c = $null
            try { $c = Resolve-SujiManualTarget -Env $Env -Path $p -Candidates $all }
            catch { Write-SujiError $_.Exception.Message }
            if ($null -ne $c) { $chosen.Add($c) } else { $refused = $true }
        }
    }
    else {
        $list = $all
        if ($Mode -eq 'uninstall') { $list = @($all | Where-Object { $_.Installed }) }
        if ($script:NonInteractive) {
            if ($list.Count -eq 1) { $chosen.Add($list[0]) }
            elseif ($list.Count -eq 0) {
                if ($Mode -eq 'uninstall') { Write-SujiError (T 'nothing_to_uninstall') } else { Write-SujiError (T 'none_found') }
                return [pscustomobject]@{ Ok = $false; Targets = @() }
            }
            else {
                Write-SujiError (T 'usage_many')
                Show-SujiCandidates $list
                return [pscustomobject]@{ Ok = $false; Targets = @() }
            }
        }
        else {
            if ($list.Count -eq 0) {
                if ($Mode -eq 'uninstall') { Write-SujiWarn (T 'nothing_to_uninstall') } else { Write-SujiWarn (T 'none_found') }
            }
            $sel = Read-SujiTargetChoice -List $list -Mode $Mode
            # $null: no more input (stdin closed or redirected), same as choosing Exit.
            if ($null -ne $sel -and -not $sel.Quit) {
                foreach ($i in $sel.Indexes) { $chosen.Add($list[$i]) }
                if ($sel.Other) {
                    $c = Read-SujiFolder -Env $Env -Candidates $all
                    if ($null -ne $c) { $chosen.Add($c) }
                }
            }
        }
    }

    # Folders that must never be used, folders with hikari, and folders that do
    # not look like mpv's.
    $safe = New-Object System.Collections.Generic.List[object]
    foreach ($c in $chosen) {
        if (Test-SujiForbiddenTarget -Env $Env -Path $c.ConfigDir) {
            Write-SujiError (T 'target_root' @($c.ConfigDir))
            $refused = $true
            continue
        }
        if (Test-SujiHikariPresent $c.ConfigDir) {
            Write-SujiWarn (T 'hikari_present' @($c.ConfigDir))
            $refused = $true
            continue
        }
        if (-not (Test-SujiLooksLikeMpvConfig -Env $Env -Candidate $c)) {
            Write-SujiWarn (T 'not_mpv_folder' @($c.ConfigDir))
            if ($script:NonInteractive) {
                Write-SujiError (T 'not_mpv_yes')
                $refused = $true
                continue
            }
            if (-not (Confirm-Suji -Question (T 'not_mpv_confirm') -Default $false)) {
                Write-SujiWarn (T 'readonly_skip' @($c.ConfigDir))
                continue
            }
        }
        $safe.Add($c)
    }
    if ($refused -and $script:NonInteractive) { return [pscustomobject]@{ Ok = $false; Targets = @() } }
    if ($Mode -eq 'uninstall') { return [pscustomobject]@{ Ok = $true; Targets = $safe.ToArray() } }
    $writable = New-Object System.Collections.Generic.List[object]
    foreach ($c in $safe) {
        $w = Resolve-SujiWritable -Env $Env -Candidate $c
        if ($null -ne $w) { $writable.Add($w) }
    }
    return [pscustomobject]@{ Ok = $true; Targets = $writable.ToArray() }
}

function Test-SujiUnderSystemDirs {
    param([hashtable]$Env, [string]$Path)
    foreach ($root in @($Env.ProgramFiles, $Env.ProgramFilesX86, $Env.ProgramData)) {
        if ($root -and (Test-SujiInside -Path $Path -Root $root)) { return $true }
    }
    return $false
}

# Running as administrator is not needed and risky: warn and ask; with -Yes,
# only allow folders under Program Files or ProgramData.
function Confirm-SujiElevation {
    param([hashtable]$Env, [object[]]$Targets)
    if (-not $Env.IsAdmin) { return $true }
    Write-SujiWarn (T 'admin_warn')
    if ($script:NonInteractive) {
        $bad = @($Targets | Where-Object { -not (Test-SujiUnderSystemDirs -Env $Env -Path $_.ConfigDir) } | ForEach-Object { $_.ConfigDir })
        if ($bad.Count -gt 0) {
            Write-SujiError (T 'admin_refused' @(([string]::Join('; ', $bad))))
            return $false
        }
        return $true
    }
    return (Confirm-Suji -Question (T 'admin_confirm') -Default $false)
}

function Invoke-SujiMain {
    param([string]$Action, [string[]]$Target, [bool]$Yes, [hashtable]$Environment = $null)
    $script:NonInteractive = $Yes
    if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        Write-SujiError (T 'old_ps')
        return 2
    }
    # powershell -File passes "-Target a,b" as one string: ';' separates folders.
    $paths = @($Target | ForEach-Object { $_ -split ';' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 } catch { }
    }

    Write-SujiInfo (T 'title' @($script:SujiVersion))
    if (-not $Action) {
        if ($Yes) { Write-SujiError (T 'usage_yes_action'); return 2 }
        while (-not $Action) {
            Write-SujiInfo (T 'menu')
            $answer = Read-SujiLine (T 'menu_prompt')
            if ($null -eq $answer) { return 0 }
            switch ($answer.Trim()) {
                '1' { $Action = 'install' }
                '2' { $Action = 'uninstall' }
                '0' { Write-SujiInfo (T 'cancelled'); return 0 }
                default { Write-SujiWarn (T 'invalid') }
            }
        }
    }

    if ($null -eq $Environment) { $Environment = New-SujiEnvironment }
    $script:SujiElevated = [bool]$Environment.IsAdmin
    $selection = Select-SujiTargets -Env $Environment -Mode $Action -Paths $paths
    if (-not $selection.Ok) { return 2 }
    $targets = @($selection.Targets)
    if ($targets.Count -eq 0) {
        if ($Yes) { Write-SujiError (T 'usage_none'); return 2 }
        Write-SujiInfo (T 'cancelled')
        return 0
    }
    if (-not (Confirm-SujiElevation -Env $Environment -Targets $targets)) {
        if ($Yes) { return 2 }
        Write-SujiInfo (T 'cancelled')
        return 0
    }

    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $ok = 0
    $temp = $null
    try {
        # Everything is downloaded and checked before any folder is touched.
        if ($Action -eq 'install') {
            $temp = New-SujiTempDir
            try {
                $source = Get-SujiSource -TempDir $temp
                $thumbFile = ''
                if (@($targets | Where-Object { -not (Test-SujiThumbfastUpToDate (Get-SujiFullPath $_.ConfigDir)) }).Count -gt 0) {
                    $thumbFile = Join-SujiPath $temp 'thumbfast.lua'
                    Write-SujiInfo ('thumbfast: ' + $script:ThumbfastUrl)
                    Invoke-SujiVerifiedDownload -Url $script:ThumbfastUrl -Sha256 $script:ThumbfastSha256 -OutFile $thumbFile
                }
            }
            catch {
                Write-SujiError (T 'error_generic' @($_.Exception.Message))
                return 1
            }
        }
        foreach ($t in $targets) {
            try {
                if ($Action -eq 'install') { Install-SujiTarget -Candidate $t -Source $source -ThumbfastFile $thumbFile -Stamp $stamp }
                else { Uninstall-SujiTarget -Candidate $t -Stamp $stamp }
                $ok++
            }
            catch { Write-SujiError (T 'target_failed' @($t.ConfigDir, $_.Exception.Message)) }
        }
    }
    finally {
        if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-SujiInfo ''
    $last = T 'summary' @($ok, $targets.Count)
    if ($ok -gt 0) { $last += ' ' + (T 'restart') }
    Write-SujiInfo $last
    if ($ok -lt $targets.Count) { return 1 }
    return 0
}

# Tests load the functions above without running the installer.
if ($env:SUJI_INSTALL_TEST) { return }

# Windows PowerShell 5.1 may need TLS 1.2 switched on for GitHub (see
# Invoke-SujiMain); that setting is process-wide, so it is put back afterwards.
$savedTls = $null
try { $savedTls = [System.Net.ServicePointManager]::SecurityProtocol } catch { }
try { $code = Invoke-SujiMain -Action $Action -Target $Target -Yes ([bool]$Yes) }
finally {
    if ($null -ne $savedTls) { try { [System.Net.ServicePointManager]::SecurityProtocol = $savedTls } catch { } }
}
# { }.File is the file this script block was read from: set with -File or
# .\suji.ps1, empty through iex or [scriptblock]::Create. Only a file run may
# exit: through iex, exit would close the user's PowerShell window.
if ({ }.File) { exit $code }
$global:LASTEXITCODE = $code
} -Action $SujiAction -Target $SujiTarget -Yes:$SujiYes
}
catch {
    # An unexpected error that got this far. Same rule as above: exit only when
    # running from a file. No new variables here: this runs in the caller's scope.
    Write-Host ('suji: ' + $_.Exception.Message) -ForegroundColor Red
    if ({ }.File) { exit 1 }
    $global:LASTEXITCODE = 1
}
finally {
    # Through iex the parameters above are variables of the caller's session.
    if (-not { }.File) { Remove-Variable -Name SujiAction, SujiTarget, SujiYes, SujiNoMenu -Scope 0 -ErrorAction SilentlyContinue }
}
