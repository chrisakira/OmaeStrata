# OmaeStrata

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

Watch a Strata LLM server from the Omarchy bar — start or stop it, see the model, tok/s, host load, and GPU stats. Works over SSH or on the same machine. NVIDIA and AMD.

<p align="center">
  <img src="preview.png" alt="OmaeStrata panel: IQ3_S online, generation and prefill rates, host CPU/RAM/disk, two P100 GPUs" width="362" />
</p>

## Install

On Omarchy 4, clone and run the installer. It asks whether Strata is local or remote, then the paths:

```sh
git clone https://github.com/chrisakira/OmaeStrata.git
cd OmaeStrata
./install.sh
```

That adds the plugin and writes `~/.config/omarchy/omaestrata.env` (existing files are copied to `.bak`). Put **OmaeStrata** on the bar if it is not there yet, then:

```sh
omarchy-restart-shell
```

Needs Python 3 on the Strata host. SSH mode needs key-based login (`BatchMode=yes`). GPU stats use `nvidia-smi`, then `rocm-smi`, then amdgpu sysfs.

## Use

| Input | Action |
| --- | --- |
| Left-click when offline | Start Strata |
| Left-click when online | Open the panel |
| Right-click | Open / close the panel |
| Middle-click | Refresh now |
| `R` in the panel | Refresh |

The bar chip shows **▶ START** when the server is down, and **● MODEL** when it is up. The panel has **Start** and **Stop**. Stop SIGTERMs matching Strata processes (`serve/server.py --engine strata`, `strata.py serve`, or a `strata` binary) and SIGKILLs leftovers after 3s; plugin SSH/python helpers are ignored. Model identity comes from the newest `strata-*.log` filename (`strata-iq3_s.log` → `IQ3_S`). Rates are the latest completed request in that log, not a live token stream. Raw log lines, prompts, and generated text are never forwarded.

## Configure

Preferred file: `~/.config/omarchy/omaestrata.env` (survives plugin updates). You can also use a plugin-local `.env`. See `.env.example`.

| Key | Meaning |
| --- | --- |
| `MODE` | `ssh` or `local` |
| `SSH_TARGET` | `user@host` (ignored in local mode) |
| `STRATA_ROOT` | Strata tree on the Strata machine |
| `START_SCRIPT` | Script that launches the server |
| `DISK_PATH` | Filesystem measured for disk % |
| `PROCESS_PATTERN` | Process match (default `strata`) |
| `REFRESH_SECONDS` | Status poll interval |

Widget settings override `MODE` / SSH / refresh / process match when they are not the schema defaults. Paths must be absolute and cannot contain `..`.

The installer also accepts flags if you do not want prompts (`--mode`, `--ssh-target`, `--yes`, `--print-env`).

## Update

```sh
omarchy plugin update io.github.akira.omaestrata
```

## Remove

```sh
omarchy plugin remove io.github.akira.omaestrata
```

Your `omaestrata.env` is left in place.

## Notes

CPU is a short host-wide `/proc/stat` sample, not process-specific. Online detection looks for `serve/server.py --engine strata` (or a matching process name), and ignores the plugin's own SSH/python helpers. Failed checks keep the last good snapshot and mark it as an error.

## License

[MIT](LICENSE) © 2026 Christopher Akira. Use it, fork it, ship it.
