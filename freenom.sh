#!/bin/bash

###############################################################################
# Domain Renewal and Dynamic DNS shell script for freenom.com                 #
###############################################################################
#                                                                             #
# Updates IP address and/or auto renews domain(s) so they do not expire       #
# See README.md for more information                                          #
#                                                               v2019-04-20   #
###############################################################################


########
# Main # 
########

scriptName="$(basename "$0")"

# Check if freenom.conf file exist, source if it does
if [ -z $scriptConf ]; then
  scriptConf="$(dirname "$0")/$(basename -s '.sh' "$0").conf"
fi
if [ -s "$scriptConf" ]; then
  source "$scriptConf" || { echo "Error: could not load $scriptConf"; exit 1; }
else
  scriptConf="$scriptName"
fi
if [ "$debug" -eq 1 ]; then echo "DEBUG: conf scriptConf=$scriptConf"; fi

# Function help
func_help () {
  cat <<-_EOF_

USAGE:

$scriptName [-l][-r][-u|-z <domain>][-s <subdomain>] [-d|-a] [-c <file>][-e][-o]

OPTIONS:    -l    List domains with id's
                  add [-d] to show renewal Details 
            -r    Renew domain
                  add [-a] to renew All domains
            -u    Update <domain> a-record with current ip
                  add [-s] to update <Subdomain>
            -z    Zone output listing dns records

            -c    Config <file> location
            -e    Error output from update result
            -o    Output from renewal result

EXAMPLES:   ./$scriptName -l -d
            ./$scriptName -r example.com
            ./$scriptName -r -a
            ./$scriptName -u example.com -s mail

NOTES:      Using [-u] or [-r] and specifying <domain> as argument
            overrides any settings in script or config file

_EOF_
  exit 0
}

# Function getDomArgs: get domain name, id (digits only) and subdomain
func_getDomArgs () {
  if [[ "$freenom_list_records" -eq 1 || "$freenom_renew_domain" -eq 1 ]]; then
    if [ "$2" != "" ]; then freenom_domain_name="$2"; fi
  fi
  if [ "$freenom_renew_domain" -eq 1 ]; then
    if echo "$3" | grep "^[0-9]\+$"; then
      freenom_domain_id="$3"
    else
      freenom_domain_id=""
    fi
  else
    if echo "$4" | grep -q "^[0-9]\+$"; then
      freenom_domain_id="$4"
      if echo -- "$@" | grep -qi -- '\-s'; then freenom_subdomain_name="$6"; fi
    elif echo "$3" | grep -q "^[0-9]\+$"; then
      freenom_domain_id="$3"
      if echo -- "$@" | grep -qi -- '\-s'; then freenom_subdomain_name="$5"; fi
    else
      if [ "$freenom_list_records" -eq 1 ]; then
        freenom_subdomain_name="$4"
      else
        #freenom_domain_id=""
        if echo -- "$@" | grep -qi -- '\-s'; then freenom_subdomain_name="$4"; fi
      fi
    fi
  fi
}

# Function showResult: format html and output as text
func_showResult () {
  lsFile="$( ls -l "$1" | cut -d' ' -f 6- )"
  printf "\n%s :\n\n" "$lsFile"
  for i in lynx links links2 wb3m elinks curl cat; do
    if which $i >/dev/null 2>&1; then
      break
    fi
  done
  case $i in
    lynx|links|links2|w3m|elinks)
      [ $i = "lynx" ] && args="-nolist"
      [ $i = "elinks" ] && args="-no-numbering -no-references"
      $i -dump $args "$1" | sed '/ \([*+□•] \?.\+\|\[.*\]\)/d'
    ;;
    curl|cat)
      [ $i = "curl" ] && args="-s file:///"
      $i ${args}"${1}" | \
        sed -e '/<a href.*>/d' -e '/<style type="text\/css">/,/</d' -e '/class="lang-/d' \
            -e 's/<[^>]\+>//g' -e '/[;}{):,>]$/d' -e '//d' -e 's/\t//g' -e '/^ \{2,\}$/d' -e '/^$/d'
    ;;
    *)
      echo "Error: Cannot display \"$1\""
      exit 1
    ;;
  esac
}

# handle arguments

# set config file
if echo "$@" | grep -qi '\-c'; then
  if [ -s $2 ]; then
    scriptConf="$1"
    source $scriptConf
  else
    echo "Error: invalid config specified"
  fi
fi

# help
if echo -- "$@" | grep -qi '\-h'; then
  func_help
  exit 0
fi
if ! echo -- "$1" | grep -qi '\-'; then
  func_help
  exit 1
fi

# list domains and id's, exit (unless list_records is set)
if echo -- "$@" | grep -qi -- '\-l'; then
  freenom_list="1"
  lMsg=""
  # list domains with details
  if echo -- "$@" | grep -Eqi -- '\-d|\-n'; then
    freenom_list_renewals="1"
    lMsg=" with renewal details, this might take a while"
  fi
  printf "\nListing Domains and ID's%s...\n" "$lMsg"
  echo
# list dns records
elif echo -- "$@" | grep -qi -- '\-z'; then
  freenom_list_records="1"
  func_getDomArgs "$@"
# update ip
elif echo -- "$@" | grep -qi -- '\-u'; then
  freenom_update_ip="1"
  func_getDomArgs "$@"
  echo -e "[$(date)] Start - Update ip" >> "${out_path}.log"
# renew domains
elif echo -- "$@" | grep -qi -- '\-r'; then
  freenom_renew_domain="1"
  if echo -- "$@" | grep -qi -- '\-a'; then
    freenom_renew_all="1"
  fi
  echo -e "[$(date)] Start - Domain renewal" >> "${out_path}.log"
# error output update result
elif echo -- "$@" | grep -qi -- '\-e'; then
  if [ -s "${out_path}.errorUpdateResult.html" ]; then
    func_showResult "${out_path}.errorUpdateResult.html"
  else
    echo "File \"${out_path}.errorUpdateResult.html\" not found"
  fi
  exit 0
# output renewal result
elif echo -- "$@" | grep -qi -- '\-o'; then
    i=0
    for r in ${out_path}.renewalResult_*.html; do
      if [ -s "$r" ]; then
        func_showResult "$r"
        i=$((i+1))
      fi
    done
    if [ "$i" -eq 0 ]; then
      echo "Renewal result file not found"
    fi
    exit 0
else
  func_help
fi

if [ "$debug" -eq 1 ]; then
  echo "DEBUG: args 1=$1 2=$2 3=$3 4=$4 5=$5  6=$6"
  echo "DEBUG: args freenom_domain_name=$freenom_domain_name freenom_domain_id=$freenom_domain_id freenom_subdomain_name=$freenom_subdomain_name"
  echo "DEBUG: action freenom_update_ip=$freenom_update_ip freenom_update_force=$freenom_update_force freenom_list_records=$freenom_list_records"
  echo "DEBUG: action freenom_list=$freenom_list freenom_list_renewals=$freenom_list_renewals"
  echo "DEBUG: action freenom_renew_domain=$freenom_renew_domain freenom_renew_all=$freenom_renew_all"
fi

#echo DEBUG: args exit
#exit

# generate "random" useragent string
agentStr[0]="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Safari/537.36"
agentStr[1]="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:59.0) Gecko/20100101 Firefox/59.0"
agentStr[2]="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2486.0 Safari/537.36 Edge/13.10586,gzip(gfe)"
agentStr[3]="Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.87 Safari/537.36"
agentStr[4]="Mozilla/5.0 (IE 11.0; Windows NT 6.3; Trident/7.0; .NET4.0E; .NET4.0C; rv:11.0) like Gecko"
agentStr[5]="Mozilla/5.0 (X11; Linux x86_64; rv:55.0) Gecko/20100101 Firefox/55.0"
agentStr[6]="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Safari/537.36"
agentStr[7]="Mozilla/5.0 (Android 4.4; Mobile; rv:41.0) Gecko/41.0 Firefox/41.0"
agent="${agentStr[$((RANDOM%${#agentStr[@]}))]}"

# optional curl args (e.g. -s silent or -v verbose -o /dev/null etc)
# comment line to disable
args="-s"
#args="-s -I -L -v -o /dev/null"

warnCount="0"; errCount="0"

# get current ip using dig or curl
if [ "$freenom_update_ip" -eq 1 ]; then
  getIp[0]="curl -A $agent -${freenom_update_ipv} -m 10 -s https://checkip.amazonaws.com"
  getIp[1]="curl -A $agent -${freenom_update_ipv} -m 10 -s https://diagnostic.opendns.com/myip"
  getIp[2]="curl -A $agent -${freenom_update_ipv} -m 10 -s https://www.ripe.net/@@ipaddress"
    if [ "$freenom_update_dig" -eq 1 ]; then
    getIp[3]="dig -${freenom_update_ipv} TXT +short o-o.myaddr.l.google.com @ns1.google.com"
      if [ "${freenom_update_ipv}" -eq 4 ]; then
        getIp[4]="dig -4 +short myip.opendns.com @resolver1.opendns.com"
        getIp[5]="dig -4 +short myip.opendns.com @resolver2.opendns.com"
        getIp[6]="dig -4 +short myip.opendns.com @resolver3.opendns.com"
        getIp[7]="dig -4 +short myip.opendns.com @resolver4.opendns.com"
        getIp[8]="dig +short whoami.akamai.net @ns1-1.akamaitech.net"
      fi
    fi
  i=0
  while [[ "$current_ip" == "" && $i -lt "$freenom_update_ip_retry" ]]; do
    current_ip="$(${getIp[$((RANDOM%${#getIp[@]}))]} 2>/dev/null | tr -d '"')"
    if [ "$debug" -eq 1 ]; then echo "DEBUG: getip i=$i current_ip=$current_ip"; fi
    i=$((i+1))
  done
  if [ "$current_ip" == "" ]; then
    eMsg="Could not get current local ip address"
    echo "Error: $eMsg"; echo "[$(date)] $eMsg" >> "${out_path}.log"
    exit 1
  fi
  if [ "$freenom_update_force" -eq 0 ]; then
    if [ "$(cat "${out_path}.ip" 2>/dev/null)" == "$current_ip" ]; then
      if [ "$freenom_update_ip_log" -eq 1 ]; then
        echo "[$(date)] Done - Update skipped, same ip" >> "${out_path}.log"
      else
        echo "[$(date)] Done" >> "${out_path}.log"
      fi
      exit 0
    fi
  fi
fi

# login
cookie_file="$(mktemp)"
# DEBUG: comment line below for debugging
loginPage="$(curl $args -A "$agent" --compressed -k -L -c "$cookie_file" \
    "https://my.freenom.com/clientarea.php" 2>&1)"
#token=$(echo "$loginPage" | grep token | grep -o value=".*" | sed 's/value=//g' | sed 's/"//g' | awk '{print $1}')
token="$(echo "$loginPage" | grep token | head -1 | grep -o value=".*" | sed 's/value=//g' | sed 's/"//g' | awk '{print $1}')"
# DEBUG: comment line below for debugging
loginResult="$(curl $args -A "$agent" -e 'https://my.freenom.com/clientarea.php' -compressed -k -L -c "$cookie_file" \
    -F "username=$freenom_email" -F "password=$freenom_passwd" -F "token=$token" \
    "https://my.freenom.com/dologin.php")"
if [ "$(echo -e "$loginResult" | grep "Location: /clientarea.php?incorrect=true")" != "" ]; then
    echo "[$(date)] Login failed" >> "${out_path}.log"
    rm -f "$cookie_file"
    errCount="$(( errCount+1 ))"
fi

# get details for all domains on update_ip or list_records and id or name is empty OR list OR renew_all
if [ "$freenom_update_ip" -eq 1 ] && [[ "$freenom_domain_id" == "" || "$freenom_domain_name" == "" ]] ||
   [ "$freenom_list_records" -eq 1 ] && [[ "$freenom_domain_id" == "" || "$freenom_domain_name" == "" ]] ||
   [[ "$freenom_list" -eq 1 || "$freenom_renew_all" -eq 1 ]];
then
  myDomainsURL="https://my.freenom.com/clientarea.php?action=domains&itemlimit=all&token=$token"
  # DEBUG: for debugging use local file instead:
  # DEBUG: myDomainsURL="file:///home/user/src/freenom/myDomainsPage"
  myDomainsPage="$(curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "$myDomainsURL")"
  if [ "$myDomainsPage" ]; then
    # myDomainsResult="$( echo -e "$myDomainsPage" | sed -n '/href.*external-link/,/action=domaindetails/p' | sed -ne 's/.*id=\([0-9]\+\).*/\1/p;g' )"
    myDomainsResult="$( echo -e "$myDomainsPage" | sed -ne 's/.*"\(clientarea.php?action=domaindetails&id=[0-9]\+\)".*/\1/p;g' )"
    u=0; i=0
    for u in $myDomainsResult; do
      # DEBUG: for debugging use local file instead:
      # DEBUG: domainDetails=$( curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "file:///home/user/src/freenom/domainDetails_$i.bak" )
      domainDetails="$( curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "https://my.freenom.com/$u" )"
      domainId[$i]="$( echo $u | sed -ne 's/.*id=\([0-9]\+\).*/\1/p;g' )"
      domainName[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Domain:\(.*\)<[a-z].*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g' )"
      if [ "$debug" -eq 1 ]; then echo "DEBUG: myDomainsPage domainId=${domainId[$i]} domainName=${domainName[$i]}" ; fi
      
      # on ip update or list_records we just need domain name
      if [[ "$freenom_update_ip" -eq 1 || "$freenom_list_records" -eq 1 ]]; then 
        if [ "${domainName[$i]}" == "$freenom_domain_name" ]; then
          if [ "$debug" -eq 1 ]; then
            echo "DEBUG: myDomainsPage - found ${domainName[$i]}=$freenom_domain_name"
          fi
          break
        fi
      else
        domainRegDate[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Registration Date:\(.*\)<.*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g' )"
        domainExpiryDate[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Expiry date:\(.*\)<.*/\1/p' | sed 's/<[^>]\+>//g' )"
      fi
      i=$(( i+1 ))
    done  
  fi
fi

# set domain_id if needed, exit if id or name is missing
if [[ "$freenom_list" -eq 0 && "$freenom_renew_all" -eq 0 ]] || [ "$freenom_list_records" -eq 1 ]; then
  if [ "$freenom_domain_id" == "" ]; then
    for ((i=0; i < ${#domainName[@]}; i++)); do
      if [ "$debug" -eq 1 ]; then echo "DEBUG: domainName $i ${domainName[$i]}"; fi
      if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then
        if [ "$debug" -eq 1 ]; then echo "DEBUG: domainName match: freenom_domain_name=$freenom_domain_name ${domainName[$i]}" ; fi
        freenom_domain_id="${domainId[$i]}"
      fi
    done
    tMsg="Try setting \"freenom_domain_name\" in config"
    uMsg="Or use: \"$scriptName [-u|-r|-z] [domain] [id]\""
    sp="       "
    if [ "$freenom_domain_id" == "" ]; then
      [ "$freenom_domain_name" != "" ] && fMsg=" for \"$freenom_domain_name\""
      printf "Error: Could not find Domain ID%s\n%s%s\n%s%s\n" "$fMsg" "$sp" "$tMsg" "$sp" "$uMsg"
      exit 1
    fi
    if [ "$freenom_domain_name" == "" ]; then
      printf "Error: Domain Name missing\n%s\n%s\n" "$fMsg" "$sp" "$tMsg" "$sp" "$uMsg"
      exit 1
    fi
  fi
fi

# get dnsManagementPage on update_ip or list_records
if [[ "$freenom_update_ip" -eq 1 || "$freenom_list_records" -eq 1 ]]; then
  dnsManagementURL="https://my.freenom.com/clientarea.php?managedns=$freenom_domain_name&domainid=$freenom_domain_id"
  dnsManagementPage="$(curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "$dnsManagementURL")"
fi

# Function func_getRec: get domain records from dnsManagementPage
#           $1 = 'raw': unformatted output, 'fmt': format output
func_getRec() {
  IFS_SAV=$IFS; IFS=$'\n'
  foundRecs=0; j=0
  for r in $( echo -e $dnsManagementPage | tr '<' '\n' | 
              sed -r -n 's/.*records\[([0-9]+)\]\[(type|name|ttl|value)\]\" value=\"([0-9A-Z\.-]*)\".*/\1 \2 \3/p;g' ); do
    foundRecs=1
    IFS=" " read -r v1 v2 v3 <<< $r
    if [[ $v2 = "name" && "$v3" = "" ]]; then
      v3="$(echo $freenom_domain_name|tr '[:lower:]' '[:upper:]')"
    fi
    if [[ "$1" == "raw" && "$v2" = "name" ]]; then
      echo $v1 $v3
    elif [ "$1" == "fmt" ]; then
      vars+="$v2: \"$v3\" ";
      if [[ "$v1" != "" && $j -eq 3 ]]; then
        recArray[$v1]="$v1 $vars"
        vars=""; j=-1
      fi
      j="$((j+1))"
    fi
  done
  IFS=$IFS_SAV
}

# call getRec function with arg "fmt" and list records only
if [ "$freenom_list_records" -eq 1 ]; then
  echo
  echo "DNS Zone: \"$freenom_domain_name\" ($freenom_domain_id)"
  echo
  func_getRec fmt
  if [ "$foundRecs" -eq 1 ]; then
    if [ ! -z "$freenom_subdomain_name" ]; then
      for ((i=0; i < ${#recArray[@]}; i++)); do
        recName="$(echo "${recArray[$i]}"|awk '{gsub(/"/,"",$5); print $5}')"
        subDomain="$(echo "$freenom_subdomain_name"|tr '[:lower:]' '[:upper:]')"
        if [ "$recName" == "$subDomain" ]; then
          echo "Subdomain Record: ${recArray[$i]}"
          break
        fi
      done
    else
      for ((i=0; i < ${#recArray[@]}; i++)); do
        echo "Domain Record: ${recArray[$i]}"
      done
    fi
    echo
  else
    echo "No records found"
    echo
  fi
  exit 0
fi

# update ip: if record does not exist add new record else update record
#      note: recName is not used in actual dns record

if [ "$freenom_update_ip" -eq 1 ]; then
  if [ "$(echo "$dnsManagementPage" | grep -F "records[0]")" == "" ]; then
      recordKey="addrecord[0]"
      dnsAction="add"
  else
    IFS_SAV=$IFS; IFS=$'\n'; recMatch=0
    for i in $( func_getRec raw ); do
      recNum="$(echo $i|cut -d' ' -f1)"
      recName="$(echo $i|cut -d' ' -f2)"
      if [ "$debug" -eq 1 ]; then echo "DEBUG: func_getRec raw i=$i recNum=$recNum recName=$recName"; fi
      sd="$(echo $freenom_subdomain_name|tr '[:lower:]' '[:upper:]')"
      if [[ "$recNum" != "" && "$recName" == "$sd" ]]; then
        recordKey="records[$recNum]"
        dnsAction="modify"
        recMatch=1
        break
      fi
    done
    IFS=$IFS_SAV
  fi
  if [ "$dnsAction" != "modify" ]; then
    recordKey="addrecord[$((recNum+1))]"
    dnsAction="add"
  fi
  if [ "$recMatch" -eq 0 ]; then recName=""; fi
  if [ "$debug" -eq 1 ]; then
    echo "DEBUG: update_ip recMatch=$recMatch recNum=$recNum recName=$recName recordKey=$recordKey dnsAction=$dnsAction"
    echo "DEBUG: update_ip name=$freenom_subdomain_name ttyl=$freenom_update_ttl value=$current_ip"
  fi

  # add/update dns record
  # if subdom is empty 'name' is also, which equals apex domain
  updateResult=$(curl $args -A "$agent" -e 'https://my.freenom.com/clientarea.php' --compressed -k -L -b "$cookie_file" \
      -F "dnsaction=$dnsAction" \
      -F "$recordKey[line]=" \
      -F "$recordKey[type]=A" \
      -F "$recordKey[name]=$freenom_subdomain_name" \
      -F "$recordKey[ttl]=$freenom_update_ttl" \
      -F "$recordKey[value]=$current_ip" \
      -F "token=$token" \
      "$dnsManagementURL" 2>&1)
fi

# DEBUG: myDomainsResult
# IFS=$'\n'; for i in $( echo $myDomainsResult ); do
#   echo DEBUG: i=$i; domainResult="$( echo $i | cut -d " " -f2 )"; domainIdResult="$( echo $i | cut -d " " -f4 )"
# done; echo "DEBUG: domainResult: $domainResult domainIdResult: $domainIdResult"

# freenom_domain_id   -> domainId
# freenom_domain_name -> domainName
 
# list all domains and id's, list renewals
if [ "$freenom_list" -eq 1 ]; then
  if [ "$freenom_list_renewals" -eq 1 ]; then
    domainRenewalsURL="https://my.freenom.com/domains.php?a=renewals&itemlimit=all&token=$token"
    domainRenewalsPage="$(curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "$domainRenewalsURL")"
    if [ "$domainRenewalsPage" ]; then
      domainRenewalsResult="$( echo -e "$domainRenewalsPage" | \
         sed -n '/<table/,/<\/table>/{//d;p;}' | \
         sed '/Domain/,/<\/thead>/{//d;}' | \
         sed 's/<.*domain=\([0-9]\+\)".*>/ domain_id: \1\n/g' | \
         sed -e 's/<[^>]\+>/ /g' -e 's/\(  \|\t\)\+/ /g' -e '/^[ \t]\+/d' )"
    fi
  fi
  for ((i=0; i < ${#domainName[@]}; i++)); do
    if [ "$freenom_list" -eq 1 ]; then
      if [ "$domainRenewalsResult" ]; then
        renewalMatch=$( echo "$domainRenewalsResult" | sed 's///g' | sed ':a;N;$!ba;s/\n //g' | grep "domain_id: ${domainId[$i]}" )
        if echo "$renewalMatch" | grep -q Minimum; then
          renewalDetails="$( echo "$renewalMatch" | sed 's/.* \([0-9]\+ Days\) * \(Minimum.*\) * domain_id:.*/\1 Until Expiry, \2/g' )"
        elif echo "$renewalMatch" | grep -q Renewable; then
          renewalDetails="$( echo "$renewalMatch" | sed 's/.* \([0-9]\+ Days\) * \(Renewable\) * domain_id:.*/\2, \1 Until Expiry/g' )"
        fi
      fi
    fi
    #if [ "$freenom_list_renewals" -eq 0 ]; then
    #  echo "$l"
    #else
    #  if [ ! "$renewalDetails" ]; then renewalDetails="N/A"; fi
    #  echo "$l | Renewal details: \"$renewalDetails\""
    #fi
    if [ "$freenom_list_renewals" -eq 1 ]; then
      if [ ! "$renewalDetails" ]; then renewalDetails="N/A"; fi
      showRenewal="$( printf "\n%4s Renewal details: %s" " " "$renewalDetails" )"
    fi
    printf "[%02d] Domain: \"%s\" Id: \"%s\" RegDate: \"%s\" ExpiryDate: \"%s\"%s\n" \
      "$((i+1))" "${domainName[$i]}" "${domainId[$i]}" "${domainRegDate[$i]}" "${domainExpiryDate[$i]}" "$showRenewal"
  done
  echo
  exit 0
fi

###############################################################################
# How to handle Renewals:
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

# Function renewDate: check date to make sure we can renew
func_renewDate() {
  expiryDay=""; expiryMonth=""; expiryYear=""; renewDateOK=""
  # example: "01/03/2018"
  IFS="/" read -a a <<< "$1"; expiryDay="${a[0]}"; expiryMonth="${a[1]}"; expiryYear="${a[2]}"
  expiryDate="$( date -d "${expiryYear}-${expiryMonth}-${expiryDay}" +%F )" 
  renewDate="$( date -d "$expiryDate - 14Days" +%F )"
  curEpoch="$( date +%s )"
  renewEpoch="$( date -d "$renewDate" +%s )"
  if [ "$debug" -eq 1 ]; then
    echo "DEBUG: func_renewDate expiryDate=$expiryDate renewDate=$renewDate" # expiryEpoch=$expiryEpoch
    echo "DEBUG: func_renewDate renewEpoch=$renewEpoch curEpoch=$curEpoch"
  fi
  if [ "$debug" -eq 2 ]; then
    echo "DEBUG: func_renewDate Test - listing full expiry date array:"
    for ((j=0; j<${#a[@]}; j++)); do echo "DEBUG: func_renewDate i=${i} ${a[$j]}"; done
  fi
  # TEST: set a date after renewDate example
  #       curEpoch="$( date -d "2018-03-18" +%s )"
  if [ "$curEpoch" -ge "$renewEpoch" ]; then
    renewDateOK="1"
  else
    warnCount="$(( warnCount+1 ))"
    renewWarn="$renewWarn\n  Cannot renew ${domainName[$i]} (${domainId[$i]}) until $renewDate"
    if [ "$debug" -eq 1 ]; then
      echo -e "DEBUG: func_renewDate cannot renew domain Name=${domainName[$i]} Id=${domainId[$i]} until Date=$renewDate"
    fi
  fi
}

# Function renewDomain: if date is ok, submit actual renewal and get result
func_renewDomain() {
  if [ "$renewDateOK" ]; then
    # use domain_id domain_name
    freenom_domain_id="${domainId[$i]} $freenom_domain_id"
    freenom_domain_name="${domainName[$i]} $freenom_domain_name"
    if [ "$debug" -eq 1 ]; then echo "DEBUG: func_renewDomain freenom_domain_name=$freenom_domain_name - curdate ge expirydate: possible to renew"; fi
    renewDomainURL="https://my.freenom.com/domains.php?a=renewdomain&domain=${domainId[$i]}&token=$token"
    renewDomainPage="$(curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "$renewDomainURL")"

    # EXAMPLE
    # url:       https://my.freenom.com/domains.php?submitrenewals=true
    # form data: 7ad1a728a6d8a96d1a8d66e63e8a698ea278986e renewalid:1234567890 renewalperiod[1234567890]:12M paymentmethod:credit

    if [ "$renewDomainPage" ]; then
      echo "$renewDomainPage" > "renewDomainPage_${domainId[$i]}.html"
      if [ "$debug" -eq 1 ]; then echo "DEBUG: renewDomainPage - OK renewDomainURL=$renewDomainURL"; fi
      renewalPeriod="$( echo "$renewDomainPage" | sed -n 's/.*option value="\(.*\)\".*FREE.*/\1/p' | sort -n | tail -1 )"
      # if [ "$renewalPeriod" == "" ]; then renewalPeriod="12M"; fi
      if [ "$renewalPeriod" ]; then
        renewalURL="https://my.freenom.com/domains.php?submitrenewals=true"
        renewalResult="$(curl $args -A "$agent" --compressed -k -L -b "$cookie_file" \
        -F "token=$token" \
        -F "renewalid=${domainId[$i]}" \
        -F "renewalperiod[${domainId[$i]}]=$renewalPeriod" \
        -F "paymentmethod=credit" \
        "$renewalURL" 2>&1)"
        if [ "$renewalResult" ] ; then
          echo -e "$renewalResult" > "${out_path}.renewalResult_${domainId[$i]}.html"
          renewOK="$renewOK\n  Successfully renewed domain ${domainName[$i]} (${domainId[$i]} ${renewalPeriod})"
        else
          errCount="$(( errCount+1 ))"
          renewError="$renewError\n  Renewal failed for ${domainName[$i]} (${domainId[$i]})"
        fi
      else
        errCount="$(( errCount+1 ))"
        renewError="$renewError\n  Cannot renew ${domainName[$i]} (${domainId[$i]}), renewal period not found"
      fi
    else
      errCount="$(( errCount+1 ))"
    fi
  fi
}

# call domain renewal functions for 1 or all domains
if [ "$freenom_renew_domain" -eq 1 ]; then
  if [ "$freenom_renew_all" -eq 1 ]; then
    for ((i=0; i < ${#domainName[@]}; i++)); do
      if [ "$debug" -eq 1 ]; then echo "DEBUG: renew_all i=$i ${#domainName[@]} domainId=${domainId[$i]} domainName=${domainName[$i]}"; fi
      func_renewDate "${domainExpiryDate[$i]}"
      func_renewDomain
    done
  else
    for ((i=0; i < ${#domainName[@]}; i++)); do
      if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then
        func_renewDate "${domainExpiryDate[$i]}"
        func_renewDomain
      fi
    done
  fi
fi

# logout and clean up

# DEBUG: comment line below for debugging
curl $args -A "$agent" --compressed -k -b "$cookie_file" "https://my.freenom.com/logout.php" > /dev/null 2>&1
rm -f "$cookie_file"

# write html result on error
if [ "$freenom_update_ip" -eq 1 ]; then
  if [ "$(echo -e "$updateResult" | grep "$current_ip")" == "" ]; then
      echo "[$(date)] Update failed (${freenom_domain_name} ${freenom_domain_id})" >> "${out_path}.log"
      echo -e "$updateResult" > "${out_path}.errorUpdateResult.html"
      errCount="$(( errCount+1 ))"
  else
      # save ip address to file and log
      sMsg="";
      echo -n "$current_ip" > "${out_path}.ip"
      if [ ! -z "$freenom_subdomain_name" ]; then sMsg="${freenom_subdomain_name}."; fi
      echo "[$(date)] Update ip successful: ${sMsg}${freenom_domain_name} (${freenom_domain_id}) - ${current_ip}" >> "${out_path}.log"
  fi
fi

# write renewal results to logfile
if [ "$freenom_renew_domain" -eq 1 ]; then
  if [ "$renewOK" ]; then
    echo -e "[$(date)] Domain renewal successful: $renewOK" >> "${out_path}.log"
  fi
  if [ "$freenom_renew_log" -eq 1 ]; then
    if [ "$warnCount" -gt 0 ]; then
      if [ ! -z "$renewWarn" ]; then
        echo -e "[$(date)] These domain(s) were not renewed - reason: ${renewWarn}" >> "${out_path}.log"
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
    echo -e "[$(date)] These domain(s) failed to renew - reason: ${renewError}" >> "${out_path}.log"
  fi
  if [ "$warnCount" -gt 0 ] && [ "$errCount" -gt 0 ]; then
    echo "[$(date)] Successfully renewed domain $freenom_domain_name (${freenom_domain_id/% /})" >> "${out_path}.log"
  fi
fi

# log any warnings and/or errors and exit with exitcode
addLogMsg=""
echo -n "[$(date)] Done" >> "${out_path}.log"
if [ "$warnCount" -gt 0 ]; then
  addLogMsg=" - $warnCount warnings"
fi
if [ "$errCount" -gt 0 ]; then
  addLogMsg+=" - $errCount errors"
fi
echo "$addLogMsg" >> "${out_path}.log"
if [ "$errCount" -gt 0 ]; then
  exit 1
else
  exit 0
fi
