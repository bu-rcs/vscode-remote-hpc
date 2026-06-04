# vscode-remote-hpc for the BU SCC

A one-click script to setup and connect VS Code to an SCC compute node, directly from the VS Code remote explorer.

## Features
This script is designed to be used with the [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension for Visual Studio Code. 

- Automatically starts a batch job, or reuses an existing one, for VS Code to connect to.
- Just connect from the remote explorer and the script handles everything automatically through the ssh `ProxyCommand`.
- Support for arbitrary types of jobs using `qsub` options.

## SCC Setup

Git clone the repo using the command line on the SCC:

```shell
git clone https://github.com/bu-rcs/vscode-remote-hpc.git
cd vscode-remote-hpc
bash install-sge.sh
```

The script will be installed in your home directory `~/bin` and added to your PATH. 

## Setup

### Step 1: SSH key 
 __If you have already set up SSH keys for passwordless access to the SCC skip this entire step!__
  
  *Windows*
  Press the windows key on your keyboard, enter `powershell`, and open a Powershell command line window. 
  
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


### Step 2: SSH Config File Setup

- Open VS Code.
- Type `ctrl-shift-P` and enter `Remote-SSH: Settings`
	+ In the settings, look for the `Remote.SSH: Connect Timeout` value and set it to 1800 seconds. This is 30 minutes, and is the same value set on the script that runs on the SCC.
- click the File menu -> Open a File.
	* Windows:  `c:\users\windows_username\.ssh\config`
	* Mac: `~/.ssh/config`
- You can use any of the login nodes to handle your SSH connection (scc1.bu.edu, scc2, geo, or scc4), but as usual to connect to the scc4 you will need to be on the SCC campus network or connected via the VPN. The choice of login node has no impact on the connection of VS Code to the compute node. 
- In the examples below replace `bu_username` with your BU username, and on Windows replace `windows_username` with the name of your account on your own computer. **NOTE**: Your username needs to be set on the line with the *User* parameter **AND** on the line with the *ProxyCommand* parameter as shown.
- Each `Host` definition in the `config` file defines a job by using `qsub` options for the `vscode-remote-sge` script. Two are defined below as examples but you can add as many as you want.
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
    ProxyCommand "C:\Program Files\Git\usr\bin\ssh.exe" bu_username@scc1.bu.edu  "~/bin/vscode-remote-sge -l h_rt=04:00:00"
    StrictHostKeyChecking no
  
# A 4-core 12-hour job named "multicore"
Host SCC-remote-cpu4
    User bu_username
    IdentityFile  c:\Users\windows_username\.ssh\id_ed25519
    ProxyCommand "C:\Program Files\Git\usr\bin\ssh.exe" bu_username@scc1.bu.edu  "~/bin/vscode-remote-sge -N multicore -pe omp 4 -l h_rt=12:00:00"
    StrictHostKeyChecking no
```
#### Mac OS X
Add this to the `config` file:
```
# A 1-core 4-hour job
Host SCC-remote-cpu
    User bu_username
    IdentityFile  ~/.ssh/id_ed25519
    ProxyCommand ssh bu_username@scc1.bu.edu  "~/bin/vscode-remote-sge -l h_rt=04:00:00"
    StrictHostKeyChecking no
  
# A 4-core 12-hour job
Host SCC-remote-cpu4
    User bu_username
    IdentityFile  ~/.ssh/id_ed25519
    ProxyCommand ssh bu_username@scc1.bu.edu  "~/bin/vscode-remote-sge -pe omp 4 -l h_rt=12:00:00"
    StrictHostKeyChecking no
```

### Step 3: VS Code Remote-SSH Setup
In the VS Code window, type `Ctrl-Shift-P`, and enter *Remote-SSH: Settings* in the search box. This opens the settings for the `Remote-SSH` extension. 

1. Set the **Connect Timeout** to a large value. This is the time that VS Code will wait for a job to be ready once requested. A value of 1800 is suggested.
2. Make sure the following options are checked and enabled:  **Enable Agent Forwarding**, **Enable Dynamic Forwarding**, **Enable Remote Command**, and **Use Local Server**.


## Usage
The defined hosts are now available in the VS Code remote explorer. Connecting to this host will automatically launch a batch job on an SCC compute node, wait for it to start, and connect to the node when the job is running.

### Make a Connection
In VS Code type `ctrl-shift-P` and enter `Remote-SSH: Connect to Host...`  Select one of the listed hosts and click it to open a new window. The new job will connect via SSH to the login node, call `qsub` with your job options, and when the job is started automatically connect thru to the compute node. 

Running jobs are **automatically reused**. If a running job for a host definition is already found, VS Code will simply connect to it. You can safely open many remote windows and they will all share the same running job. 

Note that disconnecting the remote session in vscode will **not** kill the job on the SCC. You can close the remote window and the job will keep running. Jobs are expected to be automatically killed by the job scheduler when they reach their time limit. You can manually kill the job using `qdel` or with the `vscode-remote-sge cancel` command (see [CLI](#CLI)).

## CLI
The `vscode-remote-sge` command installed on your HPC offers some commands to list or cancel running jobs. Do `vscode-remote-sge help` for help on its usage.

```bash
$ vscode-remote-sge help
Usage :  ~/bin/vscode-remote-sge [command]

    General commands:
    list      List running vscode-remote jobs
    cancel    Cancels ALL running vscode-remote jobs
    ssh       SSH into the node of a running job
    help      Display this message
```

## Troubleshooting

### Job stays in "qw" (queued waiting) state
This usually means that either the requested resources are in high demand (i.e. you are simply waiting) or the scheduler cannot allocate the resources you requested. Check:
- In a terminal on the SCC, try your job options with `qrsh` to make sure they are valid, e.g.:
```bash
qrsh -l h_rt=04:00 -N m_job
```

### Job started but VS Code fails to connect
- Edit the `~/bin/vscode-remote-sge` script on the SCC and increase the `TIMEOUT` value. The default is 1800 seconds (30 minutes). In your local VS Code you will also need to set the `Remote.SSH: Connect Timeout` to the same value.  


