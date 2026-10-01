## AICR System

The [AICR](https://docs.aicr.ai/) system uses the Slurm scheduler. On AICR, install the `vscode-remote` script following the instructions in the `README-slurm.md` file. If you already have SSH access to AICR working from your computer, don't follow the local computer setup steps.

The following Host entries can be added to your existing `~/.ssh/config` and will use your existing AICR SSH keys and certificate for the connection. 

The AICR system uses an SSH certificate. This requires a slightly more elaborate setup as the
identity file and certificate need to be specified in the ProxyCommand. This example sets up a 1 core job on the CPU queue. 

```bash
# Linux / Mac:
Host aicr-vsc-cpu
    HostName login.aicr.ai
    User USERNAME
    StrictHostKeyChecking no
    IdentityFile ~/.ssh/id_ed25519_aicr
    CertificateFile ~/.ssh/id_ed25519_aicr-cert.pub
    UserKnownHostsFile /dev/null
    ProxyCommand ssh -i ~/.ssh/id_ed25519_aicr -o CertificateFile=~/.ssh/id_ed25519_aicr-cert.pub USERNAME@login.aicr.ai "~/bin/vscode-remote --partition=cpu --time=08:00:00 --cpus-per-task 1 --mem=16GB -z conda/latest"


# Windows: Note the full path to the Github SSH program. This is
# installed automatically with VS Code and needs to be used 
# instead of the default Windows ssh.exe
Host aicr-vsc-cpu
    HostName login.aicr.ai
    User USERNAME
    StrictHostKeyChecking no
    IdentityFile ~/.ssh/id_ed25519_aicr
    CertificateFile ~/.ssh/id_ed25519_aicr-cert.pub
    UserKnownHostsFile /dev/null
    ProxyCommand "C:\Program Files\Git\usr\bin\ssh.exe" -i ~/.ssh/id_ed25519_aicr -o CertificateFile=~/.ssh/id_ed25519_aicr-cert.pub USERNAME@login.aicr.ai "~/bin/vscode-remote --partition=cpu --time=08:00:00 --cpus-per-task 1 --mem=16GB -z conda/latest"
```
