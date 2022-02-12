# Domain Renewal and DynDNS for Freenom.com

[![Shellcheck](https://github.com/mkorthof/freenom-script/actions/workflows/main.yml/badge.svg)](https://github.com/mkorthof/freenom-script/actions/workflows/main.yml)

## Last Update ##

***Latest version: v2022-01-08 ([CHANGES.md](CHANGES.md))***

**Make sure to add new config options when updating script**

---

This shell script makes sure your Freenom domains don't expire by auto renewing them.
It's original functionality of updating an A record with the clients ip address is also retained.

You'll need to have already registered an account at Freenom.com with at least one (free) domain added, before you can run the script.

## Usage

```shell

FREENOM.COM DOMAIN RENEWAL AND DYNDNS
=====================================

USAGE:
            freenom.sh -l [-d]
            freenom.sh -r <domain OR -a> [-s <subdomain>]
            freenom.sh -u <domain> [-s <subdomain>] [-m <ip>] [-f]
            freenom.sh -z <domain>

OPTIONS:
            -l    List all domains with id's in account
                  add [-d] to show renewal Details
            -r    Renew <domain> or use '-r -a' to update All
                  use [-s] with -r to update subdomains
            -u    Update <domain> A record with current ip
                  add [-s] to update <Subdomain> record
                  add [-m <ip>] to Manually update static <ip>
                  add [-f] to Force update on unchanged ip
            -z    Zone listing dns records for <domain>

            -4    Use ipv4 and modify A record on "-u" (default)
            -6    Use ipv6 and modify AAAA record on "-u"
            -c    Config <file> to be used instead freenom.conf
            -i    Ip commands list used to get current ip
            -o    Output renewals result html file(s)

EXAMPLES:
            ./freenom.sh -r example.com
            ./freenom.sh -c /etc/mycustom.conf -r -a
            ./freenom.sh -u example.com -s mail

NOTES:
            Using "-u" or "-r" and specifying <domain> as argument
            will override any settings in script or config file

```

## Installation

_Note that this shell script requires recent versions of "Bash" and "cURL"_

### Auto Installer

Run `make install` from git clone directory to automatically install the script, conf file and to configure scheduler.

### Manual install

Suggested installation path: "/usr/local/bin"

And for the config file: "/usr/local/etc" 

## Configuration

Settings can be changed in the script itself or set in a seperate config file (default). Every setting has comments with possible options and examples.

First edit config and **set your email and password** which you use to sign-in to freenom.com

- The default filename is "freenom.conf" in the same location as the script or "/usr/local/etc/freenom.conf"
- You can also use `freenom.sh -c /path/to/file.conf`
- To optionally put config in the script itself instead: copy settings from conf into `freenom.sh` (before "Main")

### Testing

Test the script by running `freenom.sh -l` and make sure your domains are listed. To update A record or Renew domains, see [Usage](#usage) or `freenom.sh -h`  

## Scheduling

Optionally you can schedule the script to run automatically. The installer creates "/etc/cron.d/freenom" or systemd timers in 'system mode' so the script runs at certain intervals. It will output a message with instructions on how to set your domain(s) to renew/update or renew all:

- Cron:
    - edit the created file, uncomment line(s)
- Systemd:
    - `systemctl enable --now freenom-renew-all.timer`
    - `systemctl enable --now freenom-update@example.tk.timer`
    - `systemctl enable --now freenom-update@mysubdom.xample.tk.timer`
    _If systemd is not available on your system the installer will use cron instead._

### Manually setup cron

Steps:

1) Copy [cron.d/freenom](cron.d/freenom) from repo to "/etc/cron.d/freenom"
2) Edit file to specify domain(s)

#### Example

``` bash
0 9 * * 0 root bash -c 'sleep $((RANDOM \% 60))m; /usr/local/bin/freenom.sh -r -a'
0 * * * * root bash -c 'sleep $((RANDOM \% 15))m; /usr/local/bin/freenom.sh -u example.tk'
0 * * * * root bash -c 'sleep $((RANDOM \% 15))m; /usr/local/bin/freenom.sh -u example.tk -s mysubdom'
```

This first line in this example will run the script with "renew all domains" options every week on Sunday between 9.00 and 10.00

The second line updates the A record of `example.tk` with the current client ip address, at hourly intervals

### Manually setup systemd

Add one or more "[timer(s)](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)"

Thanks to [@sdcloudt](https://github.com/sdcloudt) you can use the template units from the [systemd](systemd) dir.

1) Copy files from repo to: "/lib/systemd/system"

2) Create a service instance for your domain(s) by creating symlinks (or use `systemctl enable`, [see above](https://github.com/mkorthof/freenom-script#Scheduling))

3) Reload systemd

#### Example

``` bash
# Create symlinks:

mkdir /path/to/systemd/timers.target.wants
ln -s /path/to/systemd/freenom-renew@.service /etc/systemd/user/timers.target.wants/freenom-renew@example.tk.service
ln -s /path/to/systemd/freenom-update@.service /etc/systemd/user/timers.target.wants/freenom-update@example.tk.service:

# (optional) to renew a specific domain, replace freenom-renew-all by:
ln -s /path/to/systemd/freenom-renew-all.service /etc/systemd/user/timers.target.wants/freenom-renew-all.service

# then reload systemd:
systemctl daemon-reload
```

In case of any errors make sure you're using the correct paths and "freenom.conf" is setup. Check `systemctl status <unit>` and logs.

###### Note: to use 'user mode' instead of system mode replace "/system" by "/user" and use 'systemctl --user'

## Notifications

### Email

To enable email alerts, make sure `MTA` is set; the default is `/usr/sbin/sendmail`. Emails will be sent on renewal or update errors. If you do not have/want an MTA installed you could use [bashmail](https://git.io/JJdto) instead.

If you want to receive the alerts on a different email address than `freenom_email` set `RCPTTO`. You can also set an optional "From" address: `MAILFROM="Freenom Script <freenom-script@example.tk>"`

Leaving `MTA` empty or commented disables alerts.

### Apprise

Uses external lib to send notification to many services like Telegram, Discord, Slack, Amazon SNS, MS Teams etc.

To enable [Apprise](https://github.com/caronc/apprise) notifications, make sure `APPRISE` is set to the location where you installed the Apprise CLI; the default is `/usr/local/bin/apprise`. You must also set the `APPRISE_SERVER_URLS` array to contain one or more server URLs. Notifications are sent to all of the listed server URLs. As with email notifications, Apprise notifications are sent on renewal or update errors.

For details on how to construct server URLs, refer to [supported notifications](https://github.com/caronc/apprise#supported-notifications).

Leaving the `APPRISE_SERVER_URLS` array empty disables Apprise notifications.

## Optional Overrides

Default settings such as retries and timeouts can be changed in config, they are however OK to leave as-is.

See [Overrides.md](Overrides.md)

## DynDNS

To update A or AAAA records the nameservers for the domain must be set to the default Freenom Name Servers.

- As value your current ip address will be used ("Target")
- An record will be added if there is none or modified if the record already exists

### IP Address

To get your current ip address from a number of public services the script uses 3 methods:

- HTTP method: `curl https://checkip.amazonaws.com`
- DNS method: `dig TXT +short o-o.myaddr.l.google.com @ns1.google.com`
- Manually: you can set a static ip address instead of auto detect

There are a few more services defined for redundancy, the script will choose one at random. By default it will retry 3 times to get ip.

Once your ip is found it's written to "freenom.ip4.domain.lock" (or 'ip6') to prevent unnecessary updates in case the ip is unchanged.
To force an update you can remove this file which is located in the default output path: "/var/log".

To manually update: set `freenom_static_ip=<your ip>` and `freenom_update_manual="1"`, or use the `-m` option.

### Issues

Make sure 'curl' and/or 'dig' is installed (e.g. debian: dnsutils or redhat: bind-utils)

In case of issues try running curl and dig command manually.

- To list all 'get ip' commands run `freenom.sh -i` (or `grep getIp freenom.conf`)
- To disable IPv6: set `freenom_update_ipv="4"`
- To disable dig: set `freenom_update_dig="0"`

## Files

- **Installer:** `Makefile`
- **Script/cfg:** `freenom.sh` and `freenom.conf`
- **Output:**
  - Path: `"/var/log/freenom/"` (default)
  - Files: `freenom.log`, `freenom_<domain>.ip{4,6}`, `freenom_renewalResult-<id>.html`
- **View details:** use `freenom.sh -o` to view Result html files
  
Also see comment "Output files" and `freenom_out_dir` variable in conf.

### Updating

Usually you can just replace "freenom.sh" with the new version, if you're using a seperate config file.

An exeption is when config options were added/changed which you may need to compare and merge. Such config changes are listed in [CHANGES.md](CHANGES.md).

### Uninstall

Run `make uninstall`.

You can also manually reverse the steps under [Installation](#installation) above (e.g. remove .sh, .conf and scheduler files).

## Sources

See included [orig](orig) dir

- Original script: [gist.github.com/a-c-t-i-n-i-u-m/bc4b1ff265b277dbf195](https://gist.github.com/a-c-t-i-n-i-u-m/bc4b1ff265b277dbf195)
- Updated script: [gist.github.com/pgaulon/3a844a626458f56903d88c5bb1463cc6](https://gist.github.com/pgaulon/3a844a626458f56903d88c5bb1463cc6)
- Reference: [github.com/dabendan2/freenom-dns](https://github.com/dabendan2/freenom-dns) (nodejs/npm)
- Reference: [github.com/patrikx3/freenom](https://github.com/patrikx3/freenom) (nodejs/npm)

## Changes

See [CHANGES.md](CHANGES.md)
