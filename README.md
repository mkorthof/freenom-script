# Domain Renewal and DynDNS script for Freenom.com

This shell script makes sure your Freenom domains don't expire by auto renewing them.
It's original functionality of updating an A record with the clients ip address is also retained.

You'll need to have already registered an account at Freenom.com first with at least one (free) domain added before you can run the script.
For "DynDNS" (updating A record) nameservers must be set to the default Freenom NS. To force updating remove "freenom.ip" file.
A records are now added without replacing exiting record, if the record already exists it is modified. 

### Installation

Note that this shell script requires "Bash"

1) Suggested installation location: "/usr/local/bin"
2) Edit "freenom.sh" and set your email and password which you use to sign-in to freenom.com
3) Test the script by running `freenom.sh -l`, make sure your domains are listed
4) To update A record or Renew domains, see Usage below or `freenom.sh -h`  

#### Cron:

To run the script automatically cron can be used:

- Follow steps above, copy "freenom.sh" to "/usr/local/bin"
- Create a new file "/etc/cron.d/freenom"
- Add the following line(s):

```
0 9 * * 0 root bash -c 'sleep $((RANDOM \% 60))m; /usr/local/bin/freenom.sh -r -a' 
0 * * * * root bash -c 'sleep $((RANDOM \% 15))m; /usr/local/bin/freenom.sh -u example.com'
```

This first line in this example will run the script with "renew all domains" options every week on Sunday between 9.00 and 10.00
The second line updates the A record of example.com with the current client IP address at hourly intervals

Alternatively the same can be accomplished with a [systemd.timer](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)

#### Get Current IP:

The script uses 2 methods - HTTP  and DNS - to get your IP address from a number of public services:
  - `curl https://checkip.amazonaws.com`
  - `dig TXT +short o-o.myaddr.l.google.com @ns1.google.com`

There are a few more services defined for redundancy, the script will choose one at random.

In case of issues try running the curl and dig command above manually.
 - To list all services check the getIp array, e.g. `grep getIp freenom.sh`
 - To disable IPv6: set `freenom_update_ipv="4"`
 - To disable dns/dig: set `freenom_update_dig="0"`

By default the script will retry 3 times to get ip.

### Optional overrides:

The following options can be changed in config, they are however OK to leave as-is.

#### IP update:

```
freenom_update_force="0"      # force ip update, even if unchanged
freenom_update_ttl="3600"     # ttl changed from 14440 to 3600
freenom_update_ip_retry="3"   # number of retries getting ip
freenom_update_ip_logall="1"  # "0" skips 'ip unchanged' log msg
```

#### Actions:

```
freenom_update_ip="0"
freenom_list="0"
freenom_list_renewals="0"
freenom_renew_domain="0"
freenom_renew_all="0"
```

### Usage:

```
  USAGE: /usr/local/bin/freenom.sh [-l|-u|-r][-e] [-d|-a] [domain] [-s <subdomain>]

  OPTIONS:  -l    List domains with id's
                  add [-d] to show renewal Details
            -u    Update <domain> a-record with current ip
                  add [-s] to update <Subdomain>
            -r    Renew domain(s), add [-a] for All domains
            -e    View error output from update

  EXAMPLE:  ./freenom.sh -u example.com -s mail
            ./freenom.sh -r example.com
            ./freenom.sh -r -a

  NOTE:     Using -u or -r and specifying "domain" as argument
            overrides setting in "freenom.sh"
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
- handling of existing dns records (ip update)
- retry getting current ip
- preparations for seperate .conf (next version)


