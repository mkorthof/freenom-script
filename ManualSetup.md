# Scheduling

## Manually setup cron

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

## Manually setup systemd

Add one or more "[timer(s)](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)"

Thanks to [@sdcloudt](https://github.com/sdcloudt) you can use the template units from the [systemd](systemd) dir.

1) Copy files from repo to: "/lib/systemd/system"

2) Create a service instance for your domain(s) by creating symlinks (or use `systemctl enable`, [see above](https://github.com/mkorthof/freenom-script#Scheduling))

3) Reload systemd

#### Example

``` bash
# Create symlinks:

mkdir /path/to/systemd/timers.target.wants
ln -s /path/to/systemd/freenom-renew-all.service /etc/systemd/user/timers.target.wants/freenom-renew-all.service
ln -s /path/to/systemd/freenom-update@.service /etc/systemd/user/timers.target.wants/freenom-update@example.tk.service:

# (optional) to renew a specific domain, replace freenom-renew-all by:
ln -s /path/to/systemd/freenom-renew@.service /etc/systemd/user/timers.target.wants/freenom-renew@example.tk.service

# then reload systemd:
systemctl daemon-reload
```

In case of any errors make sure you're using the correct paths and "freenom.conf" is setup. Check `systemctl status <unit>` and logs.

###### Note: to use 'user mode' instead of system mode replace "/system" by "/user" and use 'systemctl --user'
