#!/bin/bash
###############################################################################
# Domain Renewal and Dynamic DNS shell script for freenom.com                 #
###############################################################################
#                                                                             #
# Updates IP address and/or auto renews domain(s) so they do not expire       #
# See README.md for more information                                          #
#                                                                             #
# freenom-script  Copyright (C) 2019  M. Korthof                              #
# This program comes with ABSOLUTELY NO WARRANTY                              #
# This is free software, and you are welcome to redistribute it               #
# under certain conditions.                                                   #
# See LICENSE file for more information                                       #
# gpl-3.0-only                                                  v2023-08-03   #
###############################################################################

# shellcheck disable=SC2317

########
# Main #
########

set -eo pipefail

# check some requirements
for i in curl grep date basename dirname sed; do
  if ! command -v $i >/dev/null 2>&1; then
    echo "Error: could not find \"$i\", exiting..."
    exit 1
  fi
done
if [ -z "$BASH" ]; then
  echo "Warning: bash not detected"
fi
if [ "$(readlink /proc/$$/exe 2>&1)" = "/bin/busybox" ]; then
  echo "Warning: looks like we're running under BusyBox"
fi
scriptName="$(basename "$0")"
infoCount="0"
warnCount="0"
errCount="0"
oldCurl="0"
if curl --version | grep -Eiq "^curl (7\.[0-5]|[0-6]\.)"; then
  oldCurl=1
fi
if [[ -n "$freenom_oldcurl_force" && "${freenom_oldcurl_force:-0}" -eq 1 ]]; then
  oldCurl=1
else
  oldCurl=0
fi

########
# Conf #
########

# configuration file from argument '-c'
SAVE_IFS="$IFS"
IFS='|'
c=0
for i in "$@"; do
  if printf -- "%s" "$i" | grep -Eq -- "(^|[^a-z])-c"; then
    c=1
    continue
  else
    if [ "${c:-0}" -eq 1 ]; then
      if printf -- "%s" "$i" | grep -Eq -- "^-"; then
        echo "Error: config file not specfied, try \"$scriptName -h\""
        exit 1
      fi
      scriptConf="$i"
      if [ ! -s "$scriptConf" ]; then
        echo "Error: invalid config file \"$scriptConf\" specified"
        exit 1
      fi
      break
    fi
  fi
done
IFS="$SAVE_IFS"
# if scriptConf is empty, check for {/usr/local,}/etc/freenom.conf and in same dir as script
if [ -z "$scriptConf" ]; then
  sc1="$(dirname "$0")/$(basename -s '.sh' "$0").conf"
  sc2="${BASH_SOURCE[0]/%.sh/}.conf"
  for i in "/usr/local/etc/freenom.conf" "/etc/freenom.conf" "$sc1" "$sc2"; do
    if [ -e "$i" ]; then
      scriptConf="$i"
      break
    fi
  done
fi
unset -v i
# make sure we dont source ourselves
if [ "$scriptConf" = "$0" ] || [ "$scriptConf" = "${BASH_SOURCE[0]}" ]; then
  echo "Error: invalid config file \"$scriptConf\" specified"
  exit 1
fi
# source scriptConf if its non empty, else exit
if [ -n "$scriptConf" ] && [ -s "$scriptConf" ]; then
  # shellcheck source=/usr/local/etc/freenom.conf
  source "$scriptConf" || {
    echo "Error: could not load $scriptConf"
    exit 1
  }
fi

# make sure debug is always set
if [ -z "$debug" ]; then
  debug=0
fi
if [ "${debug:-0}" -ge 1 ]; then
  echo "DEBUG: $pad8      $pad8    debug=$debug curlExtraOpts=$curlExtraOpts"
  echo "DEBUG: $pad8 conf $pad8    scriptConf=$scriptConf"
fi

# check args for help
help=0
if printf -- "%s" "$*" | grep -Eqi '(^|[^a-z])-h'; then
  help=1
fi

# config checks: we need these settings, so if they do not exist 'exit'
if [ -z "$freenom_email" ]; then
  echo "Error: setting \"freenom_email\" is missing in config"
  if [ "${help:-0}" -eq 0 ]; then
    exit 1
  fi
fi
if [ -z "$freenom_passwd" ]; then
  echo "Error: setting \"freenom_passwd\" is missing in config"
  if [ "${help:-0}" -eq 0 ]; then
    exit 1
  fi
fi

# if needed create freenom_out_dir. if out_path is not set or invalid, set default
if [ -d "$(dirname "$freenom_out_dir")" ]; then
  if [ ! -d "$freenom_out_dir}" ]; then
    mkdir "${freenom_out_dir}" >/dev/null 2>&1 || true
  fi
fi
out_path="${freenom_out_dir}/${freenom_out_mask}"
if [[ -z "$freenom_out_dir" || -z "$freenom_out_mask" || ! -d "$freenom_out_dir" ]]; then
  out_path="/var/log/$(basename -s '.sh' "$0")"
  echo "Warning: no valid \"freenom_out_dir\" or \"mask\" setting found, using default path: $out_path"
fi
if [ ! -e "${out_path}.log" ]; then
  touch "${out_path}.log" >/dev/null 2>&1 || true
fi
if [ ! -w "${out_path}.log" ]; then
  if [ "${help:-0}" -eq 0 ]; then
    echo "Info: logfile \"${out_path}.log\" not writable, using \"/tmp/$(basename -s '.sh' "$0").log\""
  fi
  out_path="/tmp/$(basename -s '.sh' "$0")"
fi

# shellcheck disable=SC2128
if [ -z "$uaString" ]; then
  echo "Error: setting \"uaString\" is missing in config"
  if [ "${help:-0}" -eq 0 ]; then
    exit 1
  fi
fi
# shellcheck disable=SC2128
if [ -z "$ipCmd" ]; then
  echo "Error: setting \"ipCmd\" is missing in config"
  if [ "${help:-0}" -eq 0 ]; then
    exit 1
  fi
fi

if [ -z "$RCPTTO" ]; then
  RCPTTO="$freenom_email"
fi

if [ ! -x "$MTA" ]; then
  if [ -x "/usr/sbin/sendmail" ]; then
    MTA="/usr/sbin/sendmail"
  else
    MTA=""
    echo "Warning: No MTA found, cant send email"
  fi
fi

# set a few general variables

c_opts="--connect-timeout 30 --compressed -L -s"

# generate "random" useragent string, used for curl and below in func_randIp
agent="${uaString[$((RANDOM % ${#uaString[@]}))]}"

# add http code to curl output
http_code="<!--http_code=%{http_code}-->"

ipRE='((((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])))|(((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?))'

pad4="$(printf "%*s" 4 " ")"
pad8="$(printf "%*s" 8 " ")"

# DEBUG: add proxy to curlExtraOpts
debug_proxy=0
if [ "${debug_proxy:-0}" -eq 1 ]; then
  curlExtraOpts+=" --proxy http://localhost:3128"
fi

# Make sure 'my.freenom.com' resolves correctly
if [ "${freenom_http_resolve:-0}" -eq 1 ]; then
  if curl --max-time 10 --dns-servers "$curlDns" my.freenom.com >/dev/null 2>&1; then
    curlExtraOpts+=" --dns-servers $curlDns"
  else
    for ((i = 0; i < ${#resolveCmd[@]}; i++)); do
      _myfn_ip=$(${resolveCmd[$i]} 2>/dev/null | awk '/^(.*[aA]ddress:? )?[0-9.]+$/{ print $NF; exit }')
      if [[ "$_myfn_ip" =~ ^$ipRE$ ]]; then
        curlExtraOpts+=" --resolve my.freenom.com:443:$_myfn_ip"
        break
      fi
    done
  fi
fi

# AWS WAF CAPTCHA token. To manually get it from browser:
# goto my.freenom.com, solve captcha puzzle and copy cookie 'aws-waf-token' (valid ~3 mins)
if [ -n "$AWS_WAF_TOKEN" ]; then
  TOKEN="${AWS_WAF_TOKEN#aws-waf-token=}"
  if echo "$TOKEN" | grep -Eq '[0-9a-f-]{36}:[A-Za-z0-9+/]{16}:[A-Za-z0-9+/=]{64,}'; then
    curlExtraOpts+=" -b aws-waf-token=${TOKEN} "
  else
    echo "Error: Incorrect AWS WAF CAPTCHA token"
    exit 1
  fi
else
  _wmsg="Warning: Missing AWS WAF CAPTCHA token"
  echo "$_wmsg (\$AWS_WAF_TOKEN not set)"
  echo -e "[$(date)] [$$] $_wmsg" >>"${out_path}.log"
fi

#############
# Functions #
#############

# Function cleanup: remove cookie file using trap
func_cleanup() {
  if [[ -n "$cookie_file" && -f "$cookie_file" ]]; then
    if [ "${debug:-0}" -ge 1 ]; then
      echo "DEBUG: $(date '+%H:%M:%S') func_cleanup cookie_file=$cookie_file"
    fi
    rm "$cookie_file"
  fi
}
trap "func_cleanup" EXIT HUP INT TERM

# Function help: displays options etc
func_help() {
  cat <<-_EOF_

freenom.com Domain Renewal and DynDNS
-------------------------------------

Usage:      $scriptName -l [-d]
            $scriptName -r <domain OR -a> [-s <subdomain>]
            $scriptName -u <domain> [-s <subdomain>] [-m <ip>] [-f]
            $scriptName -z <domain>

Options:    -l    List all domains and id's in account
                  add [-d] to show renewal Details
            -r    Renew <domain> or use '-r -a' to update All
                  add [-s] to renew <Subdomain>
            -u    Update <domain> A record with current ip
                  add [-s] to update <Subdomain> record
                  add [-m <ip>] to Manually update static <ip>
                  add [-f] to Force update on unchanged ip
            -z    Zone for <domain>, shows dns records

            -4    Use ipv4 and modify A record on "-u" (default)
            -6    Use ipv6 and modify AAAA record on "-u"
            -c    Config <file> to use, instead of freenom.conf
            -i    Ip commands list, used to get current ip
            -o    Output renewals, shows html file(s)

Examples    ./$scriptName -r example.com
            ./$scriptName -c /etc/mycustom.conf -r -a
            ./$scriptName -u example.com -s mail

            * When "-u" or "-r" is used with argument <domain>
              any settings in script or config file are overridden

_EOF_
  # TEST:     use [-a] with -u to update All domains and records
  #           ./$scriptName -u -a
  exit 0
}

# Function getDomainArgs: use regexps to get domain name, id etc
func_getDomainArgs() {
  local _d_args
  local _arg_domain_name
  local _arg_domain_id
  local _arg_subdomain_name
  local _subdom_set

  # check for subdomain arg '-s'
  _subdom_set=0
  if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-s'; then
    _subdom_set=1
  fi

  # first remove debug arg...
  _d_args="$(echo "$*" | sed -E 's/ ?-debug ([0-9])//')"

  # ...then remove '-c' arg and save other options to $_d_args
  # XXX: (#12) this regex has issues with bash 5.0.3/sed 4.7 but works on bash 4.4.12/sed 4.4
  #             sed -E 's| ?-c [][a-zA-Z0-9 !"#$%&'\''()*+,-.:;<=>?@^_`{}~/]+ ?||g'
  _d_args="$(echo "$_d_args" | sed -E 's| ?(-c ([^ ]+\|['\''"].+['\''"])) ?||g')"

  # now get domain_name by removing:
  #   - options "-m <ip>" and "-s"
  #   - 'digits' which match domain id
  #   - any other args e.g. "-[a-z]"
  if [[ -n "$freenom_update_all" && "${freenom_update_all:-0}" -eq 0 ]]; then
    _arg_domain_name="$(
      echo "$_d_args" |
        sed -E -e 's/-m '"$ipRE"'//' \
          -e 's/( ?-s [^ ]+|( -[[:alnum:]]+|-[[:alnum:]]+ )| [0-9]+|[0-9]+ | )|^-[[:alnum:]]+$/ /g' |
        awk '{ print $1 }'
    )"
  fi
  _arg_domain_id="$(echo "$_d_args" | sed -n -E 's/.*([0-9]{10}+).*/\1/p')"
  _arg_subdomain_name="$(echo "$_d_args" | sed -n -E 's/.*-s ([^ ]+).*/\1/p')"

  # if domain arg is not empty, use that instead of setting from conf
  if [[ -n "$freenom_update_all" && "${freenom_update_all:-0}" -eq 0 ]]; then
    if [ -n "$_arg_domain_name" ]; then
      freenom_domain_name="$_arg_domain_name"
      if [ "$((0 + $(echo "$freenom_domain_name" | tr '.' '\n' | wc -l)))" -ge 3 ]; then
        local _wmsg="Warning: \"$freenom_domain_name\" looks like a subdomain (use '-s' ?)"
        echo "$_wmsg"
        echo -e "[$(date)] [$$] $_wmsg" >>"${out_path}.log"
      fi
    fi
  fi
  if [ -n "$_arg_subdomain_name" ]; then
    freenom_subdomain_name="$_arg_subdomain_name"
  fi
  if [ -n "$_arg_domain_id" ]; then
    freenom_domain_id="$_arg_domain_id"
  fi
  debugDomainArgs=0
  if [ "${debug:-0}" -ge 1 ]; then
    debugDomainArgs=1
  fi
  # if we didnt get any args and theres no conf settings, display error message
  if [[ -n "$freenom_update_all" && "${freenom_update_all:-0}" -eq 0 ]]; then
    if [ "$freenom_domain_name" == "" ]; then
      echo "Error: domain name missing"
      echo "  Try: $scriptName [-u|-r|-z] [domain]"
      exit 1
    fi
    # handle invalid domain setting
    if [[ ! "$freenom_domain_name" =~ ^[^.-][a-zA-Z0-9.-]+$ ]] ||
      [[ "$freenom_domain_name" == "$freenom_domain_id" ]]; then
      echo "Error: invalid domain name \"$freenom_domain_name\""
      exit 1
    fi
    if [ "$_subdom_set" -ge 1 ] && [[ ! "$freenom_subdomain_name" =~ ^[^.-][a-zA-Z0-9.-]+$ ]]; then
      echo "Error: invalid or missing subdomain"
      exit 1
    fi
  fi
  if [[ ! "$freenom_domain_id" =~ ^[0-9]{10}+$ ]]; then
    freenom_domain_id=""
  fi
  if [[ -n "$debugDomainArgs" && "${debugDomainArgs:-0}" -eq 1 ]]; then
    echo "DEBUG: $pad8 getdomargs   d_args=$_d_args _subdom_set=$_subdom_set"
    echo "DEBUG: $pad8 getdomargs   arg_domain_name=$_arg_domain_name arg_subdomain_name=$_arg_subdomain_name arg_domain_id=$_arg_domain_id"
  fi
}

# Function showResult: format html and output as text
func_showResult() {
  printf "\n[ %s ]\n\n" "$1"
  local i=""
  for i in lynx links links2 wb3m elinks curl cat; do
    if command -v $i >/dev/null 2>&1; then
      break
    fi
  done
  case "$i" in
  lynx | links | links2 | w3m | elinks)
    [ $i = "lynx" ] && s_args="-nolist"
    [ $i = "elinks" ] && s_args="-no-numbering -no-references"
    # shellcheck disable=SC2086
    "$i" -dump $s_args "$1" | sed '/ \([*+□•] \?.\+\|\[.*\]\)/d'
    ;;
  curl | cat)
    [ $i = "curl" ] && s_args="-s file:///"
    # shellcheck disable=SC2086
    "$i" ${s_args}"${1}" |
      sed -e '/<a href.*>/d' -e '/<style type="text\/css">/,/</d' -e '/class="lang-/d' \
        -e 's/<[^>]\+>//g' -e '/[;}{):,>]$/d' -e '/\r/d' -e 's/\t//g' -e '/^ \{2,\}$/d' -e '/^$/d'
    ;;
  *)
    echo "Error: cannot display \"$1\""
    exit 1
    ;;
  esac
}

# Function randIp: run random dig or curl ipCmd, replace %agent% with random useragent string
#                  regex: https://www.regexpal.com/?fam=104038
#                  returns: ipv4/6 address
func_randIp() {
  [ "${debug:-0}" -ge 3 ] && set -x
  ${ipCmdSorted[$((RANDOM % ${#ipCmdSorted[@]}))]/\%agent\%/$agent} 2>/dev/null |
    grep -Pow "${ipRE}" | head -1
  [ "${debug:-0}" -ge 3 ] && set +x
}

# Function sortIpCimd: trim ipCmd array from conf for update_ipv=4|6 and whether we want dig or not
#                      replaces %ipv% with $freenom_update_ipv
#                      creates new array: $ipCmdSorted
func_sortIpCmd() {
  local i
  ipCmdSorted=()
  for ((i = 0; i < ${#ipCmd[@]}; i++)); do
    local skip=0
    # if update_ipv is set to '6', skip ipCmd's that do not not contain '-6'
    if [[ -n "$freenom_update_ipv" && "$freenom_update_ipv" -eq 6 ]]; then
      if [[ "${ipCmd[$i]}" =~ '-4' ]]; then
        skip=1
      fi
      if [ "${debug:-0}" -ge 2 ]; then
        echo "DEBUG: $(date '+%H:%M:%S') sortIpCmd skip=$skip i=$i ipCmd=${ipCmd[$i]}"
      fi
    fi
    # if update_dig is disabled, skip if ipCmd is 'dig'
    if [[ -n "$freenom_update_dig" && "${freenom_update_dig:-0}" -eq 0 ]]; then
      if [[ "${ipCmd[$i]}" =~ ^dig ]]; then skip=1; fi
    fi
    if [ "${skip:-0}" -eq 0 ]; then
      ipCmdSorted+=("${ipCmd[$i]//\%ipv\%/$freenom_update_ipv}")
    else
      i=$((i + 1))
    fi
  done
  if [ "${debug:-0}" -ge 2 ]; then
    for ((i = 0; i < ${#ipCmdSorted[@]}; i++)); do echo "DEBUG: $(date '+%H:%M:%S') sortIpCmd    i=$i ipCmdSorted: ${ipCmdSorted[$i]}"; done
  fi
  if [ ! "${#ipCmdSorted[@]}" -gt 0 ]; then
    echo "Error: no \"get ip\" command found"
    exit 1
  fi
}

# Function ipCheck: compare current ip to file 'freedom_example.cf.ip4'
#                   parameters : $1 = updateDomain
#                   returns    : 0 (ok), 1 (skip)
func_ipCheck() {
  if [ "${freenom_update_force:-0}" -eq 0 ]; then
    if [ "$(cat "${out_path}_${1}.ip${freenom_update_ipv}" 2>&1)" == "$currentIp" ]; then
      return 1
    fi
    return 0
  fi
}

# Function httpOut: set curl result and httpcode
func_httpOut() {
  local _hc_re='<!--http_code=([1-5][0-9][0-9])-->'
  httpCode=""
  httpOut=""
  httpCode="$(echo "$1" | sed -En 's/.*'"$_hc_re"'/\1/p')"
  httpOut="$(echo "$1" | sed -E 's/'"$_hc_re"'//')"
}

# Function httpError: show msg with http error code and retries
#                     $1 = url, $2= title
func_httpError() {
  local showRetry=$retry
  if [ "$retry" -ge "$freenom_http_retry" ]; then
    showRetry=$((retry - 1))
  fi
  local _c403="403 Forbidden"
  local _c500="500 Internal Service Error"
  local _c503="503 Service Temporarily Unavailable"
  local _msg="$2 - httpcode "
  if [ "${httpCode:-"000"}" -eq "403" ] || echo "$1" | grep -q "$_c403"; then
    agent="${uaString[$((RANDOM % ${#uaString[@]}))]}"
    _msg+="$_c403"
  elif [ "${httpCode:-"000"}" -eq "500" ] || echo "$1" | grep -q "$_c500"; then
    _msg+="$_c500"
  elif [ "${httpCode:-"000"}" -eq "503" ] || echo "$1" | grep -q "$_c503"; then
    _msg+="$_c503"
  else
    _msg+="${httpCode:-"000"}"
  fi
  printf "Error: %s (try %s/%s)\\n" "$_msg" "$showRetry" "$freenom_http_retry"
}

# Function lc/uc: convert $1 beween lower and UPPERCASE
func_lc() {
  echo "$@" | tr '[:upper:]' '[:lower:]'
}
func_uc() {
  echo "$@" | tr '[:lower:]' '[:upper:]'
}

# Function sleep: sleep between 'random' min and max seconds
func_sleep() {
  if [[ -n "$freenom_http_sleep" && "$freenom_http_sleep" =~ ^[1-9]+\ [1-9]+$ ]]; then
    min="$(echo "$freenom_http_sleep" | cut -d" " -f1)"
    max="$(echo "$freenom_http_sleep" | cut -d" " -f2)"
    rnd="$(((RANDOM % max) + min))"
    if [ "${debug:-0}" -ge 1 ]; then
      printf "DEBUG: %-*s sleep %s (min=%s max=%s)\n" "21" " " "$rnd" "$min" "$((min + max))"
    fi
    sleep $rnd
  fi
}

# Function mailEvent: send mail
#         parameters: $1: $event 2: $messages
mailEvent() {
  if [ "$MTA" != "" ] && [ "$RCPTTO" != "" ]; then
    if [ "${debug:-0}" -ge 1 ]; then
      echo "DEBUG: $(date '+%H:%M:%S') email $pad4   HOSTNAME=$HOSTNAME MTA=$MTA RCPTTO=$RCPTTO 1=$1 2=$2"
    fi
    [ "${debug:-0}" -ge 3 ] && set -x
    HEADER="To: <$RCPTTO>\n"
    if [ "$MAILFROM" ]; then
      HEADER+="From: $MAILFROM\n"
    fi
    echo -e "${HEADER}Subject: freenom.sh: \"$1\" on \"$HOSTNAME\"\n\nDate: $(date +%F\ %T)\n\n$2" | "$MTA" "$RCPTTO"
    EXITCODE="$?"
    if [ "$EXITCODE" -ne 0 ]; then
      echo "Error: exit code \"$EXITCODE\" while running $MTA"
    fi
    [ "${debug:-0}" -ge 3 ] && set +x
  fi
}

# Function appriseEvent: send Apprise notification
#         parameters: $1: $event 2: $messages
appriseEvent() {
  if [ -s "$APPRISE" ] && [ "${#APPRISE_SERVER_URLS[@]}" -gt 0 ]; then
    if [ "${debug:-0}" -ge 1 ]; then
      echo "DEBUG: $(date '+%H:%M:%S') apprise $pad4   HOSTNAME=$HOSTNAME APPRISE=$APPRISE APPRISE_SERVER_URLS=(${APPRISE_SERVER_URLS[*]}) 1=$1 2=$2"
    fi
    if [ "${debug:-0}" -ge 3 ]; then
      set -x
    fi
    "$APPRISE" --title "freenom.sh: \"$1\" on \"$HOSTNAME\"" --body "$2" "${APPRISE_SERVER_URLS[@]}"
    EXITCODE="$?"
    if [ "$EXITCODE" -ne 0 ]; then
      echo "Error: exit code \"$EXITCODE\" while running $APPRISE"
    fi
    if [ "${debug:-0}" -ge 3 ]; then
      set +x
    fi
  fi
}

# Function setUpdateDomVars: make sure correct domain, record and id are set
func_updateDomVars() {
  local _domain _record
  domId="1234567890"
  [ -n "$freenom_domain_name" ] && _domain="$freenom_domain_name" || _domain="${domainName[$d]}"
  [ -n "$freenom_subdomain_name" ] && _record="$freenom_subdomain_name" || _record="${recName[$r]}"
  [ -n "$freenom_domain_id" ] && domId="$freenom_domain_id" || domId="${domainId[$d]}"
  if [[ -z "${_record}" && -n "${_domain}" ]]; then
    updateDomain="$(func_lc "${_domain}")"
  else
    updateDomain="$(func_lc "${_record:+${_record}.}${_domain}")"
  fi
}

# debug functions

# Function debugHttp: show curl error
func_debugHttp() {
  local showRetry=$retry
  if [ "$retry" -ge "$freenom_http_retry" ]; then
    showRetry=$((retry - 1))
  fi
  printf "DEBUG: %s %-12s curl %s (retry=%s/%s http_code=%s errCount=%s)\n" \
    "$(date '+%H:%M:%S')" "$1" "$2" "$showRetry" "$freenom_http_retry" "$httpCode" "$errCount"
}

# Function debugVars: debug output args, actions etc
func_debugVars() {
  echo "DEBUG: $pad8 args $pad4    debug=$debug curlExtraOpts=$curlExtraOpts"
  echo "DEBUG: $pad8 args $pad4    1=$1 2=$2 3=$3 4=$4 5=$5 6=$6 7=$7 8=$8 9=$9"
  echo "DEBUG: $pad8 opts/conf    freenom_out_dir=$freenom_out_dir freenom_out_mask=$freenom_out_mask out_path=$out_path"
  echo "DEBUG: $pad8 opts/conf    freenom_domain_name=$freenom_domain_name freenom_domain_id=$freenom_domain_id freenom_subdomain_name=$freenom_subdomain_name"
  echo "DEBUG: $pad8 opts/conf    freenom_static_ip=$freenom_static_ip"
  echo "DEBUG: $pad8 action $pad4  freenom_update_ip=$freenom_update_ip freenom_update_force=$freenom_update_force freenom_update_manual=$freenom_update_manual freenom_update_all=$freenom_update_all"
  echo "DEBUG: $pad8 action $pad4  freenom_list_records=$freenom_list_records freenom_list=$freenom_list freenom_list_renewals=$freenom_list_renewals"
  echo "DEBUG: $pad8 action $pad4  freenom_renew_domain=$freenom_renew_domain freenom_renew_all=$freenom_renew_all"
}

# Function debugArrays: show domain Id, Name, Expiry
# shellcheck disable=2317
func_debugArrays() {
  echo "DEBUG: $pad8 arrays domainId domainName domainExpiryDate:"
  echo "${domainId[@]}"
  echo "${domainName[@]}"
  echo "${domainExpiryDate[@]}"
}

# Function debugMyDomainsResult
# shellcheck disable=2317
func_debugMyDomainsResult() {
  if [ "${debug:-0}" -ge 1 ]; then
    IFS_SAVE=$IFS
    IFS=$'\n'
    local i=""
    # shellcheck disable=SC2116
    for i in $(echo "$myDomainsResult"); do
      if [ "${debug:-0}" -ge 2 ]; then
        echo "DEBUG: $pad8 myDomainsResult i=$i"
      fi
      domainResult="$(echo "$i" | cut -d " " -f2)"
      domainIdResult="$(echo "$i" | cut -d " " -f4)"
    done
    echo "DEBUG: $pad8 myDomainsResult domainResult: $domainResult domainIdResult: $domainIdResult"
    IFS=$IFS_SAVE
  fi
}

###############################################################################
# Note that there are 6 more inline Functions placed down below
#   Dns:
#     - Function getDnsPage: get DNS Management Page
#     - Function getRec: get domain records from dnsManagementPage
#     - Function setRec: add/modify domain records
#   Renew:
#     - Function renewDate: check date to make sure we can renew
#     - Function renewDomain: if date is ok; submit actual renewal, get result
###############################################################################

###########
# Options #
###########

unset -v a

# handle debug
if printf -- "%s" "$*" | grep -Eiq '(^|[^a-z])-debug'; then
  debug="$(echo "$*" | sed -E 's/.*-debug ([0-9]) ?.*/\1/')"
  if [[ ! "$debug" =~ ^[0-9]$ ]]; then
    debug=0
  fi
fi
# show help
#if printf -- "%s" "$*" | grep -Eqi '(^|[^a-z])-h'; then
# shellcheck disable=2317
if [ "${help:-0}" -eq 1 ]; then
  func_help
  exit 0
fi
# handle all other arguments
if ! printf -- "%s" "$*" | grep -Eqi -- '-[46lruziceo]'; then
  echo "Error: invalid or unknown argument(s), try \"$scriptName -h\""
  exit 1
fi
# ipv4/6
if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-4'; then
  freenom_update_ipv=4
  if [ "${debug:-0}" -ge 1 ]; then
    echo "DEBUG: $pad8 ipv freenom_update_ipv=$freenom_update_ipv"
  fi
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-6'; then
  freenom_update_ipv=6
  if [ "${debug:-0}" -ge 1 ]; then
    echo "DEBUG: $pad8 ipv freenom_update_ipv=$freenom_update_ipv"
  fi
fi
# list domains and id's and exit, unless list_records is set
if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-l'; then
  freenom_list="1"
  lMsg=""
  # list domains with details
  a="$(echo "$*" | sed -E 's/ ?-debug ([0-9])//')"
  if printf -- "%s" "$a" | grep -Eqi -- '(^|[^a-z])-[dn]'; then
    freenom_list_renewals="1"
    lMsg=" with renewal details, this might take a while"
  fi
  printf "\nListing Domains and ID's%s...\n" "$lMsg"
  echo
# list dns records
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-z'; then
  printf "\nListing Domain Record(s)%s...\n" "$lMsg"
  echo
  func_getDomainArgs "$@"
  freenom_list_records="1"
# output ipcmd list
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-i'; then
  if [ "${debug:-0}" -ge 1 ]; then
    echo "DEBUG: $pad8 ipv freenom_update_ipv=$freenom_update_ipv"
  fi
  printf "\nListing all \"get ip\" commands..."
  echo
  for ((i = 0; i < ${#ipCmd[@]}; i++)); do
    printf "%2s: %s\n" "$i" "${ipCmd[$i]}"
  done
  printf "\nNOTES:\n"
  printf "  %%ipv%% gets replaced by \$freenom_update_ipv ('4' or '6')\n"
  printf "  %%agent%% gets replaced with useragent string from conf\n\n"
  exit 0
# update ip
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-u'; then
  freenom_update_ip="1"
  a="$*"
  if printf -- "%s" "$a" | grep -Eiq -- '(^|[^a-z])-f'; then
    freenom_update_force="1"
    a="$(echo "$a" | sed -E 's/ ?-f//')"
  fi
  if printf -- "%s" "$a" | grep -Eiq -- '(^|[^a-z])-m'; then
    freenom_update_manual="1"
    arg_static_ip="$(echo "$a" | sed -n -E 's/.*-m ('"$ipRE"')([^0-9].*)?/\1/p')"
    if [ -n "$arg_static_ip" ]; then
      freenom_static_ip="$arg_static_ip"
    fi
    if [[ ! "$freenom_static_ip" =~ ^$ipRE$ ]]; then
      freenom_static_ip=""
    fi
  fi
  # TEST: update all records
  if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-a'; then
    freenom_update_all="1"
  fi
  func_getDomainArgs "$@"
# renew domains
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-r'; then
  freenom_renew_domain="1"
  if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-a'; then
    freenom_renew_all="1"
  else
    func_getDomainArgs "$@"
  fi
# show update and renewal result file(s)
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])-[eo]'; then
  # use regex if file is specfied
  fget="$(printf -- "%s\n" "$*" | sed -En 's/.* ?-[eo] ?([][a-zA-Z0-9 !"#$%&'\''()*+,-.:;<=>?@^_`{}~.]+)[ -]?.*/\1/gp')"
  if [ -z "$fget" ]; then
    for f in "${out_path}"_renewalResult-*.html; do
      if [ -e "$f" ]; then fget+="$f "; fi
    done
    count="$(echo "$fget" | wc -w)"
    if [ "${count:-0}" -eq 0 ]; then
      echo "No result file(s) found"
      exit 0
    elif [ "${count-0}" -gt 1 ]; then
      printf "\nMultiple results found, listing %d html files:\n" "$count"
      for rf in $fget; do
        find "$rf" -printf '  [%TF %TH:%TM] %f\n'
      done
      printf "\nTo show a file use: \"%s -o <file.html>\"\n\n" "$scriptName"
      exit 0
    fi
  fi
  fdir="$(dirname "$out_path")"
  if ! echo "$fget" | grep -q "$fdir"; then
    ffile="$(dirname "$out_path")/$fget"
  else
    ffile="$fget"
  fi
  if [ -s "$ffile" ]; then
    func_showResult "$ffile"
  else
    echo "Result file not found"
  fi
  exit 0
else
  func_help
fi

# more config checks: if these vars are missing, set defaults
if [ -z "$freenom_http_retry" ]; then freenom_http_retry=1; fi
if [ -z "$freenom_list" ]; then freenom_list=0; fi
if [ -z "$freenom_list_records" ]; then freenom_list_records=0; fi
if [ -z "$freenom_list_renewals" ]; then freenom_list_renewals=0; fi
if [ -z "$freenom_renew_all" ]; then freenom_renew_all=0; fi
if [ -z "$freenom_update_force" ]; then freenom_update_force=0; fi
if [ -z "$freenom_update_ip" ]; then freenom_update_ip=0; fi
if [ -z "$freenom_update_ipv" ]; then freenom_update_ipv=4; fi
if [ -z "$freenom_update_ttl" ]; then freenom_update_ttl="3600"; fi
if [ -z "$freenom_update_ip_retry" ]; then freenom_update_ip_retry=3; fi

if [ "${debug:-0}" -ge 1 ]; then
  func_debugVars "$@"
fi

# log start msg
if [ "${freenom_update_ip:-0}" -eq 1 ]; then
  func_updateDomVars
  if [[ -n "$freenom_update_ip_log" && "${freenom_update_ip_log:-0}" -eq 1 ]]; then
    echo -e "[$(date)] [$$] Start: Update ip of \"${updateDomain}\"" >>"${out_path}.log"
  else
    printf "[%s] Start: Update ip of \"%s\" $(date)" "${updateDomain}"
  fi
elif [[ "${freenom_renew_domain:-0}" -eq 1 || "${freenom_renew_all:-0}" -eq 1 ]]; then
  if [[ -n "${freenom_renew_log:-0}" && "${freenom_renew_log:-0}" -eq 1 ]]; then
    echo -e "[$(date)] [$$] Start: Domain renewal" >>"${out_path}.log"
  else
    printf "[%s] Start: Domain renewal" "$(date)"
  fi
fi

##########
# Get IP #
##########

if [ "${freenom_update_ip:-0}" -eq 1 ]; then
  if [[ -n "$freenom_update_manual" && "${freenom_update_manual:-0}" -eq 0 ]]; then
    func_sortIpCmd
    i=0
    # try getting ip by running random ipCmd(s), stop after max retries
    while [[ "$currentIp" == "" && "$i" -lt "$freenom_update_ip_retry" ]]; do
      currentIp="$(func_randIp || true)"
      i=$((i + 1))
    done
    if [ "$currentIp" == "" ]; then
      eMsg="Could not get current local ip address"
    fi
  else
    if [ "$freenom_static_ip" != "" ]; then
      currentIp="$freenom_static_ip"
    else
      eMsg="Valid static ip address missing for manual update"
      uMsg="\n%7sUse \"-m <ip>\" or remove static option for auto detect\n"
    fi
  fi
  # shellcheck disable=SC2059
  if [ "$currentIp" == "" ]; then
    printf "Error: ${eMsg}${uMsg}\n"
    echo "[$(date)] [$$] Error: $eMsg" >>"${out_path}.log"
    exit 1
  fi
  # ipcheck single domain
  if [[ -n "$freenom_update_all" && "${freenom_update_all:-0}" -eq 0 ]]; then
    func_updateDomVars
    if ! func_ipCheck "$updateDomain"; then
      if [[ -n "$freenom_update_ip_log" && "${freenom_update_ip_log:-0}" -eq 1 ]]; then
        uMsg="Update: Skipping \"${updateDomain}\" - found same ip \"$currentIp\""
        echo "$uMsg"
        echo "[$(date)] [$$] $uMsg" >>"${out_path}.log"
        echo "[$(date)] [$$] Done" >>"${out_path}.log"
      fi
      exit 0
    fi
  fi
fi

#########
# Login #
#########

retry=1
while [ "$retry" -le "$freenom_http_retry" ]; do
  cookie_file="$(mktemp)"
  if [ "${debug:-0}" -ge 1 ]; then
    echo "DEBUG: $pad8 logintoken   cookie_file=$cookie_file"
  fi
  # DEBUG: comment 'loginPage' line below for debugging
  # shellcheck disable=SC2086
  loginPage="$(curl $c_opts $curlExtraOpts -A "$agent" -c "$cookie_file" -w "$http_code" \
    "https://my.freenom.com/clientarea.php" 2>&1)" || { \
      eMsg="Error: Login token - failure (curl error code: $?)"
      echo "$eMsg"
      echo "[$(date)] [$$] $eMsg" >>"${out_path}.log"
      exit 1
    }
  func_httpOut "$loginPage"
  loginPage="$httpOut"
  if [ "${httpCode:-"000"}" -eq "200" ]; then
    if echo "$loginPage" | grep -q "token.*value="; then
      # token length is 40 chars, numbers and lowercase letters a-f
      token="$(echo "$loginPage" | grep -E -m 1 -o '[0-9a-f]{40}')"
      break
    else
      printf "Error: Login token - value not found (try %s/%s)\\n" "$retry" "$freenom_http_retry"
      retry="$((retry + 1))"
    fi
  else
    # handle http status other than '200'
    func_httpError "$loginPage" "Login token"
    retry="$((retry + 1))"
  fi
done
if [ "${debug:-0}" -ge 1 ]; then
  func_debugHttp "logintoken" "clientarea token=$token"
fi
if [ -z "$token" ]; then
  eMsg="Error: Login token - value empty after $freenom_http_retry max tries, exiting..."
  echo "$eMsg"
  echo "[$(date)] [$$] $eMsg" >>"${out_path}.log"
  exit 1
fi

retry=1
clientareaURL="https://my.freenom.com/clientarea.php"
dologinURL="https://my.freenom.com/dologin.php"
while [ "$retry" -le "$freenom_http_retry" ]; do
  # DEBUG: comment loginResult for debugging
  if [ "${oldCurl:-0}   " -eq 1 ]; then
    # shellcheck disable=SC2086
    loginResult="$(curl $c_opts $curlExtraOpts -A "$agent" -e "$clientareaURL" -c "$cookie_file" -w "$http_code" \
      -F "username=$freenom_email" -F "password=$freenom_passwd" -F "token=$token" "$dologinURL")"
  else
    # shellcheck disable=SC2086
    loginResult="$(curl $c_opts $curlExtraOpts -A "$agent" -e "$clientareaURL" -c "$cookie_file" -w "$http_code" \
      -F "username=$freenom_email" -F "password=\"$freenom_passwd\"" -F "token=$token" "$dologinURL")"
  fi
  func_httpOut "$loginResult"
  loginResult="$httpOut"
  incorrectPat="Location: /clientarea.php\?incorrect=true|Login Details Incorrect"
  if [ "$(echo -e "$loginResult" | grep -E "$incorrectPat")" != "" ]; then
    eMsg="Error: Login failed, incorrect details"
    echo "$eMsg"
    echo "[$(date)] [$$] $eMsg" >>"${out_path}.log"
    exit 1
  fi
  if [ "${httpCode:-"000"}" -eq "200" ]; then
    break
  else
    func_httpError "$loginResult" "Login"
    retry="$((retry + 1))"
  fi
done
if [ "${debug:-0}" -ge 1 ]; then
  func_debugHttp "login" "dologin.php username=$freenom_email"
fi
if [ "$retry" -gt "$freenom_http_retry" ]; then
  eMsg="Error: Login - max retries $freenom_http_retry was reached, exiting..."
  echo "$eMsg"
  echo "[$(date)] [$$] $eMsg" >>"${out_path}.log"
  exit 1
fi

###################
# Get Domain info #
###################

# Retrieve client area page, get domain detail urls and loop over them to get all data
# arrays: domainId, domainName, domainRegDate, domainExpiryDate

# shellcheck disable=SC2004
if [ "$freenom_domain_id" == "" ]; then
  myDomainsURL="https://my.freenom.com/clientarea.php?action=domains&itemlimit=all&token=$token"
  # DEBUG: for debugging use local file instead:
  # DEBUG: myDomainsURL="file:///home/user/src/freenom/myDomainsPage"
  retry=1
  # first get mydomains page
  while [ "$retry" -le "$freenom_http_retry" ]; do
    if [ "${debug:-0}" -ge 1 ]; then
      func_debugHttp "domains" "myDomainsPage"
    fi
    # shellcheck disable=SC2086
    myDomainsPage="$(curl $c_opts $curlExtraOpts -A "$agent" -b "$cookie_file" -w "$http_code" "$myDomainsURL")"
    func_httpOut "$myDomainsPage"
    myDomainsPage="$httpOut"
    if [ "${httpCode:-"000"}" -eq "200" ]; then
      break
    else
      func_httpError "$myDomainsPage" "My domains page"
      retry="$((retry + 1))"
    fi
  done
  if [ "$retry" -gt "$freenom_http_retry" ]; then
    eMsg="Error: My domains page - $freenom_http_retry max retries was reached, exiting..."
    echo "$eMsg"
    echo "[$(date)] [$$] $eMsg" >>"${out_path}.log"
    exit 1
  fi
  # if we have mydomains page, get domaindetails url(s) from result
  if [ -n "$myDomainsPage" ]; then
    # old: myDomainsResult="$( echo -e "$myDomainsPage" | sed -n '/href.*external-link/,/action=domaindetails/p' | sed -n 's/.*id=\([0-9]\+\).*/\1/p;g' )"
    myDomainsResult="$(echo -e "$myDomainsPage" | sed -n 's/.*"\(clientarea.php?action=domaindetails&id=[0-9]\+\)".*/\1/p;g')"
    if [[ "${freenom_update_ip:-0}" -eq 1 || "${freenom_list_records:-0}" -eq 1 ]]; then
      # on ip update or list_records reverse sort newest first to possibly get a quicker match below
      myDomainsResult=$(echo "$myDomainsResult" | tr ' ' '\n' | sort -r)
    fi
    i=0
    # iterate over domaindetails url(s)
    for url in $myDomainsResult; do
      retry=1
      while [ "$retry" -le "$freenom_http_retry" ]; do
        if [ "${debug:-0}" -ge 1 ]; then
          func_debugHttp "domains" "domainDetails"
        fi
        # DEBUG: for debugging use local file instead:
        #        domainDetails=$( curl $c_opts $curlExtraOpts -A "$agent" -b "$cookie_file" -w "$http_code" "file:///home/user/src/freenom/domainDetails_$i.bak" )
        # shellcheck disable=SC2086
        domainDetails="$(curl $c_opts $curlExtraOpts -A "$agent" -b "$cookie_file" -w "$http_code" "https://my.freenom.com/$url")"
        func_httpOut "$domainDetails"
        domainDetails="$httpOut"
        if [ "${httpCode:-"000"}" -eq "200" ]; then
          domainId[$i]="$(echo "$url" | sed -n 's/.*id=\([0-9]\+\).*/\1/p;g')"
          domainName[$i]="$(echo -e "$domainDetails" | sed -n 's/.*Domain:\(.*\)<[a-z].*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g')"
          if [ "${debug:-0}" -ge 1 ]; then
            echo "DEBUG: $(date '+%H:%M:%S') domains $pad4 domainId=${domainId[$i]} domainName=${domainName[$i]} (${#domainId[@]}/$(echo "$myDomainsResult" | wc -w))"
          fi
          break
        else
          func_httpError "$domainDetails" "Domain details"
          retry="$((retry + 1))"
        fi
      done
      # on ip update or list_records we just need domain name matched and id set
      if [[ "${freenom_update_ip:-0}" -eq 1 || "${freenom_list_records:-0}" -eq 1 ]]; then
        if [ "${domainName[$i]}" == "$freenom_domain_name" ]; then
          freenom_domain_id="${domainId[$i]}"
          if [ "${debug:-0}" -ge 1 ]; then
            echo "DEBUG: $pad8 domains $pad4 MATCH: \"${domainName[$i]}\" == \"$freenom_domain_name\""
          fi
          break
        fi
      # for renewals we also need to get expiry date
      elif [[ "${freenom_renew_domain:-0}" -eq 1 || "${freenom_list:-0}" -eq 1 || "${freenom_list_renewals:-0}" -eq 1 ]]; then
        domainRegDate[$i]="$(echo -e "$domainDetails" | sed -n 's/.*Registration Date:\(.*\)<.*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g')"
        domainExpiryDate[$i]="$(echo -e "$domainDetails" | sed -n 's/.*Expiry date:\(.*\)<.*/\1/p' | sed 's/<[^>]\+>//g')"
        if [ "${debug:-0}" -ge 1 ]; then echo "DEBUG: $pad8 domains $pad4 domainRegDate=${domainRegDate[$i]} domainExpiryDate=${domainExpiryDate[$i]}"; fi
      fi
      i=$((i + 1))
      func_sleep
    done
  fi
else
  # XXX: if we already have domain_id and name; copy to domainId and Name array, for list and renewals also get reg/expiry date
  domainId[0]="${freenom_domain_id}"
  domainName[0]="${freenom_domain_name}"
  if [ "${freenom_list:-0}" -eq 1 ] || [[ "${freenom_renew_all:-0}" -eq 0 && "${freenom_renew_domain:-0}" -eq 1 ]]; then
    retry=1
    while [ "$retry" -le "$freenom_http_retry" ]; do
      if [ "${debug:-0}" -ge 1 ]; then
        func_debugHttp "domainDetails"
      fi
      # shellcheck disable=SC2086
      domainDetails="$(curl $c_opts $curlExtraOpts -A "$agent" -b "$cookie_file" -w "$http_code" "https://my.freenom.com/clientarea.php?action=domaindetails&id=${freenom_domain_id}")"
      func_httpOut "$domainDetails"
      domainDetails="$httpOut"
      if [ "${httpCode:-"000"}" -eq "200" ]; then
        domainRegDate[0]="$(echo -e "$domainDetails" | sed -n 's/.*Registration Date:\(.*\)<.*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g')"
        domainExpiryDate[0]="$(echo -e "$domainDetails" | sed -n 's/.*Expiry date:\(.*\)<.*/\1/p' | sed 's/<[^>]\+>//g')"
        break
      else
        func_httpError "$domainDetails" "Domain details"
        retry="$((retry + 1))"
      fi
    done
  fi
fi

# On update_ip, renew_domain or list_records; get domain_id if its empty
# also show error msg and exit if id or name is missing (e.g. wrong name as arg)
if [[ "${freenom_renew_domain:-0}" -eq 1 && "$freenom_domain_id" ]] ||
  [[ "${freenom_update_ip:-0}" -eq 1 && "${freenom_update_all:-0}" -eq 0 && "$freenom_domain_id" == "" ]] ||
  [[ "${freenom_list_renewals:-0}" -eq 1 && "$freenom_domain_id" == "" ]]; then
  for ((i = 0; i < ${#domainName[@]}; i++)); do
    if [ "${debug:-0}" -ge 1 ]; then echo "DEBUG: $(date '+%H:%M:%S') domainname i=$i domainName=${domainName[$i]}"; fi
    if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then
      freenom_domain_id="${domainId[$i]}"
      if [ "${debug:-0}" -ge 1 ]; then
        echo "DEBUG: $pad8 domainname match: freenom_domain_name=$freenom_domain_name ${domainName[$i]} (freenom_domain_id=${domainId[$i]}"
      fi
    fi
  done
  uMsg="Try \"$scriptName [-u|-r|-z] [domain] [id] [-s subdomain]\""
  cMsg="Or, set \"freenom_domain_name\" in config"
  if [ "$freenom_domain_id" == "" ]; then
    [ "$freenom_domain_name" != "" ] && fMsg=" for \"$freenom_domain_name\""
    echo -e "[$(date)] [$$] Error: Domain renewal - No Domain ID \"$freenom_domain_name\"" >>"${out_path}.log"
    printf "Error: Could not find Domain ID%s\n%7s%s\n%7s%s\n\n" "$fMsg" ' ' "$uMsg" ' ' "$cMsg"
    exit 1
  fi
  if [ "$freenom_domain_name" == "" ]; then
    if [ "$freenom_domain_id" != "" ]; then iMsg=" ($freenom_domain_id)"; fi
    echo -e "[$(date)] [$$] Error: Domain renewal - Domain Name missing${iMsg}" >>"${out_path}.log"
    printf "Error: Domain Name missing\n%7s%s\n%7s%s\n\n" ' ' "$uMsg" ' ' "$cMsg"
    exit 1
  fi
fi

###############
# DNS Records #
###############

# Function getDnsPage: get DNS Management Page
#                      parameters: $1 = $freenom_domain_name $2 = $freenom_domain_id
func_getDnsPage() {
  retry=1
  dnsManagementURL="https://my.freenom.com/clientarea.php?managedns=${1}&domainid=${2}"
  while [ "$retry" -le "$freenom_http_retry" ]; do
    if [ "${debug:-0}" -ge 1 ]; then
      func_debugHttp "managedns" "dnsManagementPage"
    fi
    # shellcheck disable=SC2086
    dnsManagementPage="$(curl $c_opts $curlExtraOpts -A "$agent" -b "$cookie_file" -w "$http_code" "$dnsManagementURL")"
    if [ "${debug:-0}" -ge 4 ]; then
      echo "$dnsManagementPage" >"/tmp/$(date +%F_%H%M%S)-dnsManagementPage.html"
      echo "DEBUG: $pad8 dnsManagementPage saved to /tmp/$(date +%F_%H%M%S)-dnsManagementPage.html"
    fi
    func_httpOut "$dnsManagementPage"
    dnsManagementPage="$httpOut"
    if [ "${httpCode:-"000"}" -eq "200" ]; then
      break
    else
      func_httpError "$dnsManagementPage" "DNS Management Page"
      retry="$((retry + 1))"
    fi
  done
  if [ "$retry" -gt "$freenom_http_retry" ]; then
    eMsg="Error: DNS Management Page - $freenom_http_retry maximum retries was reached, exiting..."
    echo "$eMsg"
    echo "[$(date)] [$$] $eMsg" >>"${out_path}.log"
    exit 1
  fi
}

# Function getRec: get domain records from dnsManagementPage
#          parameters : $1 = domain name
#          returns    : v1 = recnum, v2 = type|name|ttl|value, v3 = recname/value(ip), records
#                       sets v3 to uppercase domain if 'name' is empty
# shellcheck disable=SC2004
func_getRec() {
  IFS_SAVE=$IFS
  IFS=$'\n'
  local _line=""
  local _v1=""
  local _v2=""
  local _v3=""
  for _line in $(echo -e "$dnsManagementPage" | tr '<' '\n' |
    sed -r -n 's/.*records\[([0-9]+)\]\[(type|name|ttl|value)\]\" value=\"([0-9a-zA-Z:\.-]*)\".*/\1 \2 \3/p;g'); do
    IFS=" " read -r _v1 _v2 _v3 <<<"$_line"
    if [ "$_v1" != "" ]; then
      case "$_v2" in
      line) recLine[$_v1]="$_v3" ;;
      type) recType[$_v1]="$_v3" ;;
      name) recName[$_v1]="$_v3" ;;
      ttl) recTTL[$_v1]="$_v3" ;;
      value) recValue[$_v1]="$_v3" ;;
      esac
    fi
    if [ "${debug:-0}" -ge 2 ]; then
      echo "DEBUG: $pad8 func_getRec  v1=$_v1 v2=$_v2 v3=$_v3"
    fi
  done

  # create 'records' array, with params formatted for curl
  local r
  local _rpf="&records"
  records=()
  for ((r = 0; r < ${#recType[@]}; r++)); do
    records[$r]="${_rpf}[${r}][line]=${recLine[$r]}"
    records[$r]+="${_rpf}[${r}][type]=${recType[$r]}"
    records[$r]+="${_rpf}[${r}][name]=${recName[$r]}"
    records[$r]+="${_rpf}[${r}][ttl]=${recTTL[$r]}"
    records[$r]+="${_rpf}[${r}][value]=${recValue[$r]}"
    if [ "${debug:-0}" -ge 2 ]; then
      echo "DEBUG: $pad8 func_getRec  r=$r records array ${records[$r]}"
    fi
  done
  IFS=$IFS_SAVE
}

# Function setRec: add/modify domain records using dnsManagementURL and log
#                  parameters: $1 = subdomain or empty for apex domain (add)
#
# XXX: These are other record options
#        -F "${recKey}[port]="             -F "${recKey}[priority]="
#        -F "${recKey}[forward_type]=1"    -F "${recKey}[weight]="
#
func_setRec() {
  retry=1
  local _rec_enc
  while [ "$retry" -le "$freenom_http_retry" ]; do
    if [ "$dnsAction" = "add" ]; then
      if [ "${debug:-0}" -ge 1 ]; then
        printf "DEBUG: %s func_setRec  r=%s rec_cnt=%s recType=%s recName=%s recTTL=%s recValue=%s dnsAction=%s" \
          "$pad8" "$r" "${#recType[@]}" "${recType[$r]}" "${recName[$r]}" "${recTTL[$r]}" "${recValue[$r]}" "$dnsAction"
      fi
      if [ "${debug:-0}" -ge 2 ]; then
        printf "DEBUG: $pad8 func_setRec  curl %s -e 'https://my.freenom.com/clientarea.php' -b \"%s\" -w \"%s\" -F \"dnsaction=%s\"" \
          "$pad8" "$c_opts $curlExtraOpts" "$cookie_file" "$http_code" "$dnsAction"
        printf "DEBUG: $pad8 $pad8 $pad8    -F \"%s[name]=%s\" -F \"%s[type]=%s\" -F \"%s[ttl]=%s\" -F \"%s[value]=%s\"" \
          "$pad8" "$pad8" "$pad8" "${recKey}" "${1}" "${recKey}" "${freenom_update_type}" "${recKey}" "${freenom_update_ttl}" "${recKey}" "${currentIp}" \
          printf "DEBUG: $pad8 $pad8 $pad8    -F \"token=%s\" \"%s\"" \
          "$pad8" "$pad8" "$pad8" "$token" "$dnsManagementURL"
      fi
      # shellcheck disable=SC2086
      updateResult=$(curl $c_opts $curlExtraOpts -A "$agent" -e 'https://my.freenom.com/clientarea.php' -b "$cookie_file" -w "$http_code" \
        -F "token=$token" \
        -F "dnsaction=$dnsAction" \
        -F "${recKey}[line]=" \
        -F "${recKey}[type]=${freenom_update_type}" \
        -F "${recKey}[name]=${1}" \
        -F "${recKey}[ttl]=${freenom_update_ttl}" \
        -F "${recKey}[value]=${currentIp}" \
        "$dnsManagementURL" 2>&1)
    elif [ "$dnsAction" = "modify" ]; then
      _rec_enc="$(echo "${records[*]}" | sed -e 's/ //g' -e 's/\[/%5B/g' -e 's/\]/%5D/g')"
      if [ "${debug:-0}" -ge 2 ]; then
        echo "DEBUG: $pad8 func_setRec  data \"token=${token}&dnsaction=${dnsAction}${_rec_enc}\""
      fi
      if [ "${debug:-0}" -ge 1 ]; then
        echo -n "DEBUG: $pad8 func_setRec  url decoded data:"
        echo "$_rec_enc" | sed -e "s/&/\nDEBUG: $pad8 $pad8 $pad8/g" -e 's/%5B/\[/g' -e 's/%5D/\]/g'
      fi
      # shellcheck disable=SC2086
      updateResult=$(curl $c_opts $curlExtraOpts -A "$agent" -e 'https://my.freenom.com/clientarea.php' -b "$cookie_file" -w "$http_code" \
        --data-raw "token=${token}&dnsaction=${dnsAction}${_rec_enc}" \
        "$dnsManagementURL" 2>&1)
    fi
    if [ "${debug:-0}" -ge 1 ]; then
      func_debugHttp "func_setRec" "updateResult"
    fi
    func_httpOut "$updateResult"
    updateResult="$httpOut"
    if [ "${httpCode:-"000"}" -eq "200" ]; then
      break
    else
      retry="$((retry + 1))"
      func_httpError "$updateResult" "Update result"
    fi
  done
  # log results: for single records iterate one time
  local _max=1
  if [[ -n "$freenom_update_all" && "${freenom_update_all:-0}" -eq 1 ]]; then
    _max="${#recType[@]}"
  fi
  for ((r = 0; r < _max; r++)); do
    func_updateDomVars
    if [ "$(echo -e "$updateResult" | grep '"dnssuccess"')" != "" ] && [ "$(echo -e "$updateResult" | grep "$currentIp")" != "" ]; then
      if [[ "${freenom_update_ip:-0}" -eq 1 && "${freenom_update_all:-0}" -eq 0 ]]; then
        updateOk="\"${updateDomain}\" (${domId})"
      elif [[ -n "$freenom_update_all" && "${freenom_update_all:-0}" -eq 1 ]]; then
        updateOk="$updateOk\n  OK: \"${updateDomain}\" (${domId})"
      fi
      # write current ip to file 'freedom_example.cf.ip4'
      echo -n "$currentIp" >"${out_path}_${updateDomain}.ip${freenom_update_ipv}"
    else
      updateError="$updateError\n  Could not update record \"${updateDomain}\" ($domId)"
      updateErrMsg="$(echo -e "$updateResult" | grep '"dnserror"')"
      if [ "$updateErrMsg" != "" ]; then
        if [ "$(echo -e "$updateErrMsg" | grep "There were no changes")" != "" ]; then
          echo -n "$currentIp" >"${out_path}_${updateDomain}.ip${freenom_update_ipv}"
        fi
        errMsg="$(echo "$updateErrMsg" | sed -e 's/<[^>]\+>//g' -e 's/\(  \|\t\|^M\)//g' | sed ':a;N;$!ba;s/\n/, /g')"
        updateError+=" - \"${errMsg}\""
      fi
      errCount="$((errCount + 1))"
      if [ "${debug:-0}" -ge 1 ]; then
        # echo -e "$updateResult" > "${out_path}_errorUpdateResult-${domId}.html"
        printf "DEBUG: %s func_setRec  skipped saving updateResult to \"%s_errorUpdateResult-%s_%s.html\"" \
          "$pad8" "${out_path}" "${recName[$r]}" "${domId}"
      fi
    fi
    if [ "${debug:-0}" -ge 1 ]; then
      printf "DEBUG: %s func_setRec  log currentIp=%s ipfile=%s_%s.ip%s domId=%s" \
        "$pad8" "$currentIp" "${out_path}" "${updateDomain}" "${freenom_update_ipv}" "$domId"
    fi
  done
}

if [[ "${freenom_update_ip:-0}" -eq 1 || "${freenom_list_records:-0}" -eq 1 ]]; then
  func_getDnsPage "$freenom_domain_name" "$freenom_domain_id"
fi

# call getRec function to list records
if [ "${freenom_list_records:-0}" -eq 1 ]; then
  func_getRec "$freenom_domain_name"
  printf "DNS Zone: \"%s\" (%s)\n\n" "$freenom_domain_name" "$freenom_domain_id"
  if [ "${#recType[@]}" -gt 0 ]; then
    for ((i = 0; i < ${#recType[@]}; i++)); do
      if [ "${debug:-0}" -ge 3 ]; then
        printf "DEBUG: %s list_records func_getRec i=%s recType->count=%s recType=%s recName=%s recTTL=%s recValue=%s" \
          "$pad8" "$i" "${#recType[@]}" "${recType[$i]}" "${recName[$i]}" "${recTTL[$i]}" "${recValue[$i]}"
      fi
      # subdomains
      if [ -n "$freenom_subdomain_name" ]; then
        if [ "${recName[$i]}" == "$(func_uc "$freenom_subdomain_name")" ]; then
          printf "Subdomain Record: name=\"%s\" ttl=\"%s\" type=\"%s\" value=\"%s\"\n" \
            "${recName[$i]}" "${recTTL[$i]}" "${recType[$i]}" "${recValue[$i]}"
          break
        fi
      # domains: format can be 'plain' (default) or 'bind'
      else
        if [[ -n "$freenom_list_bind" && "${freenom_list_bind:-0}" -eq 1 ]]; then
          rn="$(func_lc "${recName[$i]}")"
          # change rn to '@' for apex domain
          if [ "${recName[$i]}" == "$(func_uc "$freenom_domain_name")" ]; then
            rn="@"
          fi
          printf "%s\t\t%s\tIN\t%s\t%s\n" "$rn" "${recTTL[$i]}" "${recType[$i]}" "${recValue[$i]}"
        else
          printf "Domain Record: name=\"%s\" ttl=\"%s\" type=\"%s\" value=\"%s\"\n" \
            "${recName[$i]}" "${recTTL[$i]}" "${recType[$i]}" "${recValue[$i]}"
        fi
      fi
    done
  else
    echo "No records found"
  fi
  echo
  exit 0
fi

######################
# Dynamic DNS Update #
######################

# Update ip: if record does not exist add a new record or if it does update the record

# set correct type for ipv4 or ipv6 address
freenom_update_type="A"
if [[ -n "$freenom_update_ipv" && "$freenom_update_ipv" -eq 4 ]]; then
  freenom_update_type="A"
elif [[ -n "$freenom_update_ipv" && "$freenom_update_ipv" -eq 6 ]]; then
  freenom_update_type="AAAA"
elif [[ "$currentIp" =~ ^(([0-9]{1,3}\.){1}([0-9]{1,3}\.){2}[0-9]{1,3})$ ]]; then
  freenom_update_type="A"
elif [[ "$currentIp" =~ ^[0-9a-fA-F]{1,4}: ]]; then
  freenom_update_type="AAAA"
fi

# handle updating single domain and record
# shellcheck disable=SC2004
if [[ "${freenom_update_ip:-0}" -eq 1 && "${freenom_update_all:-0}" -eq 0 ]]; then
  dnsEmpty="0"
  recMatch="0"
  # if theres no record at all: use 'add'
  if [ "$(echo "$dnsManagementPage" | grep -F "records[0]")" == "" ]; then
    recKey="addrecord[0]"
    dnsAction="add"
    dnsEmpty=1
  else
    # find matching record
    func_getRec "$freenom_domain_name"
    for ((r = 0; r < ${#recType[@]}; r++)); do
      if [ "${debug:-0}" -ge 1 ]; then
        echo "DEBUG: $pad8 update_ip    r=$r rec_cnt=${#recType[@]} recType=${recType[$r]} recName=${recName[$r]} recTTL=${recTTL[$r]} recValue=${recValue[$r]}"
      fi
      # make sure its the same recType (ipv4 or 6)
      if [ "${recType[$r]}" == "$freenom_update_type" ]; then
        # if domain name or subdomain name already exists, use 'modify' instead of 'add'
        if [[ "${recName[$r]}" == "$(func_uc "$freenom_subdomain_name")" ]]; then
          if [ "${debug:-0}" -ge 1 ]; then
            # display match on apex or record
            echo -n "DEBUG: $pad8 update_ip    r=$r MATCH: type AND name - recType=recType[$r] == freenom_update_type=$freenom_update_type AND recName=\"${recName[$r]}\" == "
            if [[ -n "${recName[$r]}" && -z "$freenom_domain_name" ]]; then
              echo "freenom_domain_name=\"$freenom_domain_name\" (apex/empty)"
            elif [[ "${recName[$r]}" == "$(func_uc "$freenom_subdomain_name")" ]]; then
              echo "uc_freenom_subdomain_name=\"$(func_uc "$freenom_subdomain_name"\")"
            fi
          fi
          # change matching record using the 'records' array
          rpf="&records"
          records[$r]="${rpf}[$r][line]="
          records[$r]+="${rpf}[$r][type]=${freenom_update_type}"
          records[$r]+="${rpf}[$r][name]=${freenom_subdomain_name}"
          records[$r]+="${rpf}[$r][ttl]=${freenom_update_ttl}"
          records[$r]+="${rpf}[$r][value]=${currentIp}"
          dnsAction="modify"
          recMatch=1
          break
        fi
      fi
    done
  fi
  # there are existing records, but none match: use 'add'
  if [[ "$dnsEmpty" -eq 0 && "${recMatch:-0}" -eq 0 ]]; then
    # XXX: always use addrecord[0], even on new records - freenom.com dns mgmt page does this too (!)
    #      uses $freenom_domain_name to 'add' actual dns record, not 'recName'
    #      count records/elements: recKey="addrecord[${#recType[@]}]"
    recKey="addrecord[0]"
    dnsAction="add"
  fi
  [ "${recMatch:-0}" -eq 0 ] && recName=()
  if [ "${debug:-0}" -ge 1 ]; then
    printf "DEBUG: %s update_ip    r=%s dom_vars: freenom_update_type=%s name=%s ttyl=%s value=%s dnsEmpty=%s dnsAction=%s\n" \
      "$pad8" "$r" "$freenom_update_type" "${freenom_subdomain_name}" "$freenom_update_ttl" "$currentIp" "$dnsEmpty" "$dnsAction"
    printf "DEBUG: %s update_ip    r=%s rec_vars: recMatch=%s recKey=%s recType=%s recName=%s recTTL=%s recValue=%s (vars empty on 'add' action)\n" \
      "$pad8" "$r" "$recMatch" "$recKey" "${recType[$r]}" "${recName[$r]}" "${recTTL[$r]}" "${recValue[$r]}"
  fi
  func_setRec "${freenom_subdomain_name}"
fi

# XXX: TEST feature - handle updating *ALL* domains and records (-u -a)
# TODO: maybe add matching against user supplied list of (sub)domains?

# shellcheck disable=SC2004
if [[ -n "$freenom_update_all" && "${freenom_update_all:-0}" -eq 1 ]]; then
  echo "NOTICE: Updating all domains is a TEST feature"
  # loop over domains ($d)
  for ((d = 0; d < ${#domainName[@]}; d++)); do
    if [ "${debug:-0}" -ge 1 ]; then
      echo "DEBUG: $pad8 update_all   call func_getDnsPage \"${domainName[$d]}\" \"${domainId[$d]}\""
    fi
    func_getDnsPage "${domainName[$d]}" "${domainId[$d]}"
    if [ "$(echo "$dnsManagementPage" | grep -F "records[0]")" != "" ]; then
      # get all domain records and loop over them ($r)
      func_getRec "${domainName[$d]}"
      for ((r = 0; r < ${#recType[@]}; r++)); do
        if [ "${debug:-0}" -ge 1 ]; then
          printf "DEBUG: %s update_all   r=%s rec_cnt=%s recType=%s recName=%s recTTL=%s recValue=%s" \
            "$pad8" "$r" "${#recType[@]}" "${recType[$r]}" "${recName[$r]}" "${recTTL[$r]}" "${recValue[$r]}"
        fi
        if [ "${recType[$r]}" == "$freenom_update_type" ]; then
          if [ "${debug:-0}" -ge 1 ]; then
            printf "DEBUG: %s update_all   MATCH: recType=recType[%s] == freenom_update_type=%s ( recName=\"%s\" domainName=\"%s\" )" \
              "$pad8" "$r" "$freenom_update_type" "${recName[$r]}" "${domainName[$d]}"
          fi
          if [ -n "${recName[$r]}" ] || [[ -z "${recName[$r]}" && -n "${domainName[$d]}" ]]; then
            # set updateDomain to 'apex' or 'record.domain'
            if [[ -z "${recName[$r]}" && -n "${domainName[$d]}" ]]; then
              updateDomain="$(func_lc "${domainName[$d]}")"
            else
              updateDomain="$(func_lc "${recName[$r]}.${domainName[$d]}")"
            fi
            if func_ipCheck "$updateDomain"; then
              rpf="&records"
              records[$r]="${rpf}[$r][line]="
              records[$r]+="${rpf}[$r][type]=${freenom_update_type}"
              records[$r]+="${rpf}[$r][name]=${recName[$r]}"
              records[$r]+="${rpf}[$r][ttl]=${recTTL[$r]}"
              records[$r]+="${rpf}[$r][value]=${currentIp}"
              if [ "${debug:-0}" -ge 3 ]; then
                printf "DEBUG: %s update_all   dom_vars: d=%s freenom_update_type=%s name=%s ttyl=%s value=%s updateDomain=%s\n" \
                  "$pad8" "$d" "$freenom_update_type" "${recName[$r]}" "$freenom_update_ttl" "$currentIp" "$updateDomain"
                printf "DEBUG: %s update_all   rec_vars: r=%s recType=%s recName=%s recTTL=%s recValue=%s\n" \
                  "$pad8" "$r" "${recType[$r]}" "${recName[$r]}" "${recTTL[$r]}" "${recValue[$r]}"
              fi
            else
              uMsg="Update: Skipping \"${updateDomain}\" - found same ip (\"$currentIp\")"
              echo "$uMsg"
              echo "[$(date)] [$$] $uMsg" >>"${out_path}.log"
              continue
            fi
          fi
        fi
        func_sleep
      done
      # set all modified records at once
      dnsAction="modify"
      func_setRec
    else
      infoCount="$((infoCount + 1))"
      iMsg="Update: no records found for \"${domainName[$d]}\""
      echo "$iMsg"
      echo "[$(date)] [$$] $iMsg" >>"${out_path}.log"
    fi
  done
fi

################
# List Domains #
################

# XXX: freenom_domain_id   -> domainId
#      freenom_domain_name -> domainName

# list all domains and id's, list renewals
if [ "${freenom_list:-0}" -eq 1 ]; then
  if [ "${freenom_list_renewals:-0}" -eq 1 ]; then
    domainRenewalsURL="https://my.freenom.com/domains.php?a=renewals&itemlimit=all&token=$token"
    retry=1
    while [ "$retry" -le "$freenom_http_retry" ]; do
      if [ "${debug:-0}" -ge 1 ]; then
        func_debugHttp "renewals" "domainRenewalsURL $domainRenewalsURL"
      fi
      # shellcheck disable=SC2086
      domainRenewalsPage="$(curl $c_opts $curlExtraOpts -A "$agent" -b "$cookie_file" -w "$http_code" "$domainRenewalsURL")"
      func_httpOut "$domainRenewalsPage"
      domainRenewalsPage="$httpOut"
      if [ "${httpCode:-"000"}" -eq "200" ]; then
        if [ -n "$domainRenewalsPage" ]; then
          domainRenewalsResult="$(echo -e "$domainRenewalsPage" |
            sed -n '/<table/,/<\/table>/{//d;p;}' |
            sed '/Domain/,/<\/thead>/{//d;}' |
            sed 's/<.*domain=\([0-9]\+\)".*>/ domain_id: \1\n/g' |
            sed -e 's/<[^>]\+>/ /g' -e 's/\(  \|\t\)\+/ /g' -e '/^[ \t]\+\r/d')"
        fi
        break
      else
        retry="$((retry + 1))"
        func_httpError "$domainRenewalsPage" "Domain renewals page"
      fi
    done
  fi
  for ((i = 0; i < ${#domainName[@]}; i++)); do
    if [ "${freenom_list_renewals:-0}" -eq 1 ]; then
      if [ -n "$domainRenewalsResult" ]; then
        renewalMatch=$(echo "$domainRenewalsResult" | sed 's/\r//g' | sed ':a;N;$!ba;s/\n //g' | grep "domain_id: ${domainId[$i]}")
        if echo "$renewalMatch" | grep -q Minimum; then
          # shellcheck disable=SC2001
          renewalDetails="$(echo "$renewalMatch" | sed 's/.* \([0-9]\+ Days\) * \(Minimum.*\) * domain_id:.*/\1 Until Expiry, \2/g')"
        elif echo "$renewalMatch" | grep -q Renewable; then
          # shellcheck disable=SC2001
          renewalDetails="$(echo "$renewalMatch" | sed 's/.* \([0-9]\+ Days\) * \(Renewable\) * domain_id:.*/\2, \1 Until Expiry/g')"
        fi
      fi
      if [ ! "$renewalDetails" ]; then
        renewalDetails="N/A"
      fi
      showRenewal="$(printf "\n%4s Renewal details: %s" " " "$renewalDetails")"
    fi
    printf "[%02d] Domain: \"%s\" Id: \"%s\" RegDate: \"%s\" ExpiryDate: \"%s\"%s\n" \
      "$((i + 1))" "${domainName[$i]}" "${domainId[$i]}" "${domainRegDate[$i]}" "${domainExpiryDate[$i]}" "$showRenewal"
  done
  echo
  exit 0
fi

###################
# Domain Renewals #
###################

################################################################################
# NOTE: How to handle Renewals, and alternative methods
# 1) Currently used method: call clientarea.php?action=domaindetails&id=$i
# -OR-
# 2) Only renew if "Days" < "Minimum Advance Renewal Days"
#    where "Days" is "Days Until Expiry" :
# <span class="textgreen">372 Days</span>
# <span class="textred">Minimum Advance Renewal is 14 Days for Free Domains</span>
# -OR-
# 3) Use "Current Date" vs "Expiry Date" :
# https://my.freenom.com/clientarea.php?action=domains
#   Domain      Registration Date  Expiry date
#   domain.cf   01/02/2017         01/03/2018
#   foo.ga      01/02/2017         01/03/2018
# curDate="$( date +%F )"; expiryEpoch="$( date -d "$expiryDate" +%s )"
################################################################################

# Function renewDate: check date to make sure we can renew
func_renewDate() {
  local expiryDay=""
  local expiryMonth=""
  local expiryYear=""
  local a=()
  renewDateOkay=0
  # example: "01/03/2018"
  IFS="/" read -a a -r <<<"${domainExpiryDate[$1]}"
  expiryDay="${a[0]}"
  expiryMonth="${a[1]}"
  expiryYear="${a[2]}"
  if [[ "$expiryDay" != "" && "$expiryMonth" != "" && "$expiryYear" != "" ]]; then
    if [ "${debug:-0}" -ge 1 ]; then
      echo "DEBUG: $pad8 renew_domain func_renewDate domainExpiryDate array=${domainExpiryDate[$1]}"
    fi
    expiryDate="$(date -d "${expiryYear}-${expiryMonth}-${expiryDay}" +%F)"
    renewDate="$(date -d "$expiryDate - 14Days" +%F)"
    currentEpoch="$(date +%s)"
    renewEpoch="$(date -d "$renewDate" +%s)"
    if [ "${debug:-0}" -ge 1 ]; then
      echo "DEBUG: $pad8 renew_domain func_renewDate expiryDate=$expiryDate renewDate=$renewDate"
      echo "DEBUG: $pad8 renew_domain func_renewDate renewEpoch=$renewEpoch currentEpoch=$currentEpoch"
    fi
    if [ "${debug:-0}" -ge 2 ]; then
      echo "DEBUG: renew_domain func_renewDate listing expiry date array:"
      for ((j = 0; j < ${#a[@]}; j++)); do
        echo "DEBUG: $pad8 renew_domain func_renewDate i=${i} j=${j} - a=${a[$j]}"
      done
    fi
    # TEST: example - set a date after renewDate
    #       currentEpoch="$( date -d "2099-01-01" +%s )"
    if [ "$currentEpoch" -ge "$renewEpoch" ]; then
      renewDateOkay=1
      if [ "${debug:-0}" -ge 1 ]; then
        printf "DEBUG: %s renew_domain func_renewDate domainName=%s (Id=%s) - OK (renewdateOkay=%s)" \
          "$pad8" "${domainName[$1]}" "${domainId[$1]}" "$renewDateOkay"
      fi
    else
      infoCount="$((infoCount + 1))"
      renewInfo="${renewInfo}\n  Cannot renew domain \"${domainName[$1]}\" (${domainId[$1]}) until $renewDate"
      if [ "${debug:-0}" -ge 1 ]; then
        printf "DEBUG: %s renew_domain func_renewDate domainName=%s (domainId=%s) - cannot renew until renewDate=%s" \
          "$pad8" "${domainName[$1]}" "${domainId[$1]}" "$renewDate"
      fi
    fi
  else
    errCount="$((errCount + 1))"
    renewError="${renewError}\n  No expiry date for \"${domainName[$1]}\" (${domainId[$1]})"
    if [ "${debug:-0}" -ge 1 ]; then
      printf "DEBUG: %s renew_domain func_renewDate domainName=\"%s\" (domainId=%s) (i=%s) - no expiry date" \
        "$pad8" "${domainName[$1]}" "${domainId[$1]}" "$i"
    fi
  fi
}

# Function renewDomain: if date is ok, submit actual renewal and get result
func_renewDomain() {
  if [[ -n "$renewDateOkay" && "${renewDateOkay:-0}" -eq 1 ]]; then
    # use domain_id domain_name
    freenom_domain_id="${domainId[$1]} $freenom_domain_id"
    freenom_domain_name="${domainName[$1]} $freenom_domain_name"
    if [ "${debug:-0}" -ge 1 ]; then
      printf "DEBUG: %s renew_domain func_renewDomain freenom_domain_name=%s - curdate>expirydate = possible to renew" \
        "$(date '+%H:%M:%S')" "$freenom_domain_name"
    fi
    renewDomainURL="https://my.freenom.com/domains.php?a=renewdomain&domain=${domainId[$1]}&token=$token"
    retry=1
    while [ "$retry" -le "$freenom_http_retry" ]; do
      if [ "${debug:-0}" -ge 1 ]; then
        func_debugHttp "renew_domain" "func_renewDomain renewDomainURL $renewDomainURL"
      fi
      # shellcheck disable=SC2086
      renewDomainPage="$(curl $c_opts $curlExtraOpts -A "$agent" -b "$cookie_file" -w "$http_code" "$renewDomainURL")"
      func_httpOut "$renewDomainPage"
      renewDomainPage="$httpOut"
      if [ "${httpCode:-"000"}" -eq "200" ]; then
        break
      else
        retry="$((retry + 1))"
        func_httpError "$renewDomainPage" "Renew domain page"
      fi
    done

    # XXX: EXAMPLE
    # url:       https://my.freenom.com/domains.php?submitrenewals=true
    # form data: 7ad1a728a6d8a96d1a8d66e63e8a698ea278986e renewalid:1234567890 renewalperiod[1234567890]:12M paymentmethod:credit

    if [ -n "$renewDomainPage" ]; then
      echo "$renewDomainPage" >"${out_path}_renewDomainPage-${domainId[$1]}.html"
      if [ "${debug:-0}" -ge 1 ]; then
        echo "DEBUG: $pad8 renew_domain renewDomainPage - OK renewDomainURL=$renewDomainURL"
      fi
      renewalPeriod="$(echo "$renewDomainPage" | sed -n 's/.*option value="\(.*\)\".*FREE.*/\1/p' | sort -n | tail -1)"
      # if [ "$renewalPeriod" == "" ]; then renewalPeriod="12M"; fi
      if [ -n "$renewalPeriod" ]; then
        renewalURL="https://my.freenom.com/domains.php?submitrenewals=true"
        retry=1
        while [ "$retry" -le "$freenom_http_retry" ]; do
          if [ "${debug:-0}" -ge 1 ]; then
            func_debugHttp "renew_domain renewalURL $renewalURL"
          fi
          # shellcheck disable=SC2086
          renewalResult="$(curl $c_opts $curlExtraOpts -A "$agent" -b "$cookie_file" -w "$http_code" \
            -F "token=$token" \
            -F "renewalid=${domainId[$1]}" \
            -F "renewalperiod[${domainId[$1]}]=$renewalPeriod" \
            -F "paymentmethod=credit" \
            "$renewalURL" 2>&1)"
          func_httpOut "$renewalResult"
          renewalResult="$httpOut"
          if [ "${httpCode:-"000"}" -eq "200" ]; then
            # write renewal result html file, count errors and set ok/error messages per domain
            if [ -n "$renewalResult" ]; then
              echo -e "$renewalResult" >"${out_path}_renewalResult-${domainId[$1]}.html"
              renewOk="$renewOk\n  Successfully renewed domain \"${domainName[$1]}\" (${domainId[$1]}) for ${renewalPeriod}"
            else
              errCount="$((errCount + 1))"
              renewError="$renewError\n  Renewal failed for \"${domainName[$1]}\" (${domainId[$1]})"
            fi
            break
          else
            retry="$((retry + 1))"
            func_httpError "$renewalResult" "Renewal domain URL"
          fi
        done
      else
        errCount="$((errCount + 1))"
        renewError="$renewError\n  Cannot renew \"${domainName[$1]}\" (${domainId[$1]}), renewal period not found"
      fi
    else
      errCount="$((errCount + 1))"
    fi
  else
    if [ "${debug:-0}" -ge 1 ]; then
      printf "DEBUG: %s renew_domain func_renewDomain 1=%s renewDateOkay=%s - skipped domainName=\"%s\"" \
        "$pad8" "$1" "$$renewDateOkay" "${domainName[$1]}"
    fi
  fi
}

# call domain renewal functions for all or single domain
if [ "${freenom_renew_domain:-0}" -eq 1 ]; then
  domainMatch=0
  for ((i = 0; i < ${#domainName[@]}; i++)); do
    if [ "${domainExpiryDate[$i]}" == "" ]; then
      warnCount="$((warnCount + 1))"
      echo "[$(date)] [$$] Warning: Missing domain expiry date for \"${domainName[$i]}\"" >>"${out_path}.log"
      if [ "${debug:-0}" -ge 1 ]; then
        echo "DEBUG: $(date '+%H:%M:%S') renew_domain Missing domain expiry date - domainName=\"${domainName[$i]}\" (i=$i)"
      fi
    else
      if [ "${debug:-0}" -ge 1 ]; then
        echo "DEBUG: $pad8 renew_domain i=$i arraycount=${#domainName[@]} domainId=${domainId[$i]} domainName=${domainName[$i]}"
      fi
    fi
    if [ "${freenom_renew_all:-0}" -eq 1 ]; then
      if [ "${debug:-0}" -ge 1 ]; then
        echo "DEBUG: $(date '+%H:%M:%S') renew_all i=$i domainName=${domainName[$i]}"
      fi
      func_renewDate "$i"
      func_renewDomain "$i"
    else
      if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then
        if [ "${debug:-0}" -ge 1 ]; then
          echo "DEBUG: $(date '+%H:%M:%S') renew_domain i=$i MATCH: freenom_domain_name=$freenom_domain_name == domainName=${domainName[$i]}"
        fi
        func_renewDate "$i"
        func_renewDomain "$i"
        domainMatch=1
        break
      fi
    fi
  done
  if [[ "${freenom_renew_all:-0}" -eq 0 && "$domainMatch" -eq 0 ]]; then
    if [ "${debug:-0}" -ge 1 ]; then
      echo "DEBUG: $(date '+%H:%M:%S') renew_domain freenom_domain_name=${freenom_domain_name} not found"
    fi
    errCount="$((errCount + 1))"
    renewError="\"${freenom_domain_name}\" not found"
  fi
fi

# logout
retry=1
while [ "$retry" -le "$freenom_http_retry" ]; do
  # DEBUG: comment line below for debugging
  # shellcheck disable=SC2086
  logoutPage="$(curl $c_opts $curlExtraOpts -A "$agent" -b "$cookie_file" -w "$http_code" "https://my.freenom.com/logout.php" 2>&1)"
  func_httpOut "$logoutPage"
  logoutPage="$httpOut"
  if [ "${httpCode:-"000"}" -eq "200" ]; then
    break
  else
    func_httpError "$logoutPage" "Logout page"
    retry="$((retry + 1))"
  fi
done
if [ "${debug:-0}" -ge 1 ]; then
  func_debugHttp "logout" "logoutPage"
fi
if [[ -n "$cookie_file" && -f "$cookie_file" ]]; then
  rm "$cookie_file"
fi

###########
# Logging #
###########

# log update results for single and multiple records
if [ "${freenom_update_ip:-0}" -eq 1 ]; then
  if [ -n "$updateOk" ]; then
    echo -e "[$(date)] [$$] Update(s) using \"${currentIp}\" successful - $updateOk " >>"${out_path}.log"
  fi
  if [ "$errCount" -gt 0 ] && [ -n "${updateError}" ]; then
    eMsg="Updating \"${currentIp}\" failed: ${updateError}"
    echo -e "[$(date)] [$$] $eMsg" >>"${out_path}.log"
    mailEvent UpdateError "$eMsg"
    appriseEvent UpdateError "$eMsg"
  fi
fi

# log renewal results and if needed add 'Minimum Advance Renewal Days' from renewalResult to renewError
if [ "${freenom_renew_domain:-0}" -eq 1 ]; then
  if [ -n "$renewOk" ]; then
    echo -e "[$(date)] [$$] Domain renewal successful: ${renewOk}" >>"${out_path}.log"
  fi
  if [[ -n "${freenom_renew_log:-0}" && "${freenom_renew_log:-0}" -eq 1 ]]; then
    if [ "$infoCount" -gt 0 ]; then
      if [ -n "$renewInfo" ]; then
        echo -e "[$(date)] [$$] These domain(s) were not renewed: ${renewInfo}" >>"${out_path}.log"
      fi
    fi
  fi
  if [ "$errCount" -gt 0 ]; then
    if [ -z "$renewError" ]; then
      if [ "$(echo -e "$renewalResult" | grep "Minimum Advance Renewal is")" != "" ]; then
        renewError="$(echo -e "$renewalResult" | grep "textred" |
          sed -e 's/<[^>]\+>//g' -e 's/\(  \|\t\|\r\)//g' | sed ':a;N;$!ba;s/\n/, /g')"
      fi
    fi
    eMsg="These domain(s) failed to renew: ${renewError}"
    echo -e "[$(date)] [$$] $eMsg" >>"${out_path}.log"
    mailEvent RenewError "$eMsg"
    appriseEvent RenewError "$eMsg"
  fi
fi

# log number of warnings and/or errors and exit with exitcode
dMsg="[$(date)] [$$] Done"
if [[ "$warnCount" -gt 0 || "$errCount" -gt 0 ]]; then
  dMsg+=":"
  if [ "$warnCount" -gt 0 ]; then dMsg+=" $warnCount warning(s)"; fi
  if [ "$errCount" -gt 0 ]; then dMsg+=" $errCount error(s)"; fi
fi
echo "$dMsg" >>"${out_path}.log"
if [ "$errCount" -gt 0 ]; then
  exit 1
else
  exit 0
fi
