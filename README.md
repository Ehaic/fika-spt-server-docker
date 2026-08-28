# fika-spt-server-docker
🐳 Clean and easy way to run SPT + Fika server in docker, with auto-updates, profile backups, and the flexibility to modify server files as you wish 🐳

# 🤔 Why?
Existing SPT Dockerfiles seem to leave everything, including building the image with the right sources, up to the user to manage.
This image aims to provide a fully pre-packaged SPT Docker image with optional Fika mod that is as plug-and-play as possible. All you need is
- A working docker installation
- A directory to contain your serverfiles, or an existing server directory.

That's it! The image has everything else you need to run an SPT Server, with Fika if desired.

> [!WARNING]
> With the release of SPT 4.0.0 and the rewrite to use C#, this image going forward will no longer support prior versions due to a significant change in how the image operates.
>
> If you wish to use the LTS version of SPT (3.11.4), make sure you specify the image tag `fika-spt-server-docker:3.11.4` explicitly instead of using `latest`)

> [!WARNING]
> For users attempting to run version 4.0.0 of this docker image on ARM64 platform (i.e. Raspberry Pi), please note that this image will fail to run currently.
> Please see [this issue](https://github.com/zhliau/fika-spt-server-docker/issues/33) for more information

- [🪄 Features](#-features)
- [🥡 Releases](#-releases)
- [🛫 Running](#-running)
  * [docker](#docker)
  * [docker-compose](#docker-compose)
  * [Using an existing installation](#using-an-existing-installation)
  * [Updating SPT/Fika versions](#updating-sptfika-versions)
    + [When Fika server mod is updated for the same SPT version](#when-fika-server-mod-is-updated-for-the-same-spt-version)
    + [When SPT updates](#when-spt-updates)
    + [(NEW FOR SPT 4.0) Forcing SPT Version](#new-for-spt-40-forcing-spt-versions)
  * [Automatically download & install additional mods](#automatically-download--install-additional-mods)
  * [Time Zone Support](#time-zone)
- [🌐 Environment Variables](#-environment-variables)
- [💬 FAQ](#-faq)
  * [Why are there files owned by root in my server files?](#why-are-there-files-owned-by-root-in-my-server-files)
  * [Can I use this without Fika?](#can-i-use-this-without-fika)
  * [I am running this container on Linux, why does the server output show errors regarding Windows-like paths?](#i-am-running-this-container-on-linux-why-does-the-server-output-show-errors-regarding-windows-like-paths-eg-csnapshot)
  * [Server starts but I cannot connect to it](#the-server-starts-but-i-cannot-connect-to-it-and-it-doesnt-seem-to-be-listening-on-port-6969)
- [💻 Development](#-development)
  * [Building](#building)



# 🪄 Features
- 📦 Prepackaged images versioned by SPT version e.g. `fika-spt-server-docker:4.0.13` for SPT `4.0.13`. Images are hosted in ghcr and come prebuilt with a working SPT server binary, and the latest compatible Fika servermod is downloaded and installed on container startup if enabled.
- 🏗️ Multi-architecture support: Native builds for both AMD64 and ARM64 (Raspberry Pi, Apple Silicon, etc.)
- ♻️ Reuse an existing installation of SPT! Just mount your existing SPT server folder
- 💾 Automatic profile backups by default! Profiles are copied to a backup folder every day at 00:00 UTC
- 🔒 Configurable running user and ownership of server files. Control file ownership from the host, or let the container set ownership and permissions to ease permissions issues.
- ⬆️ Optionally auto updates SPT or Fika if we detect a version mismatch between container expected version and installed version
- ⬇️ Optionally auto download and install additional mods

# 🥡 Releases
The image build is triggered off release tags and hosted on ghcr
```
docker pull ghcr.io/zhliau/fika-spt-server-docker:4.0.13
```
Check the pane on the right for the different version tags available, if you don't want to use the latest SPT release.

# 🛫 Running
### docker
```
docker run --name fika-server \
  -e FIKA_MODE=install \
  -e LISTEN_ALL_NETWORKS=true \
  -v /path/to/server/files:/opt/server \
  -p 6969:6969 \
  ghcr.io/zhliau/fika-spt-server-docker:4.0.13
```

### docker-compose
See the example docker-compose for a more complete definition.

Minimal usage
```yaml
services:
  fika-server:
    image: ghcr.io/zhliau/fika-spt-server-docker:latest
    environment:
      - FIKA_MODE=install
      # This will automatically set SPT server's configs to work in a containerized environment
      - LISTEN_ALL_NETWORKS=true
    ports:
      - 6969:6969
    volumes:
      # Set this to an empty directory, or a directory containing your existing SPT server files
      - ./path/to/server/files:/opt/server
```

If you want to run the server as a different user than root, set UID and GID
```yaml
services:
  fika-server:
    image: ghcr.io/zhliau/fika-spt-server-docker:latest
    # ...
    environment:
      # Provide the uid/gid of the user to run the server, or it will default to 0 (root)
      # You can get your host user's uid/gid by running the id command
      # ...
      - UID=1000
      - GID=1000
```

If you want to automatically install Fika, set `FIKA_MODE` appropriately:
```yaml
services:
  fika-server:
    image: ghcr.io/zhliau/fika-spt-server-docker:latest
    # ...
    environment:
      # ...
      - FIKA_MODE=install        # Install Fika and validate version (exit on mismatch)
      # OR
      - FIKA_MODE=auto-update    # Install Fika and auto-update on version mismatch
```

## Using an existing installation
> [!WARNING]
> MAKE BACKUPS OF YOUR EXISTING SPT SERVER FILES BEFORE YOU DO THIS.

If you want to migrate to this docker image with an existing SPT install:
- Set your volume mount to your existing SPT server directory (the dir containing the SPT.Server.exe file)
- If these existing server files were from a Windows installation, **delete** the `SPT.Server.exe` file to have the container use its own Linux-compiled binary
- If you don't have Fika yet, you can set `FIKA_MODE=install` or `FIKA_MODE=auto-update` to tell the container to install the server mod for you
- Run the container, optionally specify if you want the container to auto update the SPT server files via the `AUTO_UPDATE_SPT` env var

## Updating SPT/Fika versions
This image comes built with a copy of SPT Server, versioned by the image's version tag.
It also is set to automatically pull the appropriate Fika server mod version, if required.
Enable auto updates by setting the correct environment variables
```yaml
services:
  fika-server:
    image: ghcr.io/zhliau/fika-spt-server-docker:latest
    # ...
    environment:
      # ...
      - AUTO_UPDATE_SPT=true
      - FIKA_MODE=auto-update # Auto-update Fika server mod when version mismatches
```

### When Fika server mod is updated for the same SPT version
This image will hopefully be updated in a timely manner to the new Fika server mod version, and the image will be rebuilt with the same SPT version tag. Thus, all you will need to do is
- Pull the image again with `docker pull` or `docker-compose pull`
- Bring up the container again with `docker run` or `docker-compose up` (**NOT** `docker[-compose] restart` since this will not recreate the container)

The container will validate your Fika server mod version matches the image's expected version, and if not it will
- Back up the entire Fika server mod including configs to a `backups/fika` directory in the mounted server directory
- Install the expected fika server mod version
- Copy your old fika.jsonc config into the server mod config directory

> [!NOTE]
> The existing config is not guaranteed to work across versions. Expect to do some troubleshooting here especially if config options are added/removed in the new Fika server mod version.

### When SPT updates

> [!WARNING]
> If you've made any changes to files within `SPT_Data`, make backups! This upgrade process will remove that folder!

A new image will be tagged with the new SPT version number, and thus you will need to
- Update the image version tag e.g. `fika-spt-server-docker:3.9.8` to `fika-spt-server-docker:3.11.4`
- Pull the new image with `docker pull` or `docker-compose pull`
- Bring up the container again with `docker run` or `docker-compose up` (**NOT** `docker[-compose] restart` since this will not recreate the container)

The image will validate that your SPT version in the serverfiles matches the image's expected SPT version, and if not it will
- Back up the entire `user/` directory to a `backups/spt/` directory in the mounted server directory
- Remove the `SPT_Data` directory
- Install the right version of SPT in-place.

> [!NOTE]
> The user directory in your existing SPT server files is left untouched! Please make sure that you validate that the SPT version you are running works with your installed mods and profiles!
> You may want to start by removing all mods and validating them one by one

### (NEW for SPT 4.0+) Forcing SPT Versions
You can also force the install of a specific SPT version by supplying the `FORCE_SPT_VERSION` environment variable on container run. You must set this to a valid SPT release version, formatted as `<VERSION_NUMBER>-<EFT_BUILD_NUMBER>-<SPT_GIT_SHA>`. You can find an example of this in the SPT release archive name.

e.g
```
FORCE_SPT_VERSION=4.0.1-40087-1eacf0f
```

This will download the forced version release, and use that to update your server files.
Using this parameter will disable the SPT auto-update feature, since you will be running your container out of sync with the expected image version.

The image will use the presence of the archive as the indicator that the server version has been forced by this parameter. If you wish to reinstall the server, remove the `SPT-<VERSION_NUMBER>-<EFT_BUILD_NUMBER>-<SPT_GIT_SHA>.7z` archive in your serverfiles directory.

## Automatically download & install additional mods

The container can automatically install and update mods from the [sp-mod.com](https://sp-mod.com) registry on each boot. Just specify mod slugs and the container handles version resolution, dependency checking, downloading, and installation.

### How to use it

Set the `MODS` environment variable to a comma-separated list of mod slugs from sp-mod.com:

```yaml
environment:
  - MODS=scav-cat-trader-mod,sain,looting-bots
```

To find a mod's slug, go to its page on [sp-mod.com](https://sp-mod.com) — the slug is the last part of the URL. For example, `https://sp-mod.com/mod/31/scav-cat-trader-mod` has the slug `scav-cat-trader-mod`.

### What it does

On each container startup, before launching the SPT server:

1. **Resolves** each mod slug to the correct mod on sp-mod.com
2. **Selects** the latest version compatible with your SPT version
3. **Prefers** Fika-compatible versions when `FIKA_MODE` is not `disabled`
4. **Downloads** the mod archive and extracts it
5. **Installs** files to the correct locations (`BepInEx/plugins`, `user/mods`, server root)
6. **Tracks** installed versions in `mod_download/installed_mods.json`

Mods that are already installed at the latest compatible version are skipped.

### Mod updates

By default, mods are installed once and not updated automatically. To enable automatic updates on each boot, set `AUTO_UPDATE_MODS=true`:

```yaml
environment:
  - MODS=sain,looting-bots
  - AUTO_UPDATE_MODS=true
```

When enabled, the container checks sp-mod.com for newer compatible versions on every startup and updates any mods that have new releases.

### State and logs

- **State file:** `mod_download/installed_mods.json` — tracks installed mod IDs, versions, and install dates
- **Log file:** `mod_download/install_mods.log` — full log of each install run
- **Leftover files:** `mod_download/remains/` — any files the installer couldn't place automatically

### Notes

- Mods must be available on [sp-mod.com](https://sp-mod.com) — custom/private mods are not supported
- If a mod has no version compatible with your SPT version, it will be skipped with a warning
- Removing a mod from the `MODS` list does not uninstall it — it only stops the container from managing it

## Time Zone
By default the container uses the UTC time zone. This does not affect running the server or the files themselves but it does affect things that like the SPT Backup Service, which sets the backup folder name to the current timestamp.

If you want to change the time zone there are two methods (DO NOT USE BOTH)
- Mount `/etc/timezone` as a volume
- Set the `TZ` environment variable

### Mount `/etc/timezone` as a volume
This will match the time zone inside to the time zone of the host system.
- If using docker-compose, add `/etc/timezone:/etc/timezone:ro` under the volumes section.
- If using docker run, add `-v /etc/timezone:/etc/timezone:ro \` to the run command

### Set the `TZ` environment variable
This should be set to a TZ Identifier (see https://en.wikipedia.org/wiki/List_of_tz_database_time_zones for a list of valid TZ identifier).
- If using docker-compose, add `TZ=US/Eastern` under the `environment` section, substituting `US/Eastern` for your desired time zone.
- If using docker run, add `-e TZ=US/Eastern \` to the run command

# 🌐 Environment Variables
None of these env vars are required, but they may be useful.
| Env var                   | Default | Description                                                                                                                                                                                                                               |
| ------------------------- | ------- | -----------                                                                                                                                                                                                                               |
| `UID`                     | 1000    | The userID to use to run the server binary. This user is created in the container on runtime                                                                                                                                              |
| `GID`                     | 1000    | The groupID to assign when creating the user running the server binary. This has no effect if no UID is provided and no user is created                                                                                                   |
| `FIKA_MODE`               | disabled | Controls Fika installation and updates. Options: `disabled` (no Fika), `install` (install and validate, exit on mismatch), `auto-update` (install and auto-update on mismatch), `custom` (skip validation for custom builds)              |
| `MODS`                    | null    | Comma-separated list of mod slugs from sp-mod.com to auto-install (e.g. `sain,looting-bots`)                                                                                                                                                |
| `AUTO_UPDATE_MODS`        | false   | When `true`, checks for newer mod versions on each boot and updates automatically                                                                                                                                                          |
| `FIKA_VERSION`            | 2.2.1   | Override the fika version string to grab the server release from. The release URL is formatted as `https://github.com/project-fika/Fika-Server-CSharp/releases/download/v$FIKA_VERSION/Fika.Server.Release.$FIKA_VERSION.zip`              |
| `AUTO_UPDATE_SPT`         | false   | Whether you want the container to handle updating SPT in your existing serverfiles                                                                                                                                                        |
| ~~`INSTALL_FIKA`~~        | false   | **DEPRECATED:** Use `FIKA_MODE` instead. Set to `install` or `auto-update`                                                                                                                                                                |
| ~~`AUTO_UPDATE_FIKA`~~    | false   | **DEPRECATED:** Use `FIKA_MODE=auto-update` instead                                                                                                                                                                                       |
| `TAKE_OWNERSHIP`          | true    | If this is set to false, the container will not change file ownership of the server files. Make sure the running user has permissions to access these files                                                                               |
| `CHANGE_PERMISSIONS`      | true    | If this is set to false, the container will not change file permissions of the server files. Make sure the running user has permissions to access these files                                                                             |
| `ENABLE_PROFILE_BACKUP`   | true    | If this is set to false, the cron job that handles profile backups will not be enabled                                                                                                                                                    |
| `LISTEN_ALL_NETWORKS`     | false   | If you want to automatically set the SPT server IP addresses to allow it to listen on all network interfaces                                                                                                                              |
| `TZ`                      | null    | Set the desired time zone. See the `Timezone` section above for details                                                                                                                                                                   |
| `NUM_HEADLESS_PROFILES`   | null    | Set the desired number of headless profiles for the Fika server to auto-generate. This must be an integer. This will only work if the `fika.jsonc` config file exists, the server automatically generates one on startup if it is missing |
| `FORCE_SPT_VERSION`       | null    | Force a specific SPT version for this image. The version string should look like `<VERSION_NUMBER>-<EFT_BUILD_NUMBER>-<SPT_GIT_SHA>` e.g. `4.0.1-40087-1eacf0f`. You can see an example of this in the naming of the SPT release archive. |


# 💬 FAQ
### Why are there files owned by root in my server files?
If you don't want the root user to run SPT server, make sure you provide a userID/groupID to the image to use to run the server.
If none are provided, it defaults to uid 0 which is the root user.
Running the server with root will mean anything the server writes out is created by the root user.

### Can I use this without Fika?
Yes! Either don't set `FIKA_MODE` (it defaults to `disabled`) or explicitly set `FIKA_MODE=disabled`. The container will act as an ordinary SPT server container. Everything else including the autoupdate capability for SPT remains unchanged.

### Can I use custom Fika builds?
Yes! If you want to use a custom or modified Fika build instead of the official releases:

1. Set `FIKA_MODE=custom` to prevent the container from validating or updating your Fika installation
2. Manually place your custom Fika build in the `SPT/user/mods/fika-server` directory

The container will skip all Fika version checks and use whatever version you've manually installed.

### I am running this container on Linux, why does the server output show errors regarding Windows-like paths? e.g. `C:\snapshot\...`.
If you are reusing an existing SPT server that was previously running on Windows, you will need to delete the contents of your `/user/cache` folder.

### The server starts, but I cannot connect to it, and it doesn't seem to be listening on port 6969?
Set the environment variable `LISTEN_ALL_NETWORKS` to `true` and restart the container.

This will change the values of `ip` and `backendIp` in `SPT_Data/Server/configs/http.json` to `0.0.0.0`, which tells the SPT server to listen on all network interfaces. If you want to do this manually, the file should look similar to this:
```json
{
    "ip": "0.0.0.0",
    "port": 6969,
    "backendIp": "0.0.0.0",
    "backendPort": 6969,
    "webSocketPingDelayMs": 90000,
    "logRequests": true,
    "serverImagePathOverride": {}
}
```

# 💻 Development

### Version Automation

This project includes automated version tracking for SPT and Fika

The GitHub Actions workflow automatically checks for new versions daily and creates PRs when updates are available.

### Pre-commit Hooks
This project uses pre-commit hooks to maintain code quality. The hooks automatically:
- Remove trailing whitespace
- Fix end of file issues
- Check YAML syntax
- Prevent large files from being committed
- Fix mixed line endings

To set up pre-commit hooks:
```bash
# Create a virtual environment and install pre-commit
python -m venv .venv
.venv/bin/pip install pre-commit

# Install the git hooks
.venv/bin/pre-commit install

# Run on all files to verify
.venv/bin/pre-commit run --all-files
```

Once installed, the hooks will run automatically on every commit.

### Building
> [!WARNING]
> As of SPT version 4.0.0, these instructions are deprecated because we use precompiled server binaries
> In the future, I will implement building the server from source to support unreleased git tags

You can overwrite the expected SPT version by setting the `SPT_SHA` build arg. This must correspond with a git ref (tag or branch) in the
SPT Server github repo. This version must be a release [semver](https://semver.org/) value, or a pre-release ref like `3.11.4-dev`
The value is checked against the `sptVersion` value in `SPT_Data/Server/configs/core.json` when validating the SPT version on container boot. If using a pre-release version tag,
everything including and after the `-` is dropped when comparing version strings.

You can similarly override the Fika version by setting the `FIKA_VERSION` build arg. Make sure this matches the Fika version slug in the Fika Server download URL.

The URL will look like `https://github.com/project-fika/Fika-Server/releases/download/<FIKA_VERSION>/fika-server-<FIKA_VERSION_WITHOUT_V>.zip`

```bash
# Server binary built using SPT Server 3.11.4 git tag, image tagged as fika-spt-server:latest
# Downloads and validates Fika version v2.4.8

VERSION=latest FIKA_VERSION=v2.4.8 SPT_SHA=3.11.4 ./build
```
