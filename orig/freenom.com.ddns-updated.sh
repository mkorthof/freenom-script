#!/bin/bash

#
# settings
#
# login data
freenom_email="main@address"
freenom_passwd="pswd"
# Open DNS management page in your browser.
# URL vs settings:
#   https://my.freenom.com/clientarea.php?managedns={freenom_domain_name}&domainid={freenom_domain_id}
freenom_domain_name="domain.name"
freenom_subdomain_name=""
freenom_domain_id="000000000"

#
# main
#
# get current url
current_ip="$(dig TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | tr -d '"')"
log_file="/tmp/$(basename $0)"

if [ "$current_ip" == "" ]; then
    echo "[$(date)] Couldn't get current global ip address." >> ${log_file}.log
    exit 1
fi
if [ "$(cat ${log_file}.ip 2>/dev/null)" == "$current_ip" ]; then
    exit 0
fi

# login
cookie_file=$(mktemp)

loginPage=$(curl --compressed -k -L -c "$cookie_file" \                                                                                                                            
    "https://my.freenom.com/clientarea.php" 2>&1)

token=$(echo "$loginPage" | grep token | grep -o value=".*" | sed 's/value=//g' | sed 's/"//g' | awk '{print $1}')

loginResult=$(curl --compressed -k -L -c "$cookie_file" \
    -F "username=$freenom_email" -F "password=$freenom_passwd" -F "token=$token"\
    "https://my.freenom.com/dologin.php" 2>&1)

if [ "$(echo -e "$loginResult" | grep "Location: /clientarea.php?incorrect=true")" != "" ]; then
    echo "[$(date)] Login failed." >> ${log_file}.log
    rm -f $cookie_file
    exit 1
fi

# if record does not exists, add new record, else update the first record; records[0]
dnsManagementURL="https://my.freenom.com/clientarea.php?managedns=$freenom_domain_name&domainid=$freenom_domain_id"
dnsManagementPage=$(curl --compressed -k -L -b "$cookie_file" "$dnsManagementURL")
if [ "$(echo "$dnsManagementPage" | grep -F "records[0]")" == "" ]; then
    recordKey="addrecord[0]"
    dnsAction="add"
else
    recordKey="records[0]"
    dnsAction="modify"
fi

token=$(echo "$dnsManagementPage" | grep token | grep -o value=".*" | tail -n 1 | sed 's/value=//g' | sed 's/"//g' | awk '{print $1}') 

# request add/update DNS record
updateResult=$(curl --compressed -k -L -b "$cookie_file" \
    -F "dnsaction=$dnsAction" \
    -F "$recordKey[line]=" \
    -F "$recordKey[type]=A" \
    -F "$recordKey[name]=$freenom_subdomain_name" \
    -F "$recordKey[ttl]=14440" \
    -F "$recordKey[value]=$current_ip" \
    -F "token=$token" \
    "$dnsManagementURL" 2>&1)

# logout
curl --compressed -k -b "$cookie_file" "https://my.freenom.com/logout.php" > /dev/null 2>&1

# clean up
rm -f $cookie_file

if [ "$(echo -e "$updateResult" | grep "$current_ip")" == "" ]; then
    echo "[$(date)] Update failed." >> ${log_file}.log
    echo -e "$updateResult" > ${log_file}.errorUpdateResult.log
    exit 1
else
    # save ip address
    echo -n "$current_ip" > ${log_file}.ip
    exit 0
fi
