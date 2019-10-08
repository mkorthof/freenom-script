# Domain Renewal and DynDNS for Freenom.com

***Latest version: v2019-10-05 ([Changes](#Changes))***

This shell script makes sure your Freenom domains don't expire by auto renewing them.
It's original functionality of updating an A record with the clients ip address is also retained.

You'll need to have already registered an account at Freenom.com with at least one (free) domain added before you can run the script.

## Installation

_Note that this shell script requires a recent version of "Bash"_

### Installer

Run `make install` from git clone directory to automatically install the script, conf file and to configure scheduler.

### Manually

1) Suggested installation path: "/usr/local/bin" and "/etc" for the config file
2) Edit config and set your email and password which you use to sign-in to freenom.com

### Testing
Test the script by running `freenom.sh -l` and make sure your domains are listed. To update A record or Renew domains, see Usage below or `freenom.sh -h`  

## Configuration

Settings can be changed in the script itself or set in a seperate config file (default). Every setting has comments with possible options and examples.

- The default filename is "freenom.conf" in the same location as the script or "/etc/freenom.conf"
- You can also use `freename.sh -c /path/to/file.conf`
- To optionally put config in the script itself instead: copy settings from conf into `freenom.sh` (before "Main")

## Scheduling

The installer creates "/etc/cron.d/freenom" or systemd timers so the script runs automatically at certain intervals. You just have to set your domain(s), the installer will tell you how. You can also have a look at the Examples and manual steps below.

### Cron

To manually configure cron:

- Copy script and conf files (see [Installation](#Installation))
- Copy [cron.d/freenom](cron.d/freenom) to "/etc/cron.d/freenom" and edit it, or create the file yourself with these line(s)

Example:

``` bash
0 9 * * 0 root bash -c 'sleep $((RANDOM \% 60))m; /usr/local/bin/freenom.sh -r -a'
0 * * * * root bash -c 'sleep $((RANDOM \% 15))m; /usr/local/bin/freenom.sh -u example.tk'
```

This first line in this example will run the script with "renew all domains" options every week on Sunday between 9.00 and 10.00

The second line updates the A record of `example.tk` with the current client ip address, at hourly intervals

### Systemd

Alternatively the same can be accomplished by manually adding a [systemd.timer](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)

Thanks to [@sdcloudt](https://github.com/sdcloudt) you can use the templates from the [systemd](systemd) dir.

Copy the files to e.g. `/etc/systemd/user` or `~/.config/systemd/user`. Then reload systemd and either manually add symlinks or enable the unit to create a service instance for your domain.

Example:

``` bash
# manually:
mkdir /etc/systemd/user/timers.target.wants
ln -s /etc/systemd/user/freenom-renew@.service /etc/systemd/user/timers.target.wants/freenom-renew@example.com.service
# or, renew all domains:
ln -s /etc/systemd/user/freenom-renew-all@.service /etc/systemd/user/timers.target.wants/freenom-renew-all@.service
ln -s /etc/systemd/user/freenom-update@.service /etc/systemd/user/timers.target.wants/freenom-update@example.com.service
````

``` bash
# always reload systemd first:
systemctl daemon-reload
```

``` bash
# this will create symlinks automatically:
systemd enable --now freenom-renew@example.com.service
# or, renew all domains:
systemd enable --now freenom-renew-all@.service
systemd enable --now freenom-update@example.com.service
```

### Optional Overrides

The following options can be changed in config, they are however OK to leave as-is.

``` bash
freenom_http_retry="3"        # number of curl retries
freenom_update_force="0"      # [0/1] force ip update, even if unchanged
freenom_update_ttl="3600"     # ttl in sec (changed from 14440 to 3600)
freenom_update_ip_retry="3"   # number of retries to get ip
freenom_update_ip_log="1"     # [0/1] log 'skipped same ip' msg
freenom_renew_log="1"         # [0/1] log renew warnings details
freenom_list_bind="0"         # [0/1] output isc bind zone format
```

### Actions

``` bash
freenom_update_ip="0"         # [0/1] arg "-u"
freenom_list="0"              # [0/1] arg "-l"
freenom_list_renewals="0"     # [0/1] args "-l -d"
freenom_list_records="0"      # [0/1] arg "-z"
freenom_renew_domain="0"      # [0/1] arg "-r"
freenom_renew_all="0"         # [0/1] args "-r -a"
```

## DynDNS

To update A or AAAA records the nameservers for the domain must be set to the default Freenom Name Server.

- As value your current ip address will be used ("Target")
- An record will be added if there is none or modified if the record already exists

### IP Address

To get  your current ip address from a number of public services the script uses 2 methods, HTTP and DNS:

- HTTP method: `curl https://checkip.amazonaws.com`
- DNS method: `dig TXT +short o-o.myaddr.l.google.com @ns1.google.com`

There are a few more services defined for redundancy, the script will choose one at random. By default it will retry 3 times to get ip.

Once your ip is found it's written to "freenom.ip4.domain.lock" (or ip6) to prevent unnecessary updates in case the ip is unchanged.
To force an update you can remove this file which is located in the default output path "/var/log".

### Issues

In case of issues try running the curl and dig command above manually.

- To list all services check the getIp array e.g. run `grep getIp freenom.sh`
- To disable IPv6: set `freenom_update_ipv="4"`
- To disable dig: set `freenom_update_dig="0"`

## Used Files

- **Installer:**
  - `Makefile`
- **Script:**
  - `freenom.sh`
  - `freenom.conf`
- **Output:**
  - Default path: `"/var/log/freenom/"`
  - `freenom.log`
  - `freenom_\<domain\>.ip{4,6}`
  - `freenom_renewalResult-\<id\>.html`
- **More info:**
  - See "Output files" and "freenom_out_dir" variable in config
  - Use `freenom.sh -o` to view Result html files

## Updates

Usually you can just replace "freenom.sh" with the new version (unless you're not using a seperate config file).

An exeption is when config options were added/changed which you may need to compare and merge. Such config changes are listed [below](#Changes).

## Uninstall

Run `make uninstall`.

You can also manually reverse the steps under Installation above (remove .sh, .conf and scheduler files).

## Usage

```shell
FREENOM.COM DOMAIN RENEWAL AND DYNDNS
=====================================

USAGE:
            freenom.sh -l [-d]
            freenom.sh -r <domain> [-s <subdomain>] | [-a]
            freenom.sh -u <domain> [-s <subdomain>] [-f]
            freenom.sh -z <domain>

OPTIONS:
            -l    List all domains and id's for account
                  add [-d] to show renewal Details
            -r    Renew domain(s)
                  add [-a] to renew All domains
            -u    Update <domain> A record with current ip
                  add [-s] to update <Subdomain>
                  add [-f] to force update on unchanged ip
            -z    Zone listing of dns records for <domain>

            -4    Use ipv4 and modify A record on "-u" (default)
            -6    Use ipv6 and modify AAAA record on "-u"
            -c    Config <file> to be used instead freenom.conf
            -i    Ip commands list used to get current ip
            -o    Output html result file(s) for renewals

EXAMPLES:
            ./freenom.sh -r example.com
            ./freenom.sh -c /etc/myfn.conf -r -a
            ./freenom.sh -u example.com -s mail

NOTES:
            Using "-u" or "-r" and specifying <domain> as argument
            will override any settings in script or config file
```

## Sources

- Original script: [gist.github.com/a-c-t-i-n-i-u-m/bc4b1ff265b277dbf195](https://gist.github.com/a-c-t-i-n-i-u-m/bc4b1ff265b277dbf195)
- Updated script: [gist.github.com/pgaulon/3a844a626458f56903d88c5bb1463cc6](https://gist.github.com/pgaulon/3a844a626458f56903d88c5bb1463cc6)
- Reference: [github.com/dabendan2/freenom-dns](https://github.com/dabendan2/freenom-dns) (npm)
- Reference: [github.com/patrikx3/freenom](https://github.com/patrikx3/freenom) (npm)

## Changes

- [20190000] added referer url to curl to fix login
- [20190000] fixed token
- [20190000] made updating ip optional
- [20190000] added domain renewals
- [20190000] added logging
- [20190317] handling of existing dns records (ip update)
- [20190317] retry getting current ip
- [20190420] option to use seperate .conf file
- [20190420] option to list existing dns records
- [20190420] option to skip renewal notice details in log
- [20190621] added tests (BATS)
- [20190621] changed 'cannot renew until' warnings to notices
- [20190621] added recType check (A or AAAA) for dyndns
- [20190920] changed out dir, **config change:** `freenom_out_dir="/var/log/freenom"`
- [20190920] added curl retries, **config change:** `freenom_http_retry="3"`
- [20190922] fixed issue #12 (sdcloudt)
- [20190931] added systemd templates (PR #15 from sdcloudt)
- [20190927] added installer
- [20191005] errorUpdateResult is no longer saved to html file

More details: `git log --pretty=short --name-only`
