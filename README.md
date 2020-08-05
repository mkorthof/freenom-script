# Domain Renewal and DynDNS for Freenom.com

## Last Update ##

***Latest version: v2020-07-13 ([CHANGES.md](CHANGES.md))***

**Make sure to add new config options when updating script**

---

This shell script makes sure your Freenom domains don't expire by auto renewing them.
It's original functionality of updating an A record with the clients ip address is also retained.

You'll need to have already registered an account at Freenom.com with at least one (free) domain added before you can run the script.

## Usage

```shell
FREENOM.COM DOMAIN RENEWAL AND DYNDNS
=====================================

USAGE:
            freenom.sh -l [-d]
            freenom.sh -r <domain> [-s <subdomain>] | [-a]
            freenom.sh -u <domain> [-s <subdomain>] [-m <ip>] [-f]
            freenom.sh -z <domain>

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
            ./freenom.sh -r example.com
            ./freenom.sh -c /etc/myfn.conf -r -a
            ./freenom.sh -u example.com -s mail

NOTES:
            Using "-u" or "-r" and specifying <domain> as argument
            will override any settings in script or config file
```

## Installation

_Note that this shell script requires recent versions of "Bash" and "cURL"_

### Auto Installer

Run `make install` from git clone directory to automatically install the script, conf file and to configure scheduler.

### Manually

Suggested installation path: "/usr/local/bin" and "/usr/local/etc" for the config file

## Configuration

Settings can be changed in the script itself or set in a seperate config file (default). Every setting has comments with possible options and examples.

First edit config and **set your email and password** which you use to sign-in to freenom.com

- The default filename is "freenom.conf" in the same location as the script or "/usr/local/etc/freenom.conf"
- You can also use `freenom.sh -c /path/to/file.conf`
- To optionally put config in the script itself instead: copy settings from conf into `freenom.sh` (before "Main")

### Testing

Test the script by running `freenom.sh -l` and make sure your domains are listed. To update A record or Renew domains, see Usage below or `freenom.sh -h`  

## Scheduling

Optionally you can schedule the script to run automatically. The installer creates "/etc/cron.d/freenom" or systemd timers in 'system mode' so the script runs at certain intervals. It will output a message with instructions on how to set your domain(s) to renew/update or renew all:

``` bash
systemctl enable --now freenom-renew@example.tk.timer
systemctl enable --now freenom-renew-all@.timer
systemctl enable --now freenom-update@example.tk.timer
```

If systemd is not available on your system the installer will use cron instead.

### Cron

To manually configure cron:

1) Copy script and conf files (see [Installation](#Installation))
2) Copy [cron.d/freenom](cron.d/freenom) to "/etc/cron.d/freenom" and edit it, or create the file yourself with these line(s)

Example:

``` bash
0 9 * * 0 root bash -c 'sleep $((RANDOM \% 60))m; /usr/local/bin/freenom.sh -r -a'
0 * * * * root bash -c 'sleep $((RANDOM \% 15))m; /usr/local/bin/freenom.sh -u example.tk'
```

This first line in this example will run the script with "renew all domains" options every week on Sunday between 9.00 and 10.00

The second line updates the A record of `example.tk` with the current client ip address, at hourly intervals

### Systemd

To manually setup systemd add one or more "[timer(s)](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)"

Thanks to [@sdcloudt](https://github.com/sdcloudt) you can use the template units from the [systemd](systemd) dir.

1) Copy the files to:
   - "/usr/lib/systemd/system" (RedHat)
   - "/lib/systemd/system" (Debian/Ubuntu)

2) Create symlinks (or use `systemctl enable`) to create a service instance for your domain(s)

3) Reload systemd

Example:

``` bash
# Create symlinks:

mkdir /path/to/systemd/timers.target.wants
ln -s /path/to/systemd/freenom-renew@.service /etc/systemd/user/timers.target.wants/freenom-renew@example.tk.service
ln -s /path/to/systemd/freenom-renew-all@.service /etc/systemd/user/timers.target.wants/freenom-renew-all@.service
ln -s /path/to/systemd/freenom-update@.service /etc/systemd/user/timers.target.wants/freenom-update@example.tk.service:
# then reload systemd:
systemctl daemon-reload
```

In case of any errors make sure you're using the correct paths and "freenom.conf" is setup. Check `systemctl status <unit>` and the logs.

##### NOTE: to use 'user mode' instead of system mode replace "/system" by "/user" and use `freenomctl --user`

### Optional Overrides

The following options can be changed in config, they are however OK to leave as-is.

``` bash
freenom_http_retry="3"        # number of curl retries
freenom_update_force="0"      # [0/1**] force ip update, even if unchanged
freenom_update_ttl="3600"     # ttl in sec (changed from 14440 to 3600)
freenom_update_ip_retry="3"   # number of retries to get ip
freenom_update_ip_log="1"     # [0/1**] log 'skipped same ip' msg
freenom_renew_log="1"         # [0/1**] log renew warnings details
freenom_list_bind="0"         # [0/1**] output isc bind zone format
freenom_http_sleep="3 3"      # wait n to n+n secs between http requests
freenom_oldcurl_force="0"     # [0/1] force older curl version support
```

### Actions

``` bash
freenom_update_ip="0"         # [0/1**] arg "-u"
freenom_update_manual="0"     # [0/1**] arg "-m"
freenom_update_all="0"        # [0/1**] arg "-a" (future update, not working yet)
freenom_list="0"              # [0/1**] arg "-l"
freenom_list_renewals="0"     # [0/1**] args "-l -d"
freenom_list_records="0"      # [0/1**] arg "-z"
freenom_renew_domain="0"      # [0/1**] arg "-r"
freenom_renew_all="0"         # [0/1**] args "-r -a"
```

## DynDNS

To update A or AAAA records the nameservers for the domain must be set to the default Freenom Name Server.

- As value your current ip address will be used ("Target")
- An record will be added if there is none or modified if the record already exists

### IP Address

To get your current ip address from a number of public services the script uses 2 methods, HTTP and DNS:

- HTTP method: `curl https://checkip.amazonaws.com`
- DNS method: `dig TXT +short o-o.myaddr.l.google.com @ns1.google.com`
- Or, manually: updates static ip address instead of auto detect

There are a few more services defined for redundancy, the script will choose one at random. By default it will retry 3 times to get ip.

Once your ip is found it's written to "freenom.ip4.domain.lock" (or ip6) to prevent unnecessary updates in case the ip is unchanged.
To force an update you can remove this file which is located in the default output path "/var/log".

To manually update using set `freenom_static_ip` and `freenom_update_manual="0"` or use "-m" option.

### Issues

Make sure 'curl' and/or 'dig' is installed (from e.g. dnsutils or bind-utils)

In case of issues try running the curl and dig command above manually.

- To list all 'get ip' commands run `freenom.sh -i` (or `grep getIp freenom.sh`)
- To disable IPv6: set `freenom_update_ipv="4"`
- To disable dig: set `freenom_update_dig="0"`

## Files

- **Installer:**
  - `Makefile`
- **Script:**
  - `freenom.sh`
  - `freenom.conf`
- **Output:**
  - Default path: `"/var/log/freenom/"`
  - `freenom.log`
  - `freenom_<domain>.ip{4,6}`
  - `freenom_renewalResult-<id>.html`
- **More info:**
  - See "Output files" and "freenom_out_dir" variable in config
  - Use `freenom.sh -o` to view Result html files

## Updating

Usually you can just replace "freenom.sh" with the new version (unless you're not using a seperate config file).

An exeption is when config options were added/changed which you may need to compare and merge. Such config changes are listed [below](#Changes).

## Uninstall

Run `make uninstall`.

You can also manually reverse the steps under Installation above (remove .sh, .conf and scheduler files).

## Sources

- Original script: [gist.github.com/a-c-t-i-n-i-u-m/bc4b1ff265b277dbf195](https://gist.github.com/a-c-t-i-n-i-u-m/bc4b1ff265b277dbf195)
- Updated script: [gist.github.com/pgaulon/3a844a626458f56903d88c5bb1463cc6](https://gist.github.com/pgaulon/3a844a626458f56903d88c5bb1463cc6)
- Reference: [github.com/dabendan2/freenom-dns](https://github.com/dabendan2/freenom-dns) (npm)
- Reference: [github.com/patrikx3/freenom](https://github.com/patrikx3/freenom) (npm)

## Changes

See [CHANGES.md](CHANGES.md)
