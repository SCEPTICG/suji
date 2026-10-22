#!/usr/bin/env bash
# shellcheck shell=bash
#
# suji installer for macOS and Linux (mpv).
#
# Installs, updates or removes suji (https://github.com/SCEPTICG/suji), together
# with thumbfast for the timeline thumbnails, in an mpv config folder. It does
# the same as install/suji.ps1 on Windows, with the same messages.
#
# From a published release (this file then downloads that release's suji.zip
# and checks its SHA256 before using it):
#     curl -fsSL https://github.com/SCEPTICG/suji/releases/latest/download/suji.sh | bash
#     curl -fsSL https://github.com/SCEPTICG/suji/releases/latest/download/suji.sh | bash -s -- --action uninstall
# From a copy of the repository (the suji files then come from that copy):
#     bash install/suji.sh
#
# Options:
#     --action install|uninstall   skip the first menu
#     --target <folder>            mpv config folder to work on (repeat it for several)
#     --yes                        no questions: take the default answer to everything
#     --help
#
# Questions are read from the terminal (/dev/tty), also when this file comes
# through a pipe as above. With no terminal at all it runs as with --yes: the
# default (safe) answer to every question, and install when no action is given.
#
# A folder with hikari in it is never touched: hikari installs suji itself.
#
# Exit codes: 0 done (or cancelled), 1 at least one folder failed, 2 wrong usage
# or nothing to work on.
#
# Written for the bash 3.2 of macOS and for BSD and GNU tools alike: no
# associative arrays, no sed -i, no GNU-only options. Everything is inside
# functions and the last line calls main, so a download cut short runs nothing.
# No sudo: it only touches the config folder, the backups next to it and a
# temporary folder that it deletes when it ends. Needs bash, curl and unzip.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

suji_defaults() {
    # Release markers. tools/make-release.sh replaces these three lines, matched
    # whole and exactly once each, with the version, the URL of that release's
    # suji.zip and its SHA256. Keep them exactly as they are. In the repository
    # they stay empty: the suji files then come from the repository copy this
    # file sits in, and run on its own (curl | bash) it says there is no release.
    SUJI_VERSION='dev'
    SUJI_URL=''
    SUJI_SHA256=''

    # thumbfast: a fixed version, verified by SHA256 (the same as install/suji.ps1
    # and the hikari installers).
    THUMBFAST_URL='https://raw.githubusercontent.com/po5/thumbfast/0f711de3138c9bd6718209d819ac54022c23ded2/thumbfast.lua'
    THUMBFAST_SHA256='a3d08e71eae8b892f6cd39f9593ea219768e709312d176bca883841b156448bf'

    BLOCK_BEGIN='# >>> suji (managed block, do not edit) >>>'
    BLOCK_END='# <<< suji (managed block, do not edit) <<<'
    MPV_CONF_LINES=('osc=no')
    BACKUP_KEEP=3
    RECORD_NAME='suji-installed.txt'
    RECORD_HEADER='# Written by the suji installer. Used to update and uninstall; do not edit.'
    DISABLED_DIR='scripts-apartados-suji'
    # What the backup copies, when it is there: only what the installer can
    # change (and whatever it sets aside).
    BACKUP_ITEMS=(
        'mpv.conf' 'suji-installed.txt' 'scripts/suji' 'scripts/thumbfast.lua'
        'script-opts/thumbfast.conf' 'script-opts/suji.conf' 'suji-size' 'scripts-apartados-suji'
    )
    MPV_CONFIG_FILES=('mpv.conf' 'input.conf')
    MPV_CONFIG_DIRS=('scripts' 'script-opts')
    # Scripts that replace mpv's on-screen controller and clash with suji (file
    # names in scripts/, case-insensitive), as the hikari installer lists them,
    # plus uosc (scripts/uosc or scripts/uosc.lua). The fonts of some of them.
    CONFLICT_PATTERNS=(
        'osc.lua' 'osc_*.lua' 'osc-*.lua' 'oscc.lua' 'oscc_*.lua' 'oscc-*.lua'
        'modernx*.lua' 'modernz*.lua' 'mordenx*.lua' 'mpv-osc-*.lua'
        'mfpbar.lua' 'mpv_thumbnail_script_client_osc*.lua' 'uosc.lua'
    )
    CONFLICT_FONT_PATTERNS=('modernx*' 'modernz*' 'mordenx*')
}

# thumbfast.conf as suji writes it when there is none (the same as install/suji.ps1).
thumbfast_conf_text() {
    cat <<'EOF'
# suji settings for thumbfast (https://github.com/po5/thumbfast), which makes the
# timeline thumbnails suji shows. thumbfast itself is not part of suji: the
# installer downloads it. Anything not set here keeps thumbfast's default.

# Thumbnails on network streams too. thumbfast opens a second, hidden mpv with
# its own connection to the stream, so it uses some extra bandwidth.
network=yes

# Decode thumbnails on the GPU instead of the CPU.
hwdec=yes

# Only start the thumbnailer when the timeline is first hovered.
spawn_first=no

# Maximum thumbnail size in pixels (scaled down to fit, scaled up with hidpi).
max_height=200
max_width=200
EOF
}

# ---------------------------------------------------------------------------
# Messages (English and Spanish, the same as install/suji.ps1). %s is replaced
# by the arguments, in order.
# ---------------------------------------------------------------------------

suji_text_en() {
    local s=''
    case $1 in
        title) s='suji installer %s' ;;
        menu) s='1) Install or update\n2) Uninstall\n0) Exit' ;;
        menu_prompt) s='Choose an option' ;;
        invalid) s='Invalid option.' ;;
        found_header) s='Config folders found:' ;;
        found_header_uninst) s='Folders with suji:' ;;
        cand_exe) s='     Player: %s' ;;
        cand_config) s='     Config: %s' ;;
        kind_folder) s='config folder' ;;
        kind_flatpak) s='mpv (Flatpak)' ;;
        kind_snap) s='mpv (Snap)' ;;
        tag_installed) s='[suji %s installed]' ;;
        tag_hikari) s='[hikari: use its installer]' ;;
        tag_readonly) s='[no write permission]' ;;
        tag_new) s='[will be created]' ;;
        opt_other) s='O) Other folder' ;;
        opt_quit) s='0) Exit' ;;
        select_prompt) s='Choose one or more, separated by commas (e.g. 1,3)' ;;
        ask_folder) s='Full path of the mpv config folder (where mpv.conf is or should go)' ;;
        folder_missing) s='The folder %s does not exist and neither does its parent.' ;;
        readonly_warn) s='Cannot write to %s.' ;;
        readonly_skip) s='Skipping %s.' ;;
        none_found) s='mpv was not found. Install it first: https://mpv.io/installation/' ;;
        yes_no_default_yes) s=' [Y/n] ' ;;
        yes_no_default_no) s=' [y/N] ' ;;
        backup_done) s='Backup: %s' ;;
        backup_failed) s='Could not back up %s: %s. Nothing was changed in that folder.' ;;
        backup_pruned) s='Old backup deleted: %s' ;;
        backup_prune_failed) s='Could not delete the old backup %s.' ;;
        link_skipped) s='Not copied to the backup: %s is a symbolic link.' ;;
        conflicts_found) s='These interfaces draw their own controls and clash with suji:' ;;
        conflicts_confirm) s='Move them to %s? Nothing is deleted, and they come back when you uninstall.' ;;
        conflicts_kept) s='Left in place: suji and that interface will both draw controls.' ;;
        moved) s='Moved %s -> %s' ;;
        downloading) s='Downloading %s...' ;;
        download_failed) s='Could not download %s.' ;;
        hash_bad) s='The download of %s does not match its expected SHA256 (expected %s, got %s). Nothing was installed from it.' ;;
        url_bad) s='Refusing to download %s: only HTTPS from GitHub is allowed.' ;;
        release_unpublished) s='This installer has no suji release to install. Download the repository and run install/suji.sh from that copy.' ;;
        source_missing) s='suji files not found in %s.' ;;
        thumbfast_uptodate) s='thumbfast is already installed, unchanged.' ;;
        mpvpath_set) s='thumbfast.conf: mpv_path=%s' ;;
        install_ok) s='suji %s installed in %s.' ;;
        uninstall_ok) s='suji removed from %s.' ;;
        target_failed) s='%s: %s' ;;
        restore_hint) s='Your previous files are in %s.' ;;
        summary) s='Done: %s of %s folders.' ;;
        restart) s='Restart the player to see the changes.' ;;
        ask_remove_thumbfast) s='Remove thumbfast (the thumbnails) too?' ;;
        ask_delete_settings) s='Delete your suji settings and saved size (script-opts/suji.conf, suji-size)?' ;;
        ask_restore) s='Move back the interfaces suji set aside (%s)?' ;;
        restore_skipped) s='%s not moved back: %s already exists.' ;;
        nothing_to_uninstall) s='suji does not seem to be installed in any detected folder.' ;;
        usage_many) s='Several folders found; without questions, choose with --target:' ;;
        usage_none) s='Nothing to work on.' ;;
        malformed_block) s='%s has an incomplete or repeated suji block (a start or end marker is missing or repeated). Fix it by hand and run the installer again.' ;;
        outside_target) s='Refusing to touch %s: it is outside %s.' ;;
        cancelled) s='Cancelled.' ;;
        path_bad) s='%s is not a valid folder path.' ;;
        target_root) s='Refusing %s: the root folder or your home folder is not an mpv config folder.' ;;
        not_mpv_folder) s='%s does not look like an mpv config folder: no mpv.conf, input.conf, scripts or script-opts in it.' ;;
        not_mpv_confirm) s='Use it anyway?' ;;
        not_mpv_yes) s='Without questions such a folder is refused: run it in a terminal to confirm it.' ;;
        hikari_here) s='%s has hikari: nothing is changed there. hikari installs suji itself: use the hikari installer with -Interface suji.' ;;
        root_warn) s='The installer is running as root (sudo). It does not need it, and what it creates would belong to root.' ;;
        root_confirm) s='Continue as root?' ;;
        root_refused) s='As root and without questions nothing is done: run it as your own user, without sudo.' ;;
        record_bad) s='Ignored an invalid entry in suji-installed.txt: %s' ;;
        unsupported_os) s='This installer is for macOS and Linux (this system is %s). On Windows use suji.ps1: see the README.' ;;
        missing_tool) s='%s is needed and was not found.' ;;
        bad_option) s='Unknown option: %s (see --help).' ;;
        no_input) s='No terminal to ask on: every question takes its default answer.' ;;
        usage) s='Usage: suji.sh [--action install|uninstall] [--target <folder>]... [--yes]' ;;
    esac
    printf '%s' "$s"
}

suji_text_es() {
    local s=''
    case $1 in
        title) s='Instalador de suji %s' ;;
        menu) s='1) Instalar o actualizar\n2) Desinstalar\n0) Salir' ;;
        menu_prompt) s='Elige una opción' ;;
        invalid) s='Opción no válida.' ;;
        found_header) s='Carpetas de configuración encontradas:' ;;
        found_header_uninst) s='Carpetas con suji:' ;;
        cand_exe) s='     Reproductor: %s' ;;
        cand_config) s='     Configuración: %s' ;;
        kind_folder) s='carpeta de configuración' ;;
        kind_flatpak) s='mpv (Flatpak)' ;;
        kind_snap) s='mpv (Snap)' ;;
        tag_installed) s='[suji %s instalado]' ;;
        tag_hikari) s='[hikari: usa su instalador]' ;;
        tag_readonly) s='[sin permiso de escritura]' ;;
        tag_new) s='[se creará]' ;;
        opt_other) s='O) Otra carpeta' ;;
        opt_quit) s='0) Salir' ;;
        select_prompt) s='Elige uno o varios separados por comas (p. ej. 1,3)' ;;
        ask_folder) s='Ruta completa de la carpeta de configuración de mpv (donde está o irá mpv.conf)' ;;
        folder_missing) s='No existe la carpeta %s ni la que la contiene.' ;;
        readonly_warn) s='No se puede escribir en %s.' ;;
        readonly_skip) s='Se omite %s.' ;;
        none_found) s='No se ha encontrado mpv. Instálalo primero: https://mpv.io/installation/' ;;
        yes_no_default_yes) s=' [S/n] ' ;;
        yes_no_default_no) s=' [s/N] ' ;;
        backup_done) s='Copia de seguridad: %s' ;;
        backup_failed) s='No se ha podido hacer la copia de seguridad de %s: %s. No se ha cambiado nada en esa carpeta.' ;;
        backup_pruned) s='Borrada la copia de seguridad antigua %s' ;;
        backup_prune_failed) s='No se ha podido borrar la copia de seguridad antigua %s.' ;;
        link_skipped) s='No se copia a la copia de seguridad: %s es un enlace simbólico.' ;;
        conflicts_found) s='Estas interfaces dibujan sus propios controles y chocan con suji:' ;;
        conflicts_confirm) s='¿Moverlas a %s? No se borra nada y vuelven a su sitio al desinstalar.' ;;
        conflicts_kept) s='Se quedan donde están: suji y esa interfaz dibujarán controles a la vez.' ;;
        moved) s='Movido %s -> %s' ;;
        downloading) s='Descargando %s...' ;;
        download_failed) s='No se ha podido descargar %s.' ;;
        hash_bad) s='La descarga de %s no coincide con su SHA256 esperado (esperado %s, obtenido %s). No se ha instalado nada de ella.' ;;
        url_bad) s='No se descarga %s: solo se admite HTTPS desde GitHub.' ;;
        release_unpublished) s='Este instalador no tiene ninguna versión de suji que instalar. Descarga el repositorio y ejecuta install/suji.sh desde esa copia.' ;;
        source_missing) s='No se encuentran los ficheros de suji en %s.' ;;
        thumbfast_uptodate) s='thumbfast ya está instalado y sin cambios.' ;;
        mpvpath_set) s='thumbfast.conf: mpv_path=%s' ;;
        install_ok) s='suji %s instalado en %s.' ;;
        uninstall_ok) s='suji quitado de %s.' ;;
        target_failed) s='%s: %s' ;;
        restore_hint) s='Tus ficheros de antes están en %s.' ;;
        summary) s='Hecho: %s de %s carpetas.' ;;
        restart) s='Reinicia el reproductor para ver los cambios.' ;;
        ask_remove_thumbfast) s='¿Quitar también thumbfast (las miniaturas)?' ;;
        ask_delete_settings) s='¿Borrar tus ajustes de suji y el tamaño guardado (script-opts/suji.conf, suji-size)?' ;;
        ask_restore) s='¿Devolver a su sitio las interfaces que suji apartó (%s)?' ;;
        restore_skipped) s='%s no se devuelve: ya existe %s.' ;;
        nothing_to_uninstall) s='No parece que suji esté instalado en ninguna de las carpetas encontradas.' ;;
        usage_many) s='Hay varias carpetas; sin preguntas, elige con --target:' ;;
        usage_none) s='No hay nada sobre lo que trabajar.' ;;
        malformed_block) s='%s tiene un bloque de suji incompleto o repetido (falta o sobra una marca de inicio o de fin). Arréglalo a mano y vuelve a ejecutar el instalador.' ;;
        outside_target) s='No se toca %s: está fuera de %s.' ;;
        cancelled) s='Cancelado.' ;;
        path_bad) s='%s no es una ruta de carpeta válida.' ;;
        target_root) s='No se usa %s: la carpeta raíz o tu carpeta personal no son una carpeta de configuración de mpv.' ;;
        not_mpv_folder) s='%s no parece una carpeta de configuración de mpv: no tiene mpv.conf, input.conf, scripts ni script-opts.' ;;
        not_mpv_confirm) s='¿Usarla de todos modos?' ;;
        not_mpv_yes) s='Sin preguntas se rechaza una carpeta así: ejecútalo en un terminal para confirmarla.' ;;
        hikari_here) s='%s tiene hikari: no se cambia nada ahí. hikari ya instala suji: usa el instalador de hikari con -Interface suji.' ;;
        root_warn) s='El instalador se está ejecutando como root (sudo). No le hace falta, y lo que cree pertenecería a root.' ;;
        root_confirm) s='¿Seguir como root?' ;;
        root_refused) s='Como root y sin preguntas no se hace nada: ejecútalo con tu usuario, sin sudo.' ;;
        record_bad) s='Se ignora una entrada no válida de suji-installed.txt: %s' ;;
        unsupported_os) s='Este instalador es para macOS y Linux (este sistema es %s). En Windows usa suji.ps1: mira el README.' ;;
        missing_tool) s='Hace falta %s y no se encuentra.' ;;
        bad_option) s='Opción desconocida: %s (mira --help).' ;;
        no_input) s='No hay terminal en el que preguntar: cada pregunta toma su respuesta por defecto.' ;;
        usage) s='Uso: suji.sh [--action install|uninstall] [--target <carpeta>]... [--yes]' ;;
    esac
    printf '%s' "$s"
}

# T <key> [args...]: the message in the current language, with %s replaced.
T() {
    local key=$1 fmt
    shift
    if [ "$SUJI_LANG_CODE" = es ]; then fmt=$(suji_text_es "$key"); else fmt=$(suji_text_en "$key"); fi
    [ -n "$fmt" ] || fmt=$key
    # shellcheck disable=SC2059 # the messages above are the format strings.
    printf -- "$fmt" "$@"
}

# The system's preferred languages on macOS ("es-ES", ...), one per line.
suji_apple_languages() { defaults read -g AppleLanguages 2>/dev/null; }

# es when LC_ALL, LC_MESSAGES or LANG (the first one set, as the C library
# does) starts with "es"; en otherwise. On macOS the system language comes
# before LANG: terminals often set LANG=en_US.UTF-8 on a Mac set to Spanish.
# SUJI_LANG=es|en wins (tests).
suji_language() {
    case ${SUJI_LANG:-} in es | en) printf '%s' "$SUJI_LANG"; return 0 ;; esac
    local v=${LC_ALL:-} first
    [ -n "$v" ] || v=${LC_MESSAGES:-}
    if [ -z "$v" ] && [ "$(suji_uname)" = Darwin ]; then
        # First entry of the list: the line after "(", without blanks or quotes.
        first=$(suji_apple_languages | tr -d ' \t"' | grep -v '^($' | head -n 1)
        case $first in es*) printf es; return 0 ;; ?*) printf en; return 0 ;; esac
    fi
    [ -n "$v" ] || v=${LANG:-}
    case $v in es*) printf es ;; *) printf en ;; esac
}

# ---------------------------------------------------------------------------
# Output and input
# ---------------------------------------------------------------------------

info() { printf '%s\n' "$1"; }
warn() { printf '%s\n' "$1"; }
error() { printf '%s\n' "$1" >&2; }

# $1 without control characters: C0, DEL and, written as UTF-8, C1 (U+0080 to
# U+009F, which some terminals take as escape sequences too). For anything
# shown that may come from outside: paths, the record.
clean_text() {
    local c1
    c1=$(printf '\302[\200-\237]')
    # C0 first: removing it could otherwise join the bytes of a C1 back together.
    printf '%s' "$1" | LC_ALL=C tr -d '[:cntrl:]' | LC_ALL=C sed "s/$c1//g"
}

# Replaceable in tests: the terminal questions are read from.
suji_tty_path() { printf '%s' /dev/tty; }

# Where answers come from: stdin when it is a terminal, otherwise the terminal
# itself (curl ... | bash: stdin is the script), opened as fd 3. Without one,
# every question takes its default answer.
io_setup() {
    HAVE_INPUT=0
    if [ -t 0 ]; then
        exec 3<&0
        HAVE_INPUT=1
    else
        local tty
        tty=$(suji_tty_path)
        if [ -n "$tty" ] && (: <"$tty") 2>/dev/null; then
            if { exec 3<"$tty"; } 2>/dev/null; then HAVE_INPUT=1; fi
        fi
    fi
}

# Reads a line into REPLY_LINE (fails at the end of the input).
read_line() {
    REPLY_LINE=''
    printf '%s: ' "$1"
    if [ "$HAVE_INPUT" != 1 ]; then printf '\n'; return 1; fi
    if IFS= read -r REPLY_LINE <&3; then
        [ -t 3 ] || printf '%s\n' "$REPLY_LINE"
        return 0
    fi
    printf '\n'
    [ -n "$REPLY_LINE" ]
}

# ASCII only, byte by byte: with LC_ALL=C, BSD tr does not complain about
# bytes that are not UTF-8.
lower() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }

# Sets TRIMMED to $1 without leading and trailing blanks.
trim() {
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    s=${s%"${s##*[![:space:]]}"}
    TRIMMED=$s
}

# confirm <question> <default yes|no>: 0 for yes, 1 for no. Without questions
# (--yes or no terminal) the default answer.
confirm() {
    local question=$1 default=$2 answer suffix
    if [ "$NONINTERACTIVE" = 1 ]; then [ "$default" = yes ]; return; fi
    if [ "$default" = yes ]; then suffix=$(T yes_no_default_yes); else suffix=$(T yes_no_default_no); fi
    while :; do
        printf '%s' "$question$suffix"
        REPLY_LINE=''
        if ! IFS= read -r REPLY_LINE <&3 && [ -z "$REPLY_LINE" ]; then
            printf '\n'
            [ "$default" = yes ]
            return
        fi
        [ -t 3 ] || printf '%s\n' "$REPLY_LINE"
        trim "$REPLY_LINE"
        answer=$(lower "$TRIMMED")
        case $answer in
            '') [ "$default" = yes ]; return ;;
            s | si | sí | y | yes) return 0 ;;
            n | no) return 1 ;;
        esac
        warn "$(T invalid)"
    done
}

# ---------------------------------------------------------------------------
# Paths and files
# ---------------------------------------------------------------------------

# Absolute, lexically normalised path (~ expanded, . and .. resolved, no
# trailing /). Links are not resolved. Fails for an empty path.
abs_path() {
    local p=$1 out='' seg
    case $p in '') return 1 ;; \~) p=$HOME ;; \~/*) p=$HOME/${p#\~/} ;; esac
    case $p in /*) ;; *) p=$PWD/$p ;; esac
    local IFS=/
    local parts stack
    read -r -a parts <<<"$p"
    stack=()
    for seg in ${parts[@]+"${parts[@]}"}; do
        case $seg in
            '' | .) ;;
            ..) [ "${#stack[@]}" -gt 0 ] && unset "stack[$((${#stack[@]} - 1))]" ;;
            *) stack[${#stack[@]}]=$seg ;;
        esac
    done
    for seg in ${stack[@]+"${stack[@]}"}; do out="$out/$seg"; done
    printf '%s' "${out:-/}"
}

# True when $1 is strictly inside $2 (never $2 itself).
is_inside() {
    local p r
    p=$(abs_path "$1") || return 1
    r=$(abs_path "$2") || return 1
    [ "$r" = / ] && r=''
    case $p in "$r"/?*) return 0 ;; esac
    return 1
}

# Deletes a file, link or folder inside $2. A link is removed as a link.
remove_item() {
    local p=$1 root=$2
    if ! is_inside "$p" "$root"; then
        SUJI_ERR=$(T outside_target "$(clean_text "$p")" "$(clean_text "$root")")
        return 1
    fi
    if [ -L "$p" ] || [ -f "$p" ]; then
        rm -f "$p" || return 1
    elif [ -d "$p" ]; then
        rm -rf "$p" || return 1
    fi
    return 0
}

# Path of $1 relative to the folder $2 ('/'-separated).
rel_path() {
    local p r
    p=$(abs_path "$1")
    r=$(abs_path "$2")
    printf '%s' "${p#"$r"/}"
}

# Can the folder (or, if missing, its nearest existing parent) be written to?
dir_writable() {
    local p=$1 parent
    while [ ! -d "$p" ]; do
        parent=${p%/*}
        [ -n "$parent" ] || parent=/
        [ "$parent" != "$p" ] || return 1
        p=$parent
    done
    [ -w "$p" ]
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# Writes stdin to $1 through a temporary file next to it and a rename, so a
# failure never leaves half a file. The file keeps its permissions (a new one
# gets the usual ones for the umask); a link is written through (dotfile
# managers link mpv.conf), not replaced.
write_file() {
    local path=$1 tmp
    tmp=$(mktemp "$1.suji-tmp.XXXXXX") || return 1
    if [ -f "$path" ]; then
        cp -p "$path" "$tmp" 2>/dev/null || :
    else
        chmod "$(printf '%o' $((0666 & ~0$(umask))))" "$tmp" 2>/dev/null || :
    fi
    if ! cat >"$tmp"; then rm -f "$tmp"; return 1; fi
    if [ -L "$path" ]; then
        cat "$tmp" >"$path" || { rm -f "$tmp"; return 1; }
        rm -f "$tmp"
    else
        mv -f "$tmp" "$path" || { rm -f "$tmp"; return 1; }
    fi
}

# The lines of a text file: F_LINE (content, without line break), F_EOL (crlf,
# lf, or empty for a last line without line break) and F_COUNT. Bytes are kept
# as they are, so writing it back gives the same file.
load_file() {
    F_LINE=()
    F_EOL=()
    F_COUNT=0
    [ -f "$1" ] || return 0
    local line n=0
    while :; do
        if IFS= read -r line; then
            case $line in
                *$'\r') F_LINE[n]=${line%$'\r'}; F_EOL[n]=crlf ;;
                *) F_LINE[n]=$line; F_EOL[n]=lf ;;
            esac
            n=$((n + 1))
        else
            if [ -n "$line" ]; then F_LINE[n]=$line; F_EOL[n]=''; n=$((n + 1)); fi
            break
        fi
    done <"$1"
    F_COUNT=$n
}

print_lines() {
    local i=0
    while [ "$i" -lt "$F_COUNT" ]; do
        case ${F_EOL[i]} in
            crlf) printf '%s\r\n' "${F_LINE[i]}" ;;
            lf) printf '%s\n' "${F_LINE[i]}" ;;
            *) printf '%s' "${F_LINE[i]}" ;;
        esac
        i=$((i + 1))
    done
}

save_file() { print_lines | write_file "$1"; }

# Line break used for new lines: CRLF when the file has any, LF otherwise.
file_eol() {
    local i=0
    while [ "$i" -lt "$F_COUNT" ]; do
        [ "${F_EOL[i]}" = crlf ] && { printf crlf; return; }
        i=$((i + 1))
    done
    printf lf
}

# ---------------------------------------------------------------------------
# The managed block in mpv.conf
# ---------------------------------------------------------------------------

BOM=$'\357\273\277'

# Sets BLOCK_BEGIN_AT and BLOCK_END_AT (-1 when there is no block) in the
# loaded file. Fails, with SUJI_ERR set, when the markers do not pair up.
find_block() {
    local i=0 line
    BLOCK_BEGIN_AT=-1
    BLOCK_END_AT=-1
    while [ "$i" -lt "$F_COUNT" ]; do
        line=${F_LINE[i]}
        [ "$i" != 0 ] || line=${line#"$BOM"}
        trim "$line"
        if [ "$TRIMMED" = "$BLOCK_BEGIN" ]; then
            if [ "$BLOCK_BEGIN_AT" -ge 0 ]; then SUJI_ERR=$(T malformed_block mpv.conf); return 1; fi
            BLOCK_BEGIN_AT=$i
        elif [ "$TRIMMED" = "$BLOCK_END" ]; then
            if [ "$BLOCK_BEGIN_AT" -lt 0 ] || [ "$BLOCK_END_AT" -ge 0 ]; then SUJI_ERR=$(T malformed_block mpv.conf); return 1; fi
            BLOCK_END_AT=$i
        fi
        i=$((i + 1))
    done
    if [ "$BLOCK_BEGIN_AT" -ge 0 ] && [ "$BLOCK_END_AT" -lt 0 ]; then SUJI_ERR=$(T malformed_block mpv.conf); return 1; fi
    return 0
}

# Keeps only the lines of the loaded file outside the block found last. A
# byte order mark at the start of the block moves to the line after it.
drop_block() {
    [ "$BLOCK_BEGIN_AT" -ge 0 ] || return 0
    local i=0 n=0 bom='' lines eols
    lines=()
    eols=()
    case ${F_LINE[BLOCK_BEGIN_AT]} in "$BOM"*) bom=$BOM ;; esac
    while [ "$i" -lt "$F_COUNT" ]; do
        if [ "$i" -lt "$BLOCK_BEGIN_AT" ] || [ "$i" -gt "$BLOCK_END_AT" ]; then
            lines[n]=${F_LINE[i]}
            eols[n]=${F_EOL[i]}
            if [ -n "$bom" ] && [ "$i" -gt "$BLOCK_END_AT" ]; then lines[n]=$bom${lines[n]}; bom=''; fi
            n=$((n + 1))
        fi
        i=$((i + 1))
    done
    F_LINE=(${lines[@]+"${lines[@]}"})
    F_EOL=(${eols[@]+"${eols[@]}"})
    F_COUNT=$n
}

# Puts the suji block in mpv.conf (created when missing): in place of the old
# one, or at the very start, where it can never fall inside a [profile].
update_mpv_conf() {
    local path=$1 eol i n bom='' new lines eols
    load_file "$path"
    eol=$(file_eol)
    find_block || return 1
    if [ "$BLOCK_BEGIN_AT" -ge 0 ]; then
        case ${F_LINE[BLOCK_BEGIN_AT]} in "$BOM"*) bom=$BOM ;; esac
        n=$BLOCK_BEGIN_AT
        drop_block
        # drop_block moved the mark to the next line: it goes back to the block.
        if [ -n "$bom" ] && [ "$n" -lt "$F_COUNT" ]; then F_LINE[n]=${F_LINE[n]#"$BOM"}; fi
    else
        n=0
        if [ "$F_COUNT" -gt 0 ]; then
            case ${F_LINE[0]} in "$BOM"*) bom=$BOM; F_LINE[0]=${F_LINE[0]#"$BOM"} ;; esac
        fi
    fi
    new=("$bom$BLOCK_BEGIN" "${MPV_CONF_LINES[@]}" "$BLOCK_END")
    # Lines 0..n-1 as they are, the block, then the rest.
    lines=()
    eols=()
    i=0
    while [ "$i" -lt "$n" ]; do lines[i]=${F_LINE[i]}; eols[i]=${F_EOL[i]}; i=$((i + 1)); done
    for i in "${new[@]}"; do lines[${#lines[@]}]=$i; eols[${#eols[@]}]=$eol; done
    i=$n
    while [ "$i" -lt "$F_COUNT" ]; do
        lines[${#lines[@]}]=${F_LINE[i]}
        eols[${#eols[@]}]=${F_EOL[i]}
        i=$((i + 1))
    done
    F_LINE=("${lines[@]}")
    F_EOL=("${eols[@]}")
    F_COUNT=${#F_LINE[@]}
    # A file that did not end in a line break still does not.
    save_file "$path"
}

# Removes the block from mpv.conf. $2 = 1: suji created the file, so it goes
# when nothing but blank lines is left.
remove_mpv_block() {
    local path=$1 created=$2 i=0
    [ -f "$path" ] || return 0
    load_file "$path"
    find_block || return 1
    [ "$BLOCK_BEGIN_AT" -ge 0 ] || return 0
    drop_block
    if [ "$created" = 1 ]; then
        while [ "$i" -lt "$F_COUNT" ]; do
            trim "${F_LINE[i]}"
            [ -z "$TRIMMED" ] || break
            i=$((i + 1))
        done
        if [ "$i" -eq "$F_COUNT" ]; then remove_item "$path" "$CFG"; return; fi
    fi
    save_file "$path"
}

# ---------------------------------------------------------------------------
# Installer record (suji-installed.txt, the same format as install/suji.ps1)
# ---------------------------------------------------------------------------

# The record can be edited by anyone, so its paths are checked before use:
# relative, '/'-separated, no '.', '..' or empty segment, no backslash, colon,
# wildcard or control character.
record_path_ok() {
    local rel=$1 seg segs
    [ -n "$rel" ] || return 1
    case $rel in /* | */ | *\\* | *:* | *'*'* | *'?'* | *'['* | *'"'* | *'<'* | *'>'* | *'|'* | *[[:cntrl:]]*) return 1 ;; esac
    local IFS=/
    read -r -a segs <<<"$rel"
    for seg in ${segs[@]+"${segs[@]}"}; do
        case $seg in '' | . | ..) return 1 ;; esac
    done
    return 0
}

# "moved|original", both clean record paths.
pair_ok() {
    case $1 in *'|'*'|'*) return 1 ;; *'|'*) ;; *) return 1 ;; esac
    record_path_ok "${1%%|*}" && record_path_ok "${1#*|}"
}

# Reads the record of folder $1 (fails when there is none): REC_KEYS/REC_VALS
# and REC_DISABLED. $2 = 1: no warnings for bad entries.
read_record() {
    REC_KEYS=(); REC_VALS=(); REC_DISABLED=()
    local path="$1/$RECORD_NAME" quiet=${2:-0} line key value i=0
    [ -f "$path" ] || return 1
    load_file "$path"
    while [ "$i" -lt "$F_COUNT" ]; do
        line=${F_LINE[i]}
        i=$((i + 1))
        trim "$line"
        case $TRIMMED in '#'* | '') continue ;; *=*) ;; *) continue ;; esac
        trim "${line%%=*}"
        key=$TRIMMED
        trim "${line#*=}"
        value=$TRIMMED
        if [ "$key" = disabled ]; then
            if pair_ok "$value"; then REC_DISABLED[${#REC_DISABLED[@]}]=$value
            elif [ "$quiet" != 1 ]; then warn "$(T record_bad "$(clean_text "$line")")"; fi
        else
            REC_KEYS[${#REC_KEYS[@]}]=$key
            REC_VALS[${#REC_VALS[@]}]=$value
        fi
    done
    return 0
}

# rec_get <key>: REC_VALUE, and success when the record has that key.
rec_get() {
    local i=${#REC_KEYS[@]}
    REC_VALUE=''
    while [ "$i" -gt 0 ]; do
        i=$((i - 1))
        if [ "${REC_KEYS[i]}" = "$1" ]; then REC_VALUE=${REC_VALS[i]}; return 0; fi
    done
    return 1
}

# prev_flag <record key> <now 1|0>: yes or no, what the first install saw
# (from the record), or what is there now on a first install.
prev_flag() {
    if [ "$FIRST" = 0 ] && rec_get "$1"; then
        if [ "$REC_VALUE" = yes ]; then printf yes; else printf no; fi
        return
    fi
    if [ "$2" = 1 ]; then printf yes; else printf no; fi
}

# Writes the record of CFG from what install_steps knows. Written again after
# each interface it sets aside, so a failure never leaves one unrecorded.
write_record() {
    local d
    {
        printf '%s\n' "$RECORD_HEADER"
        printf 'suji_version=%s\n' "$SUJI_VERSION"
        printf 'installed_at=%s\n' "$(date +%Y-%m-%dT%H:%M:%S)"
        printf 'player=%s\n' "$KIND"
        printf 'thumbfast_preexisting=%s\n' "$THUMB_BEFORE"
        printf 'thumbfast_conf_preexisting=%s\n' "$TCONF_BEFORE"
        printf 'mpv_conf_preexisting=%s\n' "$MPV_BEFORE"
        for d in ${DISABLED[@]+"${DISABLED[@]}"}; do printf 'disabled=%s\n' "$d"; done
    } | write_file "$CFG/$RECORD_NAME"
}

# ---------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------

# Replaceable in tests: downloads $1 to $2. Only HTTPS, TLS 1.2 or newer, at
# most 50 MB; a connection that takes over 20 s to open or stays under 1 KB/s
# for a minute is given up. Redirects (GitHub sends release files elsewhere)
# stay on HTTPS; what arrives is only used if its SHA256 matches.
suji_fetch() {
    curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --max-redirs 5 --max-filesize 52428800 \
        --retry 2 --connect-timeout 20 --speed-limit 1024 --speed-time 60 -o "$2" "$1"
}

# Downloads $1 to $3 and checks its SHA256 ($2). On mismatch the file is
# deleted: nothing unverified is ever used.
verified_download() {
    local url=$1 sha=$2 out=$3 actual
    case $url in
        https://github.com/* | https://raw.githubusercontent.com/*) ;;
        *) SUJI_ERR=$(T url_bad "$(clean_text "$url")"); return 1 ;;
    esac
    [ -n "$sha" ] || { SUJI_ERR=$(T hash_bad "$url" '?' '?'); return 1; }
    info "$(T downloading "$url")"
    rm -f "$out"
    if ! suji_fetch "$url" "$out" || [ ! -f "$out" ]; then
        rm -f "$out"
        SUJI_ERR=$(T download_failed "$url")
        return 1
    fi
    actual=$(sha256_of "$out")
    if [ "$actual" != "$(lower "$sha")" ]; then
        rm -f "$out"
        SUJI_ERR=$(T hash_bad "$url" "$(lower "$sha")" "$actual")
        return 1
    fi
}

# Where the suji files come from: SRC_DIR (a folder with main.lua). A release
# build always uses its own suji.zip, downloaded and checked; the repository
# version uses the suji folder of its copy.
get_source() {
    if [ -n "$SUJI_URL" ]; then
        verified_download "$SUJI_URL" "$SUJI_SHA256" "$TEMP_DIR/suji.zip" || return 1
        mkdir -p "$TEMP_DIR/release" && unzip -q -o "$TEMP_DIR/suji.zip" -d "$TEMP_DIR/release" >/dev/null 2>&1
        SRC_DIR="$TEMP_DIR/release/suji"
        [ -f "$SRC_DIR/main.lua" ] || { SUJI_ERR=$(T source_missing suji.zip); return 1; }
        return 0
    fi
    if [ -n "$SCRIPT_FILE" ] && [ -f "$SCRIPT_FILE" ]; then
        SRC_DIR="$(cd "$(dirname "$SCRIPT_FILE")/.." && pwd)/suji"
        [ -f "$SRC_DIR/main.lua" ] && return 0
    fi
    SUJI_ERR=$(T release_unpublished)
    return 1
}

# Is the thumbfast of folder $1 the pinned file, byte for byte?
thumbfast_uptodate() {
    local f="$1/scripts/thumbfast.lua"
    [ -f "$f" ] && [ ! -L "$f" ] && [ "$(sha256_of "$f")" = "$(lower "$THUMBFAST_SHA256")" ]
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

# Replaceable in tests.
suji_uname() { uname -s; }
suji_flatpak_mpv() {
    [ -d "$HOME/.var/app/io.mpv.Mpv" ] && return 0
    command -v flatpak >/dev/null 2>&1 && flatpak info io.mpv.Mpv >/dev/null 2>&1
}
suji_snap_mpv() { [ -e /snap/bin/mpv ] || [ -d "$HOME/snap/mpv" ]; }

# Absolute path of the mpv binary (not the Flatpak or Snap one), or nothing.
# On macOS also where Homebrew and mpv.app put it: launched from Finder mpv
# does not get the shell's PATH.
suji_find_mpv() {
    local p
    p=$(command -v mpv 2>/dev/null)
    case $p in /snap/*) p='' ;; /*) ;; *) p='' ;; esac
    if [ -n "$p" ] && [ -x "$p" ]; then printf '%s' "$p"; return; fi
    if [ "$OS" = Darwin ]; then
        for p in /opt/homebrew/bin/mpv /usr/local/bin/mpv /opt/local/bin/mpv /Applications/mpv.app/Contents/MacOS/mpv \
            "$HOME/Applications/mpv.app/Contents/MacOS/mpv"; do
            if [ -x "$p" ]; then printf '%s' "$p"; return; fi
        done
    else
        for p in /usr/bin/mpv /usr/local/bin/mpv; do
            if [ -x "$p" ]; then printf '%s' "$p"; return; fi
        done
    fi
}

# Candidates: C_KIND (mpv, flatpak, snap, folder), C_DIR and C_EXE.
add_candidate() {
    local dir i=0
    dir=$(abs_path "$2") || return 0
    while [ "$i" -lt "${#C_DIR[@]}" ]; do
        [ "${C_DIR[i]}" = "$dir" ] && return 0
        i=$((i + 1))
    done
    C_KIND[i]=$1
    C_DIR[i]=$dir
    C_EXE[i]=$3
}

# macOS: $MPV_HOME, or ~/.config/mpv (Homebrew's mpv and mpv.app). Linux: the
# same for a native mpv (with $XDG_CONFIG_HOME), plus the Flatpak and Snap
# folders when those are installed.
find_candidates() {
    C_KIND=(); C_DIR=(); C_EXE=()
    local xdg=${XDG_CONFIG_HOME:-$HOME/.config}
    if [ "$OS" = Darwin ]; then
        add_candidate mpv "${MPV_HOME:-$HOME/.config/mpv}" "$MPV_EXE"
        return 0
    fi
    if [ -n "$MPV_EXE" ] || [ -d "$xdg/mpv" ] || [ -n "${MPV_HOME:-}" ]; then
        add_candidate mpv "${MPV_HOME:-$xdg/mpv}" "$MPV_EXE"
    fi
    if suji_flatpak_mpv; then add_candidate flatpak "$HOME/.var/app/io.mpv.Mpv/config/mpv" ''; fi
    if suji_snap_mpv; then add_candidate snap "$HOME/snap/mpv/current/.config/mpv" ''; fi
    return 0
}

kind_label() {
    case $1 in
        flatpak) T kind_flatpak ;;
        snap) T kind_snap ;;
        folder) T kind_folder ;;
        *) printf mpv ;;
    esac
}

# hikari (or sosc, its name before v0.3.0) is installed in folder $1, as the
# hikari installer itself recognises it.
hikari_present() {
    local f
    [ -e "$1/hikari-installed.txt" ] || [ -e "$1/sosc-installed.txt" ] && return 0
    for f in "$1"/scripts/hikari-*.lua; do [ -f "$f" ] && return 0; done
    return 1
}

suji_present() { [ -f "$1/$RECORD_NAME" ] || [ -e "$1/scripts/suji" ] || [ -L "$1/scripts/suji" ]; }

# Tags of a candidate: installed (version), hikari, read-only, new.
candidate_tags() {
    local dir=${C_DIR[$1]} tags=''
    if hikari_present "$dir"; then
        tags=$(T tag_hikari)
    elif read_record "$dir" 1; then
        rec_get suji_version
        tags=$(T tag_installed "$(clean_text "$REC_VALUE")")
    fi
    dir_writable "$dir" || tags="$tags${tags:+ }$(T tag_readonly)"
    [ -d "$dir" ] || tags="$tags${tags:+ }$(T tag_new)"
    printf '%s' "$tags"
}

# The root folder and the bare home folder are never config folders.
forbidden_target() {
    local p
    p=$(abs_path "$1")
    [ "$p" = / ] || [ "$p" = "$(abs_path "$HOME")" ]
}

# False only for a folder that exists, is not empty and shows no sign of mpv.
looks_like_mpv_config() {
    local d=$1 n
    [ -d "$d" ] || return 0
    [ -n "$(ls -A "$d" 2>/dev/null)" ] || return 0
    for n in "${MPV_CONFIG_FILES[@]}"; do [ -f "$d/$n" ] && return 0; done
    for n in "${MPV_CONFIG_DIRS[@]}"; do [ -d "$d/$n" ] && return 0; done
    case $(abs_path "$d") in */mpv) return 0 ;; esac
    return 1
}

# ---------------------------------------------------------------------------
# Backups and interfaces set aside
# ---------------------------------------------------------------------------

# Copies what the installer may change (BACKUP_ITEMS and the paths given,
# relative to CFG) to <config>-respaldo-suji-<stamp>, next to it, each at its
# own relative path (BACKUP; '' when there is nothing to copy). Symbolic links
# to folders are skipped, never followed; a linked file is copied as the file.
# A copy that fails half-way is deleted.
make_backup() {
    local parent rel items base n
    BACKUP=''
    parent=${CFG%/*}
    [ -n "$parent" ] || { SUJI_ERR=$(T target_root "$CFG"); return 1; }
    items=()
    for rel in "${BACKUP_ITEMS[@]}" ${1+"$@"}; do
        [ -e "$CFG/$rel" ] || [ -L "$CFG/$rel" ] || continue
        if [ -L "$CFG/$rel" ] && { [ -d "$CFG/$rel" ] || [ ! -e "$CFG/$rel" ]; }; then
            warn "$(T link_skipped "$(clean_text "$CFG/$rel")")"
            continue
        fi
        items[${#items[@]}]=$rel
    done
    [ "${#items[@]}" -gt 0 ] || return 0
    base="$CFG-respaldo-suji-$STAMP"
    BACKUP=$base
    n=2
    while [ -e "$BACKUP" ] || [ -L "$BACKUP" ]; do BACKUP="$base-$n"; n=$((n + 1)); done
    if ! mkdir "$BACKUP"; then SUJI_ERR=$(clean_text "$BACKUP"); BACKUP=''; return 1; fi
    for rel in "${items[@]}"; do
        case $rel in */*) mkdir -p "$BACKUP/${rel%/*}" || { rm -rf "$BACKUP"; SUJI_ERR=$rel; BACKUP=''; return 1; } ;; esac
        if [ -d "$CFG/$rel" ]; then
            cp -pPR "$CFG/$rel" "$BACKUP/$rel" || { rm -rf "$BACKUP"; SUJI_ERR=$(clean_text "$rel"); BACKUP=''; return 1; }
        else
            cp -p "$CFG/$rel" "$BACKUP/$rel" || { rm -rf "$BACKUP"; SUJI_ERR=$(clean_text "$rel"); BACKUP=''; return 1; }
        fi
    done
}

# Keeps the newest BACKUP_KEEP backups of CFG and deletes older ones. Only
# folders named exactly <config>-respaldo-suji-<stamp>[-n] next to it count;
# links are never touched.
prune_backups() {
    local parent leaf d name re list path kept=0
    parent=${CFG%/*}
    leaf=${CFG##*/}
    re='^-respaldo-suji-([0-9]{8}-[0-9]{6})(-([0-9]+))?$'
    list=''
    for d in "$parent/$leaf"-respaldo-suji-*; do
        if [ ! -d "$d" ] || [ -L "$d" ]; then continue; fi
        name=${d##*/}
        name=${name#"$leaf"}
        [[ $name =~ $re ]] || continue
        list="$list${BASH_REMATCH[1]} ${BASH_REMATCH[3]:-1} $d"$'\n'
    done
    [ -n "$list" ] || return 0
    # "<stamp> <n> <path>", newest first.
    while IFS=' ' read -r _ _ path; do
        [ -n "$path" ] || continue
        kept=$((kept + 1))
        [ "$kept" -gt "$BACKUP_KEEP" ] || continue
        if is_inside "$path" "$parent" && rm -rf "$path"; then
            info "$(T backup_pruned "$(clean_text "$path")")"
        else
            warn "$(T backup_prune_failed "$(clean_text "$path")")"
        fi
    done <<EOF
$(printf '%s' "$list" | sort -k1,1r -k2,2nr)
EOF
}

# The backup step of an install or uninstall. Fails, with SUJI_ERR set, when
# the backup cannot be made.
backup_step() {
    if ! make_backup ${1+"$@"}; then
        SUJI_ERR=$(T backup_failed "$(clean_text "$CFG")" "$SUJI_ERR")
        return 1
    fi
    [ -z "$BACKUP" ] || info "$(T backup_done "$(clean_text "$BACKUP")")"
    prune_backups
}

# Interfaces that clash with suji (CONFLICTS: paths), as install/suji.ps1:
# the scripts, then their options and, for some, their fonts.
find_conflicts() {
    local f name pat stem names
    CONFLICTS=()
    names=()
    shopt -s nocasematch
    for f in "$CFG"/scripts/*; do
        name=${f##*/}
        if [ -d "$f" ]; then
            [[ $name == uosc ]] && { CONFLICTS[${#CONFLICTS[@]}]=$f; names[${#names[@]}]=$name; }
            continue
        fi
        [ -f "$f" ] || continue
        for pat in "${CONFLICT_PATTERNS[@]}"; do
            # shellcheck disable=SC2053 # $pat is a glob on purpose.
            if [[ $name == $pat ]]; then CONFLICTS[${#CONFLICTS[@]}]=$f; names[${#names[@]}]=${name%.*}; break; fi
        done
    done
    for f in "$CFG"/script-opts/*.conf; do
        [ -f "$f" ] || continue
        name=${f##*/}
        for stem in ${names[@]+"${names[@]}"}; do
            if [[ $name == "$stem.conf" ]]; then CONFLICTS[${#CONFLICTS[@]}]=$f; break; fi
        done
    done
    if [ "${#names[@]}" -gt 0 ]; then
        for f in "$CFG"/fonts/*; do
            [ -f "$f" ] || continue
            name=${f##*/}
            for pat in "${CONFLICT_FONT_PATTERNS[@]}"; do
                # shellcheck disable=SC2053
                [[ $name == $pat ]] || continue
                for stem in "${names[@]}"; do
                    # shellcheck disable=SC2053
                    if [[ $stem == $pat ]]; then CONFLICTS[${#CONFLICTS[@]}]=$f; break 2; fi
                done
            done
        done
    fi
    shopt -u nocasematch
}

# Moves a file or folder of CFG into scripts-apartados-suji, keeping its
# sub-folder (script-opts/, fonts/; scripts/ goes straight in). Sets
# MOVED_PAIR "moved|original".
move_aside() {
    local p=$1 rel sub dest_dir name dest
    is_inside "$p" "$CFG" || { SUJI_ERR=$(T outside_target "$(clean_text "$p")" "$(clean_text "$CFG")"); return 1; }
    rel=$(rel_path "$p" "$CFG")
    sub=''
    case $rel in */*) sub=${rel%/*} ;; esac
    dest_dir="$CFG/$DISABLED_DIR"
    if [ -n "$sub" ] && [ "$sub" != scripts ]; then dest_dir="$dest_dir/$sub"; fi
    mkdir -p "$dest_dir" || return 1
    name=${p##*/}
    dest="$dest_dir/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ -d "$p" ] || [ "${name%.*}" = "$name" ]; then dest="$dest_dir/$name-$STAMP"
        else dest="$dest_dir/${name%.*}-$STAMP.${name##*.}"; fi
    fi
    mv "$p" "$dest" || return 1
    MOVED_PAIR="$(rel_path "$dest" "$CFG")|$rel"
    info "$(T moved "$(clean_text "$rel")" "$(clean_text "${MOVED_PAIR%%|*}")")"
}

# Moves set-aside items back ("moved|original" entries, relative to CFG),
# checked again (the record is not trusted): clean paths inside the folder,
# nothing overwritten.
restore_pairs() {
    local entry from to
    for entry in ${1+"$@"}; do
        if ! pair_ok "$entry"; then warn "$(T record_bad "$(clean_text "$entry")")"; continue; fi
        from="$CFG/${entry%%|*}"
        to="$CFG/${entry#*|}"
        if ! is_inside "$from" "$CFG" || ! is_inside "$to" "$CFG"; then
            warn "$(T outside_target "$(clean_text "$from")" "$(clean_text "$CFG")")"
            continue
        fi
        [ -e "$from" ] || [ -L "$from" ] || continue
        if [ -e "$to" ] || [ -L "$to" ]; then warn "$(T restore_skipped "$(clean_text "${entry%%|*}")" "$(clean_text "${entry#*|}")")"; continue; fi
        mkdir -p "${to%/*}" || return 1
        mv "$from" "$to" || return 1
        info "$(T moved "$(clean_text "${entry%%|*}")" "$(clean_text "${entry#*|}")")"
    done
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

# Installs into the candidate $1 (index).
install_target() {
    CFG=${C_DIR[$1]}
    KIND=${C_KIND[$1]}
    local exe=${C_EXE[$1]} c moving
    BACKUP=''
    mkdir -p "$CFG" || { SUJI_ERR=$(clean_text "$CFG"); return 1; }
    # Checked before anything changes: a broken block stops it here.
    load_file "$CFG/mpv.conf"
    find_block || return 1

    moving=()
    find_conflicts
    if [ "${#CONFLICTS[@]}" -gt 0 ]; then
        warn "$(T conflicts_found)"
        for c in "${CONFLICTS[@]}"; do warn "  - $(clean_text "$(rel_path "$c" "$CFG")")"; done
        if confirm "$(T conflicts_confirm "$DISABLED_DIR")" yes; then
            for c in "${CONFLICTS[@]}"; do moving[${#moving[@]}]=$(rel_path "$c" "$CFG"); done
        else
            warn "$(T conflicts_kept)"
        fi
    fi
    backup_step ${moving[@]+"${moving[@]}"} || return 1
    if ! install_steps "$exe" ${moving[@]+"${moving[@]}"}; then
        [ -z "$BACKUP" ] || SUJI_ERR="$SUJI_ERR $(T restore_hint "$(clean_text "$BACKUP")")"
        return 1
    fi
    info "$(T install_ok "$SUJI_VERSION" "$(clean_text "$CFG")")"
}

# install_steps <mpv path or ''> <paths to set aside...>
install_steps() {
    local exe=$1 rel tmp now
    shift
    FIRST=1
    DISABLED=()
    REC_KEYS=(); REC_VALS=(); REC_DISABLED=()
    if read_record "$CFG"; then
        FIRST=0
        DISABLED=(${REC_DISABLED[@]+"${REC_DISABLED[@]}"})
    fi
    now=0; [ -f "$CFG/scripts/thumbfast.lua" ] && now=1
    THUMB_BEFORE=$(prev_flag thumbfast_preexisting "$now")
    now=0; [ -f "$CFG/script-opts/thumbfast.conf" ] && now=1
    TCONF_BEFORE=$(prev_flag thumbfast_conf_preexisting "$now")
    now=0; [ -f "$CFG/mpv.conf" ] && now=1
    MPV_BEFORE=$(prev_flag mpv_conf_preexisting "$now")

    # Interfaces set aside, each one recorded as soon as it moves.
    write_record || return 1
    for rel in ${1+"$@"}; do
        move_aside "$CFG/$rel" || return 1
        DISABLED[${#DISABLED[@]}]=$MOVED_PAIR
        write_record || return 1
    done

    # thumbfast: not copied again when it is exactly as pinned.
    mkdir -p "$CFG/scripts" "$CFG/script-opts" || return 1
    if thumbfast_uptodate "$CFG"; then
        info "$(T thumbfast_uptodate)"
    else
        [ -f "$TEMP_DIR/thumbfast.lua" ] || { SUJI_ERR=$(T source_missing "$THUMBFAST_URL"); return 1; }
        rm -f "$CFG/scripts/thumbfast.lua"
        cp "$TEMP_DIR/thumbfast.lua" "$CFG/scripts/thumbfast.lua" || return 1
    fi

    # suji: copied next to the old one first, so a failed copy leaves the old
    # one in place.
    tmp=$(mktemp -d "$CFG/scripts/.suji-new.XXXXXX") || return 1
    if ! cp -R "$SRC_DIR/." "$tmp/"; then rm -rf "$tmp"; return 1; fi
    remove_item "$CFG/scripts/suji" "$CFG" || { rm -rf "$tmp"; return 1; }
    mv "$tmp" "$CFG/scripts/suji" || { rm -rf "$tmp"; return 1; }
    # mktemp -d made it private: the usual permissions for the umask.
    chmod "$(printf '%o' $((0777 & ~0$(umask))))" "$CFG/scripts/suji" 2>/dev/null || :

    # thumbfast.conf: written when missing; else only mpv_path added when it
    # has none. thumbfast starts a second mpv for the thumbnails, and an mpv
    # started from Finder (or another app) does not have Homebrew in its PATH:
    # on macOS it gets the full path. Not on Linux, where "mpv" is found.
    local conf="$CFG/script-opts/thumbfast.conf" path=''
    [ "$OS" = Darwin ] && [ "$KIND" = mpv ] && path=$exe
    if [ ! -e "$conf" ] && [ ! -L "$conf" ]; then
        { thumbfast_conf_text; [ -z "$path" ] || mpv_path_lines "$path" lf; } | write_file "$conf" || return 1
        [ -z "$path" ] || info "$(T mpvpath_set "$(clean_text "$path")")"
    elif [ -n "$path" ] && [ -f "$conf" ] && ! grep -qE '^[[:space:]]*mpv_path[[:space:]]*=' "$conf"; then
        load_file "$conf"
        local eol
        eol=$(file_eol)
        { print_lines; [ "$F_COUNT" -eq 0 ] || [ -n "${F_EOL[F_COUNT - 1]}" ] || printf_eol "$eol"; mpv_path_lines "$path" "$eol"; } |
            write_file "$conf" || return 1
        info "$(T mpvpath_set "$(clean_text "$path")")"
    fi

    update_mpv_conf "$CFG/mpv.conf" || return 1
    write_record
}

printf_eol() { if [ "$1" = crlf ]; then printf '\r\n'; else printf '\n'; fi; }

# The lines added for mpv_path, with line break $2 (lf or crlf).
mpv_path_lines() {
    printf_eol "$2"
    printf '%s' '# Added by the suji installer: mpv started from another app may not find mpv in its PATH.'
    printf_eol "$2"
    printf 'mpv_path=%s' "$1"
    printf_eol "$2"
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

uninstall_target() {
    CFG=${C_DIR[$1]}
    BACKUP=''
    # Checked before anything changes: a broken block stops it here.
    load_file "$CFG/mpv.conf"
    find_block || return 1
    backup_step || return 1
    if ! uninstall_steps; then
        [ -z "$BACKUP" ] || SUJI_ERR="$SUJI_ERR $(T restore_hint "$(clean_text "$BACKUP")")"
        return 1
    fi
    info "$(T uninstall_ok "$(clean_text "$CFG")")"
}

# was_there <key>: yes, no, or '' when the record does not say.
was_there() {
    if [ "$HAS_RECORD" = 1 ] && rec_get "$1"; then
        if [ "$REC_VALUE" = yes ]; then printf yes; else printf no; fi
    fi
}

uninstall_steps() {
    local def created d e names f
    HAS_RECORD=0
    REC_KEYS=(); REC_VALS=(); REC_DISABLED=()
    read_record "$CFG" && HAS_RECORD=1

    remove_item "$CFG/scripts/suji" "$CFG" || return 1
    created=0; [ "$(was_there mpv_conf_preexisting)" = no ] && created=1
    remove_mpv_block "$CFG/mpv.conf" "$created" || return 1

    if [ -f "$CFG/scripts/thumbfast.lua" ]; then
        def=no; [ "$(was_there thumbfast_preexisting)" = no ] && def=yes
        if confirm "$(T ask_remove_thumbfast)" "$def"; then
            remove_item "$CFG/scripts/thumbfast.lua" "$CFG" || return 1
            if [ "$(was_there thumbfast_conf_preexisting)" = no ]; then
                remove_item "$CFG/script-opts/thumbfast.conf" "$CFG" || return 1
            fi
        fi
    fi

    if [ -e "$CFG/script-opts/suji.conf" ] || [ -e "$CFG/suji-size" ]; then
        if confirm "$(T ask_delete_settings)" no; then
            remove_item "$CFG/script-opts/suji.conf" "$CFG" || return 1
            remove_item "$CFG/suji-size" "$CFG" || return 1
        fi
    fi

    if [ "${#REC_DISABLED[@]}" -gt 0 ]; then
        names=''
        for e in "${REC_DISABLED[@]}"; do names="$names${names:+, }${e#*|}"; done
        if confirm "$(T ask_restore "$(clean_text "$names")")" yes; then restore_pairs "${REC_DISABLED[@]}" || return 1; fi
    fi

    remove_item "$CFG/$RECORD_NAME" "$CFG" || return 1
    # Folders left empty go too: the set-aside one when no file is left in
    # it, scripts and script-opts when suji may have created them.
    d="$CFG/$DISABLED_DIR"
    if [ -d "$d" ] && [ ! -L "$d" ] && [ -z "$(find "$d" ! -type d -print 2>/dev/null | head -n 1)" ]; then
        remove_item "$d" "$CFG" || return 1
    fi
    for f in script-opts scripts; do
        d="$CFG/$f"
        if [ -d "$d" ] && [ ! -L "$d" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ]; then rmdir "$d" || return 1; fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# Interactive flow
# ---------------------------------------------------------------------------

show_candidates() { # numbered list of the candidates in LIST
    local i=0 idx
    while [ "$i" -lt "${#LIST[@]}" ]; do
        idx=${LIST[i]}
        info " $((i + 1))) $(kind_label "${C_KIND[idx]}")  $(candidate_tags "$idx")"
        [ -z "${C_EXE[idx]}" ] || info "$(T cand_exe "$(clean_text "${C_EXE[idx]}")")"
        info "$(T cand_config "$(clean_text "${C_DIR[idx]}")")"
        i=$((i + 1))
    done
}

# Typed folder into PICKED_DIR; fails when the user gives up.
read_folder() {
    local p parent
    while :; do
        read_line "$(T ask_folder)" || return 1
        trim "$REPLY_LINE"
        p=$TRIMMED
        p=${p#\"}; p=${p%\"}; p=${p#\'}; p=${p%\'}
        case $p in '' | 0) return 1 ;; esac
        if ! p=$(abs_path "$p"); then warn "$(T path_bad "$(clean_text "$REPLY_LINE")")"; continue; fi
        parent=${p%/*}
        [ -n "$parent" ] || parent=/
        if [ -d "$p" ] || [ -d "$parent" ]; then PICKED_DIR=$p; return 0; fi
        warn "$(T folder_missing "$(clean_text "$p")")"
    done
}

# Adds the candidate for a folder to CHOSEN (as "folder" when it is not one).
add_folder_candidate() {
    local dir i=0
    dir=$(abs_path "$1")
    while [ "$i" -lt "${#C_DIR[@]}" ] && [ "${C_DIR[i]}" != "$dir" ]; do i=$((i + 1)); done
    [ "$i" -lt "${#C_DIR[@]}" ] || add_candidate folder "$dir" ''
    CHOSEN[${#CHOSEN[@]}]=$i
}

# Which folders: CHOSEN (candidate indexes). Fails for "exit".
choose_targets() {
    local mode=$1 i text part n bad quit other picks
    CHOSEN=()
    if [ "${#OPT_TARGETS[@]}" -gt 0 ]; then
        for i in "${OPT_TARGETS[@]}"; do
            if ! abs_path "$i" >/dev/null; then error "$(T path_bad "$(clean_text "$i")")"; REFUSED=1; continue; fi
            add_folder_candidate "$i"
        done
        return 0
    fi
    LIST=()
    i=0
    while [ "$i" -lt "${#C_DIR[@]}" ]; do
        if [ "$mode" = install ] || suji_present "${C_DIR[i]}"; then LIST[${#LIST[@]}]=$i; fi
        i=$((i + 1))
    done
    if [ "$NONINTERACTIVE" = 1 ]; then
        if [ "${#LIST[@]}" -eq 1 ]; then CHOSEN=("${LIST[0]}"); return 0; fi
        if [ "${#LIST[@]}" -eq 0 ]; then
            if [ "$mode" = uninstall ]; then error "$(T nothing_to_uninstall)"; else error "$(T usage_none)"; fi
        else
            error "$(T usage_many)"
            show_candidates
        fi
        USAGE_ERROR=1
        return 1
    fi
    [ "${#LIST[@]}" -gt 0 ] || [ "$mode" != uninstall ] || warn "$(T nothing_to_uninstall)"
    while :; do
        if [ "${#LIST[@]}" -gt 0 ]; then
            if [ "$mode" = uninstall ]; then info "$(T found_header_uninst)"; else info "$(T found_header)"; fi
            show_candidates
        fi
        info " $(T opt_other)"
        info " $(T opt_quit)"
        read_line "$(T select_prompt)" || return 1
        text=$REPLY_LINE
        bad=0; quit=0; other=0
        picks=()
        local IFS=$', ;\t'
        for part in $text; do
            case $(lower "$part") in
                0 | q | x) quit=1 ;;
                o) other=1 ;;
                *[!0-9]* | '') bad=1 ;;
                *)
                    n=$((10#$part))
                    if [ "$n" -ge 1 ] && [ "$n" -le "${#LIST[@]}" ]; then picks[${#picks[@]}]=${LIST[n - 1]}; else bad=1; fi
                    ;;
            esac
        done
        IFS=$' \t\n'
        [ -n "$text" ] || bad=1
        if [ "$bad" = 1 ]; then warn "$(T invalid)"; continue; fi
        [ "$quit" = 0 ] || return 1
        CHOSEN=(${picks[@]+"${picks[@]}"})
        if [ "$other" = 1 ] && read_folder; then add_folder_candidate "$PICKED_DIR"; fi
        return 0
    done
}

# Drops forbidden folders, folders with hikari and, after asking, folders that
# do not look like mpv's; for install also folders that cannot be written.
# Sets TARGETS.
check_targets() {
    local mode=$1 i t dup dir
    TARGETS=()
    for i in ${CHOSEN[@]+"${CHOSEN[@]}"}; do
        dup=0
        for t in ${TARGETS[@]+"${TARGETS[@]}"}; do [ "$t" = "$i" ] && dup=1; done
        [ "$dup" = 0 ] || continue
        dir=${C_DIR[i]}
        if forbidden_target "$dir"; then error "$(T target_root "$(clean_text "$dir")")"; REFUSED=1; continue; fi
        if hikari_present "$dir"; then warn "$(T hikari_here "$(clean_text "$dir")")"; REFUSED=1; continue; fi
        if ! looks_like_mpv_config "$dir"; then
            warn "$(T not_mpv_folder "$(clean_text "$dir")")"
            if [ "$NONINTERACTIVE" = 1 ]; then error "$(T not_mpv_yes)"; REFUSED=1; continue; fi
            if ! confirm "$(T not_mpv_confirm)" no; then warn "$(T readonly_skip "$(clean_text "$dir")")"; continue; fi
        fi
        if [ "$mode" = install ] && ! dir_writable "$dir"; then
            warn "$(T readonly_warn "$(clean_text "$dir")")"
            warn "$(T readonly_skip "$(clean_text "$dir")")"
            continue
        fi
        TARGETS[${#TARGETS[@]}]=$i
    done
}

suji_cleanup() {
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then rm -rf "$TEMP_DIR"; fi
    TEMP_DIR=''
}

parse_args() {
    OPT_ACTION=''
    OPT_YES=0
    OPT_TARGETS=()
    while [ $# -gt 0 ]; do
        case $1 in
            --action)
                [ $# -ge 2 ] || { error "$(T bad_option "$1")"; return 2; }
                case $2 in install | uninstall) OPT_ACTION=$2 ;; *) error "$(T bad_option "$1 $(clean_text "$2")")"; return 2 ;; esac
                shift
                ;;
            --action=*)
                case ${1#*=} in install | uninstall) OPT_ACTION=${1#*=} ;; *) error "$(T bad_option "$(clean_text "$1")")"; return 2 ;; esac
                ;;
            --target)
                if [ $# -lt 2 ] || [ -z "$2" ]; then error "$(T bad_option "$1")"; return 2; fi
                OPT_TARGETS[${#OPT_TARGETS[@]}]=$2
                shift
                ;;
            --target=*) OPT_TARGETS[${#OPT_TARGETS[@]}]=${1#*=} ;;
            --yes | -y) OPT_YES=1 ;;
            -h | --help) T usage; printf '\n'; return 1 ;;
            *) error "$(T bad_option "$(clean_text "$1")")"; return 2 ;;
        esac
        shift
    done
    return 0
}

main() {
    # Unset variables are errors; every other failure is checked where it
    # happens (no set -e: its rules in functions and conditions are a trap).
    set -u
    suji_defaults
    SUJI_LANG_CODE=$(suji_language)
    SCRIPT_FILE=${BASH_SOURCE[0]:-}
    SUJI_ERR=''
    TEMP_DIR=''
    REFUSED=0
    USAGE_ERROR=0
    MPV_EXE=''
    local rc action t done_count=0
    parse_args "$@"
    rc=$?
    case $rc in 0) ;; 1) return 0 ;; *) error "$(T usage)"; return 2 ;; esac

    trap 'suji_cleanup' EXIT
    trap 'suji_cleanup; trap - EXIT; exit 130' INT
    trap 'suji_cleanup; trap - EXIT; exit 143' TERM

    OS=$(suji_uname)
    case $OS in Darwin | Linux) ;; *) error "$(T unsupported_os "$(clean_text "$OS")")"; return 2 ;; esac
    action=$OPT_ACTION

    io_setup
    NONINTERACTIVE=0
    if [ "$OPT_YES" = 1 ] || [ "$HAVE_INPUT" != 1 ]; then NONINTERACTIVE=1; fi
    info "$(T title "$SUJI_VERSION")"
    [ "$HAVE_INPUT" = 1 ] || [ "$OPT_YES" = 1 ] || warn "$(T no_input)"
    if [ -z "$action" ]; then
        if [ "$NONINTERACTIVE" = 1 ]; then
            action=install
        else
            while [ -z "$action" ]; do
                printf '%b\n' "$(T menu)"
                read_line "$(T menu_prompt)" || return 0
                trim "$REPLY_LINE"
                case $TRIMMED in
                    1) action=install ;;
                    2) action=uninstall ;;
                    0) info "$(T cancelled)"; return 0 ;;
                    *) warn "$(T invalid)" ;;
                esac
            done
        fi
    fi
    if [ "$action" = install ]; then
        for t in curl unzip; do
            command -v "$t" >/dev/null 2>&1 || { error "$(T missing_tool "$t")"; return 2; }
        done
    fi

    if [ "$(id -u)" = 0 ]; then
        warn "$(T root_warn)"
        if [ "$NONINTERACTIVE" = 1 ]; then error "$(T root_refused)"; return 2; fi
        confirm "$(T root_confirm)" no || { info "$(T cancelled)"; return 0; }
    fi

    MPV_EXE=$(suji_find_mpv)
    if [ "$action" = install ] && [ -z "$MPV_EXE" ] && { [ "$OS" = Darwin ] || ! { suji_flatpak_mpv || suji_snap_mpv; }; }; then
        warn "$(T none_found)"
    fi
    find_candidates
    if ! choose_targets "$action"; then
        [ "$USAGE_ERROR" = 1 ] && return 2
        info "$(T cancelled)"
        return 0
    fi
    check_targets "$action"
    if [ "$REFUSED" = 1 ] && [ "$NONINTERACTIVE" = 1 ]; then return 2; fi
    if [ "${#TARGETS[@]}" -eq 0 ]; then
        if [ "$NONINTERACTIVE" = 1 ]; then error "$(T usage_none)"; return 2; fi
        info "$(T cancelled)"
        return 0
    fi

    STAMP=$(date +%Y%m%d-%H%M%S)
    if [ "$action" = install ]; then
        # Everything is downloaded and checked before any folder is touched.
        TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/suji-install.XXXXXX") || { error mktemp; return 1; }
        if ! get_source; then error "$SUJI_ERR"; return 1; fi
        for t in "${TARGETS[@]}"; do
            thumbfast_uptodate "${C_DIR[t]}" && continue
            if ! verified_download "$THUMBFAST_URL" "$THUMBFAST_SHA256" "$TEMP_DIR/thumbfast.lua"; then error "$SUJI_ERR"; return 1; fi
            break
        done
    fi
    for t in "${TARGETS[@]}"; do
        SUJI_ERR=''
        info ''
        if [ "$action" = install ]; then
            install_target "$t" && done_count=$((done_count + 1)) && continue
        else
            uninstall_target "$t" && done_count=$((done_count + 1)) && continue
        fi
        error "$(T target_failed "$(clean_text "${C_DIR[t]}")" "$SUJI_ERR")"
    done
    suji_cleanup
    info ''
    [ "${#TARGETS[@]}" -le 1 ] || info "$(T summary "$done_count" "${#TARGETS[@]}")"
    [ "$done_count" -eq 0 ] || info "$(T restart)"
    [ "$done_count" -eq "${#TARGETS[@]}" ]
}

# Braces: a download cut anywhere in this line is a syntax error, never a call.
{ main "$@"; }
