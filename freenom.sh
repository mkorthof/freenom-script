#!/bin/bash

###############################################################################
#                                                                             #
# Domain Renewal and Dynamic DNS support shell script for freenom.com         #
# Updates IP address and/or auto renews domain(s) so they do not expire       #
#                                                                             #
# Sources:  https://github.com/dabendan2/freenom-dns                          #
#           https://gist.github.com/a-c-t-i-n-i-u-m/bc4b1ff265b277dbf195      #
#           https://gist.github.com/pgaulon/3a844a626458f56903d88c5bb1463cc6  #
#           https://github.com/patrikx3/freenom                               #
#                                                                             #
# Changes:  - added referer url to curl to fix loginA                         #
#           - fixed token                                                     #
#           - made updating ip optional                                       #
#           - added domain renewals                                           #
#                                                               v2019-02-22   #
###############################################################################

############
# Settings #
############

# Login data
# Set variables for email/passwords (or source a "secrets" file)

# Examples:
#   freenom_email="main@address"
#   freenom_passwd="pswd"
#   source "/home/${LOGNAME}/.secret/.freenom"

freenom_email="you@example.com"
freenom_passwd="yourpassword"

# The following is not needed anymore and can be skipped as we get domain_id's automatically now
# NOTE: There is a "hidden" option to specificy domain_id's as 3rd argument if you need it
#   Open DNS management page in your browser, URL vs settings:
#   https://my.freenom.com/clientarea.php?managedns={freenom_domain_name}&domainid={freenom_domain_id}
#   freenom_domain_name="domain.name"
#   freenom_subdomain_name=""
#   freenom_domain_id="000000000"

# Use ipv4 or ipv6: [4/6]

freenom_update_ipver="4"

# Output files

# Set path, 'basename' can be used for same filename as current script
# Set freenom_update_ip_logall="0" to disable "ip unchanged" log messages
# Path and files:
# - /dir/to/freenom.log
# - /dir/to/freenom.ip
# - /dir/to/freenom.errorUpdateResult.html

# Examples:
#   - tmpdir  : out_path="/tmp/$(basename $0)"
#   - current : out_path="$(basename -s '.sh' "$0")"

out_path="/var/log/$(basename -s '.sh' "$0")"

# Optional overrides (ok to leave these as-is)

freenom_update_ip="0"
freenom_update_ip_logall="1"
freenom_list="0"
freenom_list_renewals="0"
freenom_renew_domain="0"
freenom_renew_all="0"

debug=0

##############
# CONFIG END #
##############


########
# Main # 
########

# help and handle arguments
if echo "$*" | grep -qi '\-h'; then
cat <<-_EOF_

USAGE: $0 [-l|-u|-r] [-d|-a] [domain] [-s <subdomain>]

OPTIONS:  -l    List domains with id's
                add [-d] to show renewal Details 
          -u    Update <domain> a-record with current ip
                add [-s] to update <Subdomain>
          -r    Renew domain(s), add [-a] for All domains

EXAMPLE:  ./$(basename "$0") -u example.com -s mail
          ./$(basename "$0") -r example.com
          ./$(basename "$0") -r -a

NOTE:     Using -u or -r and specifying "domain" as argument
          overrides setting in "$(basename "$0")"

_EOF_
exit 0
elif echo -- "$@" | grep -qi -- '\-l'; then
  freenom_list="1"
  echo
  echo -n "Listing Domains and ID's"
  if echo -- "$@" | grep -Eqi -- '\-d|\-n'; then
    echo -n " with renewal details, this might take a while"
    freenom_list_renewals="1"
  fi
  echo "..."; echo
elif echo -- "$@" | grep -qi -- '\-u'; then
  echo -e "[$(date)] Start - Update IP" >> "${out_path}.log"
  if [ "$2" != "" ]; then
    freenom_domain_name="$2"
    if echo "$3" | grep "^[0-9]\+$"; then freenom_domain_id="$3"
      if echo -- "$@" | grep -qi -- '\-s'; then freenom_subdomain_name="$5"; fi
    else
      freenom_update_ip="1"
      freenom_domain_id=""
      if echo -- "$@" | grep -qi -- '\-s'; then freenom_subdomain_name="$4"; fi
    fi
  fi
elif echo -- "$@" | grep -qi -- '\-r'; then
  freenom_renew_domain="1"
  echo -e "[$(date)] Start - Domain renewal" >> "${out_path}.log"
  if echo -- "$@" | grep -qi -- '\-a'; then
    freenom_renew_all="1"
  else
    if [ "$2" != "" ]; then freenom_domain_name="$2"
      if echo "$3" | grep "^[0-9]\+$"; then freenom_domain_id="$3"; else freenom_domain_id=""; fi
    fi
  fi
fi

if [ "$debug" -eq 1 ]; then
  echo "DEBUG: freenom_update_ip=$freenom_update_ip freenom_list=$freenom_list freenom_list_renewals=$freenom_list_renewals"
  echo "DEBUG: freenom_renew_domain=$freenom_renew_domain freenom_renew_all=$freenom_renew_all"
  echo "DEBUG: 1: $1 2: $2 3: $3 freenom_domain_name=$freenom_domain_name freenom_domain_id=$freenom_domain_id freenom_subdomain_name=$freenom_subdomain_name"
fi

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
# or comment line to disable
args="-s"
#args="-s -I -L -v -o /dev/null"

exitCode="0"

# get current ip using dig or curl
if [ "$freenom_update_ip" -eq "1" ]; then
  getIp[0]="dig -${freenom_update_ipver} TXT +short o-o.myaddr.l.google.com @ns1.google.com"
  getIp[1]="curl -A $agent -${freenom_update_ipver} -m 10 -s https://checkip.amazonaws.com"
  getIp[2]="curl -A $agent -${freenom_update_ipver} -m 10 -s https://diagnostic.opendns.com/myip"
  getIp[3]="curl -A $agent -${freenom_update_ipver} -m 10 -s https://www.ripe.net/@@ipaddress"
  if [ "${freenom_update_ipver}" -eq 4 ]; then
    getIp[4]="dig -4 +short myip.opendns.com @resolver1.opendns.com"
    getIp[5]="dig -4 +short myip.opendns.com @resolver2.opendns.com"
    getIp[6]="dig -4 +short myip.opendns.com @resolver3.opendns.com"
    getIp[7]="dig -4 +short myip.opendns.com @resolver4.opendns.com"
    getIp[8]="dig +short whoami.akamai.net @ns1-1.akamaitech.net"
  fi
  current_ip="$(${getIp[$((RANDOM%${#getIp[@]}))]} 2>/dev/null | tr -d '"')"

  if [ "$current_ip" == "" ]; then
      echo "[$(date)] Couldn't get current global ip address" >> "${out_path}.log"
      #exitCode="$(( exitCode+1 ))"
      exit 1
  fi
  if [ "$(cat "${out_path}.ip" 2>/dev/null)" == "$current_ip" ]; then
      if [ "$freenom_update_ip_logall" -eq "1" ]; then
        echo "[$(date)] Done. Update not needed, ip unchanged" >> "${out_path}.log"
      fi
      exit 0
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
    exitCode="$(( exitCode+1 ))"
fi

# get domaindetails for all domains, run always
myDomainsURL="https://my.freenom.com/clientarea.php?action=domains&itemlimit=all&token=$token"
# DEBUG: for debugging use local file instead:
# DEBUG: myDomainsURL="file:///home/user/src/freenom/myDomainsPage"
myDomainsPage="$(curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "$myDomainsURL")"
if [ "$myDomainsPage" ]; then
#  myDomainsResult="$( echo -e "$myDomainsPage" | sed -n '/href.*external-link/,/action=domaindetails/p' | sed -ne 's/.*id=\([0-9]\+\).*/\1/p;g' )"
  myDomainsResult="$( echo -e "$myDomainsPage" | sed -ne 's/.*"\(clientarea.php?action=domaindetails&id=[0-9]\+\)".*/\1/p;g' )"
  u=0; i=0
  for u in $myDomainsResult; do
    # DEBUG: for debugging use local file instead:
    # DEBUG: domainDetails=$( curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "file:///home/user/src/freenom/domainDetails_$i.bak" )
    domainDetails="$( curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "https://my.freenom.com/$u" )"
    domainId[$i]="$( echo $u | sed -ne 's/.*id=\([0-9]\+\).*/\1/p;g' )"
    domainName[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Domain:\(.*\)<[a-z].*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g' )"
    
    # on ip update we just need a domain name
    if [[ "$freenom_update_ip" -eq "1" && "${domainName[$i]}" == "$freenom_domain_name" ]]; then
      break
    else
      domainRegDate[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Registration Date:\(.*\)<.*/\1/p' | sed -e 's/<[^>]\+>//g' -e 's/  *//g' )"
      domainExpiryDate[$i]="$( echo -e "$domainDetails" | sed -n 's/.*Expiry date:\(.*\)<.*/\1/p' | sed 's/<[^>]\+>//g' )"
    fi
    i=$(( i+1 ))
  done  
fi

# set domain_id if needed
if [[ "$freenom_list" -eq 0 && "$freenom_renew_all" -eq 0 ]]; then
  if [ "$freenom_domain_id" == "" ]; then
    for ((i=0; i < ${#domainName[@]}; i++)); do
      if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then freenom_domain_id="${domainId[$i]}"; fi
    done
    if [ "$freenom_domain_id" == "" ]; then
      echo "ERROR: Could not find Domain ID for \"$freenom_domain_id\""
      echo "       Try setting \"freenom_domain_id\" in script or use \"$0 [-u|-r] [domain] [id]\""
      exit 1
    fi
  fi
fi

# update ip: if record does not exists, add new record, else update the first record; records[0]
if [ "$freenom_update_ip" -eq "1" ]; then
  dnsManagementURL="https://my.freenom.com/clientarea.php?managedns=$freenom_domain_name&domainid=$freenom_domain_id"
  dnsManagementPage="$(curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "$dnsManagementURL")"
  if [ "$(echo "$dnsManagementPage" | grep -F "records[0]")" == "" ]; then
      recordKey="addrecord[0]"
      dnsAction="add"
  else
      recordKey="records[0]"
      dnsAction="modify"
  fi

  # request add/update DNS record
  updateResult=$(curl $args -A "$agent" -e 'https://my.freenom.com/clientarea.php' --compressed -k -L -b "$cookie_file" \
      -F "dnsaction=$dnsAction" \
      -F "$recordKey[line]=" \
      -F "$recordKey[type]=A" \
      -F "$recordKey[name]=$freenom_subdomain_name" \
      -F "$recordKey[ttl]=14440" \
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
if [ "$freenom_list" -eq "1" ]; then
  if [ "$freenom_list_renewals" -eq "1" ]; then
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
    if [ "$freenom_list" -eq "1" ]; then
      if [ "$domainRenewalsResult" ]; then
        renewalMatch=$( echo "$domainRenewalsResult" | sed 's///g' | sed ':a;N;$!ba;s/\n //g' | grep "domain_id: ${domainId[$i]}" )
        if echo "$renewalMatch" | grep -q Minimum; then
          renewalDetails="$( echo "$renewalMatch" | sed 's/.* \([0-9]\+ Days\) * \(Minimum.*\) * domain_id:.*/\1 Until Expiry, \2/g' )"
        elif echo "$renewalMatch" | grep -q Renewable; then
          renewalDetails="$( echo "$renewalMatch" | sed 's/.* \([0-9]\+ Days\) * \(Renewable\) * domain_id:.*/\2, \1 Until Expiry/g' )"
        fi
      fi
    fi
    #if [ "$freenom_list_renewals" -eq "0" ]; then
    #  echo "$l"
    #else
    #  if [ ! "$renewalDetails" ]; then renewalDetails="N/A"; fi
    #  echo "$l | Renewal details: \"$renewalDetails\""
    #fi
    if [ "$freenom_list_renewals" -eq "1" ]; then
      if [ ! "$renewalDetails" ]; then renewalDetails="N/A"; fi
      showRenewal="$( echo ", Renewal details: \"$renewalDetails\"" )"
    fi
    printf "[%02d] Domain: \"%s\" Id: \"%s\" RegDate: \"%s\" ExpiryDate: \"%s\"%s\n" \
      "$((i+1))" "${domainName[$i]}" "${domainId[$i]}" "${domainRegDate[$i]}" "${domainExpiryDate[$i]}" "$showRenewal"
  done
  echo
  exit 0
fi

# Function renewDate: check date to make sure we can renew
#
# (1) Currently used method: call clientarea.php?action=domaindetails&id=$i
# -OR-
# (2) Only renew if Days < Minimum Advance Renewal Days 
# Where Days is: "Days Until Expiry":
#   <span class="textgreen">372 Days</span>
#   <span class="textred">Minimum Advance Renewal is 14 Days for Free Domains</span>
# -OR-
# (3) Use Current Date vs Expiry Date (https://my.freenom.com/clientarea.php?action=domains)
#   Domain      Registration Date  Expiry date
#   domain.cf   01/02/2017         01/03/2018 
#   foo.ga      01/02/2017         01/03/2018 
#   curDate="$( date +%F )"; expiryEpoch="$( date -d "$expiryDate" +%s )"  
func_renewDate() {
  expiryDay=""; expiryMonth=""; expiryYear=""; renewDateOK=""
  # example: "01/03/2018"
  IFS="/" read -a a <<< "$1"; expiryDay="${a[0]}"; expiryMonth="${a[1]}"; expiryYear="${a[2]}"
  expiryDate="$( date -d "${expiryYear}-${expiryMonth}-${expiryDay}" +%F )" 
  renewDate="$( date -d "$expiryDate - 14Days" +%F )"
  curEpoch="$( date +%s )"
  renewEpoch="$( date -d "$renewDate" +%s )"
  #echo "DEBUG: expiryDate=$expiryDate renewDate=$renewDate expiryEpoch=$expiryEpoch"
  #echo "DEBUG: renewEpoch=$renewEpoch curEpoch=$curEpoch"
  if [ "$debug" -eq 1 ]; then
    echo DEBUG: TEST - list full expiry date array: 
    for ((j=0; j<${#a[@]}; j++)); do echo "DEBUG: $i: ${a[$j]}"; done
  fi
  # TEST: set a date after renewDate example: curEpoch="$( date -d "2018-03-18" +%s )"
  if [ "$curEpoch" -ge "$renewEpoch" ]; then
    renewDateOK="1"
  else
    exitCode="$(( exitCode+1 ))"
    renewError="$renewError\nCannot renew ${domainName[$i]} (${domainId[$i]}) until $renewDate"
    if [ "$debug" -eq 1 ]; then echo -e "DEBUG: $renewError"; fi
  fi
}

# Function renewDomain: if date is ok, submit actual renewal and get result
func_renewDomain() {
  if [ "$renewDateOK" ]; then

    # use id/name
    freenom_domain_id="${domainId[$i]} $freenom_domain_id"
    freenom_domain_name="${domainName[$i]} $freenom_domain_name"
    if [ "$debug" -eq 1 ]; then echo "DEBUG: curdate greater or equal than expirydate -> possible to renew"; fi
    renewDomainURL="https://my.freenom.com/domains.php?a=renewdomain&domain=${domainId[$i]}&token=$token"
    renewDomainPage="$(curl $args -A "$agent" --compressed -k -L -b "$cookie_file" "$renewDomainURL")"

    # EXAMPLE:
    # url:       https://my.freenom.com/domains.php?submitrenewals=true
    # form data: 7ad1a728a6d8a96d1a8d66e63e8a698ea278986e renewalid:1000000000 renewalperiod[1000000000]:12M paymentmethod:credit

    if [ "$renewDomainPage" ]; then
      #echo "$renewDomainPage"
      echo "$renewDomainPage" > "renewDomainPage_${domainId[$i]}.html"
      if [ "$debug" -eq 1 ]; then echo "DEBUG: OK a=renewdomain $renewDomainURL"; fi
      renewalPeriod="$( echo "$renewDomainPage" | sed -n 's/.*option value="\(.*\)\".*FREE.*/\1/p' | sort -n | tail -1 )"
      #if [ "$renewalPeriod" == "" ]; then renewalPeriod="12M"; fi
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
          renewOK="$renewOK\nSuccessfully renewed domain ${domainName[$i]} (${domainId[$i]} ${renewalPeriod})"
        else
          exitCode="$(( exitCode+1 ))"
          renewError="$renewError\nRenewal failed for ${domainName[$i]} (${domainId[$i]})"
        fi
      else
        exitCode="$(( exitCode+1 ))"
        renewError="$renewError\nCannot renew ${domainName[$i]} (${domainId[$i]}), renewal period not found"
      fi
    else
      exitCode="$(( exitCode+1 ))"
    fi
  fi
  #echo
}

# call renewal functions for all domains
if [ "$freenom_renew_domain" -eq 1 ]; then
  if [ "$freenom_renew_all" -eq 1 ]; then
    for ((i=0; i < ${#domainName[@]}; i++)); do
      if [ "$debug" -eq 1 ]; then echo "DEBUG: $i ${#domainName[@]} domainId: ${domainId[$i]} domainName: ${domainName[$i]}"; fi
      func_renewDate "${domainExpiryDate[$i]}"; func_renewDomain
    done
  else
    for ((i=0; i < ${#domainName[@]}; i++)); do
      if [ "$freenom_domain_name" == "${domainName[$i]}" ]; then
        func_renewDate "${domainExpiryDate[$i]}"; func_renewDomain
      fi
    done
  fi
fi

# logout and clean up

# DEBUG: comment line below for debugging
curl $args -A "$agent" --compressed -k -b "$cookie_file" "https://my.freenom.com/logout.php" > /dev/null 2>&1
rm -f "$cookie_file"

# write html result on error
if [ "$freenom_update_ip" -eq "1" ]; then
  if [ "$(echo -e "$updateResult" | grep "$current_ip")" == "" ]; then
      echo "[$(date)] Update failed (${freenom_domain_name} ${freenom_domain_id})" >> "${out_path}.log"
      echo -e "$updateResult" > "${out_path}.errorUpdateResult.html"
      exitCode="$(( exitCode+1 ))"
  else
      # save ip address
      echo -n "$current_ip" > "${out_path}.ip"
      echo "[$(date)] Update successful (${freenom_domain_name} ${freenom_domain_id} ${current_ip})" >> "${out_path}.log"
  fi
fi

# write renewal results to logfile, exit with exitcode
if [ "$freenom_renew_domain" -eq "1" ]; then
  if [ "$renewOK" ]; then
    echo -e "[$(date)] Renewal OK: $renewOK" >> "${out_path}.log"
  fi
  if [ "$exitCode" -gt "0" ]; then
    if [ -z "$renewError" ]; then
      if [ "$(echo -e "$renewalResult" | grep "Minimum Advance Renewal is")" != "" ]; then
        renewError="$( echo -e "$renewalResult" | grep textred | \
            sed -e 's/<[^>]\+>//g' -e 's/\(  \|\t\|\)//g' | sed ':a;N;$!ba;s/\n/, /g')"
      fi
    fi
    echo -e "[$(date)] Did not renew domain(s), reason: ${renewError}" >> "${out_path}.log"
  else
    echo "[$(date)] Successfully renewed domain $freenom_domain_name (${freenom_domain_id/% /})" >> "${out_path}.log"
  fi
fi

echo -e "[$(date)] Done" >> "${out_path}.log"
if [ "$exitCode" -gt "0" ]; then
  echo " (with errors)" >> "${out_path}.log"
  exit 1
else
  echo >> "${out_path}.log"
  exit 0
fi
