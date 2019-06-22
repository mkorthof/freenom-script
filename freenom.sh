#!/bin/bash

###############################################################################
# Domain Renewal and Dynamic DNS shell script for freenom.com                 #
###############################################################################
#                                                                             #
# Updates IP address and/or auto renews domain(s) so they do not expire       #
# See README.md for more information                                          #
#                                                                             #
# gpl-3.0-only                                                                #
# freenom-script  Copyright (C) 2019  M. Korthof                              #
# This program comes with ABSOLUTELY NO WARRANTY                              #
# This is free software, and you are welcome to redistribute it               #
# under certain conditions.                                                   #
# See LICENSE file for more information                                       #
#                                                               v2019-06-21   #
###############################################################################


########
# Main #
########

set -eo pipefail
scriptName="$(basename "$0")"
noticeCount="0"; warnCount="0"; errCount="0"

########
# Conf #
########

# configuration file specfied in argument
if echo -- "$@" | grep -qi '[^a-z]\-c'; then
  # shellcheck source=./freenom.conf
  #scriptConf="$( echo "$@" | sed 's/-c \?\([^ ]\+\)\(.*\|$\)/\1/' )"
  scriptConf="$( printf -- "%s\n" "$*" | sed -En 's/.* ?-c ?([][a-zA-Z0-9 !"#$%&'\''()*+,-.:;<=>?@^_`{}~./]+)( -.*| |$)/\1/gp' )"
  if [ ! -s "$scriptConf" ]; then
    echo "Error: invalid config \"$scriptConf\" specified"
    exit 1
  fi
fi
# if scriptConf is empty, check for freenom.conf in same dir as script
if [ -z "$scriptConf" ]; then
  scriptConf="$(dirname "$0")/$(basename -s '.sh' "$0").conf"
  # use BASH_SOURCE instead when called from 'bash -x $scriptName'
  if [ "$(dirname "$0")" = "." ]; then
    scriptConf="${BASH_SOURCE[0]/%sh/conf}"
  fi
fi
# source scriptConf if its non empty else exit
if [ -s "$scriptConf" ]; then
  # shellcheck source=./freenom.conf
  source "$scriptConf" || { echo "Error: could not load $scriptConf"; exit 1; }
fi

# make sure debug is always set
if [ -z "$debug" ]; then debug=0; fi

if [ "$debug" -ge 1 ]; then echo "DEBUG: conf scriptConf=$scriptConf"; fi

# we need these config settings, if not exit
if [ -z "$freenom_email" ]; then echo "Error: setting \"freenom_email\" is missing in config"; exit 1; fi
if [ -z "$freenom_passwd" ]; then echo "Error: setting \"freenom_passwd\" is missing in config"; exit 1; fi

# if out_path is not set or invalid, set default
out_path="${freenom_out_dir}/${freenom_out_mask}"
if [[ -z "$freenom_out_dir" || -z "$freenom_out_mask" || ! -d "$freenom_out_dir" ]]; then
  out_path="/var/log/$(basename -s '.sh' "$0")"
  echo "Warning: no valid \"freenom_out_dir\" or \"mask\" setting found, using default path: $out_path"
fi
if [ ! -w "${out_path}.log" ]; then
  echo "Error: Logfile \"${out_path}.log\" not writable, using \"/tmp/$(basename -s '.sh' "$0").log\" instead"
  out_path="/tmp/$(basename -s '.sh' "$0")"
fi

# generate "random" useragent string, used for curl and below in func_randIp
agent="${uaString[$((RANDOM%${#uaString[@]}))]}"

if [ -z "$c_args" ]; then
  c_args="-s"
fi

#############
# Functions #
#############

# Function help: displays options etc
func_help () {
  cat <<-_EOF_

FREENOM.COM DOMAIN RENEWAL AND DYNDNS

USAGE:
            $scriptName -l [-d]
            $scriptName -r <domain> [-s <subdomain>] | [-a]
            $scriptName -u <domain> [-s <subdomain>]
            $scriptName -z <domain>

OPTIONS:
            -l    List all domains and id's for account
                  add [-d] to show renewal Details
            -r    Renew domain(s)
                  add [-a] to renew All domains
            -u    Update <domain> A record with current ip
                  add [-s] to update <Subdomain>
            -z    Zone listing of dns records for <domain>

            -4    Use ipv4 and modify A record on "-u" (default)
            -6    Use ipv6 and modify AAAA record on "-u"
            -c    Config <file> to be used instead freenom.conf
            -i    Ip commands list used to get current ip
            -o    Output html result file(s) for update and renewal

EXAMPLES:
            ./$scriptName -r example.com
            ./$scriptName -c /etc/my.conf -r -a
            ./$scriptName -u example.com -s mail

NOTES:
            Using "-u" or "-r" and specifying <domain> as argument
            will override any settings in script or config file

_EOF_
  exit 0
}

# Function getDomArgs: use regex to get domain name digits only domain_id and -s <subdomain>
func_getDomArgs () {
  # first remove -c arg and save other options to $d_args
  d_args="$( echo "$@" | sed -E 's/ ?-c [][a-zA-Z0-9 !"#$%&'\''()*+,-.:;<=>?@^_`{}~.]+ ?//g' )"
  # to get domain_name: remove "-s" option, any other args e.g. "-[a-z]"
  #                     remove any 'digits only' options too (= domain id)
  arg_domain_name="$( echo "$d_args" | sed -E 's/( ?-s [^ ]+|( -[[:alnum:]]|-[[:alnum:]] )| [0-9]+|[0-9]+ | )|^-[[:alnum:]]$//g' )"
  arg_domain_id="$( echo "$d_args" | sed -n -E 's/.*([0-9]{10}+).*/\1/p' )"
  arg_subdomain_name="$( echo "$d_args" | sed -n -E 's/.*-s ?([^ ]+).*/\1/p' )"
  # if domain arg is not empty use it instead of setting in conf
  if [ -n "$arg_domain_name" ]; then
    freenom_domain_name="$arg_domain_name"
  fi
  if [ -n "$arg_subdomain_name" ]; then
    freenom_subdomain_name="$arg_subdomain_name"
  fi
  if [ -n "$arg_domain_id" ]; then
    freenom_domain_id="$arg_domain_id"
  fi
  if [ "$debug" -ge 1 ]; then
    echo "DEBUG: getDomArgs d_args=$d_args arg_domain_name=$arg_domain_name arg_domain_id=$arg_domain_id arg_subdomain_name=$arg_subdomain_name"
  fi
  # if we didnt get any args and no conf settings display error message
  if [ "$freenom_domain_name" == "" ]; then
    echo "Error: Domain Name missing"
    echo "  Try: $scriptName [-u|-r|-z] [domain]"
    exit 1
  fi
  # handle invalid domain settings
  if [[ ! "$freenom_domain_name" =~ ^[^.-][a-zA-Z0-9.-]+$ ]] || \
     [[ "$freenom_domain_name" == "$freenom_domain_id" ]]; then
    echo "Error: invalid domain name \"$freenom_domain_name\""
    exit 1
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
  for i in lynx links links2 wb3m elinks curl cat; do
    if command -v $i >/dev/null 2>&1; then
      break
    fi
  done
  case "$i" in
    lynx|links|links2|w3m|elinks)
      [ $i = "lynx" ] && s_args="-nolist"
      [ $i = "elinks" ] && s_args="-no-numbering -no-references"
      "$i" -dump $s_args "$1" | sed '/ \([*+□•] \?.\+\|\[.*\]\)/d'
    ;;
    curl|cat)
      [ $i = "curl" ] && s_args="-s file:///"
      "$i" ${s_args}"${1}" | \
        sed -e '/<a href.*>/d' -e '/<style type="text\/css">/,/</d' -e '/class="lang-/d' \
            -e 's/<[^>]\+>//g' -e '/[;}{):,>]$/d' -e '//d' -e 's/\t//g' -e '/^ \{2,\}$/d' -e '/^$/d'
    ;;
    *)
      echo "Error: Cannot display \"$1\""
      exit 1
    ;;
  esac
}

# TODO: test re_ip

# Function randIp: run random dig or curl ipCmd, replace %agent% with random useragent string
#                  regex: https://www.regexpal.com/?fam=104038
#                  return ipv4/6 address
RE_IP='((((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])))|(((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?))'
func_randIp() {
  [ "$debug" -ge 2 ] && set -x
  #echo "$( ${ipCmdTrim[$((RANDOM%${#ipCmdTrim[@]}))]/\%agent\%/$agent} 2>/dev/null )" | \
  ${ipCmdTrim[$((RANDOM%${#ipCmdTrim[@]}))]/\%agent\%/$agent} 2>/dev/null | \
    grep -Pow "$RE_IP"
  [ "$debug" -ge 2 ] && set +x
}

# Function trimIpcmd: trim ipCmd array from conf for update_ipv=4|6 and whether we want dig or not
#                     replaces %ipv% with $freenom_update_ipv
#                     creates new array: $ipCmdTrim
func_trimIpCmd () {
  for ((i=0; i < ${#ipCmd[@]}; i++)); do
    skip=0;
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

# There are 3 more functions down below:
# - Function getRec: get domain records from dnsManagementPage
# - Function renewDate: check date to make sure we can renew
# - Function renewDomain: if date is ok, submit actual renewal and get result

# debug functions

# Function debugVars: debug output args, actions etc
func_debugVars () {
  echo "DEBUG: args 1=$1 2=$2 3=$3 4=$4 5=$5 6=$6"
  echo "DEBUG: opts/conf freenom_out_dir=$freenom_out_dir freenom_out_mask=$freenom_out_mask out_path=$out_path"
  echo "DEBUG: opts/conf freenom_domain_name=$freenom_domain_name freenom_domain_id=$freenom_domain_id freenom_subdomain_name=$freenom_subdomain_name"
  echo "DEBUG: action    freenom_update_ip=$freenom_update_ip freenom_update_force=$freenom_update_force freenom_list_records=$freenom_list_records"
  echo "DEBUG: action    freenom_list=$freenom_list freenom_list_renewals=$freenom_list_renewals"
  echo "DEBUG: action    freenom_renew_domain=$freenom_renew_domain freenom_renew_all=$freenom_renew_all"
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
    IFS=$'\n'; for i in $( echo $myDomainsResult ); do
      echo DEBUG: myDomainsResult i="$i"; domainResult="$( echo "$i" | cut -d " " -f2 )"; domainIdResult="$( echo "$i" | cut -d " " -f4 )"
    done; echo "DEBUG: myDomainsResult domainResult: $domainResult domainIdResult: $domainIdResult"
  fi
}

###########
# Options #
###########

# show help
if echo -- "$@" | grep -qi '[^a-z]\-h'; then
  func_help
  exit 0
fi
# handle all other arguments
if ! echo -- "$@" | grep -qi -- '\-[46lruziceo]'; then
  echo "Error: invalid or unknown argument(s), try \"$scriptName -h\""
  exit 1
fi
if echo -- "$@" | grep -qi -- '[^a-z]\-4'; then
  freenom_update_ipv=4
  if [ "$debug" -ge 1 ]; then echo "DEBUG: ipv freenom_update_ipv=$freenom_update_ipv"; fi
elif echo -- "$@" | grep -qi -- '[^a-z]\-6'; then
  freenom_update_ipv=6
  if [ "$debug" -ge 1 ]; then echo "DEBUG: ipv freenom_update_ipv=$freenom_update_ipv"; fi
fi
# list domains and id's and exit, unless list_records is set
if echo -- "$@" | grep -qi -- '[^a-z]\-l'; then
  freenom_list="1"
  lMsg=""
  # list domains with details
  if echo -- "$@" | grep -Eqi -- '[^a-z]\-[dn]'; then
    freenom_list_renewals="1"
    lMsg=" with renewal details, this might take a while"
  fi
  printf "\nListing Domains and ID's%s...\n" "$lMsg"
  echo
# list dns records
elif echo -- "$@" | grep -qi -- '[^a-z]\-z'; then
  func_getDomArgs "$@"
  freenom_list_records="1"
# output ipcmd list
elif echo -- "$@" | grep -iq -- '[^a-z]\-i'; then
  if [ "$debug" -ge 1 ]; then echo "DEBUG: ipv freenom_update_ipv=$freenom_update_ipv"; fi
  echo; echo "Listing all \"get ip\" commands..."; echo
  for ((i=0; i < ${#ipCmd[@]}; i++)); do
    printf "%2s: %s\n" "$i" "${ipCmd[$i]}"
  done
  printf "\nNOTES:\n"
  printf "  %%ipv%% gets replaced by \$freenom_update_ipv\n"
  printf "  %%agent%% gets replaced with useragent string\n\n"
  exit 0
# update ip
elif echo -- "$@" | grep -qi -- '[^a-z]\-u'; then
  func_getDomArgs "$@"
  freenom_update_ip="1"
# renew domains
elif echo -- "$@" | grep -qi -- '[^a-z]\-r'; then
  freenom_renew_domain="1"
  if echo -- "$@" | grep -qi -- '[^a-z]\-a'; then
    freenom_renew_all="1"
  else
    func_getDomArgs "$@"
  fi
# show update and renewal result file(s)
elif echo -- "$@" | grep -qi -- '[^a-z]\-[eo]'; then
  # use regex if file is specfied
  fget="$( printf -- "%s\n" "$*" | sed -En 's/.* ?-[eo] ?([][a-zA-Z0-9 !"#$%&'\''()*+,-.:;<=>?@^_`{}~.]+)[ -]?.*/\1/gp' )"
  if [ -z "$fget" ]; then
    for f in "${out_path}".errorUpdateResult_*.html "${out_path}".renewalResult_*.html; do
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

# if these are missing, set defaults
if [ -z "$freenom_update_ipv" ]; then freenom_update_ipv=4; fi
if [ -z "$freenom_update_ttl" ]; then freenom_update_ttl="3600"; fi
if [ -z "$freenom_update_ip_retry" ]; then freenom_update_ip_retry="3"; fi

if [ "$debug" -ge 1 ]; then func_debugVars "$@"; fi

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

#############
# Update IP #
#############

# try getting ip by running a random ipCmd's, stop after max retries
if [ "$freenom_update_ip" -eq 1 ]; then
  func_trimIpCmd
  i=0
  while [[ "$current_ip" == "" && "$i" -lt "$freenom_update_ip_retry" ]]; do
    current_ip="$(func_randIp || true)"
    if [ "$debug" -ge 1 ]; then echo "DEBUG: getip i=$i current_ip=$current_ip"; fi
    i=$((i+1))
  done
  if [ "$current_ip" == "" ]; then
    eMsg="Could not get current local ip address"
    echo "Error: $eMsg"; echo "[$(date)] $eMsg" >> "${out_path}.log"
    exit 1
  fi
  if [[ -n "$freenom_update_force" && "$freenom_update_force" -eq 0 ]]; then
    if [ "$(cat "${out_path}.ip${freenom_update_ipv}_${freenom_domain_name}.lock" 2>&1)" == "$current_ip" ]; then
      if [[ -n "$freenom_update_ip_log" && "$freenom_update_ip_log" -eq 1 ]]; then
        echo "[$(date)] Done: Update skipped, same ip" >> "${out_path}.log"
      fi
      exit 0
    fi
  fi
fi

#########
# Login #
#########

cookie_file="$(mktemp)"
# DEBUG: comment line below for debugging
loginPage="$(curl $c_args -A "$agent" --compressed -k -L -c "$cookie_file" \
    "https://my.freenom.com/clientarea.php" 2>&1)"
# old: token=$(echo "$loginPage" | grep token | grep -o value=".*" | sed 's/value=//g' | sed 's/"//g' | awk '{print $1}')
token="$(echo "$loginPage" | grep token | head -1 | grep -o value=".*" | sed 's/value=//g' | sed 's/"//g' | awk '{print $1}')"
# DEBUG: comment line below for debugging
loginResult="$(curl $c_args -A "$agent" -e 'https://my.freenom.com/clientarea.php' -compressed -k -L -c "$cookie_file" \
    -F "username=$freenom_email" -F "password=$freenom_passwd" -F "token=$token" \
    "https://my.freenom.com/dologin.php")"
if [ "$(echo -e "$loginResult" | grep "Location: /clientarea.php?incorrect=true")" != "" ]; then
    echo "[$(date)] Login failed" >> "${out_path}.log"
    rm -f "$cookie_file"
    errCount="$((errCount+1))"
fi

###############
# Domain info #
###############

# retrieve client area page, get domain detail urls and loop over them to get all data
# arrays: domainId, domainName, domainRegDate, domainExpiryDate

if [ "$freenom_domain_id" == "" ]; then
  myDomainsURL="https://my.freenom.com/clientarea.php?action=domains&itemlimit=all&token=$token"
  # DEBUG: for debugging use local file instead:
  # DEBUG: myDomainsURL="file:///home/user/src/freenom/myDomainsPage"
  myDomainsPage="$(curl $c_args -A "$agent" --compressed -k -L -b "$cookie_file" "$myDomainsURL")"
  if [ "$myDomainsPage" ]; then
    # old: myDomainsResult="$( echo -e "$myDomainsPage" | sed -n '/href.*external-link/,/action=domaindetails/p' | sed -ne 's/.*id=\([0-9]\+\).*/\1/p;g' )"
    myDomainsResult="$( echo -e "$myDomainsPage" | sed -ne 's/.*"\(clientarea.php?action=domaindetails&id=[0-9]\+\)".*/\1/p;g' )"
    if [[ "$freenom_update_ip" -eq 1 || "$freenom_list_records" -eq 1 ]]; then
      # (NOTE): on ip update or list_records reverse sort newest first to possibly get a quicker match below
      myDomainsResult=$( echo "$myDomainsResult" | tr ' ' '\n' | sort -r )
    fi
    u=0; i=0
    for u in $myDomainsResult; do
      # DEBUG: for debugging use local file instead:
      # DEBUG: domainDetails=$( curl $c_args -A "$agent" --compressed -k -L -b "$cookie_file" "file:///home/user/src/freenom/domainDetails_$i.bak" )
      domainDetails="$( curl $c_args -A "$agent" --compressed -k -L -b "$cookie_file" "https://my.freenom.com/$u" )"
      domainId[$i]="$( echo "$u" | sed -ne 's/.*id=\([0-9]\+\).*/\1/p;g' )"
      domainName[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Domain:\(.*\)<[a-z].*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g' )"
      if [ "$debug" -ge 1 ]; then echo "DEBUG: myDomains domainId=${domainId[$i]} domainName=${domainName[$i]}" ; fi
      # (NOTE): on ip update or list_records we just need domain name matched and id set
      if [[ "$freenom_update_ip" -eq 1 || "$freenom_list_records" -eq 1 ]]; then
        if [ "${domainName[$i]}" == "$freenom_domain_name" ]; then
          freenom_domain_id="${domainId[$i]}"
          if [ "$debug" -ge 1 ]; then
             echo "DEBUG: myDomainsPage match: \"${domainName[$i]}\" = \"$freenom_domain_name\""
          fi
          break
        fi
      # (NOTE): for renewals we need to get expiry date
      elif [[ "$freenom_renew_domain" -eq 1 || "$freenom_list" -eq 1 || "$freenom_list_renewals" -eq 1 ]]; then
        domainRegDate[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Registration Date:\(.*\)<.*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g' )"
        domainExpiryDate[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Expiry date:\(.*\)<.*/\1/p' | sed 's/<[^>]\+>//g' )"
        if [ "$debug" -ge 1 ]; then echo "DEBUG: myDomains domainRegDate=${domainRegDate[$i]} domainExpiryDate=${domainExpiryDate[$i]}"; fi
      fi
      i=$((i+1))
    done
  fi
else
  # (NOTE): if we already have domain_id and name: copy to domainId and Name array, for renewals also get expiry date
  domainId[0]="${freenom_domain_id}"
  domainName[0]="${freenom_domain_name}"
  if [[ "$freenom_renew_all" -eq 0 && "$freenom_renew_domain" -eq 1 ]]; then
    domainDetails="$( curl $c_args -A "$agent" --compressed -k -L -b "$cookie_file" "https://my.freenom.com/clientarea.php?action=domaindetails&id=${freenom_domain_id}" )"
    domainExpiryDate[0]="$( echo -e "$domainDetails" | sed -n 's/.*Expiry date:\(.*\)<.*/\1/p' | sed 's/<[^>]\+>//g' )"
  fi
fi

# update_ip, renew_domain or list_records get domain_id if its empty
# also show error msg and exit if id or name is missing (e.g. wrong name as arg)
if [[ "$freenom_renew_domain" -eq 1 && "$freenom_domain_id" ]] ||
   [[ "$freenom_update_ip" -eq 1 && "$freenom_domain_id" == "" ]] ||
   [[ "$freenom_list_records" -eq 1 && "$freenom_domain_id" == "" ]]
then
  for ((i=0; i < ${#domainName[@]}; i++)); do
    if [ "$debug" -ge 1 ]; then echo "DEBUG: domainName i=$i ${domainName[$i]}"; fi
    if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then
      freenom_domain_id="${domainId[$i]}"
      if [ "$debug" -ge 1 ]; then
        echo "DEBUG: domainName match: freenom_domain_name=$freenom_domain_name ${domainName[$i]} (freenom_domain_id=${domainId[$i]}"
      fi
    fi
  done
  uMsg="Try \"$scriptName [-u|-r|-z] [domain] [id]\""
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

# get dnsManagementPage on update_ip or list_records
if [[ "$freenom_update_ip" -eq 1 || "$freenom_list_records" -eq 1 ]]; then
  dnsManagementURL="https://my.freenom.com/clientarea.php?managedns=$freenom_domain_name&domainid=$freenom_domain_id"
  dnsManagementPage="$(curl $c_args -A "$agent" --compressed -k -L -b "$cookie_file" "$dnsManagementURL")"
fi

# Function getRec: get domain records from dnsManagementPage
#          v1 = recnum, v2 = type|name|ttl|value, v3 = recname/value(ip)
#          set dnUC and sdLC to UPPERCASE (sub)domain
#          set v3 to dnUC if 'name' if its empty
func_getRec() {
  IFS_SAV=$IFS; IFS=$'\n'
  dnUC="$( echo "$freenom_domain_name" | tr '[:lower:]' '[:upper:]' )"
  sdUC="$(echo "$freenom_subdomain_name" | tr '[:lower:]' '[:upper:]')"
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

# call getRec function to list records
if [ "$freenom_list_records" -eq 1 ]; then
  func_getRec
  printf "\nDNS Zone: \"%s\" (%s)\n\n" "$freenom_domain_name" "$freenom_domain_id"
  if [ "${#recType[@]}" -gt 0 ]; then
    for ((i=0; i < ${#recType[@]}; i++)); do
      if [ "$debug" -ge 3 ]; then
        echo "DEBUG: func_getRec i=$i recType=${recType[$i]} recName=${recName[$i]} recTTL=${recTTL[$i]} recValue=${recValue[$i]}"
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
        if [ "$freenom_list_bind" -eq "1" ]; then
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

# update ip: if record does not exist add new record else update record
#      note: recName is not used in actual dns record
if [ "$freenom_update_ip" -eq 1 ]; then
  recMatch="0"; freenom_update_type="A"
  # make sure it's a ipv4 or ipv6 address
  if [[ -n "$freenom_update_ipv" && "$freenom_update_ipv" -eq 4 ]]; then freenom_update_type="A"
    elif [[ -n "$freenom_update_ipv" && "$freenom_update_ipv" -eq 6 ]]; then freenom_update_type="AAAA"
    elif [[ "$current_ip" =~ ^(([0-9]{1,3}\.){1}([0-9]{1,3}\.){2}[0-9]{1,3})$ ]]; then freenom_update_type="A"
    elif [[ "$current_ip" =~ ^[0-9a-fA-F]{1,4}: ]]; then freenom_update_type="AAAA"
  fi
  # if theres no recored at all: 'add'
  if [ "$(echo "$dnsManagementPage" | grep -F "records[0]")" == "" ]; then
    recordKey="addrecord[0]"
    dnsAction="add"
  else
    func_getRec
    for ((i=0; i < ${#recType[@]}; i++)); do
      if [ "$debug" -ge 1 ]; then
        echo "DEBUG: func_getRec i=$i recType=${recType[$i]} recName=${recName[$i]} recTTL=${recTTL[$i]} recValue=${recValue[$i]}"
      fi
      # make sure its the same recType (ipv4 or 6)
      if [ "${recType[$i]}" == "$freenom_update_type" ]; then
        # if domain name, or subdomain name already exists 'modify' instead of 'add'
        if [ "${recName[$i]}" != "" ]; then
          if [ "${recName[$i]}" == "$sdUC" ] ||
             [[ "${recName[$i]}" == "$dnUC" && "$freenom_subdomain_name" == "" ]]
          then
            if [ "$debug" -ge 1 ]; then
              echo "DEBUG: func_getRec i=$i type/domain match: recType=${recType[$i]} recName=${recName[$i]} dnUC=$dnUC *OR* sdUC=$sdUC"
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
  if [ "$dnsAction" != "modify" ]; then
    recordKey="addrecord[${#recType[@]}]"
    dnsAction="add"
  fi
  if [ "$recMatch" -eq 0 ]; then recName=(); fi
  if [ "$debug" -ge 1 ]; then
    echo "DEBUG: update_ip i=$i recMatch=$recMatch recordKey=$recordKey dnsAction=$dnsAction"
    echo "DEBUG: update_ip recType=${recType[$i]} recName=${recName[$i]} recTTL=${recTTL[$i]} recValue=${recValue[$i]} (empty on add)"
    echo "DEBUG: update_ip freenom_update_type=$freenom_update_type name=$freenom_subdomain_name ttyl=$freenom_update_ttl value=$current_ip"
  fi
  # add/update dns record, if subdom is empty then 'name' is also, which equals apex domain
  updateResult=$(curl $c_args -A "$agent" -e 'https://my.freenom.com/clientarea.php' --compressed -k -L -b "$cookie_file" \
      -F "dnsaction=$dnsAction" \
      -F "${recordKey}[line]=" \
      -F "${recordKey}[type]=${freenom_update_type}" \
      -F "${recordKey}[name]=${freenom_subdomain_name}" \
      -F "${recordKey}[ttl]=${freenom_update_ttl}" \
      -F "${recordKey}[value]=${current_ip}" \
      -F "token=$token" \
      "$dnsManagementURL" 2>&1)
fi

# NOTE: freenom_domain_id   -> domainId
#       freenom_domain_name -> domainName

# list all domains and id's, list renewals
if [ "$freenom_list" -eq 1 ]; then
  if [ "$freenom_list_renewals" -eq 1 ]; then
    domainRenewalsURL="https://my.freenom.com/domains.php?a=renewals&itemlimit=all&token=$token"
    domainRenewalsPage="$(curl $c_args -A "$agent" --compressed -k -L -b "$cookie_file" "$domainRenewalsURL")"
    if [ "$domainRenewalsPage" ]; then
      domainRenewalsResult="$( echo -e "$domainRenewalsPage" | \
         sed -n '/<table/,/<\/table>/{//d;p;}' | \
         sed '/Domain/,/<\/thead>/{//d;}' | \
         sed 's/<.*domain=\([0-9]\+\)".*>/ domain_id: \1\n/g' | \
         sed -e 's/<[^>]\+>/ /g' -e 's/\(  \|\t\)\+/ /g' -e '/^[ \t]\+/d' )"
    fi
  fi
  for ((i=0; i < ${#domainName[@]}; i++)); do
    #if [ "$freenom_list_renewals" -eq 0 ]; then
    #  echo "$l"
    #else
    #  if [ ! "$renewalDetails" ]; then renewalDetails="N/A"; fi
    #  echo "$l | Renewal details: \"$renewalDetails\""
    #fi
    if [ "$freenom_list_renewals" -eq 1 ]; then
      if [ "$domainRenewalsResult" ]; then
        renewalMatch=$( echo "$domainRenewalsResult" | sed 's///g' | sed ':a;N;$!ba;s/\n //g' | grep "domain_id: ${domainId[$i]}" )
        if echo "$renewalMatch" | grep -q Minimum; then
          renewalDetails="$( echo "$renewalMatch" | sed 's/.* \([0-9]\+ Days\) * \(Minimum.*\) * domain_id:.*/\1 Until Expiry, \2/g' )"
        elif echo "$renewalMatch" | grep -q Renewable; then
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

###############################################################################
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
###############################################################################

# Function renewDate: check date to make sure we can renew
func_renewDate() {
  expiryDay=""; expiryMonth=""; expiryYear=""; renewDateOkay=""
  # example: "01/03/2018"
  IFS="/" read -a a -r <<< "${domainExpiryDate[$1]}"; expiryDay="${a[0]}"; expiryMonth="${a[1]}"; expiryYear="${a[2]}"
  if [[ "$expiryDay" != "" && "$expiryMonth" != ""&& "$expiryYear" != "" ]]; then
    if [ "$debug" -ge 1 ]; then echo "DEBUG: domainExpiryDate array: ${domainExpiryDate[$1]}"; fi
    expiryDate="$( date -d "${expiryYear}-${expiryMonth}-${expiryDay}" +%F )"
    renewDate="$( date -d "$expiryDate - 14Days" +%F )"
    currentEpoch="$( date +%s )"
    renewEpoch="$( date -d "$renewDate" +%s )"
    if [ "$debug" -ge 1 ]; then
      echo "DEBUG: func_renewDate expiryDate=$expiryDate renewDate=$renewDate"
      echo "DEBUG: func_renewDate renewEpoch=$renewEpoch currentEpoch=$currentEpoch"
    fi
    if [ "$debug" -ge 2 ]; then
      echo "TEST: func_renewDate listing full expiry date array:"
      for ((j=0; j<${#a[@]}; j++)); do echo "DEBUG: func_renewDate i=${i} ${a[$j]}"; done
    fi
    # TEST: example - set a date after renewDate
    #       currentEpoch="$( date -d "2099-01-01" +%s )"
    if [ "$currentEpoch" -ge "$renewEpoch" ]; then
      renewDateOkay="1"
    else
      noticeCount="$((noticeCount+1))"
      renewNotice="${renewNotice}\n  Cannot renew ${domainName[$1]} (${domainId[$1]}) until $renewDate"
      if [ "$debug" -ge 1 ]; then
        echo -e "DEBUG: func_renewDate domainName=${domainName[$1]} (Id=${domainId[$1]}) - cannot renew until Date=$renewDate"
      fi
    fi
  else
    errCount="$((errCount+1))"
    renewError="${renewError}\n  No expiry date for \"${domainName[$1]}\" (${domainId[$1]})"
    if [ "$debug" -ge 1 ]; then
      echo "DEBUG: renewDate domainName=\"${domainName[$1]}\" (Id=${domainId[$1]}) (i=$i) - no expiry date"
    fi
  fi
}

# Function renewDomain: if date is ok, submit actual renewal and get result
func_renewDomain() {
  if [ "$renewDateOkay" ]; then
    # use domain_id domain_name
    freenom_domain_id="${domainId[$1]} $freenom_domain_id"
    freenom_domain_name="${domainName[$1]} $freenom_domain_name"
    if [ "$debug" -ge 1 ]; then echo "DEBUG: func_renewDomain freenom_domain_name=$freenom_domain_name - curdate>expirydate = possible to renew"; fi
    renewDomainURL="https://my.freenom.com/domains.php?a=renewdomain&domain=${domainId[$1]}&token=$token"
    renewDomainPage="$(curl $c_args -A "$agent" --compressed -k -L -b "$cookie_file" "$renewDomainURL")"

    # NOTE: EXAMPLE
    # url:       https://my.freenom.com/domains.php?submitrenewals=true
    # form data: 7ad1a728a6d8a96d1a8d66e63e8a698ea278986e renewalid:1234567890 renewalperiod[1234567890]:12M paymentmethod:credit

    if [ "$renewDomainPage" ]; then
      echo "$renewDomainPage" > "renewDomainPage_${domainId[$1]}.html"
      if [ "$debug" -ge 1 ]; then echo "DEBUG: renewDomainPage - OK renewDomainURL=$renewDomainURL"; fi
      renewalPeriod="$( echo "$renewDomainPage" | sed -n 's/.*option value="\(.*\)\".*FREE.*/\1/p' | sort -n | tail -1 )"
      # if [ "$renewalPeriod" == "" ]; then renewalPeriod="12M"; fi
      if [ "$renewalPeriod" ]; then
        renewalURL="https://my.freenom.com/domains.php?submitrenewals=true"
        renewalResult="$(curl $c_args -A "$agent" --compressed -k -L -b "$cookie_file" \
        -F "token=$token" \
        -F "renewalid=${domainId[$1]}" \
        -F "renewalperiod[${domainId[$1]}]=$renewalPeriod" \
        -F "paymentmethod=credit" \
        "$renewalURL" 2>&1)"
        # write renewal result html file, count errors and set error messages per domain
        if [ "$renewalResult" ] ; then
          echo -e "$renewalResult" > "${out_path}.renewalResult_${domainId[$1]}.html"
          renewOkay="$renewOkay\n  Successfully renewed domain \"${domainName[$1]}\" (${domainId[$1]}) - ${renewalPeriod}"
        else
          errCount="$((errCount+1))"
          renewError="$renewError\n  Renewal failed for \"${domainName[$1]}\" (${domainId[$1]})"
        fi
      else
        errCount="$((errCount+1))"
        renewError="$renewError\n  Cannot renew \"${domainName[$1]}\" (${domainId[$1]}), renewal period not found"
      fi
    else
      errCount="$((errCount+1))"
    fi
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
      echo "DEBUG: renew_all i=$i domainName=${domainName[$i]}"
      func_renewDate "$i"
      func_renewDomain "$i"
    else
      if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then
        if [ "$debug" -ge 1 ]; then
          echo "DEBUG: renew_domain i=$i match: freenom_domain_name=$freenom_domain_name domainName=${domainName[$i]}"
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
# DEBUG: comment line below for debugging
curl $c_args -A "$agent" --compressed -k -b "$cookie_file" "https://my.freenom.com/logout.php" > /dev/null 2>&1
rm -f "$cookie_file"

###########
# Logging #
###########

# on error write update result to html file, handle error count and error messages
if [ "$freenom_update_ip" -eq 1 ]; then
  if [ "$(echo -e "$updateResult" | grep "$current_ip")" == "" ]; then
    echo "[$(date)] Update failed: \"${freenom_domain_name}\" (${freenom_domain_id}) - ${current_ip}" >> "${out_path}.log"
    echo -e "$updateResult" > "${out_path}.errorUpdateResult_${freenom_domain_id}.html"
    errCount="$((errCount+1))"
  else
    # save ip address to lock and log file, del html file success
    sMsg=""
    echo -n "$current_ip" > "${out_path}.ip${freenom_update_ipv}_${freenom_domain_name}.lock"
    if [ -n "$freenom_subdomain_name" ]; then sMsg="${freenom_subdomain_name}."; fi
    echo "[$(date)] Update successful: \"${sMsg}${freenom_domain_name}\" (${freenom_domain_id}) - ${current_ip}" >> "${out_path}.log"
    if [[ -n ${out_path} && -n ${freenom_domain_id} ]]; then
      if [ -e "${out_path}.errorUpdateResult_${freenom_domain_id}.html" ]; then
        rm -f "${out_path}.errorUpdateResult_${freenom_domain_id}.html"
      fi
    fi
  fi
fi

# write renewal results to logfile, count errors, warnings and set messages
if [ "$freenom_renew_domain" -eq 1 ]; then
  if [ "$renewOkay" ]; then
    echo -e "[$(date)] Domain renewal successful: $renewOkay" >> "${out_path}.log"
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
