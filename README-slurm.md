# vscode-remote-hpc

A one-click script to setup and connect vscode to an HPC compute node, directly from the VS Code remote explorer. 

**Supported job schedulers:** Slurm (default) and SGE (Sun Grid Engine)

For **Slurm**, use the main scripts: `vscode-remote.sh` and `install.sh`
For **SGE**, use the SGE variants: `vscode-remote-sge.sh` and `install-sge.sh` (see [README-SGE.md](README-SGE.md) for setup instructions)

## Features
This script is designed to be used with the [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension for Visual Studio Code. 

- Automatically starts a batch job, or reuses an existing one, for vscode to connect to.
- No need to manually execute the script on the HPC, just connect from the remote explorer and the script handles everything automagically through `ProxyCommand`.
- Support for arbitrary types of jobs using `sbatch` options.
- Optionally load Lmod modules on the compute node; the resulting environment (including the loaded modules and `SLURM_*` variables) is injected into the VS Code server and every terminal it spawns.

## Requirements
- `sshd` must be available on the compute node, installed in `/usr/sbin` or available in the PATH
- A typical `sshd` installation is required, it must read login keys from `~/.ssh/authorized_keys` 
- You must be allowed to run `sshd` in a batch job on an arbitrary port above 10000, and connect to it from the login node
- The `nc` command (netcat) must be available on the HPC login node
- Compute node names must resolve to their internal IP addresses
- Compute nodes must be accessible via IP from the login node
- You must have SSH access to the HPC login node
- Slurm must be properly configured on your HPC system

These requirements are usually met, except if explicitly changed or forbidden by your system admin.

## Setup

Git clone the repo on the HPC login node (replace `HPC-LOGIN` with your own) and run the installer. 

```shell
ssh HPC-LOGIN
git clone git@github.com:gmertes/vscode-remote-hpc.git
cd vscode-remote-hpc
bash install.sh
```

The script will be installed in `~/bin` and added to your PATH. 

Job resources are no longer hard-coded in the script. Instead, you pass `sbatch`
options directly in the `ProxyCommand` of each `~/.ssh/config` host (see below).
A unique job name is derived from those options using an md5 hash, so
reconnecting to the same host always reuses the same running job.

It is recommended to keep the job time (`-t`) to a reasonable amount. The script expects that jobs get automatically killed when they reach their wall clock time. 

On your local machine, generate a new ssh key for vscode-remote:

```shell
ssh-keygen -f ~/.ssh/vscode-remote -t ed25519 -N ""
```

Copy the public key to your HPC `authorized_keys`, you can use `ssh-copy-id`:

```shell
ssh-copy-id -i ~/.ssh/vscode-remote HPC-LOGIN
```

In VS Code, change the `remote.SSH.connectTimeout` setting. Set this to the maximum time in seconds you expect a new job to start on your HPC. The script default (`TIMEOUT`) is `1800`.

```yaml
"remote.SSH.connectTimeout": 1800
```

Add an entry to your local machine's `~/.ssh/config` for each job you want. Change `USERNAME` and `HPC-LOGIN` accordingly, and pass whatever `sbatch` options you need after the script name:

```bash
Host vscode-remote-cpu
    User USERNAME
    IdentityFile ~/.ssh/vscode-remote
    ProxyCommand ssh HPC-LOGIN "~/bin/vscode-remote -c 4 -t 12:00:00 --mem=32G"
    StrictHostKeyChecking no
```

For a GPU job, add the appropriate Slurm flags, for example:

```bash
Host vscode-remote-gpu
    User USERNAME
    IdentityFile ~/.ssh/vscode-remote
    ProxyCommand ssh HPC-LOGIN "~/bin/vscode-remote -c 8 --gpus=1 -t 04:00:00 --mem=32G"
    StrictHostKeyChecking no
```

### Job options

Any option after the script name that is not listed below is passed straight through to `sbatch`.

- `-J <label>` / `--job-name <label>`: a label used to distinguish multiple jobs that would otherwise have identical resource options. The label is prepended to the job-name hash (e.g. `jobA.HASH.username`). It is consumed by the script and is **not** passed to `sbatch`. Without it, two hosts with identical `sbatch` options map to the same job and share a single session.
- `-z <modules>`: a comma-separated list of Lmod modules to load on the compute node before the VS Code server starts, e.g. `-z gcc/12.2.0,openmpi/4.1.5`. The loaded environment is captured and injected into the VS Code server and its terminals. Different module lists produce different jobs.

Example of two independent single-core sessions and a module-loading session:

```bash
Host vscode-remote-a
    User USERNAME
    IdentityFile ~/.ssh/vscode-remote
    ProxyCommand ssh HPC-LOGIN "~/bin/vscode-remote -c 1 -J jobA"
    StrictHostKeyChecking no

Host vscode-remote-b
    User USERNAME
    IdentityFile ~/.ssh/vscode-remote
    ProxyCommand ssh HPC-LOGIN "~/bin/vscode-remote -c 1 -J jobB"
    StrictHostKeyChecking no

Host vscode-remote-openmpi
    User USERNAME
    IdentityFile ~/.ssh/vscode-remote
    ProxyCommand ssh HPC-LOGIN "~/bin/vscode-remote -c 8 --mem=32G -z gcc/12.2.0,openmpi/4.1.5"
    StrictHostKeyChecking no
```

## Usage
The configured hosts are now available in the VS Code remote explorer. Connecting to a host will automatically launch a batch job with the options from its `ProxyCommand`, wait for it to start, and connect to the node when the job is running.

Running jobs are automatically reused. If a running job with the same options is already found, it will simply connect to it. You can safely open many remote windows and they will all share the same running job. 

Note that disconnecting the remote session in vscode will **not** kill the job on the HPC. You can close the remote window and the job will keep running. Jobs are expected to be automatically killed by the Slurm scheduler when they reach their wall clock time. You can manually kill the job using `scancel` or with the `vscode-remote cancel` command (see [CLI](#CLI)).

You can have as many jobs running at the same time as you like, just add a new `Host` entry in your `~/.ssh/config` with different options (and a `-J <label>` if the options are otherwise identical).

## CLI
The `vscode-remote` command installed on your HPC offers some commands to list or cancel running jobs. Do `vscode-remote help` for help on its usage.

```bash
$ vscode-remote help
Usage :  ~/bin/vscode-remote [command | sbatch-options]

    General commands:
    list      List running vscode-remote jobs
    cancel    Cancels all running vscode-remote jobs
    ssh       SSH into the node of a running job
    help      Display this message
```
