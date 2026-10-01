# vscode-remote-hpc

Run VS Code on an HPC compute node with one click from the VS Code remote explorer. This software is inspired by and is heavily based on [Gert Mertes' original code](https://github.com/gmertes).

## What it does
Login nodes on an HPC system are shared and aren't meant for heavy work. VS Code's [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension, when used on an HPC system, connects to the login nodes. `vscode-remote-hpc` lets VS Code connect to a compute node inside a batch job instead, so your editor, terminals, debugger, and extensions all run with the CPUs, GPUs, memory, and software of a regular cluster job.

You install a small script in your HPC account and add a few entries to the SSH config file on your own computer. Each entry describes a job (cores, time limit, GPUs, modules to load, and so on). When you connect to one of those entries from VS Code, the script, run through the ssh `ProxyCommand`:

- submits a batch job with your options, or reuses one that is already running,
- starts a private `sshd` inside the job and waits for the job to start,
- connects VS Code through the login node to the compute node.

Jobs are reused automatically, so many VS Code windows can share one job. Closing VS Code does not end the job; it stops when it reaches its time limit, or when you cancel it with the included `list`/`cancel` commands executed on the HPC system's login node. Software modules (like [Lmod](https://lmod.readthedocs.io/en/latest/)) can optionally be loaded in the job, and the loaded modules are available in VS Code and its terminals.

## Getting started
Pick the instructions for the system you use:

- **Boston University users**
  - **Shared Computing Cluster (SCC):** follow [README-scc.md](README-scc.md). The SCC uses the Grid Engine scheduler, so it has its own scripts in the `scc` folder, and the instructions include the BU-specific settings.

- **AICR system:** AICR uses Slurm. Follow [README-slurm.md](README-slurm.md), and then follow the the AICR SSH settings as described in [README-AICR.md](README-AICR.md) for the SSH config step.

- **Everyone else (i.e. HPC systems that use the Slurm scheduler):** follow [README-slurm.md](README-slurm.md). It uses the scripts in the `slurm` folder. The Slurm configuration is deliberately more generic than the BU SCC configuration and you will need to do some customization to some files like `~/.ssh/config` to make it work correctly for you.

If you're not sure which scheduler your system uses, run `which sbatch qsub` on its login node. If `sbatch` is found the system uses Slurm (some Slurm systems also provide a `qsub` look-alike); if only `qsub` is found it uses Grid Engine. If you are using this on a Grid Engine scheduler on an HPC system other than the BU SCC you will need to modify elements like the login node name. 

## What's in this repo

| Path | What it is |
| --- | --- |
| `scc/` | Scripts for the BU SCC: `install-scc.sh` installs `vscode-remote-scc.sh` (and its job script `vscode-remote-job-scc.sh`) in your SCC account. |
| `scc/local_installers/` | `install-mac-scc.sh` and `install-win-scc.ps1` set up your own Mac or Windows computer to connect to the SCC. |
| `slurm/` | Scripts for Slurm systems: `install.sh` installs `vscode-remote.sh` (and its job script `vscode-remote-job.sh`) in your account on the HPC system. |
| `slurm/local_installers/` | `install-mac-slurm.sh` and `install-win-slurm.ps1` set up your own Mac or Windows computer to connect to a Slurm system. |
