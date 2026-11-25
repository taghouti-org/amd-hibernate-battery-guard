# Hibernate that silently fails and drains the battery (AMD laptops, systemd)

Found and fixed on a **ThinkPad T14 Gen 5 (Ryzen 7 PRO 8840U, Radeon 780M)**, Kubuntu 26.04, kernel 7.0 OEM, with suspend-then-hibernate to a swap file. Likely relevant to other AMD laptops.

## Symptom

You close the lid on battery, and some time later the laptop is warm and **dead at 0%**, even though it was supposed to hibernate. The journal shows a loop of failed sleep attempts every ~2 minutes:

```
Freezing user space processes failed after 20.004 seconds (3 tasks refusing to freeze)
task:kwin_wayland state:D ...  amdgpu_vm_wait_idle ...
Failed to freeze unit 'user.slice': Connection timed out
Failed to put system to sleep. System resumed again: Device or resource busy
```

## Root cause

1. Hibernate writes the image, then tries to enter ACPI S4 ("platform" mode).
2. A wakeup event (lid, external display) aborts S4 entry, so the machine **resumes in place without ever powering off**.
3. On that path amdgpu hangs about 3 s later: `ring sdma0 timeout` → `Mode2 reset failed` → `GPU Recovery Failed: -5`.
4. kwin and plasmashell are stuck in D state (uninterruptible) waiting on the dead GPU, so they can't be frozen and **every later suspend or hibernate fails**. logind keeps retrying the lid-closed action until the battery is empty.

A real power-off followed by a restore never triggered the hang.

**How to tell if you're affected:** `PM: Image saving done` appears in the **same boot** as `returned from sleep operation 'hibernate'`.

```sh
journalctl --since -30d -o short-iso | grep -E "Image saving done|returned from sleep operation 'hibernate'|ring sdma0 timeout|GPU Recovery Failed"
```

## Fix and safety nets

| File | Installs to | What it does |
|---|---|---|
| `hibernate-mode.conf` | `/etc/systemd/sleep.conf.d/` | `HibernateMode=shutdown`: power off after writing the image instead of entering S4, so a wakeup can't abort it. **Trade-off:** only the power button resumes from hibernate. |
| `battery-guard.sh` + `.service` + `.timer` | `/usr/local/sbin/`, `/etc/systemd/system/` | Every minute: if the battery is discharging and at or below 2% (`BATTERY_GUARD_LIMIT`), run `systemctl poweroff`. A clean shutdown instead of a dead battery if sleep ever fails again. |
| `resume-health-check.sh` | `/usr/lib/systemd/system-sleep/` | 20 s after every resume, checks the kernel log and shows a critical desktop notification if the GPU failed to recover, or if the firmware faulted and the kernel disabled EFI runtime services (another resume bug seen on this BIOS). |
| *(optional)* charge limit | `/etc/tmpfiles.d/battery-charge-limit.conf` | Caps charging (e.g. 75–80%) for battery longevity. |

## Install

```sh
git clone https://gist.github.com/e13d840343614c2e285331490783a2a4.git hibernate-fix && cd hibernate-fix
sudo sh install.sh                      # fix + safety nets
sudo sh install.sh --charge-limit 80    # same, plus 75–80% charge limit
sudo sh install.sh --uninstall          # remove everything
```

Check that it took effect: `cat /sys/power/disk` should show `[shutdown]` during a hibernate, `systemctl list-timers battery-guard.timer` should list the timer, and any warnings are logged with `journalctl -t resume-health-check -t battery-guard`.

Requires systemd and `notify-send` (libnotify) for the warnings. Tested on Kubuntu 26.04 / Plasma 6.6 Wayland / systemd 259. No warranty; read the scripts before running them.

---

First published as a [gist](https://gist.github.com/taghouttarek/e13d840343614c2e285331490783a2a4).
