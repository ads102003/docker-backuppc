# BackupPC (revived fork of tiredofit/docker-backuppc)

The upstream project [tiredofit/docker-backuppc](https://github.com/tiredofit/docker-backuppc) is archived and its
images (including the `tiredofit/nginx` / `tiredofit/alpine` base images it was built on) are no longer published.
This fork rebuilds the same BackupPC 4.4.0 stack on plain `alpine` so an existing BackupPC pool and config can be
mounted again, mainly to get data back off an old machine.

It keeps the same volume paths, so an old `docker-compose.yml` should only need its `image:` line changed.

## Getting the image

Images are built by GitHub Actions and pushed to the GitHub Container Registry:

```bash
docker pull ghcr.io/ads102003/docker-backuppc:latest
```

Or build it yourself with `docker build -t backuppc .`

## Configuration


### Quick Start

- The quickest way to get started is using [docker-compose](https://docs.docker.com/compose/). See the examples folder for a working [docker-compose.yml](examples/docker-compose.yml) that can be modified for development or production use.

- Set various [environment variables](#environment-variables) to understand the capabilities of this image.
- Map [persistent storage](#data-volumes) for access to configuration and data files for backup.
- Enter inside the container and as user `backuppc` `ssh-copy-id` your public keys to a remote host
- Visit your Web interface

### Persistent Storage

The following directories are used for configuration and can be mapped for persistent storage.

| Directory           | Description                            |
| ------------------- | -------------------------------------- |
| `/etc/backuppc`     | Configuration Files                    |
| `/home/backuppc`    | Home Directory for Backuppc (SSH Keys) |
| `/var/lib/backuppc` | The backed up Data                     |
| `/www/logs`         | Logfiles for Nginx, BackupPC           |

### Environment Variables

| Variable                           | Description                                              | Default               |
| ---------------------------------- | -------------------------------------------------------- | --------------------- |
| `USER_BACKUPPC`                    | uid for the backuppc user - set to the owner of old data | `1000`                |
| `GROUP_BACKUPPC`                   | gid for the backuppc user - set to the owner of old data | `1000`                |
| `NGINX_AUTHENTICATION_TYPE`        | Set to `BASIC` to password-protect the web UI            | `NONE`                |
| `NGINX_AUTHENTICATION_TITLE`       | Basic auth realm                                         | `Please login`        |
| `NGINX_AUTHENTICATION_BASIC_USER1` | Basic auth username (increment for more users)           |                       |
| `NGINX_AUTHENTICATION_BASIC_PASS1` | Basic auth password (increment for more users)           |                       |

BackupPC is installed when the image is built, so the paths above are fixed. On start the container writes a
default config only when `/etc/backuppc` has no `config.pl`; an existing config is never modified, and the
volumes may be mounted read-only. Only the top level of the data directory is `chown`ed, so make sure
`USER_BACKUPPC`/`GROUP_BACKUPPC` match the uid/gid that owns your existing pool (`ls -ln /path/to/data`).

The upstream image's zabbix monitoring, SMTP (msmtp) and LDAP/LLNG auth options are not included.

### Networking

The following ports are exposed and available to public interfaces

| Port | Description |
| ---- | ----------- |
| `80` | HTTP        |

**NOTE**: It is highly recommended this be run through a SSL proxy, or via localhost and tunnel via SSH.

## Maintenance

### Shell Access

For debugging and maintenance purposes you may want access the containers shell.

````bash
docker exec -it (whatever your container name is) bash
````

## License
MIT. See [LICENSE](LICENSE) for more details.

# References

- http://backuppc.sourceforge.net/
- https://backuppc.github.io/backuppc/
