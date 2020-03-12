#!/bin/bash

###############################################################################
# Domain Renewal and Dynamic DNS shell script for freenom.com                 #
###############################################################################
#                                                                             #
# Updates IP address and/or auto renews domain(s) so they do not expire       #
# See README.md for more information                                          #
# gpl-3.0-only                                                                #
#                                                                             #
# freenom-script  Copyright (C) 2019  M. Korthof                              #
# This program comes with ABSOLUTELY NO WARRANTY                              #
# This is free software, and you are welcome to redistribute it               #
# under certain conditions.                                                   #
# See LICENSE file for more information                                       #
#                                                               v2020-01-28   #
###############################################################################

########
# Main #
########

set -eo pipefail
for i in curl grep date basename; do
  if ! command -v $i >/dev/null 2>&1; then
    echo "Error: could not find \"$i\", exiting..."
    exit 1
  fi
done
scriptName="$(basename "$0")"
noticeCount="0"
warnCount="0"
errCount="0"

########
# Conf #
########

## configuration file specfied as argument
SAVIFS="$IFS"
IFS='|'; c=0
for i in "$@"; do
  if printf -- "%s" "$i" | grep -Eq -- "(^|[^a-z])\-c";
    then c=1; continue
  else
    if [ "$c" -eq 1 ]; then
      scriptConf="$i"
      if [ ! -s "$scriptConf" ]; then
        echo "Error: invalid config \"$scriptConf\" specified"
        exit 1
      fi
      break
    fi
  fi
done
IFS="$SAVIFS"

# if scriptConf is empty, check for {/usr/local,}/etc/freenom.conf and in same dir as script
if [ -z "$scriptConf" ]; then
  if [ -e "/usr/local/etc/freenom.conf" ]; then
    scriptConf="/usr/local/etc/freenom.conf"
  elif [ -e "/etc/freenom.conf" ]; then
    scriptConf="/etc/freenom.conf"
  else
    scriptConf="$(dirname "$0")/$(basename -s '.sh' "$0").conf"
    # use BASH_SOURCE instead when called from 'bash -x $scriptName'
    if [ "$(dirname "$0")" = "." ]; then
      scriptConf="${BASH_SOURCE[0]/%sh/conf}"
    fi
  fi
fi

# source scriptConf if its non empty else exit
if [ -s "$scriptConf" ]; then
  # shellcheck source=/usr/local/etc/freenom.conf
  source "$scriptConf" || { echo "Error: could not load $scriptConf"; exit 1; }
fi

# make sure debug is always set
if [ -z "$debug" ]; then debug=0; fi

if [ "$debug" -ge 1 ]; then
  echo "DEBUG: debug=$debug c_args=$c_args"
  echo "DEBUG: conf scriptConf=$scriptConf"
fi

# we need these config settings, if they do not exist exit
if [ -z "$freenom_email" ]; then echo "Error: setting \"freenom_email\" is missing in config"; exit 1; fi
if [ -z "$freenom_passwd" ]; then echo "Error: setting \"freenom_passwd\" is missing in config"; exit 1; fi

## if needed create freenom_out_dir. if out_path is not set or invalid, set default
if [ -d "$( dirname "$freenom_out_dir" )" ]; then
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
  echo "Error: logfile \"${out_path}.log\" not writable, using \"/tmp/$(basename -s '.sh' "$0").log\""
  out_path="/tmp/$(basename -s '.sh' "$0")"
fi

# generate "random" useragent string, used for curl and below in func_randIp
agent="${uaString[$((RANDOM%${#uaString[@]}))]}"

# add http code to curl output
http_code="<!--http_code=%{http_code}-->"

if [ -z "$c_args" ]; then
  #c_args="-s --proxy http://localhost:3128"
  c_args="-s"
fi

ipRE='((((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])))|(((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?))'

#############
# Functions #
#############

# Function func_cleanup: remove cookie file, using trap
func_cleanup() { 
  if [[ -n "$cookie_file" && -f "$cookie_file" ]]; then
    if [ $debug -ge 1 ]; then
      echo "DEBUG: func_cleanup cookie_file=$cookie_file"
    fi
    rm "$cookie_file"
  fi
}
trap "func_cleanup" EXIT HUP INT TERM

# Function help: displays options etc
func_help () {
  cat <<-_EOF_

FREENOM.COM DOMAIN RENEWAL AND DYNDNS
=====================================

USAGE:
            $scriptName -l [-d]
            $scriptName -r <domain> [-s <subdomain>] | [-a]
            $scriptName -u <domain> [-s <subdomain>] [-m <ip>] [-f]
            $scriptName -z <domain>

OPTIONS:
            -l    List all domains with id's in account
                  add [-d] to show renewal Details
            -r    Renew domain(s)
                  add [-a] to renew All domains
            -u    Update <domain> A record with current ip
                  add [-s] to update <Subdomain>
                  add [-m <ip>] to manually update static <ip>
                  add [-f] to force update on unchanged ip
            -z    Zone listing of dns records for <domain>

            -4    Use ipv4 and modify A record on "-u" (default)
            -6    Use ipv6 and modify AAAA record on "-u"
            -c    Config <file> to be used instead freenom.conf
            -i    Ip commands list used to get current ip
            -o    Output html result file(s) for renewals

EXAMPLES:
            ./$scriptName -r example.com
            ./$scriptName -c /etc/myfn.conf -r -a
            ./$scriptName -u example.com -s mail

NOTES:
            Using "-u" or "-r" and specifying <domain> as argument
            will override any settings in script or config file

_EOF_
#
# TODO:
#                  add [-a] to update All domains
#
  exit 0
}

# Function getDomArgs: use regexps to get domain name/id etc
func_getDomArgs () {
  local arg_domain_name
  local arg_domain_id
  local arg_subdomain_name

  # first remove debug arg
  d_args="$( echo "$*" | sed -E 's/ ?-debug ([0-9])//' )"

  # then remove "-c'"arg and save other options to $d_args
  # [#12] this re has issues with bash 5.0.3/sed 4.7 (works on bash 4.4.12/sed 4.4)
  #   sed -E 's| ?-c [][a-zA-Z0-9 !"#$%&'\''()*+,-.:;<=>?@^_`{}~/]+ ?||g' 
  d_args="$( echo "$d_args" | sed -E 's| ?(-c ([^ ]+\|['\''"].+['\''"])) ?||g' )"

  # now get domain_name by removing option "-m <ip>" and "-s"
  # 'digits' to match domain id, plus any other args e.g. "-[a-z]"
  if [[ -n "$freenom_update_all" && "$freenom_update_all" -eq 0 ]]; then
    arg_domain_name="$(
      echo "$d_args" | \
      sed -E -e 's/-m '"$ipRE"'//' \
             -e 's/( ?-s [^ ]+|( -[[:alnum:]]+|-[[:alnum:]]+ )| [0-9]+|[0-9]+ | )|^-[[:alnum:]]+$/ /g' | \
      awk '{ print $1 }'
    )"
  fi
  arg_domain_id="$( echo "$d_args" | sed -n -E 's/.*([0-9]{10}+).*/\1/p' )"
  arg_subdomain_name="$( echo "$d_args" | sed -n -E 's/.*-s ?([^ ]+).*/\1/p' )"

  # if domain arg is not empty use that instead of setting from conf
  if [[ -n "$freenom_update_all" && "$freenom_update_all" -eq 0 ]]; then
    if [ -n "$arg_domain_name" ]; then
      freenom_domain_name="$arg_domain_name"
      if [ "$(( 0 + $(echo "$freenom_domain_name" | tr '.' '\n' | wc -l) ))" -ge 3 ]; then
        wMsg="Warning: \"$freenom_domain_name\" looks like a subdomain (use '-s' ?)"
        echo "$wMsg"
        echo -e "[$(date)] $wMsg" >> "${out_path}.log"
      fi
    fi
  fi
  if [ -n "$arg_subdomain_name" ]; then
    freenom_subdomain_name="$arg_subdomain_name"
  fi
  if [ -n "$arg_domain_id" ]; then
    freenom_domain_id="$arg_domain_id"
  fi
  debugDomArgs=0
  if [ "$debug" -ge 1 ]; then
    debugDomArgs=1
  fi
  # if we didnt get any args and no conf settings display error message
  if [[ -n "$freenom_update_all" && "$freenom_update_all" -eq 0 ]]; then
    if [ "$freenom_domain_name" == "" ]; then
      echo "Error: Domain Name missing"
      echo "  Try: $scriptName [-u|-r|-z] [domain]"
      exit 1
    fi
    # handle invalid domain setting
    if [[ ! "$freenom_domain_name" =~ ^[^.-][a-zA-Z0-9.-]+$ ]] || \
       [[ "$freenom_domain_name" == "$freenom_domain_id" ]]; then
      echo "Error: invalid domain name \"$freenom_domain_name\""
      exit 1
    fi
  fi
  if [[ ! "$freenom_domain_id" =~ ^[0-9]{10}+$ ]]; then
    freenom_domain_id=""
  fi
  if [[ ! "$freenom_subdomain_name" =~ ^[^-][a-zA-Z0-9-]+$ ]]; then
    freenom_subdomain_name=""
  fi
}

# Function showResult: format html and output as text
func_showResult () {
  printf "\n[ %s ]\n\n" "$1"
  local i=""
  for i in lynx links links2 wb3m elinks curl cat; do
    if command -v $i >/dev/null 2>&1; then
      break
    fi
  done
  case "$i" in
    lynx|links|links2|w3m|elinks)
      [ $i = "lynx" ] && s_args="-nolist"
      [ $i = "elinks" ] && s_args="-no-numbering -no-references"
      # shellcheck disable=SC2086
      "$i" -dump $s_args "$1" | sed '/ \([*+□•] \?.\+\|\[.*\]\)/d'
    ;;
    curl|cat)
      [ $i = "curl" ] && s_args="-s file:///"
      # shellcheck disable=SC2086
      "$i" ${s_args}"${1}" | \
        sed -e '/<a href.*>/d' -e '/<style type="text\/css">/,/</d' -e '/class="lang-/d' \
            -e 's/<[^>]\+>//g' -e '/[;}{):,>]$/d' -e '//d' -e 's/\t//g' -e '/^ \{2,\}$/d' -e '/^$/d'
    ;;
    *)
      echo "Error: cannot display \"$1\""
      exit 1
    ;;
  esac
}

# Function randIp: run random dig or curl ipCmd, replace %agent% with random useragent string
#                  regex: https://www.regexpal.com/?fam=104038
#                  return ipv4/6 address
func_randIp() {
  [ "$debug" -ge 2 ] && set -x
  ${ipCmdTrim[$((RANDOM%${#ipCmdTrim[@]}))]/\%agent\%/$agent} 2>/dev/null | \
    grep -Pow "^${ipRE}$"
  [ "$debug" -ge 2 ] && set +x
}

# Function trimIpcmd: trim ipCmd array from conf for update_ipv=4|6 and whether we want dig or not
#                     replaces %ipv% with $freenom_update_ipv
#                     creates new array: $ipCmdTrim
func_trimIpCmd () {
  for ((i=0; i < ${#ipCmd[@]}; i++)); do
    local skip=0;
    # if update_ipv is set to '6', skip ipCmd's that do not not contain '-6'
    if [[ -n "$freenom_update_ipv" && "$freenom_update_ipv" -eq 6 ]]; then
      if [[ "${ipCmd[$i]}" =~ '-4' ]]; then skip=1; fi
      echo DEBUG: trimIpCmd skip=$skip i=$i ipCmd="${ipCmd[$i]}"
    fi
    # if update_dig is disabled, skip if ipCmd is 'dig'
    if [[ -n "$freenom_update_dig" && "$freenom_update_dig" -eq 0 ]]; then
      if [[ "${ipCmd[$i]}" =~ ^dig ]]; then skip=1; fi
    fi
    if [ $skip -eq 0 ]; then
      ipCmdTrim+=("${ipCmd[$i]/\%ipv\%/$freenom_update_ipv}")
    else
      i=$((i+1))
    fi
  done
  if [ "$debug" -ge 2 ]; then
    for ((i=0; i < ${#ipCmdTrim[@]}; i++)); do echo "DEBUG: trimIpCmd $i: ${ipCmdTrim[$i]}"; done
  fi
}

# Function httpOut: set curl result and httpcode
func_httpOut() {
  local hcRE='<!--http_code=([1-5][0-9][0-9])-->'
  httpCode=""; httpOut="";
  httpCode="$( echo "$1" | sed -En 's/.*'"$hcRE"'/\1/p' )"
  httpOut="$( echo "$1" | sed -E 's/'"$hcRE"'//')"
}

# Function func_errMsgHttp: show msg with curl error
func_errMsgHttp() {
  #echo \"403 Forbidden\" (try ${r}/${freenom_http_retry})
  retry=$r
  if [ $r -ge $freenom_http_retry ]; then
    retry=$((r-1))
  fi
  echo "Error: $1 httpcode \"${httpCode:-"000"}\" (try ${retry}/${freenom_http_retry})"
}

# debug functions

# Function debugHttp: show curl error
func_debugHttp () {
  retry=$r
  if [ $r -ge $freenom_http_retry ]; then
    retry=$((r-1))
  fi
  echo "DEBUG: $1 curl $2 (r=${retry}/$freenom_http_retry http_code=$httpCode errCount=$errCount)"
}
# Function debugVars: debug output args, actions etc
func_debugVars () {
  echo "DEBUG: args       debug=$debug c_args=$c_args"
  echo "DEBUG: args       1=$1 2=$2 3=$3 4=$4 5=$5 6=$6 7=$7 8=$8 9=$9"
  echo "DEBUG: opts/conf  freenom_out_dir=$freenom_out_dir freenom_out_mask=$freenom_out_mask out_path=$out_path"
  echo "DEBUG: opts/conf  freenom_domain_name=$freenom_domain_name freenom_domain_id=$freenom_domain_id freenom_subdomain_name=$freenom_subdomain_name"
  echo "DEBUGL opts/conf  freenom_static=ip=$freenom_static_ip"
  echo "DEBUG: action     freenom_update_ip=$freenom_update_ip freenom_update_force=$freenom_update_force freenom_update_manual=$freenom_update_manual freenom_update_all=$freenom_update_all"
  echo "DEBUG: action     freenom_list_records=$freenom_list_records freenom_list=$freenom_list freenom_list_renewals=$freenom_list_renewals"
  echo "DEBUG: action     freenom_renew_domain=$freenom_renew_domain freenom_renew_all=$freenom_renew_all"
  if [[ -n "$debugDomArgs" && "$debugDomArgs" -eq 1 ]]; then
    echo "DEBUG: getDomArgs d_args=$d_args arg_domain_name=$arg_domain_name arg_domain_id=$arg_domain_id"
    echo "DEBUG: getDomArgs arg_subdomain_name=$arg_subdomain_name"
  fi
}
# Function debugArrays: show domain Id, Name, Expiry
func_debugArrays () {
  echo "DEBUG: arrays domainId domainName domainExpiryDate:"
  echo "${domainId[@]}"
  echo "${domainName[@]}"
  echo "${domainExpiryDate[@]}"
}
# Function debugMyDomainsResult
func_debugMyDomainsResult () {
  if [ "$debug" -ge 1 ]; then
    local i=""
    IFS=$'\n'
    # shellcheck disable=SC2116
    for i in $( echo "$myDomainsResult" ); do
      echo DEBUG: myDomainsResult i="$i"; domainResult="$( echo "$i" | cut -d " " -f2 )"; domainIdResult="$( echo "$i" | cut -d " " -f4 )"
    done
    echo "DEBUG: myDomainsResult domainResult: $domainResult domainIdResult: $domainIdResult"
  fi
}


# NOTE: there are 6 more inline functions down below:
#
#   Dns
#     - Function_getDnsPage: get DNS Management Page
#     - Function getRec: get domain records from dnsManagementPage
#     - Function setRec: add/modify domain records
#
#   Renew
#     - Function renewDate: check date to make sure we can renew
#     - Function renewDomain: if date is ok, submit actual renewal and get result
#

###########
# Options #
###########

if printf -- "%s" "$*" | grep -Eiq '(^|[^a-z])\-debug'; then
  debug="$( echo "$8" | sed -E 's/.*-debug ([0-9]) ?.*/\1/' )"
  if [[ ! "$debug" =~ ^[0-9]$ ]]; then
    debug=0
  fi
fi
# show help
if printf -- "%s" "$*" | grep -Eqi '(^|[^a-z])\-h'; then
  func_help
  exit 0
fi
# handle all other arguments
if ! printf -- "%s" "$*" | grep -Eqi -- '\-[46lruziceo]'; then
  echo "Error: invalid or unknown argument(s), try \"$scriptName -h\""
  exit 1
fi
if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-4'; then
  freenom_update_ipv=4
  if [ "$debug" -ge 1 ]; then echo "DEBUG: ipv freenom_update_ipv=$freenom_update_ipv"; fi
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-6'; then
  freenom_update_ipv=6
  if [ "$debug" -ge 1 ]; then echo "DEBUG: ipv freenom_update_ipv=$freenom_update_ipv"; fi
fi
# list domains and id's and exit, unless list_records is set
if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-l'; then
  freenom_list="1"
  lMsg=""
  # list domains with details
  if printf -- "%s" "$*" | grep -Eqi -- '(^|[^a-z])\-[dn]'; then
    freenom_list_renewals="1"
    lMsg=" with renewal details, this might take a while"
  fi
  printf "\nListing Domains and ID's%s...\n" "$lMsg"
  echo
# list dns records
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-z'; then
  printf "\nListing Domain Record(s)%s...\n" "$lMsg"
  echo
  func_getDomArgs "$@"
  freenom_list_records="1"
# output ipcmd list
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-i'; then
  if [ "$debug" -ge 1 ]; then echo "DEBUG: ipv freenom_update_ipv=$freenom_update_ipv"; fi
  printf "\nListing all \"get ip\" commands..."; echo
  for ((i=0; i < ${#ipCmd[@]}; i++)); do
    printf "%2s: %s\n" "$i" "${ipCmd[$i]}"
  done
  printf "\nNOTES:\n"
  printf "  %%ipv%% gets replaced by \$freenom_update_ipv\n"
  printf "  %%agent%% gets replaced with useragent string\n\n"
  exit 0
# update ip
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-u'; then
  freenom_update_ip="1"
  if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-f'; then
    freenom_update_force="1"
  fi
  if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-m'; then
    freenom_update_manual="1"
    arg_static_ip="$( echo "$@" | sed -n -E 's/.*-m ('"$ipRE"')([^0-9].*)?/\1/p' )"
    if [ -n "$arg_static_ip" ]; then
      freenom_static_ip="$arg_static_ip"
    fi
    if [[ ! "$freenom_static_ip" =~ ^$ipRE$ ]]; then
      freenom_static_ip=""
    fi
  fi
# TODO:
#  if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-a'; then
#    freenom_update_all="1"
#  fi
  func_getDomArgs "$@"
# renew domains
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-r'; then
  freenom_renew_domain="1"

  if printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-a'; then
    freenom_renew_all="1"
  else
    func_getDomArgs "$@"
  fi
# show update and renewal result file(s)
elif printf -- "%s" "$*" | grep -Eiq -- '(^|[^a-z])\-[eo]'; then
  # use regex if file is specfied
  fget="$( printf -- "%s\n" "$*" | sed -En 's/.* ?-[eo] ?([][a-zA-Z0-9 !"#$%&'\''()*+,-.:;<=>?@^_`{}~.]+)[ -]?.*/\1/gp' )"
  if [ -z "$fget" ]; then
    for f in "${out_path}"_renewalResult-*.html; do
      if [ -e "$f" ]; then fget+="$f "; fi
    done
    count="$( echo "$fget" | wc -w )"
    if [ "$count" -eq 0 ]; then
      echo "No result file(s) found"
      exit 0
    elif [ "$count" -gt 1 ]; then
      printf "Multiple results found, listing %d html files:\n" "$count"
      for r in $fget; do
        find "$r" -printf '  (%TF %TH:%TM) %f\n'
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

# config checks

# if these vars are missing, set defaults
if [ -z "$freenom_http_retry" ]; then freenom_http_retry=1; fi
if [ -z "$freenom_update_force" ]; then freenom_update_force=0; fi
if [ -z "$freenom_update_ipv" ]; then freenom_update_ipv=4; fi
if [ -z "$freenom_update_ttl" ]; then freenom_update_ttl="3600"; fi
if [ -z "$freenom_update_ip_retry" ]; then freenom_update_ip_retry="3"; fi

if [ "$debug" -ge 1 ]; then
  func_debugVars "$@"
fi

# log start msg
  if [ "$freenom_update_ip" -eq 1 ]; then
  if [[ -n "$freenom_update_ip_log" && "$freenom_update_ip_log" -eq 1 ]]; then
    echo -e "[$(date)] Start: Update ip" >> "${out_path}.log"
  else
    echo -e "[$(date)] Update ip" >> "${out_path}.log"
  fi
elif [[ "$freenom_renew_domain" -eq 1 || "$freenom_renew_all" -eq 1 ]]; then
  echo -e "[$(date)] Start: Domain renewal" >> "${out_path}.log"
fi

##########
# Get IP #
##########

# try getting ip by running a random ipCmd's, stop after max retries
if [ "$freenom_update_ip" -eq 1 ]; then
  if [[ -n "$freenom_update_all" && "$freenom_update_all" -eq 0 ]]; then
    ipDomName="${freenom_subdomain_name:+${freenom_subdomain_name}.}${freenom_domain_name}"
  fi
  # TODO: (?)need to set these later
  #  ipDomName="all"
  #  freenom_domain_id="all"
  if [[ -n "$freenom_update_manual" && "$freenom_update_manual" -eq 0 ]]; then
    func_trimIpCmd
    i=0
    while [[ "$currentIp" == "" && "$i" -lt "$freenom_update_ip_retry" ]]; do
      currentIp="$(func_randIp || true)"
      if [ "$debug" -ge 1 ]; then 
        echo "DEBUG: getip i=$i currentIp=$currentIp ipfile=${out_path}_${ipDomName}.ip${freenom_update_ipv}"
      fi
      i=$((i+1))
    done
    if [ "$currentIp" == "" ]; then
      eMsg="Could not get current local ip address"
    fi
  elif [[ -n "$freenom_update_manual" && "$freenom_update_manual" -eq 1 ]]; then
    if [ "$freenom_static_ip" != "" ]; then
      currentIp="$freenom_static_ip"
    else
      eMsg="Valid static ip address missing for manual update"
      uMsg="\n%7sUse \"-m <ip>\" or remove option for auto detect\n"
    fi
  fi
  if [ "$currentIp" == "" ]; then
    # shellcheck disable=SC2059
    printf "Error: ${eMsg}${uMsg}"
    echo "[$(date)] $eMsg" >> "${out_path}.log"
    exit 1
  fi
  if [ "$freenom_update_force" -eq 0 ]; then
    if [ "$(cat "${out_path}_${ipDomName}.ip${freenom_update_ipv}" 2>&1)" == "$currentIp" ]; then
      if [[ -n "$freenom_update_ip_log" && "$freenom_update_ip_log" -eq 1 ]]; then
        uMsg="Skip: ${ipDomName//_/.}, same ip ($currentIp)" 
        echo "$uMsg"
        echo "[$(date)] $uMsg" >> "${out_path}.log"
      fi
      exit 0
    fi
  fi
fi

#########
# Login #
#########

r=1
while [ "$r" -le "$freenom_http_retry" ]; do
  cookie_file="$(mktemp)"
  if [ "$debug" -ge 1 ]; then
    echo "DEBUG: login cookie_file=$cookie_file"
  fi
  # DEBUG: comment line below for debugging
  loginPage="$(curl $c_args -A "$agent" --compressed -L -c "$cookie_file" -w $http_code \
      "https://my.freenom.com/clientarea.php" 2>&1)" || \
    { echo "Error: Login - token failure (curl error code: $?)"; exit 1; }
  func_httpOut "$loginPage"; loginPage="$httpOut"
  if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${loginPage}" | grep -q "403 Forbidden"; then
    if echo "$loginPage" | grep -m 1 -q "token.*value="; then
      token="$(echo "$loginPage" | grep token | head -1 | grep -o value=".*" | sed 's/value=//g' | sed 's/"//g' | awk '{print $1}')"
      break
    else
      echo "Error: Login - token not found"
      r="$((r+1))"
    fi
  else
    func_errMsgHttp "Login"
    agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
    r="$((r+1))"
  fi
done
if [ "$debug" -ge 1 ]; then
  func_debugHttp "login" "clientarea token=$token"
fi
if [ -z "$token" ]; then
  echo "Error: Login - token empty after $freenom_http_retry max tries, exiting..."
  exit 1
fi

r=1
while [ "$r" -le "$freenom_http_retry" ]; do
  # DEBUG: comment line below for debugging
  loginResult="$(curl $c_args -A "$agent" -e 'https://my.freenom.com/clientarea.php' -compressed -L -c "$cookie_file" -w $http_code \
      -F "username=$freenom_email" -F "password=\"$freenom_passwd\"" -F "token=$token" \
      "https://my.freenom.com/dologin.php")"
  func_httpOut "$loginResult"; loginResult="$httpOut"
  if [ "$(echo -e "$loginResult" | grep -E "Location: /clientarea.php\?incorrect=true|Login Details Incorrect")" != "" ]; then
    eMsg="Error: Login failed"
    echo "$eMsg"
    echo "[$(date)] $eMsg" >> "${out_path}.log"
    exit 1
  fi
  if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${loginResult}" | grep -q "403 Forbidden"; then
    break
  else
    r="$((r+1))"
    agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
    func_errMsgHttp "Login"
  fi
done
if [ "$debug" -ge 1 ]; then
  func_debugHttp "login" "dologin.php username=$freenom_email"
fi
if [ "$r" -gt "$freenom_http_retry" ]; then
  echo "Error: Login - max retries $freenom_http_retry was reached, exiting..."
  exit 1
fi

#exit

###############
# Domain info #
###############

# retrieve client area page, get domain detail urls and loop over them to get all data
# arrays: domainId, domainName, domainRegDate, domainExpiryDate

if [ "$freenom_domain_id" == "" ]; then
  myDomainsURL="https://my.freenom.com/clientarea.php?action=domains&itemlimit=all&token=$token"
  # DEBUG: for debugging use local file instead:
  # DEBUG: myDomainsURL="file:///home/user/src/freenom/myDomainsPage"
  r=1
  # (NOTE): first get mydomains page
  while [ "$r" -le "$freenom_http_retry" ]; do
    if [ "$debug" -ge 1 ]; then
      func_debugHttp "domains" "myDomainsPage"
    fi
    myDomainsPage="$(curl $c_args -A "$agent" --compressed -L -b "$cookie_file" -w $http_code "$myDomainsURL")"
    func_httpOut "$myDomainsPage"; myDomainsPage="$httpOut"
    if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${myDomainsPage}" | grep -q "403 Forbidden"; then
      break
    else
      func_errMsgHttp "My domains page"
      agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
      r="$((r+1))"
    fi
  done
  if [ "$r" -gt "$freenom_http_retry" ]; then
    echo "Error: My domains page - $freenom_http_retry max retries was reached, exiting..."
    exit 1
  fi
  # (NOTE): if we have mydomains page, get domaindetails url(s) from result 
  if [ -n "$myDomainsPage" ]; then
    # old: myDomainsResult="$( echo -e "$myDomainsPage" | sed -n '/href.*external-link/,/action=domaindetails/p' | sed -n 's/.*id=\([0-9]\+\).*/\1/p;g' )"
    myDomainsResult="$( echo -e "$myDomainsPage" | sed -n 's/.*"\(clientarea.php?action=domaindetails&id=[0-9]\+\)".*/\1/p;g' )"
    if [[ "$freenom_update_ip" -eq 1 || "$freenom_list_records" -eq 1 ]]; then
      # (NOTE): on ip update or list_records reverse sort newest first to possibly get a quicker match below
      myDomainsResult=$( echo "$myDomainsResult" | tr ' ' '\n' | sort -r )
    fi
    i=0
    # (NOTE): iterate over domaindetails url(s)
    for url in $myDomainsResult; do
      r=1
      while [ "$r" -le "$freenom_http_retry" ]; do
        if [ "$debug" -ge 1 ]; then
          func_debugHttp "domains" "domainDetails"
        fi
        # DEBUG: for debugging use local file instead:
        #        domainDetails=$( curl $c_args -A "$agent" --compressed -L -b "$cookie_file" -w $http_code "file:///home/user/src/freenom/domainDetails_$i.bak" )
        domainDetails="$( curl $c_args -A "$agent" --compressed -L -b "$cookie_file" -w $http_code "https://my.freenom.com/$url" )"
        func_httpOut "$domainDetails"; domainDetails="$httpOut"
        if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${domainDetails}" | grep -q "403 Forbidden"; then
          domainId[$i]="$( echo "$url" | sed -n 's/.*id=\([0-9]\+\).*/\1/p;g' )"
          domainName[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Domain:\(.*\)<[a-z].*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g' )"
          if [ "$debug" -ge 1 ]; then
            echo "DEBUG: domains domainId=${domainId[$i]} domainName=${domainName[$i]}" 
          fi
          break
        else
          func_errMsgHttp "Domain details"
          agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
          r="$((r+1))"
        fi
      done
      # (NOTE): on ip update or list_records we just need domain name matched and id set
      if [[ "$freenom_update_ip" -eq 1 || "$freenom_list_records" -eq 1 ]]; then
        if [ "${domainName[$i]}" == "$freenom_domain_name" ]; then
          freenom_domain_id="${domainId[$i]}"
          if [ "$debug" -ge 1 ]; then
             echo "DEBUG: domains MATCH: \"${domainName[$i]}\" = \"$freenom_domain_name\""
          fi
          break
        fi
      # (NOTE): for renewals we also need to get expiry date
      elif [[ "$freenom_renew_domain" -eq 1 || "$freenom_list" -eq 1 || "$freenom_list_renewals" -eq 1 ]]; then
        domainRegDate[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Registration Date:\(.*\)<.*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g' )"
        domainExpiryDate[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Expiry date:\(.*\)<.*/\1/p' | sed 's/<[^>]\+>//g' )"
        if [ "$debug" -ge 1 ]; then echo "DEBUG: domains domainRegDate=${domainRegDate[$i]} domainExpiryDate=${domainExpiryDate[$i]}"; fi
      fi
      i=$((i+1))
    done
  fi
else
  # (NOTE): if we already have domain_id and name; copy to domainId and Name array, for renewals also get expiry date
  domainId[0]="${freenom_domain_id}"
  domainName[0]="${freenom_domain_name}"
  if [[ "$freenom_renew_all" -eq 0 && "$freenom_renew_domain" -eq 1 ]]; then
    r=1
    while [ "$r" -le "$freenom_http_retry" ]; do
      if [ "$debug" -ge 1 ]; then
        func_debugHttp "domainDetails"
      fi
      domainDetails="$( curl $c_args -A "$agent" --compressed -L -b "$cookie_file" -w $http_code "https://my.freenom.com/clientarea.php?action=domaindetails&id=${freenom_domain_id}" )"
      func_httpOut "$domainDetails"; domainDetails="$httpOut"
      if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${domainDetails}" | grep -q "403 Forbidden"; then
        domainExpiryDate[0]="$( echo -e "$domainDetails" | sed -n 's/.*Expiry date:\(.*\)<.*/\1/p' | sed 's/<[^>]\+>//g' )"
        break
      else
        agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
        r="$((r+1))"
        func_errMsgHttp "Domain details"
      fi
    done
  fi
fi

# on update_ip, renew_domain or list_records; get domain_id if its empty
# also show error msg and exit if id or name is missing (e.g. wrong name as arg)
if [[ "$freenom_renew_domain" -eq 1 && "$freenom_domain_id" ]] ||
   [[ "$freenom_update_ip" -eq 1 && "$freenom_update_all" -eq 0 && "$freenom_domain_id" == "" ]] ||
   [[ "$freenom_list_records" -eq 1 && "$freenom_domain_id" == "" ]]
then
  for ((i=0; i < ${#domainName[@]}; i++)); do
    if [ "$debug" -ge 1 ]; then echo "DEBUG: domainname i=$i domainName=${domainName[$i]}"; fi
    if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then
      freenom_domain_id="${domainId[$i]}"
      if [ "$debug" -ge 1 ]; then
        echo "DEBUG: domainname match: freenom_domain_name=$freenom_domain_name ${domainName[$i]} (freenom_domain_id=${domainId[$i]}"
      fi
    fi
  done
  uMsg="Try \"$scriptName [-u|-r|-z] [domain] [id] [-s subdomain]\""
  cMsg="Or set \"freenom_domain_name\" in config"
  if [ "$freenom_domain_id" == "" ]; then
    [ "$freenom_domain_name" != "" ] && fMsg=" for \"$freenom_domain_name\""
    echo -e "[$(date)] Error: Domain renewal - No Domain ID \"$freenom_domain_name\"" >> "${out_path}.log"
    printf "Error: Could not find Domain ID%s\n%7s%s\n%7s%s\n" "$fMsg" ' ' "$uMsg" ' ' "$cMsg"
    exit 1
  fi
  if [ "$freenom_domain_name" == "" ]; then
    if [ "$freenom_domain_id" != "" ]; then iMsg=" ($freenom_domain_id)"; fi
    echo -e "[$(date)] Error: Domain renewal - Domain Name missing${iMsg}" >> "${out_path}.log"
    printf "Error: Domain Name missing\n%7s%s\n%7s%s\n" ' ' "$uMsg" ' ' "$cMsg"
    exit 1
  fi
fi

###############
# DNS Records #
###############

# Function func_getDnsPage: get DNS Management Page
#                           parameters: $1 = $freenom_domain_name $2 = $freenom_domain_id
func_getDnsPage () {
  r=1
  dnsManagementURL="https://my.freenom.com/clientarea.php?managedns=${1}&domainid=${2}"
  while [ "$r" -le "$freenom_http_retry" ]; do
    if [ "$debug" -ge 1 ]; then
        func_debugHttp "managedns" "dnsManagementPage"
    fi
    dnsManagementPage="$(curl $c_args -A "$agent" --compressed -L -b "$cookie_file" -w $http_code "$dnsManagementURL")"
    # TODO:
    if [ "$debug" -ge 2 ]; then
      echo "$dnsManagementPage" > /tmp/"$(date +%F_%T)-dnsManagementPage.html"
      echo "DEBUG: dnsManagementPage saved to /tmp/$(date +%F_%T)-dnsManagementPage.html"
    fi
    func_httpOut "$dnsManagementPage"; dnsManagementPage="$httpOut"
    if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${dnsManagementPage}" | grep -q "403 Forbidden"; then
      break
    else
      r="$((r+1))"
      agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
      func_errMsgHttp "DNS Management Page"
    fi
  done
  if [ "$r" -gt "$freenom_http_retry" ]; then
    echo "Error: DNS Management Page - $freenom_http_retry maximum retries was reached, exiting..."
    exit 1
  fi
}

# Function getRec: get domain records from dnsManagementPage
#          parameters : $1 = freenom_domain_name $2 = freenom_subdomain_name
#          returns    : v1 = recnum, v2 = type|name|ttl|value, v3 = recname/value(ip)
#                       sets dnUC and sdLC to UPPERCASE (sub)domain
#                       sets v3 to dnUC if 'name' if its empty
func_getRec() {
  IFS_SAV=$IFS; IFS=$'\n'
  if [ -n "$1" ]; then
    dnUC="$( echo "$1" | tr '[:lower:]' '[:upper:]' )"
  fi
  if [ -n "$2" ]; then
    sdUC="$(echo "$2" | tr '[:lower:]' '[:upper:]')"
  fi
  local r; local v1; local v2; local v3 
  for r in $( echo -e "$dnsManagementPage" | tr '<' '\n' |
              sed -r -n 's/.*records\[([0-9]+)\]\[(type|name|ttl|value)\]\" value=\"([0-9a-zA-Z:\.-]*)\".*/\1 \2 \3/p;g' ); do
    IFS=" " read -r v1 v2 v3 <<< "$r"
    # if name is empty, set it to apex domain
    if [[ $v2 == "name" && "$v3" == "" ]]; then
      v3="$dnUC"
    fi
    if [ "$v3" == "" ]; then v3="NULL"; fi
    if [ "$v1" != "" ]; then
      case "$v2" in
        type)   recType[$v1]="$v3" ;;
        name)   recName[$v1]="$v3" ;;
        ttl)    recTTL[$v1]="$v3" ;;
        value)  recValue[$v1]="$v3" ;;
      esac
    fi
    if [ "$debug" -ge 2 ]; then echo "DEBUG: v1=$v1 v2=$v2 v3=$v3"; fi
    v1=""; v2=""; v3=""
  done
  IFS=$IFS_SAV
}

# Function setRec: add/modify domain records
func_setRec() {
  # add/update dns record, 
  # params: $1 = freenom_subdomain_name
  r=1
  while [ "$r" -le "$freenom_http_retry" ]; do
    if [ "$debug" -ge 1 ]; then
      func_debugHttp "update_ip" "updateResult"
    fi
    # other record types:
    #   -F "${recordKey}[line]="    -F "${recordKey}[priority]="
    #   -F "${recordKey}[port]="    -F "${recordKey}[weight]="
    #   -F "${recordKey}[forward_type]=1"
    updateResult=$(curl $c_args -A "$agent" -e 'https://my.freenom.com/clientarea.php' --compressed -L -b "$cookie_file" -w $http_code \
        -F "dnsaction=$dnsAction" \
        -F "${recordKey}[name]=${1}" \
        -F "${recordKey}[type]=${freenom_update_type}" \
        -F "${recordKey}[ttl]=${freenom_update_ttl}" \
        -F "${recordKey}[value]=${currentIp}" \
        -F "token=$token" \
        "$dnsManagementURL" 2>&1)
    func_httpOut "$updateResult"; updateResult="$httpOut"
    if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${updateResult}" | grep -q "403 Forbidden"; then
      break
    else
      r="$((r+1))"
      agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
      func_errMsgHttp "Update result"
    fi
  done
  if [ "$debug" -ge 1 ]; then
    echo "DEBUG: update_ip vars i=$i recEmtpy=$dnsEmpty recMatch=$recMatch recordKey=$recordKey dnsAction=$dnsAction"
    if [ "$freenom_update_all" -eq 0 ]; then
      echo "DEBUG: update_ip vars recType=${recType[$n]} recName=${recName[$n]} recTTL=${recTTL[$n]} recValue=${recValue[$n]} (empty on 'add' actnon)"
    fi
    echo "DEBUG: update_ip vars freenom_update_type=$freenom_update_type name=$1 ttyl=$freenom_update_ttl value=$currentIp"
  fi
}

if [[ "$freenom_update_ip" -eq 1 || "$freenom_list_records" -eq 1 ]]; then
  func_getDnsPage "$freenom_domain_name" "$freenom_domain_id"
fi

# call getRec function to list records
if [ "$freenom_list_records" -eq 1 ]; then
  func_getRec "$freenom_domain_name" "$freenom_subdomain_name"
  printf "DNS Zone: \"%s\" (%s)\n\n" "$freenom_domain_name" "$freenom_domain_id"
  if [ "${#recType[@]}" -gt 0 ]; then
    for ((i=0; i < ${#recType[@]}; i++)); do
      if [ "$debug" -ge 3 ]; then
        echo "DEBUG: list_records func_getRec i=$i recTypeArray=${#recType[@]} recType=${recType[$i]} recName=${recName[$i]} recTTL=${recTTL[$i]} recValue=${recValue[$i]}"
      fi
      # subdomains
      if [ -n "$freenom_subdomain_name" ]; then
        if [ "${recName[$i]}" == "$sdUC" ]; then
          printf "Subdomain Record: name=\"%s\" ttl=\"%s\" type=\"%s\" value=\"%s\"\n" \
            ${recName[$i]} "${recTTL[$i]}" "${recType[$i]}" "${recValue[$i]}"
          break
        fi
      # domains - format: plain(default) or bind
      else
        rnLC="$( echo ${recName[$i]} | tr '[:upper:]' '[:lower:]' )"
        if [[ -n "$freenom_list_bind" && "$freenom_list_bind" -eq 1 ]]; then
          # if apex domain change name to '@'
          if [ "${recName[$i]}" == "$dnUC" ]; then rnLC="@"; fi
            printf "%s\t\t%s\tIN\t%s\t%s\n" "$rnLC" "${recTTL[$i]}" "${recType[$i]}" "${recValue[$i]}"
        else
          printf "Domain Record: name=\"%s\" ttl=\"%s\" type=\"%s\" value=\"%s\"\n" \
            ${recName[$i]} "${recTTL[$i]}" "${recType[$i]}" "${recValue[$i]}"
        fi
      fi
    done
  else
    echo "No records found"
  fi
  echo
  exit 0
fi

##########
# DynDNS #
##########

# Update ip: if record does not exist add new record, else update record
#      NOTE: 'recName' is not used in actual dns record
if [ "$freenom_update_ip" -eq 1 ]; then
  # make sure it's a ipv4 or ipv6 address
  freenom_update_type="A"
  if [[ -n "$freenom_update_ipv" && "$freenom_update_ipv" -eq 4 ]]; then freenom_update_type="A"
    elif [[ -n "$freenom_update_ipv" && "$freenom_update_ipv" -eq 6 ]]; then freenom_update_type="AAAA"
    elif [[ "$currentIp" =~ ^(([0-9]{1,3}\.){1}([0-9]{1,3}\.){2}[0-9]{1,3})$ ]]; then freenom_update_type="A"
    elif [[ "$currentIp" =~ ^[0-9a-fA-F]{1,4}: ]]; then freenom_update_type="AAAA"
  fi
  # (NOTE): handle SINGLE domain and record here
  if [ "$freenom_update_all" -eq 0 ]; then
    dnsEmpty="0"; recMatch="0"
    # if theres no record at all: use 'add'
    if [ "$(echo "$dnsManagementPage" | grep -F "records[0]")" == "" ]; then
      recordKey="addrecord[0]"
      dnsAction="add"
      dnsEmpty=1
    else
      # find matching record
      func_getRec "$freenom_domain_name" "$freenom_subdomain_name"
      for ((i=0; i < ${#recType[@]}; i++)); do
        if [ "$debug" -ge 1 ]; then
          echo "DEBUG: update_ip i=$i recTypeArray=${#recType[@]} recType=${recType[$i]} recName=${recName[$i]} recTTL=${recTTL[$i]} recValue=${recValue[$i]}"
        fi
        # make sure its the same recType (ipv4 or 6)
        if [ "${recType[$i]}" == "$freenom_update_type" ]; then
          # if domain name or subdomain name already exists, use 'modify' instead of 'add'
          if [ "${recName[$i]}" != "" ]; then
            if [ "${recName[$i]}" == "$sdUC" ] ||
               [[ "${recName[$i]}" == "$dnUC" && "$freenom_subdomain_name" == "" ]]
            then
              if [ "$debug" -ge 1 ]; then
                echo "DEBUG: update_ip i=$i type/domain MATCH: recType=${recType[$i]} recName=${recName[$i]} -> dnUC=$dnUC *OR* sdUC=$sdUC"
              fi
              recordKey="records[$i]"
              dnsAction="modify"
              recMatch=1
              break
            fi
          fi
        fi
      done
    fi
    # there are existing records, but none match: use 'add' 
    if [[ "$dnsEmpty" -eq 0 && "$recMatch" -eq 0 ]]; then
      # (NOTE): always use addrecord[0], even on new records; freenom dns mgmt page also does this(!)
      # recordKey="addrecord[${#recType[@]}]"
      recordKey="addrecord[0]"
      dnsAction="add"
    fi
    [ "$recMatch" -eq 0 ] && recName=()
    # if subdom is empty then 'name' is also, which equals apex domain
    func_setRec "${freenom_subdomain_name}" 

  # (NOTE): handle ALL domains and records here

  elif [ "$_TODO_" -eq 1 ]; then
    exit
# elif [[ -n "$freenom_update_all" && "$freenom_update_all" -eq 1 ]]; then
#
# TODO:
# - remove checks and update *all* domains and records
#   OR: user specifies subdomain -> update subdomain, if not - update all
# - error handling
# - .ip file ("all"?)
#
#    for ((i=0; i < ${#domainName[@]}; i++)); do
#      if [ "$debug" -ge 1 ]; then
#        echo "DEBUG: update_all call func_getDnsPage \"${domainName[$i]}\" \"${domainId[$i]}\""
#      fi
#      func_getDnsPage "${domainName[$i]}" "${domainId[$i]}"
#
#      if [ "$(echo "$dnsManagementPage" | grep -F "records[0]")" != "" ]; then
#        func_getRec "${domainName[$i]}" "$freenom_subdomain_name"
#        for ((j=0; j < ${#recType[@]}; j++)); do
#          if [ "$debug" -ge 1 ]; then
#            echo "DEBUG: update_all j=$j recTypeArray=${#recType[@]} recType=${recType[$j]} recName=${recName[$j]} recTTL=${recTTL[$j]} recValue=${recValue[$j]}"
#          fi
#
#          # TODO:
#          if [ "$debug" -ge 1 ]; then
#            echo "DEBUG: update_all freenom_subdomain_name=$freenom_subdomain_name"
#            echo "DEBUG: update_all freenom_update_type=$freenom_update_type"
#            echo "DEBUG: update_all sdUC=$sdUC"
#            echo "DEBUG: update_all dnUC=$dnUC"
#          fi
#
#          if [ "${recType[$j]}" == "$freenom_update_type" ]; then
#            if [ "${recName[$j]}" != "" ]; then
#              if [ "${recName[$j]}" == "$sdUC" ] ||
#                 [[ "${recName[$j]}" == "$dnUC" && "$freenom_subdomain_name" == "" ]]
#              then
#                if [ "$debug" -ge 1 ]; then
#                  echo "DEBUG: update_all j=$j type/domain MATCH: recType=${recType[$j]} recName=${recName[$j]} -> dnUC=$dnUC *OR* sdUC=$sdUC"
#                  #echo "DEBUG: update_all j=$j recType=${recType[$j]} recName=${recName[$j]} (?)unused: dnUC=$dnUC sdUC=$sdUC"
#                  echo "DEBUG: calling func_setRec ${freenom_subdomain_name}"
#                fi
#                recordKey="records[$j]"
#                dnsAction="modify"
#                func_setRec "${freenom_subdomain_name}"
#                #
#                # TODO: add 'else' to save ip to file on success? or move to setRec function? 
#                #
#                if [ "$(echo -e "$updateResult" | grep "$currentIp")" == "" ]; then
#                  echo "[$(date)] Update failed: all (\"${domainName[$i]}\" \"${domainId[$i]}\") - ${currentIp}" >> "${out_path}.log"
#                  errCount="$((errCount+1))"
#                fi
#              fi
#            fi
#          fi
#        done
#      else
#        eMsg="Error: no records found for \"${domainName[$i]}\""
#        echo "$eMsg"; echo "[$(date)] $eMsg \"${domainName[$i]}\"" >> "${out_path}.log"
#      fi
#    done
  fi
fi

################
# List Domains #
################

# NOTE: freenom_domain_id   -> domainId
#       freenom_domain_name -> domainName

# list all domains and id's, list renewals
if [ "$freenom_list" -eq 1 ]; then
  if [ "$freenom_list_renewals" -eq 1 ]; then
    domainRenewalsURL="https://my.freenom.com/domains.php?a=renewals&itemlimit=all&token=$token"
    r=1
    while [ "$r" -le "$freenom_http_retry" ]; do
      if [ "$debug" -ge 1 ]; then
        func_debugHttp "renewals" "domainRenewalsURL $domainRenewalsURL"
      fi
      domainRenewalsPage="$(curl $c_args -A "$agent" --compressed -L -b "$cookie_file" -w $http_code "$domainRenewalsURL")"
      func_httpOut "$domainRenewalsPage"; domainRenewalsPage="$httpOut"
      if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${domainRenewalsPage}" | grep -q "403 Forbidden"; then
        if [ -n "$domainRenewalsPage" ]; then
          domainRenewalsResult="$( echo -e "$domainRenewalsPage" | \
            sed -n '/<table/,/<\/table>/{//d;p;}' | \
            sed '/Domain/,/<\/thead>/{//d;}' | \
            sed 's/<.*domain=\([0-9]\+\)".*>/ domain_id: \1\n/g' | \
            sed -e 's/<[^>]\+>/ /g' -e 's/\(  \|\t\)\+/ /g' -e '/^[ \t]\+/d' )"
        fi
        break
      else
        r="$((r+1))"
        agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
        func_errMsgHttp "Domain renewals page"
      fi
    done
  fi
  for ((i=0; i < ${#domainName[@]}; i++)); do
    if [ "$freenom_list_renewals" -eq 1 ]; then
      if [ -n "$domainRenewalsResult" ]; then
        renewalMatch=$( echo "$domainRenewalsResult" | sed 's///g' | sed ':a;N;$!ba;s/\n //g' | grep "domain_id: ${domainId[$i]}" )
        if echo "$renewalMatch" | grep -q Minimum; then
          # shellcheck disable=SC2001
          renewalDetails="$( echo "$renewalMatch" | sed 's/.* \([0-9]\+ Days\) * \(Minimum.*\) * domain_id:.*/\1 Until Expiry, \2/g' )"
        elif echo "$renewalMatch" | grep -q Renewable; then
          # shellcheck disable=SC2001
          renewalDetails="$( echo "$renewalMatch" | sed 's/.* \([0-9]\+ Days\) * \(Renewable\) * domain_id:.*/\2, \1 Until Expiry/g' )"
        fi
      fi
      if [ ! "$renewalDetails" ]; then
        renewalDetails="N/A"
      fi
      showRenewal="$( printf "\n%4s Renewal details: %s" " " "$renewalDetails" )"
    fi
    printf "[%02d] Domain: \"%s\" Id: \"%s\" RegDate: \"%s\" ExpiryDate: \"%s\"%s\n" \
      "$((i+1))" "${domainName[$i]}" "${domainId[$i]}" "${domainRegDate[$i]}" "${domainExpiryDate[$i]}" "$showRenewal"
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
  IFS="/" read -a a -r <<< "${domainExpiryDate[$1]}"; expiryDay="${a[0]}"; expiryMonth="${a[1]}"; expiryYear="${a[2]}"
  if [[ "$expiryDay" != "" && "$expiryMonth" != ""&& "$expiryYear" != "" ]]; then
    if [ "$debug" -ge 1 ]; then
      echo "DEBUG: renew_domain func_renewDate domainExpiryDate array=${domainExpiryDate[$1]}"
    fi
    expiryDate="$( date -d "${expiryYear}-${expiryMonth}-${expiryDay}" +%F )"
    renewDate="$( date -d "$expiryDate - 14Days" +%F )"
    currentEpoch="$( date +%s )"
    renewEpoch="$( date -d "$renewDate" +%s )"
    if [ "$debug" -ge 1 ]; then
      echo "DEBUG: renew_domain func_renewDate expiryDate=$expiryDate renewDate=$renewDate"
      echo "DEBUG: renew_domain func_renewDate renewEpoch=$renewEpoch currentEpoch=$currentEpoch"
    fi
    if [ "$debug" -ge 2 ]; then
      echo "TEST: renew_domain func_renewDate listing full expiry date array:"
      for ((j=0; j<${#a[@]}; j++)); do echo "DEBUG: func_renewDate i=${i} ${a[$j]}"; done
    fi
    # TEST: example - set a date after renewDate
    #       currentEpoch="$( date -d "2099-01-01" +%s )"
    if [ "$currentEpoch" -ge "$renewEpoch" ]; then
      renewDateOkay=1
      if [ "$debug" -ge 1 ]; then
        echo -e "DEBUG: renew_domain func_renewDate domainName=${domainName[$1]} (Id=${domainId[$1]}) - OK (renewdateOkay=$renewDateOkay)"
      fi
    else
      noticeCount="$((noticeCount+1))"
      renewNotice="${renewNotice}\n  Cannot renew \"${domainName[$1]}\" (${domainId[$1]}) until $renewDate"
      if [ "$debug" -ge 1 ]; then
        echo -e "DEBUG: renew_domain func_renewDate domainName=${domainName[$1]} (Id=${domainId[$1]}) - cannot renew until Date=$renewDate"
      fi
    fi
  else
    errCount="$((errCount+1))"
    renewError="${renewError}\n  No expiry date for \"${domainName[$1]}\" (${domainId[$1]})"
    if [ "$debug" -ge 1 ]; then
      echo "DEBUG: renew_domain func_renewDate domainName=\"${domainName[$1]}\" (Id=${domainId[$1]}) (i=$i) - no expiry date"
    fi
  fi
}

# Function renewDomain: if date is ok, submit actual renewal and get result
func_renewDomain() {
  if [[ -n "$renewDateOkay" && "$renewDateOkay" -eq 1 ]]; then
    # use domain_id domain_name
    freenom_domain_id="${domainId[$1]} $freenom_domain_id"
    freenom_domain_name="${domainName[$1]} $freenom_domain_name"
    if [ "$debug" -ge 1 ]; then
      echo "DEBUG: renew_domain func_renewDomain freenom_domain_name=$freenom_domain_name - curdate>expirydate = possible to renew"
    fi
    renewDomainURL="https://my.freenom.com/domains.php?a=renewdomain&domain=${domainId[$1]}&token=$token"
    r=1
    while [ "$r" -le "$freenom_http_retry" ]; do
      if [ "$debug" -ge 1 ]; then
          func_debugHttp "renew_domain" "func_renewDomain renewDomainURL $renewDomainURL"
      fi
      renewDomainPage="$(curl $c_args -A "$agent" --compressed -L -b "$cookie_file" -w $http_code "$renewDomainURL")"
      func_httpOut "$renewDomainPage"; renewDomainPage="$httpOut"
      if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${renewDomainPage}" | grep -q "403 Forbidden"; then
        break
      else
        r="$((r+1))"
        agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
        func_errMsgHttp "Renew domain page"
      fi
    done

    # NOTE: EXAMPLE
    # url:       https://my.freenom.com/domains.php?submitrenewals=true
    # form data: 7ad1a728a6d8a96d1a8d66e63e8a698ea278986e renewalid:1234567890 renewalperiod[1234567890]:12M paymentmethod:credit

    if [ -n "$renewDomainPage" ]; then
      echo "$renewDomainPage" > "${out_path}_renewDomainPage-${domainId[$1]}.html"
      if [ "$debug" -ge 1 ]; then echo "DEBUG: renew_domain renewDomainPage - OK renewDomainURL=$renewDomainURL"; fi
      renewalPeriod="$( echo "$renewDomainPage" | sed -n 's/.*option value="\(.*\)\".*FREE.*/\1/p' | sort -n | tail -1 )"
      # if [ "$renewalPeriod" == "" ]; then renewalPeriod="12M"; fi
      if [ -n "$renewalPeriod" ]; then
        renewalURL="https://my.freenom.com/domains.php?submitrenewals=true"
        r=1
        while [ "$r" -le "$freenom_http_retry" ]; do
          if [ "$debug" -ge 1 ]; then
              func_debugHttp "renew_domain renewalURL $renewalURL"
          fi
          renewalResult="$(curl $c_args -A "$agent" --compressed -L -b "$cookie_file" -w $http_code \
            -F "token=$token" \
            -F "renewalid=${domainId[$1]}" \
            -F "renewalperiod[${domainId[$1]}]=$renewalPeriod" \
            -F "paymentmethod=credit" \
            "$renewalURL" 2>&1)"
          func_httpOut "$renewalResult"; renewalResult="$httpOut"
          if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${renewalResult}" | grep -q "403 Forbidden"; then
            # write renewal result html file, count errors and set ok/error messages per domain
            if [ -n "$renewalResult" ] ; then
              echo -e "$renewalResult" > "${out_path}_renewalResult-${domainId[$1]}.html"
              renewOK="$renewOK\n  Successfully renewed domain \"${domainName[$1]}\" (${domainId[$1]}) - ${renewalPeriod}"
            else
              errCount="$((errCount+1))"
              renewError="$renewError\n  Renewal failed for \"${domainName[$1]}\" (${domainId[$1]})"
            fi
            break
          else
            r="$((r+1))"
            agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
            func_errMsgHttp "Renewal domain URL"
          fi
        done
      else
        errCount="$((errCount+1))"
        renewError="$renewError\n  Cannot renew \"${domainName[$1]}\" (${domainId[$1]}), renewal period not found"
      fi
    else
      errCount="$((errCount+1))"
    fi
  else
    if [ "$debug" -ge 1 ]; then echo "DEBUG: renew_domain func_renewDomain 1=$1 renewDateOkay=$renewDateOkay - skipped domainName=\"${domainName[$1]}\""; fi
  fi
}

# call domain renewal functions for all or single domain
if [ "$freenom_renew_domain" -eq 1 ]; then
  domMatch=0
  for ((i=0; i < ${#domainName[@]}; i++)); do
    if [ "${domainExpiryDate[$i]}" == "" ]; then
      warnCount="$((warnCount+1))"
      echo "[$(date)] Warning: Missing domain expiry date for \"${domainName[$i]}\"" >> "${out_path}.log"
      if [ "$debug" -ge 1 ]; then
        echo "DEBUG: renew_domain Missing domain expiry date - domainName=\"${domainName[$i]}\" (i=$i)"
      fi
    else
      if [ "$debug" -ge 1 ]; then
        echo "DEBUG: renew_domain i=$i arraycount=${#domainName[@]} domainId=${domainId[$i]} domainName=${domainName[$i]}"
      fi
    fi
    if [ "$freenom_renew_all" -eq 1 ]; then
      if [ "$debug" -ge 1 ]; then
        echo "DEBUG: renew_all i=$i domainName=${domainName[$i]}"
      fi
      func_renewDate "$i"
      func_renewDomain "$i"
    else
      if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then
        if [ "$debug" -ge 1 ]; then
          echo "DEBUG: renew_domain i=$i MATCH: freenom_domain_name=$freenom_domain_name - domainName=${domainName[$i]}"
        fi
        func_renewDate "$i"
        func_renewDomain "$i"
        domMatch=1
        break
      fi
    fi
  done
  if [[ "$freenom_renew_all" -eq 0 && "$domMatch" -eq 0 ]]; then
    if [ "$debug" -ge 1 ]; then
      echo "DEBUG: renew_domain freenom_domain_name=${freenom_domain_name} not found"
    fi
    errCount="$((errCount+1))"
    renewError="\"${freenom_domain_name}\" not found"
  fi
fi

# logout
r=1
while [ "$r" -le "$freenom_http_retry" ]; do
  # DEBUG: comment line below for debugging
  logoutPage="$(curl $c_args -A "$agent" --compressed -L -b "$cookie_file" -w $http_code "https://my.freenom.com/logout.php" 2>&1)"
  func_httpOut "$logoutPage"; logoutPage="$httpOut"
  if [ "${httpCode:-"000"}" -eq "200" ] && ! echo "${logoutPage}" | grep -q "403 Forbidden"; then
    break
  else
    r="$((r+1))"
    agent="${uaString[$((RANDOM%${#uaString[@]}))]}"
    func_errMsgHttp "Logout page"
  fi
done
if [ "$debug" -ge 1 ]; then
  func_debugHttp "logout" "logoutPage"
fi
if [[ -n "$cookie_file" && -f "$cookie_file" ]]; then
  rm "$cookie_file"
fi

###########
# Logging #
###########

# TODO: handle 'all_domains' here?

# handle error count and error messages
if [ "$freenom_update_ip" -eq 1 ]; then
  if [ "$(echo -e "$updateResult" | grep "$currentIp")" == "" ]; then
    echo "[$(date)] Update failed: \"${ipDomName//_/.}\" (${freenom_domain_id}) - ${currentIp}" >> "${out_path}.log"
    if [ "$debug"  -ge 1 ]; then
      #echo -e "$updateResult" > "${out_path}_errorUpdateResult-${freenom_domain_id}.html"
      echo "DEBUG: skipped saving updateResult to \"${out_path}_errorUpdateResult-${freenom_domain_id}.html\""
    fi
    errCount="$((errCount+1))"
  else
    # save ip address to ip and log file
    echo -n "$currentIp" > "${out_path}_${ipDomName}.ip${freenom_update_ipv}"
    echo "[$(date)] Update successful: \"${ipDomName//_/.}\" (${freenom_domain_id}) - ${currentIp}" >> "${out_path}.log"
  fi
fi

# write renewal results to logfile, count errors, warnings and set messages
if [ "$freenom_renew_domain" -eq 1 ]; then
  if [ -n "$renewOK" ]; then
    echo -e "[$(date)] Domain renewal successful: $renewOK" >> "${out_path}.log"
  fi
  if [[ -n "$freenom_renew_log" && "$freenom_renew_log" -eq 1 ]]; then
    if [ "$noticeCount" -gt 0 ]; then
      if [ -n "$renewNotice" ]; then
        echo -e "[$(date)] These domain(s) were not renewed: ${renewNotice}" >> "${out_path}.log"
      fi
    fi
  fi
  if [ "$errCount" -gt 0 ]; then
    if [ -z "$renewError" ]; then
      if [ "$(echo -e "$renewalResult" | grep "Minimum Advance Renewal is")" != "" ]; then
        renewError="$( echo -e "$renewalResult" | grep textred | \
            sed -e 's/<[^>]\+>//g' -e 's/\(  \|\t\|\)//g' | sed ':a;N;$!ba;s/\n/, /g')"
      fi
    fi
    echo -e "[$(date)] These domain(s) failed to renew: ${renewError}" >> "${out_path}.log"
  fi
  if [ "$noticeCount" -eq 0 ] && [ "$warnCount" -eq 0 ] && [ "$errCount" -eq 0 ]; then
    echo "[$(date)] Successfully renewed domain \"$freenom_domain_name\" (${freenom_domain_id/% /})" >> "${out_path}.log"
  fi
fi

# log any warnings and/or errors and exit with exitcode
dMsg="[$(date)] Done"
if [[ "$warnCount" -gt 0 || "$errCount" -gt 0 ]]; then
  dMsg+=":"
  if [ "$warnCount" -gt 0 ]; then dMsg+=" $warnCount warning(s)"; fi
  if [ "$errCount" -gt 0 ];  then dMsg+=" $errCount error(s)"; fi
fi
echo "$dMsg" >> "${out_path}.log"
if [ "$errCount" -gt 0 ]; then
  exit 1
else
  exit 0
fi
