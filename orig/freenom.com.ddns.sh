#!/bin/bash
 
# settings
# Login information of freenom.com
freenom_email="main@address"
freenom_passwd="pswd"
# Open DNS management page in your browser.
# URL vs settings:
#   https://my.freenom.com/clientarea.php?managedns={freenom_domain_name}&domainid={freenom_domain_id}
freenom_domain_name="domain.name"
freenom_domain_id="000000000"
 
# main
# get current ip address
current_ip="$(curl -s "https://api.ipify.org/")"
 
if [ "${current_ip}" == "" ]; then
    echo "Could not get current IP address." 1>&2
    exit 1
fi

# login
cookie_file=$(mktemp)
loginResult=$(curl --compressed -k -L -c "${cookie_file}" \
    -F "username=${freenom_email}" -F "password=${freenom_passwd}" \
    "https://my.freenom.com/dologin.php" 2>&1)

if [ "$(echo -e "${loginResult}" | grep "/clientarea.php?incorrect=true")" != "" ]; then
    echo "Login failed." 1>&2
    exit 1
fi

exit 0

# update
updateResult=$(curl --compressed -k -L -b "${cookie_file}" \
    -F "dnsaction=modify" -F "records[0][line]=" -F "records[0][type]=A" -F "records[0][name]=" -F "records[0][ttl]=14440" -F "records[0][value]=${current_ip}" \
    "hxxttps://my.freenom.com/clientarea.php?managedns=${freenom_domain_name}&domainid=${freenom_domain_id}" 2>&1)

if [ "$(echo -e "$updateResult" | grep "<li class=\"dnssuccess\">")" == "" ]; then
    echo "Update failed." 1>&2
    exit 1
fi

# logout
curl --compressed -k -b "${cookie_file}" "https://my.freenom.com/logout.php" > /dev/null 2>&1

# clean up
rm -f ${cookie_file}

exit 0
