# Domain Renewal and DynDNS script for Freenom.com

This shell script makes sure your Freenom domains don't expire by auto renewing them.
It's original functionality of updating an A record with the clients ip address is also retained.

You'll need to have already registered an account at Freenom.com first with at least one (free) domain added before you can run the script.

### Installation

This shell script uses "bash"

1) Edit "freenom.sh" ands set your email and password which you use to sign-in to freenom.com
2) Test the script by running `freenom.sh -l`, make sure your domains at listed
3) To update A records or Renew domains, see Usage below or `freenom.sh -h`

### Cron 

To run the script weekly can you use cron:

- copy "freenom.sh" to "/usr/local/bin"
- create "/etc/cron.d/freenom" and add this line:

```
0 9 * * 0 root bash -c 'sleep $((RANDOM \% 60))m; /usr/local/bin/freenom.sh -r -a' 
0 * * * * root bash -c 'sleep $((RANDOM \% 15))m; /usr/local/bin/freenom.sh -u example.com'
```

This first line in this example will run the script with "renew all domains" options every week on Sunday between 9.00 and 10.00
The second line updates the A record of example.com with the current client IP address at hourly intervals

### Usage

```
USAGE: ./freenom.sh [-l|-r|-u] [-n|-a] [domain] [-s <subdomain>]

OPTIONS:  -l    list domains with id's
                add [-n] to show renewal details
          -u    update <domain> A record with current ip
                add [-s] to update <subdomain>
          -r    renew domain(s), add [-a] for all domains

EXAMPLE:  ./freenom.sh -u example.com -s mail
          ./freenom.sh -r example.com
          ./freenom.sh -r -a

NOTE:     Using -u or -r and specifying "domain" overrides
          setting in "freenom.sh"
```

### Sources 

- Original script: https://gist.github.com/a-c-t-i-n-i-u-m/bc4b1ff265b277dbf195
- Updated script: https://gist.github.com/pgaulon/3a844a626458f56903d88c5bb1463cc6
- Reference: https://github.com/dabendan2/freenom-dns (npm)
- Reference: https://github.com/patrikx3/freenom  (npm)

### Changes

- added referer url to curl to fix login
- fixed token
- made updating ip optional
- added domain renewals
- added logging

