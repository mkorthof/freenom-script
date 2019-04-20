# Domain Renewal and DynDNS for Freenom.com

This shell script makes sure your Freenom domains don't expire by auto renewing them.
It's original functionality of updating an A record with the clients ip address is also retained.

You'll need to have already registered an account at Freenom.com first with at least one (free) domain added before you can run the script.

## Installation

Note that this shell script requires a recent version of "Bash"

1) Suggested installation path: "/usr/local/bin"
2) Edit "freenom.sh" and set your email and password which you use to sign-in to freenom.com
3) Test the script by running `freenom.sh -l`, make sure your domains are listed
4) To update A record or Renew domains, see Usage below or `freenom.sh -h`  

### Configuration:

Settings can be changed in the script itself or set in a seperate config file (default). Every setting has comments with possible options and examples.

- The default filename is "freenom.conf" in the same location as the script
- You can also use `freename.sh -c /path/to/file.conf`
- To optionally use the script itself instead copy settings from conf into "freenom.sh" (put them before "Main")

### Scheduling:

To run the script automatically you can use cron or systemd.

#### Cron

- Follow Installation steps above e.g. copy "freenom.sh" to "/usr/local/bin"
- Create a new file "/etc/cron.d/freenom" and add the following line(s):

```
0 9 * * 0 root bash -c 'sleep $((RANDOM \% 60))m; /usr/local/bin/freenom.sh -r -a' 
0 * * * * root bash -c 'sleep $((RANDOM \% 15))m; /usr/local/bin/freenom.sh -u example.com'
```

This first line in this example will run the script with "renew all domains" options every week on Sunday between 9.00 and 10.00

The second line updates the A record of example.com with the current client ip address, at hourly intervals

#### Systemd

Alternatively the same can be accomplished with a [systemd.timer](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)

### Optional Overrides:

The following options can be changed in config, they are however OK to leave as-is.

#### Update ip

```
freenom_update_force="0"      # [0/1] force ip update, even if unchanged
freenom_update_ttl="3600"     # ttl in sec (changed from 14440 to 3600)
freenom_update_ip_retry="3"   # number of retries to get ip
freenom_update_ip_log="1"     # [0/1] log 'skipped same ip' msg
freenom_renew_log="1"         # [0/1] log renew warnings details
```

#### Actions

```
freenom_update_ip="0"         # [0/1] arg "-u"
freenom_list="0"              # [0/1] arg "-l"
freenom_list_renewals="0"     # [0/1] arg "-l -d"
freenom_list_records="0"      # [0/1] arg "-z"
freenom_renew_domain="0"      # [0/1] arg "-r"
freenom_renew_all="0"         # [0/1] args "-r -a"
```

## DynDNS

To update A records the nameservers for the domain must be set to the default Freenom NS.

- As value your current ip address will be used ("Target")
- An A record will be added if there is none or modified if the record already exists

### IP Address:

To get  your current ip address from a number of public services the script uses 2 methods, HTTP and DNS:

  - HTTP method: `curl https://checkip.amazonaws.com`
  - DNS method: `dig TXT +short o-o.myaddr.l.google.com @ns1.google.com`

There are a few more services defined for redundancy, the script will choose one at random. By default it will retry 3 times to get ip.

Once your ip is found it's written to "freenom.ip" to prevent unnecessary updates in case the ip is unchanged.
To force an update you can remove this file which is located in the default output path "/var/log".

### Issues:

In case of issues try running the curl and dig command above manually.

 - To list all services check the getIp array e.g. run `grep getIp freenom.sh`
 - To disable IPv6: set `freenom_update_ipv="4"`
 - To disable dig: set `freenom_update_dig="0"`

## Used Files

### Script:
 
- freenom.sh
- freenom.conf

### Output:

- Default path: "/var/log/freenom<.ext>"
	- freenom.log
	- freenom.ip
	- freenom.renewalResult_<domain_id>.html
	- freenom.errorUpdateResult.html
- More info: see "Output files" and "out_path" variable in config
- Use `freenom.sh -e` or `-o` to view the Result html files

## Usage

```
USAGE:

freenom.sh [-l][-r][-u|-z <domain>][-s <subdomain>] [-d|-a] [-c <file>][-e][-o]

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

EXAMPLES:   ./freenom.sh -l -d
            ./freenom.sh -r example.com
            ./freenom.sh -r -a
            ./freenom.sh -u example.com -s mail

NOTES:      Using [-u] or [-r] and specifying <domain> as argument
            overrides any settings in script or config file
```

## Sources

- Original script: https://gist.github.com/a-c-t-i-n-i-u-m/bc4b1ff265b277dbf195
- Updated script: https://gist.github.com/pgaulon/3a844a626458f56903d88c5bb1463cc6
- Reference: https://github.com/dabendan2/freenom-dns (npm)
- Reference: https://github.com/patrikx3/freenom  (npm)

## Changes

- added referer url to curl to fix login
- fixed token
- made updating ip optional
- added domain renewals
- added logging
- handling of existing dns records (ip update)
- retry getting current ip
- option to use seperate .conf file
- option to list existing dns records
- option to skip renewal warning details in log
