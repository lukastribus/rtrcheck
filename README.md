# rtrcheck

rtrcheck is a shell script to monitor RTR servers ([RFC6810](https://tools.ietf.org/html/rfc6810) and [RFC8210](https://tools.ietf.org/html/rfc8210)).

It compares the RTR serial number and data (binary comparison of jq data output) with a previous run and returns zero (success) when both serial and data have changed. Otherwise it returns various nagios-friendly non-zero exit codes and prints errors on stderr. It will not print any informational outputs, unless the `-v` argument is used, so it's cronjob friendly.


## Table of contents
<!--ts-->
   * [rtrcheck](#rtrcheck)
      * [Table of contents](#table-of-contents)
      * [Requirements](#requirements)
      * [Installation](#installation)
      * [Arguments](#arguments)
      * [Return codes (nagios-friendly):](#return-codes-nagios-friendly)
      * [Output example](#output-example)
      * [Cronjobs](#cronjobs)
      * [Nagios](#nagios)
      * [FAQ](#faq)
         * [CRITICAL: RTR serial X stale!](#critical-rtr-serial-x-stale)
         * [jq: error: Could not open file](#jq-error-could-not-open-file)
         * [WARNING: RTR serial DECREASED from X to Y!](#warning-rtr-serial-decreased-from-x-to-y)
         * [No serial found in FILE, assuming zero](#no-serial-found-in-file-assuming-zero)
         * [RTR serial is all over the place (instead of steadily increasing)](#rtr-serial-is-all-over-the-place-instead-of-steadily-increasing)
      * [development goals](#development-goals)
<!--te-->

## Requirements
* [jq](https://stedolan.github.io/jq/)
* rtrdump [Cloudflare's GoRTR project](https://github.com/cloudflare/gortr) 


## Installation
* install jq and rtrdump (you can get amd64 binaries for linux/libc from both projects directly if you can't find it in your OS repositories)
* download the rtrcheck script and chmod +x 'it (and of course always double check what you are downloading before executing it):

```
wget https://raw.githubusercontent.com/lukastribus/rtrcheck/master/rtrcheck -qO /usr/local/bin/rtrcheck && chmod +x /usr/local/bin/rtrcheck
```


## Arguments

* `-c <HOST:PORT> / RTRCHK_CONNECT=<HOST:PORT>` : it's required to specify the destination host and port wit the -c argument or the RTRCHK_CONNECT environment variable, e.g.
  * `rtrcheck -c 127.0.0.1:323`
  * `RTRCHK_CONNECT=127.0.0.1:323 rtrcheck`
* `-r <rtr-args> / RTRCHK_RTRDUMP_OPT=<rtr-args>` : additional parameters to pass to rtrdump, required for SSH or TLS access. Do not pass `-connect`, `-loglevel` or `-file`.
* `-w <dir> / RTRCHK_WRK_DIR=<dir>` : use this directory instead of the current working directory
* `-i / RTRCHK_IGN_DCR=1` : ignore RTR serial decrease (e.g. when a RTR servers restarts)
* `-n / RTRCHK_SERIALONLY` : ignore data, just compare RTR serial number
* `-y <MIN>/ RTRCHK_YOUNGERTHN` : abort if last run was less than `<MIN>` ago, exit 3 (UNKNOWN)
* `-v / RTRCHK_VERBOSE` : generate informational output on stdout before returning success


## Return codes (nagios-friendly):
* returns 0 : OK, RTR serial increased and data changed (unless `-n`)
* returns 1 : WARNING, RTR serial decreased (unless `-i`)
* returns 2 : CRITICAL, RTR serial or data was the same (stale data), or rtrdump failure
* returns 3 : UNKNOWN, other errors


## Output example

```
~$ RTRCHK_CONNECT=localhost:323 ./rtrcheck -v
SUCCESS: RTR serial changed from 13 to 19, VRPs changed also.
~$ echo $?
0
~$ RTRCHK_CONNECT=localhost:323 ./rtrcheck -v
CRITICAL: RTR serial 19 stale!
~$ echo $?
2
~$
```

So you can `&&` to execute a command when everything is good:
```
rtrcheck && <all good>
```

Or `||` for problems:
```
rtrcheck || <something wrong>
```


## Cronjobs

The amount of time between consecutive rtrcheck runs needs to be longer than the time between consecutive validation runs. For example, if RPKI validation runs every 20 minutes, you could run rtrcheck hourly, leaving enough time for longer than usual validation runs. Setup accordingly.

rtrcheck works fine in a cronjob, no external tooling is necessary, as there is no output by default. Errors will then be mailed (requires [working mail setup](https://lost-carrier.org/proper-email-setup-on-debian-ubuntu/) of course):

`/etc/rtrcheck.conf` would contain the environment variables parameters for rtrcheck:
```
export RTRCHK_CONNECT="rpki1.example.org:22"
export RTRCHK_RTRDUMP_OPT="-type ssh -ssh.method password -ssh.auth.user rpki -ssh.auth.password SecretSshPW"
export RTRCHK_WRK_DIR="/var/rtrcheck/"
```

Which will be sourced before executing rtrcheck:
```
MAILTO=rtrcheck-reports@example.org
5 * * * * . "/etc/rtrcheck.conf" && /usr/local/bin/rtrcheck
```

For a healthchecks.io ping on success just:
```
MAILTO=rtrcheck-reports@example.org
5 * * * * . "/etc/rtrcheck.conf" && /usr/local/bin/rtrcheck && curl -fsSm10 --retry 5 -o /dev/null "https://hc-ping.com/<GUID>"
```

Or if you want to send error and success outputs to healthchecks.io (not using's local mail), use a wrapper script:
```
~$ crontab -l
~5 * * * * . "/etc/rtrcheck.conf" && /usr/local/bin/rtrcheck-healthchecksio-wrapper
~$
cat /usr/local/bin/rtrcheck-healthchecksio-wrapper
#!/usr/bin/env sh
#
# healthchecks.io report based on return code, replace <GUID>

PINGIOURL="curl -fsSm10 --retry 5 -o /dev/null https://hc-ping.com/<GUID>"

if OUT=$(/usr/local/bin/rtrcheck -v 2>&1) ; then
  $PINGIOURL --data-raw "$OUT"
else
  $PINGIOURL/fail --data-raw "$OUT"
fi
```

## Nagios

This can be used as a nagios plugin. Return codes are what nagios expects.

Some suggestions:
* nagios service settings
  * `max_check_attempts`: 1 (avoid running multiple times)
  * `check_interval`: see [Cronjobs](#cronjobs)
  * `retry_interval`: see [Cronjobs](#cronjobs)
* use verbose mode (`-v`), so you get RTR serial increase outputs
* nagios is a complex beast, it may call rtrcheck with smaller intervals anyway, use something like `-y55` to abort the check (`UNKNOWN`) when this happens
* you could use an environment variable file for the global settings (working directory, rtrdump options like SSH credentials) and source it before the check, just like in the see [Cronjobs](#cronjobs) example

## FAQ

### CRITICAL: RTR serial X stale!

Enough time has to pass between rtrcheck runs. If your validator runs multiple times an hour, you can run rtrcheck once an hour. But the closer you are to the validation interval, the easier it is to get the same RTR serial twice. RPKI validation time itself also varies, so keep a large enough margin to account for all this.

Running rtrcheck with an interval of less than one hour is discouraged for those reasons. If the caller is unreliable (calls rtrcheck sooner than expected), use `-y` argument to abort the check (return code 3 / nagios: `UNKNOWN`), e.g. `-y55`.

### jq: error: Could not open file

Previous data is not available for comparison; most likely this is the first run (and expected in that case).

### WARNING: RTR serial DECREASED from X to Y!

The RTR serial actually decreased; this is most likely caused by a RTR server restart.

### No serial found in FILE, assuming zero

This verbose output means that a serial field was empty or non-existing, zero is therefor assumed. This is caused by [rtrdump omitting zero in JSON](https://github.com/cloudflare/gortr/issues/83).

### RTR serial is all over the place (instead of steadily increasing)

```
~$ ./rtrcheck -c rtr.rpki.cloudflare.com:8282
WARNING: RTR serial DECREASED from 1368 to 255!
~$ ./rtrcheck -c rtr.rpki.cloudflare.com:8282 -v
SUCCESS: RTR serial changed from 255 to 1368, VRPs changed also.
~$ ./rtrcheck -c rtr.rpki.cloudflare.com:8282 -v
WARNING: RTR serial DECREASED from 1368 to 95!
~$ ./rtrcheck -c rtr.rpki.cloudflare.com:8282 -v
SUCCESS: RTR serial changed from 95 to 255, VRPs changed also.
~$ ./rtrcheck -c rtr.rpki.cloudflare.com:8282 -v
SUCCESS: RTR serial changed from 255 to 773, VRPs changed also.
~$ ./rtrcheck -c rtr.rpki.cloudflare.com:8282 -v
SUCCESS: RTR serial changed from 773 to 981, VRPs changed also.
~$ ./rtrcheck -c rtr.rpki.cloudflare.com:8282 -v
WARNING: RTR serial DECREASED from 981 to 773!
~$ ./rtrcheck -c rtr.rpki.cloudflare.com:8282 -v
WARNING: RTR serial DECREASED from 773 to 256!
~$
```

You can't monitor load-balanced RTR servers (multiple RTR servers behind the host:port), because the RTR serial number is only locally relevant (it will also reset on server restart).

Cloudflare load-balances single TCP connections to different servers, so RTR serial monitoring cannot work in this case.


From a monitoring perspective, it doesn't make sense to monitor a load-balanced endpoint either; you need to monitor single backend servers directly.


## development goals

* basic shell only, no bashism
* shellcheck tested
* exit on failure with appriopiate nagios-friendly exit codes
* and of course [KISS](https://en.wikipedia.org/wiki/KISS_principle)
