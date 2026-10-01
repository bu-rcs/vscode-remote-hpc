# vscode-remote-hpc for Slurm

A one-click script to setup and connect VS Code to a compute node on a Slurm-based HPC system, directly from the VS Code remote explorer.

## Features
This script is designed to be used with the [Remote-SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension for Visual Studio Code. The instructions assume you have already installed or enabled the `Remote-SSH` extension. 

- Automatically starts a batch job, or reuses an existing one, for VS Code to connect to.
- Just connect from the remote explorer and the script handles everything automatically through the ssh `ProxyCommand`.
- Support for arbitrary types of jobs using `sbatch` options and the loading of software modules within those jobs.
- Optionally load Lmod modules on the compute node. The resulting environment (including the loaded modules and `SLURM_*` variables) is passed to the VS Code server and every terminal it opens.

## Requirements
- `sshd` must be available on the compute node, installed in `/usr/sbin` or available in the PATH
- A typical `sshd` installation is required, it must read login keys from `~/.ssh/authorized_keys` 
- You must be allowed to run `sshd` in a batch job on an arbitrary port above 10000, and connect to it from the login node
- The `nc` command (netcat) must be available on the HPC login node
- Compute node names must resolve to their internal IP addresses
- Compute nodes must be accessible via IP from the login node
- You must have SSH access to the HPC login node

These requirements are usually met, except if explicitly changed or forbidden by your system admin.

## HPC Setup

Git clone the repo using the command line on your HPC login node:

```shell
git clone https://github.com/bu-rcs/vscode-remote-hpc.git
cd vscode-remote-hpc
bash slurm/install.sh
```

The `slurm/vscode-remote.sh` script will be installed in your home directory as `~/bin/vscode-remote`, and `~/bin` will be added to your PATH. 
 
## Setup on Your Computer

In the steps below, replace `username` with your username on the HPC system and `HPC-LOGIN` with the hostname of its login node (for example `login.cluster.example.edu`).

### Automatic Setup on Your Computer (recommended)

Steps 1-3 below are done on your own computer. You can follow them by hand, or let an installer in the `slurm/local_installers` folder do all three for you. Download this repo to your computer (on GitHub click **Code** -> **Download ZIP** and unzip it, or `git clone` it), open a window in the repo's folder, and run the installer for your computer. It asks for the login node's hostname and your username, then asks before each step.

- *Mac OS X*: in a Terminal window run
  ```shell
  bash slurm/local_installers/install-mac-slurm.sh
  ```
- *Windows*: in a PowerShell window run
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\slurm\local_installers\install-win-slurm.ps1
  ```
  The `-ExecutionPolicy Bypass` option lets this one script run without changing any settings on your computer. Alternatively, right-click the file and choose "Run with Powershell". The Windows installer needs [Git for Windows](https://git-scm.com/download/win), as do the SSH settings in Step 2. This is typically installed by the installer for VS Code. To verify, press the Windows key, enter `cmd` and run a `Command Prompt`. Paste in (including the double quotes) `"C:\Program Files\Git\usr\bin\ssh.exe"`  The SSH program should print its options. If this does not work, download and install [Git for Windows](https://git-scm.com/download/win) before proceeding.


### Step 1: Manual SSH key generation
 __If you have already set up SSH keys for passwordless access to your HPC system or another system you can skip this entire step!__
  
  *Windows*
  Press the Windows key on your keyboard, enter `powershell`, and open a Powershell command line window. 
  
  *Mac OS X*
  Open a Terminal window.
  
Create an SSH key for logging on to the HPC system:
  
  ```powershell
  cd ~/.ssh
  ls
  # If files called id_ed25519 and id_ed25519.pub exist, 
  # skip this next step. Otherwise do:
  ssh-keygen -t ed25519 -N ""
  
# Now copy the key to the HPC system. In these
# commands replace username with your
# actual username and HPC-LOGIN with the
# login node's hostname.
# On a Mac run:
ssh-copy-id -i ~/.ssh/id_ed25519 username@HPC-LOGIN

# On Windows it's a little more complicated:
type .\id_ed25519.pub | ssh username@HPC-LOGIN "cat >> ~/.ssh/authorized_keys"
 ```


### Step 2: Manual SSH Config File Setup

- Open VS Code.
- click the File menu -> Open a File.
	* Windows:  `c:\users\windows_username\.ssh\config`
	* Mac: `~/.ssh/config`
- In the examples below replace `username` with your HPC username, `HPC-LOGIN` with the login node's hostname, and on Windows replace `windows_username` with the name of your account on your own computer. **NOTE**: Your username needs to be set on the line with the *User* parameter **AND** on the line with the *ProxyCommand* parameter as shown.
- Each `Host` definition in the `config` file defines a job by using `sbatch` options for the `vscode-remote` script. Two are defined below as examples but you can add as many as you want.
	+ Common options are `-c` (number of cores), `-t` (time limit, e.g. `04:00:00`), and `--mem` (memory, e.g. `--mem=16G`).
	+ GPU jobs can be requested by adding GPU flags, for example `--gpus=1`
- If you normally need to specify an account with `-A account_name` or a partition with `-p partition_name` for a batch job you'll need to do the same here.
- It is recommended to keep the job time (`-t`) to a reasonable amount. The script expects that jobs get automatically killed when they reach their time limit.
- The job names have the format: `vscode-remote-<long string>.username-<a number>`. If you add the `-J XYZ` flag to your job options the name will appear after the `vscode-remote-` string in the job name, for example as `vscode-remote-XYZ`. The `-J` flag is used by the `vscode-remote` script and is not passed to `sbatch`. Use it to tell apart two hosts whose job options are otherwise identical; without it they share a single job.
- Lmod modules can be loaded on the compute node with the `-z` flag and a comma-separated list of modules, for example `-z gcc/12.2.0,openmpi/4.1.5`. Different module lists produce different jobs.
- The name of the `Host` section can be anything you want, the prefix `HPC-remote` is used here as an example.
- If your HPC system requires SSH certificates, such as the AICR system, see [README-AICR.md](README-AICR.md) for the extra settings.

#### Windows
Add this to the `config` file:
```
# A 1-core 4-hour job
Host HPC-remote-cpu
    User username
    IdentityFile  c:\Users\windows_username\.ssh\id_ed25519
    ProxyCommand "C:\Program Files\Git\usr\bin\ssh.exe" username@HPC-LOGIN  "~/bin/vscode-remote -c 1 -t 04:00:00"
    StrictHostKeyChecking no
  
# A 4-core 12-hour job where the Slurm job is named "multicore"
# Modules gcc/12.2.0 and openmpi/4.1.5 are preloaded
Host HPC-remote-cpu4
    User username
    IdentityFile  c:\Users\windows_username\.ssh\id_ed25519
    ProxyCommand "C:\Program Files\Git\usr\bin\ssh.exe" username@HPC-LOGIN  "~/bin/vscode-remote -J multicore -c 4 -t 12:00:00 --mem=16G -z gcc/12.2.0,openmpi/4.1.5"
    StrictHostKeyChecking no
```
#### Mac OS X
Add this to the `config` file:
```
# A 1-core 4-hour job
Host HPC-remote-cpu
    User username
    IdentityFile  ~/.ssh/id_ed25519
    ProxyCommand ssh username@HPC-LOGIN  "~/bin/vscode-remote -c 1 -t 04:00:00"
    StrictHostKeyChecking no
  
# A 4-core 12-hour job
# Modules gcc/12.2.0 and openmpi/4.1.5 are preloaded
Host HPC-remote-cpu4
    User username
    IdentityFile  ~/.ssh/id_ed25519
    ProxyCommand ssh username@HPC-LOGIN  "~/bin/vscode-remote -c 4 -t 12:00:00 --mem=16G -z gcc/12.2.0,openmpi/4.1.5"
    StrictHostKeyChecking no
```

### Step 3: Manual VS Code Remote-SSH Setup
In the VS Code window, type `ctrl-shift-P` (Mac: `cmd-shift-P`), and enter *Remote-SSH: Settings* in the search box. This opens the settings for the `Remote-SSH` extension. 

1. Set **Remote.SSH: Connect Timeout** to `3600`. This is how many seconds VS Code waits for a connection, which includes waiting for your job to start. The default of 15 seconds is far too short, so VS Code gives up before the job is running. 3600 seconds (1 hour) is longer than the 1800 second `TIMEOUT` in `~/bin/vscode-remote` on the HPC system, so the HPC script, not VS Code, decides when to stop waiting. Enter `3600` in the **Connect Timeout** box on the settings page, or run *Preferences: Open User Settings (JSON)* and add this line inside the outer `{ }`, with a comma between it and any other settings:
   ```json
   "remote.SSH.connectTimeout": 3600
   ```
2. Make sure the following options are checked and enabled:  **Enable Agent Forwarding**, **Enable Dynamic Forwarding**, **Enable Remote Command**, and **Use Local Server**.

------

## Usage
The defined hosts are now available in the VS Code remote explorer. Connecting to this host will automatically launch a batch job on a compute node, wait for it to start, and connect to the node when the job is running.

### Editing `~/.ssh/config` in VS Code
You can define new hosts to run different types of jobs by editing your `~/.ssh/config` file. To open it, just enter `~/.ssh/config` in the VS Code `Search` field at the top of the VS Code editor window. 

New types of jobs (for example, to use a GPU, or to allocate a large number of cores) can be configured by creating new `Host` entries in this file. 

### Make a Connection
In VS Code type `ctrl-shift-P` (Mac: `cmd-shift-P`) and enter `Remote-SSH: Connect to Host...`  Select one of the listed hosts and click it to open a new window. The new job will connect via SSH to the login node, call `sbatch` with your job options, and when the job is started automatically connect thru to the compute node. 

Running jobs are **automatically reused**. If a running job for a host definition is already found, VS Code will simply connect to it. You can safely open many remote windows and they will all share the same running job. 

Note that disconnecting the remote session in vscode will **not** kill the job on the HPC system. You can close the remote window and the job will keep running. Jobs are expected to be automatically killed by the job scheduler when they reach their time limit. You can manually kill the job using `scancel` or with the `vscode-remote cancel` command (see [CLI](#CLI)).

## CLI
The `vscode-remote` command installed on your HPC system offers some commands to list or cancel running jobs. Do `vscode-remote help` for help on its usage.

```bash
$ vscode-remote help
Usage :  ~/bin/vscode-remote [command | sbatch-options]

    General commands:
    list      List running vscode-remote jobs
    cancel    Cancels all running vscode-remote jobs
    ssh       SSH into the node of a running job
    help      Display this message
```

## Shutting Down a Running Job 
If you want to shut down a running job without letting it end at the end of its scheduled lifetime, don't do it from the VS Code window that's connected to it. 

For example, you connect VS Code to the `SCC-remote-cpu` job. From the VS Code terminal window you issue the `vscode-remote-scc cancel` command or use `qdel` to kill the job. VS Code will detect that its remote session has vanished and will **instantly re-submit** a new one. 

#### Shutdown Procedure
To shut down jobs launched by VS Code using these tools:

1. First close all VC Code windows connected to the remote jobs. 
2. Next, connect to a login node (via OnDemand and the "login node" menu, or via an `ssh` connection to a login node).
3. Finally, use `vscode-remote cancel` or `scancel` to kill the job. 


## Troubleshooting

### Job stays in "PD" (pending) state
This usually means that either the requested resources are in high demand (i.e. you are simply waiting) or the scheduler cannot allocate the resources you requested. Check:
- In a terminal on the login node, run `squeue --me` and look at the `NODELIST(REASON)` column to see why the job is waiting.
- Try your job options with `srun` to make sure they are valid, e.g.:
```bash
srun -c 1 -t 04:00:00 --pty bash
```

### Job started but VS Code fails to connect
- Edit the `~/bin/vscode-remote` script on the HPC system and increase the `TIMEOUT` value. The default is 1800 seconds (30 minutes). In your local VS Code, make sure `Remote.SSH: Connect Timeout` is at least as large as the new value (the suggested 3600 covers any `TIMEOUT` up to 3600). The TIMEOUT values can be larger than this if you wish, but if you are not connecting to requested resources with an hour you should probably alter your approach and request those resources through a batch job.
