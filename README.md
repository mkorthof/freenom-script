# Domain Renewal and DynDNS for Freenom.com

[![Shellcheck](https://github.com/mkorthof/freenom-script/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/mkorthof/freenom-script/actions/workflows/shellcheck.yml)
[![Docker](https://github.com/mkorthof/freenom-script/actions/workflows/docker.yml/badge.svg)](https://github.com/mkorthof/freenom-script/actions/workflows/docker.yml)
[![BATS](https://github.com/mkorthof/freenom-script/actions/workflows/bats.yml/badge.svg)](https://github.com/mkorthof/freenom-script/actions/workflows/bats.yml)

## Last Update ##

***Latest version: v2022-12-17 ([CHANGES.md](CHANGES.md))***

**Make sure to add new config options when updating script**

---

This shell script makes sure your Freenom domains don't expire by auto renewing them. It can also set a DNS record with the clients ip address.

You'll need to have already registered an account at Freenom.com with at least one (free) domain added, before you can run the script.

## Usage

```shell

freenom.com Domain Renewal and DynDNS
-------------------------------------

Usage:      freenom.sh -l [-d]
            freenom.sh -r <domain OR -a> [-s <subdomain>]
            freenom.sh -u <domain> [-s <subdomain>] [-m <ip>] [-f]
            freenom.sh -z <domain>

Options:    -l    List all domains and id's in account
                  add [-d] to show renewal Details
            -r    Renew <domain> or use '-r -a' to update All
                  add [-s] to renew <Subdomain>
            -u    Update <domain> A record with current ip
                  add [-s] to update <Subdomain> record
                  add [-m <ip>] to Manually update static <ip>
                  add [-f] to Force update on unchanged ip
            -z    Zone for <domain>, shows dns records

            -4    Use ipv4 and modify A record on "-u" (default)
            -6    Use ipv6 and modify AAAA record on "-u"
            -c    Config <file> to use, instead of freenom.conf
            -i    Ip commands list, used to get current ip
            -o    Output renewals, shows html file(s)

Examples    ./freenom.sh -r example.com
            ./freenom.sh -c /etc/mycustom.conf -r -a
            ./freenom.sh -u example.com -s mail

            * When "-u" or "-r" is used with argument <domain>
              any settings in script or config file are overridden

```

## Installation

Using a full Linux distro including coreutils is recommended (e.g. Debian). Embedded and BusyBox based systems are untested and will probably not work correctly or at all.

_Note that this shell script requires recent versions of "Bash" and "cURL"_

### Auto Installer

Run: `make install` 

(from git clone directory)

This automatically installs the script, .conf file and configures scheduler.

### Manual install

Suggested installation path: "/usr/local/bin/freenom.sh"

And for the config file: "/usr/local/etc/freenom.conf"

### Docker

There's an [image](https://github.com/mkorthof/freenom-script/pkgs/container/freenom_script) available from GitHub Container Registry which you can run like this:

 `docker run --rm --env freenom_email="you@example.com" --env freenom_passwd="yourpassword" ghcr.io/mkorthof/freenom_script -l`

For more information see [Docker.md](docs/Docker.md)

## Configuration

Settings can be changed in the script itself or set in a separate config file (default). Every setting has comments with possible options and examples.

First edit config and **set your email and password** which you use to sign-in to freenom.com

- The default filename is "freenom.conf" in the same location as the script, or "/usr/local/etc/freenom.conf"
- You can also use `freenom.sh -c /path/to/file.conf`
- To optionally put config in the script itself instead: copy settings from conf file into `freenom.sh` (before "Main")

Default settings such as retries and timeouts can be changed, they are however OK to leave as-is (see [Overrides.md](docs/Overrides.md)).

### Testing

Test the script by running `freenom.sh -l` and make sure your domains are listed. To Renew domains or Update A record, see [Usage](#usage) or `freenom.sh -h`  

## Scheduling

Optionally you can schedule the script to run automatically. The installer creates "/etc/cron.d/freenom" or systemd timers in 'system mode' so the script runs at certain intervals. It will output a message with instructions on how to set your domain(s) to renew/update or renew all:

- Cron:
    - edit the created file in /etc/cron.d and uncomment line(s)
- Systemd:
    - `systemctl enable --now freenom-renew-all.timer`
    - `systemctl enable --now freenom-update@example.tk.timer`
    - `systemctl enable --now freenom-update@mysubdom.example.tk.timer`
    
_If systemd is not available on your system, the installer will use cron instead._

### Manual setup

See [Scheduling.md](docs/Scheduling.md)

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

## DynDNS

To update A or AAAA records the nameservers for the domain must be set to the default Freenom Name Servers.

The record will be added if there is none, or modified if the record already exists. Your current ip address will be used as value (aka "Target").

### IP Address

The script uses 3 methods to get your current ip address from a number of public services:

- HTTP method: `curl https://checkip.amazonaws.com`
- DNS method: `dig TXT +short o-o.myaddr.l.google.com @ns1.google.com`
- Manually: you can also set a static ip address instead of auto detect (see below)

There are a few more HTTP and DNS services defined for redundancy, the script will choose one at random. By default it will retry to get the ip 3 times.

Once your ip is found it's written to "freenom_\<domain\>.ml.ip4" (or 'ip6'). Same if freenom returns dnserror "There were no changes". This is to prevent unnecessary updates in case the ip is unchanged.
To force an update you can remove this file which is located in the default output path: "/var/log".

To manually update: set `freenom_static_ip=<your ip>` and `freenom_update_manual="1"`, or use the `-m` option.

### Issues

You need an actual freenom account, as Social Sign-in will not work. Workaround: use password reset, see [KB](https://my.freenom.com/knowledgebase.php?action=displayarticle&id=27) and issue [#56](https://github.com/mkorthof/freenom-script/issues/56).

Make sure 'curl' and/or 'dig' is installed (e.g. debian: dnsutils or redhat: bind-utils). In case of issues try running curl and dig command manually.

- To list all 'get ip' commands run `freenom.sh -i` (or `grep getIp freenom.conf`)
- To disable IPv6: set `freenom_update_ipv="4"`
- To disable dig: set `freenom_update_dig="0"`

## Files

- Installer: Makefile (`make install`)
- Script/config: `freenom.sh` and `freenom.conf`
- Output:
  - Path: `"/var/log/freenom/"` (default)
  - Files: `freenom.log`, `freenom_<domain>.ip{4,6}`, `freenom_renewalResult-<id>.html`
- View Results: use `freenom.sh -o` to view html files
  
Also see comment "Output files" and `freenom_out_dir` variable in conf.

### Updating

Usually you can just replace "freenom.sh" with the new version, if you're using a separate config file.

An exception is when config options were added/changed which you may need to compare and merge. Such config changes are listed in [CHANGES.md](CHANGES.md).

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
