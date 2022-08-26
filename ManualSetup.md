# Manual Setup

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
ln -s /path/to/systemd/freenom-renew-all.service /etc/systemd/user/timers.target.wants/freenom-renew-all.service
ln -s /path/to/systemd/freenom-update@.service /etc/systemd/user/timers.target.wants/freenom-update@example.tk.service:

# (optional) to renew a specific domain, replace freenom-renew-all by:
ln -s /path/to/systemd/freenom-renew@.service /etc/systemd/user/timers.target.wants/freenom-renew@example.tk.service

# then reload systemd:
systemctl daemon-reload
```

In case of any errors make sure you're using the correct paths and "freenom.conf" is setup. Check `systemctl status <unit>` and logs.

###### Note: to use 'user mode' instead of system mode replace "/system" by "/user" and use 'systemctl --user'
