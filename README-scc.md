# vscode-remote-hpc for the BU SCC

A one-click script to setup and connect your local VS Code session to an SCC compute node.

## Features
This script is designed to be used with the [Remote-SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension for Visual Studio Code. The instructions assume you have already installed or enabled the `Remote-SSH` extension.

- Automatically starts a batch job, or reuses an existing one, for VS Code to connect to.
- Just connect from the remote explorer and the script handles everything automatically through the ssh `ProxyCommand`.
- Support for arbitrary types of jobs using `qsub` options and the loading of software modules within those jobs.
- Is not impacted by resource limits or the 15 minute CPU time limit on the login nodes. 

## SCC Setup

Git clone the repo using the command line on the SCC:

```shell
git clone https://github.com/bu-rcs/vscode-remote-hpc.git
cd vscode-remote-hpc
sh scc/install-scc.sh
```

The `scc/vscode-remote-scc.sh` script will be installed in your home directory as `~/bin/vscode-remote-scc`, and `~/bin` will be added to your PATH. 

## Setup on Your Computer

Steps 1-3 below are done on your own computer. You can follow them by hand, or let an installer in the `scc/local_installers` folder do all three for you. Download this repo to your computer (on GitHub click **Code** -> **Download ZIP** and unzip it, or `git clone` it), open a window in the repo's folder, and run the installer for your computer. It asks for your BU username, then asks before each step.

### Automatic Setup on Your Computer (recommended)

If you are running the local install scripts **skip steps 1-3** below. 

- *Mac OS X*: in a Terminal window run
  ```shell
  bash scc/local_installers/install-mac-scc.sh
  ```
- *Windows*: in a PowerShell window run
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scc\local_installers\install-win-scc.ps1
  ```
  The `-ExecutionPolicy Bypass` option lets this one script run without changing any settings on your computer. Alternatively, right-click the file and choose "Run with Powershell". The Windows installer needs [Git for Windows](https://git-scm.com/download/win), as do the SSH settings in Step 2. This is typically installed by the installer for VS Code. To verify, press the Windows key, enter `cmd` and run a `Command Prompt`. Paste in (including the double quotes) `"C:\Program Files\Git\usr\bin\ssh.exe"`  The SSH program should print its options. If this does not work, download and install [Git for Windows](https://git-scm.com/download/win) before proceeding.

### Step 1: Manual SSH key generation
 __If you have already set up SSH keys for passwordless access to the SCC or another system and you want to use your existing keys you can skip this entire step!__
  
  *Windows*
  Press the Windows key on your keyboard, enter `powershell`, and open a Powershell command line window. 
  
  *Mac OS X*
  Open a Terminal window.
  
Create an SSH key for logging on to the SCC:
  
  ```powershell
  cd ~/.ssh
  ls
  # If files called id_ed25519 and id_ed25519.pub exist, 
  # skip this next step. Otherwise do:
  ssh-keygen -t ed25519 -N ""
  
# Now copy the key to the SCC. In these
# commands replace bu_username with your
# actual BU username.
# On a Mac run:
ssh-copy-id -i ~/.ssh/id_ed25519 bu_username@scc1.bu.edu

# On Windows it's a little more complicated:
type .\id_ed25519.pub | ssh bu_username@scc1.bu.edu "cat >> ~/.ssh/authorized_keys"
 ```


### Step 2: Manual SSH Config File Setup

- Open VS Code.
- click the File menu -> Open a File.
	* Windows:  `c:\users\windows_username\.ssh\config`
	* Mac: `~/.ssh/config`
- You can use any of the login nodes to handle your SSH connection (scc1.bu.edu, scc2, geo, or scc4), but as usual to connect to the scc4 you will need to be on the SCC campus network or connected via the VPN. The choice of login node has no impact on the connection of VS Code to the compute node. 
- In the examples below replace `bu_username` with your BU username, and on Windows replace `windows_username` with the name of your account on your own computer. **NOTE**: Your username needs to be set on the line with the *User* parameter **AND** on the line with the *ProxyCommand* parameter as shown.
- Each `Host` definition in the `config` file defines a job by using `qsub` options for the `vscode-remote-scc` script. Two are defined below as examples but you can add as many as you want.
	+ GPU jobs can be requested by adding GPU flags, for example `-l gpus=1 -l gpu_c=7.0`
- If you normally need to specify a project with `-P proj_name` for a batch job you'll need to do the same here.
- The job names have the format: `vscode-remote-<long string>.bu-username-<a number>`. If you add the `-N XYZ` flag to your job options the anme will appear after the `vscode-remote-` string in the job name, for example as `vscode-remote-XYZ`
- The name of the `Host` section can be anything you want, the prefix `SCC-remote` is used here as an example.

#### Windows
Add this to the `config` file:
```
# A 1-core 4-hour job
Host SCC-remote-cpu
    User bu_username
    IdentityFile  c:\Users\windows_username\.ssh\id_ed25519
    ProxyCommand "C:\Program Files\Git\usr\bin\ssh.exe" bu_username@scc1.bu.edu  "~/bin/vscode-remote-scc -l h_rt=04:00:00"
    StrictHostKeyChecking no
  
# A 4-core 12-hour job where the SCC job is named "multicore"
# Modules python3/3.13.8 and matlab/2025a are preloaded
Host SCC-remote-cpu4
    User bu_username
    IdentityFile  c:\Users\windows_username\.ssh\id_ed25519
    ProxyCommand "C:\Program Files\Git\usr\bin\ssh.exe" bu_username@scc1.bu.edu  "~/bin/vscode-remote-scc -N multicore -pe omp 4 -l h_rt=12:00:00 -z python3/3.13.8,matlab/2025a"
    StrictHostKeyChecking no
```
#### Mac OS X
Add this to the `config` file:
```
# A 1-core 4-hour job
Host SCC-remote-cpu
    User bu_username
    IdentityFile  ~/.ssh/id_ed25519
    ProxyCommand ssh bu_username@scc1.bu.edu  "~/bin/vscode-remote-scc -l h_rt=04:00:00"
    StrictHostKeyChecking no
  
# A 4-core 12-hour job
# Modules python3/3.13.8 and matlab/2025a are preloaded
Host SCC-remote-cpu4
    User bu_username
    IdentityFile  ~/.ssh/id_ed25519
    ProxyCommand ssh bu_username@scc1.bu.edu  "~/bin/vscode-remote-scc -pe omp 4 -l h_rt=12:00:00  -z python3/3.13.8,matlab/2025a"
    StrictHostKeyChecking no
```

### Step 3: Manual VS Code Remote-SSH Setup
In the VS Code window, type `ctrl-shift-P` (Mac: `cmd-shift-P`), and enter *Remote-SSH: Settings* in the search box. This opens the settings for the `Remote-SSH` extension. 

1. Set **Remote.SSH: Connect Timeout** to `3600`. This is how many seconds VS Code waits for a connection, which includes waiting for your job to start. The default of 15 seconds is far too short, so VS Code gives up before the job is running. 3600 seconds (1 hour) is longer than the 1800 second `TIMEOUT` in `~/bin/vscode-remote-scc` on the SCC, so the SCC script, not VS Code, decides when to stop waiting. Enter `3600` in the **Connect Timeout** box on the settings page, or run *Preferences: Open User Settings (JSON)* and add this line inside the outer `{ }`, with a comma between it and any other settings:
   ```json
   "remote.SSH.connectTimeout": 3600
   ```
2. Make sure the following options are checked and enabled:  **Enable Agent Forwarding**, **Enable Dynamic Forwarding**, **Enable Remote Command**, and **Use Local Server**.

------

## Usage
The defined hosts are now available in the VS Code remote explorer. Connecting to this host will automatically launch a batch job on an SCC compute node, wait for it to start, and connect to the node when the job is running. 

### Editing `~/.ssh/config` in VS Code
You can define new hosts to run different types of jobs by editing your `~/.ssh/config` file. To open it, just enter `~/.ssh/config` in the VS Code `Search` field at the top of the VS Code editor window. 

New types of jobs (for example, to use a GPU, or to allocate a large number of cores) can be configured by creating new `Host` entries in this file. 

### Make a Connection
In VS Code type `ctrl-shift-P` (Mac: `cmd-shift-P`) and enter `Remote-SSH: Connect to Host...`  Select one of the listed hosts and click it to open a new window. The new job will connect via SSH to the login node, call `qsub` with your job options, and when the job is started automatically connect thru to the compute node. 

Running jobs are **automatically reused**. If a running job for a host definition is already found, VS Code will simply connect to it. You can safely open many remote windows and they will all share the same running job. 

Note that disconnecting the remote session in vscode will **not** kill the job on the SCC. You can close the remote window and the job will keep running. Jobs are expected to be automatically killed by the job scheduler when they reach their time limit. You can manually kill the job using `qdel` or with the `vscode-remote-scc cancel` command (see [CLI](#CLI)).

## CLI
The `vscode-remote-scc` command installed on your HPC offers some commands to list or cancel running jobs. Do `vscode-remote-scc help` for help on its usage.

```bash
$ vscode-remote-scc help
Usage :  ~/bin/vscode-remote-scc [command]

    General commands:
    list      List running vscode-remote jobs
    cancel    Cancels ALL running vscode-remote jobs
    ssh       SSH into the node of a running job
    help      Display this message
```

## Shutting Down a Running Job 
If you want to shut down a running job without letting it end at the end of its scheduled lifetime, don't do it from the VS Code window that's connected to it. 

For example, you connect VS Code to the `SCC-remote-cpu` job. From the VS Code terminal window you issue the `vscode-remote-scc cancel` command or use `qdel` to kill the job. VS Code will detect that its remote session has vanished and will **instantly re-submit** a new one. 

#### The Correct Procedure
To shut down jobs launched by VS Code using these tools:

1. First close all VC Code windows connected to the remote jobs. 
2. Next, connect to a login node (via OnDemand and the "login node" menu, or via an `ssh` connection to a login node).
3. Finally, use `vscode-remote-scc cancel` or `qdel job_id` to kill the job. 

## Troubleshooting

### Job stays in "qw" (queued waiting) state
This usually means that either the requested resources are in high demand (i.e. you are simply waiting) or the scheduler cannot allocate the resources you requested. Check:
- In a terminal on the SCC, try your job options with `qrsh` to make sure they are valid, e.g.:
```bash
qrsh -l h_rt=04:00 -N m_job
```

### Job started but VS Code fails to connect
- Edit the `~/bin/vscode-remote-scc` script on the SCC and increase the `TIMEOUT` value. The default is 1800 seconds (30 minutes). In your local VS Code, make sure `Remote.SSH: Connect Timeout` is at least as large as the new value (the suggested 3600 covers any `TIMEOUT` up to 3600). The TIMEOUT values can be larger than this if you wish, but if you are not connecting to requested resources with an hour you should probably alter your approach and request those resources through a batch job.


