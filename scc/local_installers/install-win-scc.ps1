<#
.SYNOPSIS
    Sets up a Windows computer to connect VS Code to a BU SCC compute node
    with vscode-remote-hpc.

.DESCRIPTION
    This does the steps from README-scc.md that happen on your own computer:

      Step 1: create an SSH key pair, if you don't have one, and copy it to the SCC
      Step 2: add the sample SCC-remote-cpu and SCC-remote-cpu4 hosts to your
              SSH config file, C:\Users\<you>\.ssh\config
      Step 3: set the VS Code Remote-SSH settings, including Connect Timeout = 3600

    You still need to do the "SCC Setup" step from README-scc.md on the SCC itself.

    The ProxyCommand lines in the SSH config use the ssh.exe that comes with
    Git for Windows (https://git-scm.com/download/win), so install Git first.

    The script asks before each step, backs up any file it changes, and is safe
    to re-run. It does not need administrator rights.

.NOTES
    HOW TO RUN THIS SCRIPT

    Windows won't run a PowerShell script when you double-click it. Use either
    of these methods.

    Method 1 (recommended): from a PowerShell window
      1. Press the Windows key, type powershell, and open "Windows PowerShell".
      2. Go to the folder where you saved this script, for example:

             cd $HOME\Downloads

      3. Run this command:

             powershell -ExecutionPolicy Bypass -File .\install-win-scc.ps1

         "-ExecutionPolicy Bypass" lets this one script run without changing
         any settings on your computer.

    Method 2: from File Explorer
      Right-click install-win-scc.ps1 and choose "Run with PowerShell". On
      Windows 11 you may need to click "Show more options" first. If you're
      asked whether to change the execution policy, type Y and press Enter;
      that only applies to the window the script runs in.

    If Windows still says that running scripts is disabled, your computer is
    managed by a policy that blocks scripts. Ask your IT support for help, or
    follow Steps 1-3 of README-scc.md by hand.
#>

Set-StrictMode -Version 2.0

$LoginNode      = 'scc1.bu.edu'
$ConnectTimeout = 3600

$SshDir         = Join-Path $HOME '.ssh'
$KeyFile        = Join-Path $SshDir 'id_ed25519'
$PubFile        = "$KeyFile.pub"
$SshConfig      = Join-Path $SshDir 'config'
$VSCodeSettings = Join-Path $env:APPDATA 'Code\User\settings.json'

# Where README-scc.md expects Git for Windows' ssh.exe, if it can't be found elsewhere
$DefaultGitSsh  = 'C:\Program Files\Git\usr\bin\ssh.exe'

# The Remote-SSH settings from README-scc.md Step 3, with their JSON values
$VSCodeSshSettings = [ordered]@{
    'remote.SSH.connectTimeout'          = "$ConnectTimeout"
    'remote.SSH.enableAgentForwarding'   = 'true'
    'remote.SSH.enableDynamicForwarding' = 'true'
    'remote.SSH.enableRemoteCommand'     = 'true'
    'remote.SSH.useLocalServer'          = 'true'
}

# Marks the lines this script adds to the SSH config so a re-run can find them
$BlockBegin = '# BEGIN vscode-remote-hpc SCC hosts'
$BlockEnd   = '# END vscode-remote-hpc SCC hosts'


function Write-Ok([string]$Message)   { Write-Host "  + $Message" -ForegroundColor Green }
# Shows a warning; any lines after the first are indented to line up with it
function Write-Warn([string[]]$Lines) {
    $prefix = "  - "
    foreach ($line in $Lines) {
        Write-Host "$prefix$line" -ForegroundColor Yellow
        $prefix = "    "
    }
}

# Asks a yes/no question. $Default is the answer used if you just press Enter.
function Read-YesNo([string]$Question, [bool]$Default) {
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $reply = "$(Read-Host "$Question $hint")".Trim().ToLower()
        if ($reply -eq '') { return $Default }
        if ($reply -eq 'y' -or $reply -eq 'yes') { return $true }
        if ($reply -eq 'n' -or $reply -eq 'no') { return $false }
        Write-Host 'Please answer y or n.'
    }
}

# Returns the file's text, or '' if it doesn't exist
function Read-TextFile([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return [System.IO.File]::ReadAllText($Path) }
    return ''
}

# Writes UTF-8 with no byte order mark, because ssh can't read a config file that has one
function Write-TextFile([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Backup-File([string]$Path) {
    $copy = "$Path.bak.$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $Path -Destination $copy -ErrorAction Stop
    Write-Ok "Backed up $Path to $copy"
}

# The line ending $Text already uses, so added lines match it
function Get-LineEnding([string]$Text) {
    if ($Text -match "`r`n" -or $Text -notmatch "`n") { return "`r`n" }
    return "`n"
}

# Git for Windows' ssh.exe, which the ProxyCommand lines use as in README-scc.md
function Find-GitSsh {
    $gitRoots = @((Join-Path $env:ProgramFiles 'Git'), (Join-Path $env:LOCALAPPDATA 'Programs\Git'))
    $git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) { $gitRoots += Split-Path (Split-Path $git.Source) }
    foreach ($root in $gitRoots) {
        $ssh = Join-Path $root 'usr\bin\ssh.exe'
        if (Test-Path -LiteralPath $ssh) { return $ssh }
    }
    return $null
}

# An OpenSSH program: the one built in to Windows if there is one, otherwise Git's copy
function Find-SshTool([string]$Name) {
    $cmd = Get-Command "$Name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    if ($script:GitSsh) {
        $tool = Join-Path (Split-Path $script:GitSsh) "$Name.exe"
        if (Test-Path -LiteralPath $tool) { return $tool }
    }
    return $null
}

function Read-BuUsername {
    while ($true) {
        $name = "$(Read-Host 'Your BU username (the one you use to log in to the SCC)')".Trim().ToLower()
        $name = $name -replace '@bu\.edu$', ''
        if ($name -notmatch '^[a-z0-9][a-z0-9._-]*$') {
            Write-Warn "That doesn't look like a BU username, please try again."
        } elseif (Read-YesNo "Use '$name'?" $true) {
            return $name
        }
    }
}

# True if the key logs in to the SCC without asking for a password
function Test-KeyLogin {
    $sshArgs = @('-n', '-q', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'IdentitiesOnly=yes',
                 '-i', $KeyFile, "$script:BuUser@$LoginNode", 'true')
    & $script:SshExe @sshArgs | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Appends the public key to ~/.ssh/authorized_keys on the SCC, like README-scc.md's
#   type .\id_ed25519.pub | ssh bu_username@scc1.bu.edu "cat >> ~/.ssh/authorized_keys"
# The key is sent from a file so PowerShell can't change its line ending, and it
# starts with a newline in case the existing file's last line isn't terminated.
function Copy-KeyToScc {
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Write-TextFile $tmp ("`n" + (Read-TextFile $PubFile).Trim() + "`n")
        $ssh = @{
            FilePath              = $script:SshExe
            ArgumentList          = "$script:BuUser@$LoginNode `"umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys`""
            RedirectStandardInput = $tmp
            NoNewWindow           = $true
            Wait                  = $true
        }
        Start-Process @ssh
    } finally {
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }
}

function Initialize-SshKey {
    Write-Host ''
    Write-Host 'Step 1: SSH key'

    if (-not $script:SshExe -or -not $script:SshKeygen) {
        Write-Warn 'ssh.exe and ssh-keygen.exe were not found. Install Git for Windows from',
                   'https://git-scm.com/download/win and re-run this script.'
        return
    }

    $hasKey = Test-Path -LiteralPath $KeyFile
    $hasPub = Test-Path -LiteralPath $PubFile
    if ($hasKey -and $hasPub) {
        Write-Ok "Found your SSH key pair $KeyFile and $PubFile"
    } elseif ($hasKey) {
        Write-Host "  Found $KeyFile but not $PubFile, recreating the public key."
        $pub = & $script:SshKeygen -y -f $KeyFile
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Could not recreate $PubFile"
            return
        }
        Write-TextFile $PubFile "$pub`n"
        Write-Ok "Created $PubFile"
    } elseif ($hasPub) {
        Write-Warn "Found $PubFile but not the matching private key $KeyFile.",
                   "Rename $PubFile and re-run this script to create a new key pair."
        return
    } else {
        Write-Host "  You don't have an SSH key pair ($KeyFile) yet."
        if (-not (Read-YesNo 'Create one now?' $true)) {
            Write-Warn "Skipped. The SSH config in Step 2 expects $KeyFile."
            return
        }
        if (-not (Test-Path -LiteralPath $SshDir)) {
            New-Item -ItemType Directory -Path $SshDir -ErrorAction Stop | Out-Null
        }
        # Start-Process hands ssh-keygen -N "" (an empty passphrase) exactly as written,
        # which calling it directly doesn't do in every PowerShell version
        $keygen = @{
            FilePath     = $script:SshKeygen
            ArgumentList = "-q -t ed25519 -N `"`" -f `"$KeyFile`""
            NoNewWindow  = $true
            Wait         = $true
            PassThru     = $true
        }
        if ((Start-Process @keygen).ExitCode -ne 0) {
            Write-Warn 'ssh-keygen failed'
            return
        }
        Write-Ok "Created $KeyFile and $PubFile"
    }

    Write-Host "  Checking whether the key logs you in to $LoginNode..."
    if (Test-KeyLogin) {
        Write-Ok "Passwordless login to $LoginNode already works"
        return
    }
    Write-Host '  Your public key needs to be copied to the SCC. You will be asked for your'
    Write-Host '  BU password, and if asked whether to continue connecting, answer yes.'
    if (-not (Read-YesNo "Copy $PubFile to $script:BuUser@$LoginNode now?" $true)) {
        Write-Warn 'Skipped. Re-run this script later to copy it.'
        return
    }
    Copy-KeyToScc
    if (Test-KeyLogin) {
        Write-Ok "Passwordless login to $LoginNode works"
    } else {
        Write-Warn "Passwordless login to $LoginNode still doesn't work. Re-run this script to try again."
    }
}

function Add-SshConfigHosts {
    Write-Host ''
    Write-Host "Step 2: SSH config file $SshConfig"

    $text = Read-TextFile $SshConfig
    $nl = Get-LineEnding $text
    $identity = if ($KeyFile -match '\s') { "`"$KeyFile`"" } else { $KeyFile }
    $user = $script:BuUser
    $proxySsh = $script:ProxySsh

    $block = @"
$BlockBegin
# Added by install-win-scc.ps1. See README-scc.md for how to customize these hosts.

# A 1-core 4-hour job
Host SCC-remote-cpu
    User $user
    IdentityFile $identity
    ProxyCommand "$proxySsh" $user@$LoginNode "~/bin/vscode-remote-scc -l h_rt=04:00:00"
    StrictHostKeyChecking no

# A 4-core 12-hour job where the SCC job is named "multicore"
# Modules python3/3.13.8 and matlab/2025a are preloaded
Host SCC-remote-cpu4
    User $user
    IdentityFile $identity
    ProxyCommand "$proxySsh" $user@$LoginNode "~/bin/vscode-remote-scc -N multicore -pe omp 4 -l h_rt=12:00:00 -z python3/3.13.8,matlab/2025a"
    StrictHostKeyChecking no
$BlockEnd
"@
    $block = $block -replace "`r?`n", $nl

    # From the BEGIN line through the END line, leaving their line endings alone
    $blockRe = '(?ms)^' + [regex]::Escape($BlockBegin) + '(?=\r?$).*?^' + [regex]::Escape($BlockEnd) + '(?=\r?$)'
    $hostRe  = '(?im)^[ \t]*Host[ \t](.*[ \t])?SCC-remote-cpu4?(?=\s|$)'

    if ($text -match ('(?m)^' + [regex]::Escape($BlockBegin) + '\r?$')) {
        $m = [regex]::Match($text, $blockRe)
        if (-not $m.Success) {
            Write-Warn "$SshConfig has a `"$BlockBegin`" line with no",
                       "`"$BlockEnd`" line after it. Fix it by hand, then re-run this script."
            return
        }
        Write-Host '  Your SSH config already has the SCC hosts from an earlier run of this script.'
        if (-not (Read-YesNo 'Replace them with a fresh copy?' $false)) {
            Write-Ok "Left $SshConfig unchanged"
            return
        }
        Backup-File $SshConfig
        Write-TextFile $SshConfig ($text.Substring(0, $m.Index) + $block + $text.Substring($m.Index + $m.Length))
        Write-Ok "Replaced the SCC hosts in $SshConfig"
    } elseif ($text -match $hostRe) {
        Write-Warn "$SshConfig already has an SCC-remote-cpu or SCC-remote-cpu4 host, so it",
                   'was left unchanged. Compare it with the Windows example in README-scc.md.'
    } else {
        if ($text.Length -gt 0) {
            Backup-File $SshConfig
            # Finish an unterminated last line, then leave a blank line before the new hosts
            if (-not $text.EndsWith("`n")) { $text += $nl }
            $text += $nl
        } elseif (-not (Test-Path -LiteralPath $SshDir)) {
            New-Item -ItemType Directory -Path $SshDir -ErrorAction Stop | Out-Null
        }
        Write-TextFile $SshConfig ($text + $block + $nl)
        Write-Ok "Added hosts SCC-remote-cpu and SCC-remote-cpu4 to $SshConfig"
    }
}

# Edits settings.json as text, rather than parsing it, so its comments and layout survive
function Update-VSCodeSettings {
    Write-Host ''
    Write-Host 'Step 3: VS Code Remote-SSH settings'
    Write-Host "  This sets Connect Timeout to $ConnectTimeout seconds and turns on Enable Agent"
    Write-Host '  Forwarding, Enable Dynamic Forwarding, Enable Remote Command, and Use Local'
    Write-Host "  Server in $VSCodeSettings"
    if (-not (Read-YesNo 'Update your VS Code settings?' $true)) {
        Write-Warn 'Skipped. Set these by hand as described in Step 3 of README-scc.md.'
        return
    }

    $original = Read-TextFile $VSCodeSettings
    $text = if ($original.Trim()) { $original } else { "{`r`n}`r`n" }
    $nl = Get-LineEnding $text

    # The file without its // comment lines, for checks that shouldn't be fooled by them
    $code = ($text -split "`r?`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    if ($code -notmatch '\{') {
        Write-Warn "$VSCodeSettings doesn't look like a VS Code settings file, so it was left unchanged."
        return
    }
    $hasSettings = $code -match '"'

    $newLines = @()
    foreach ($key in $VSCodeSshSettings.Keys) {
        $value = $VSCodeSshSettings[$key]
        $keyRe = [regex]::Escape($key)
        $re = [regex]('(?m)^([ \t]*"' + $keyRe + '"[ \t]*:[ \t]*)([^,}/\s]*)')
        $m = $re.Match($text)
        if ($m.Success) {
            # The setting is on a line of its own: change its value in place
            $current = $m.Groups[2].Value
            if ($current -ceq $value -or
                ($key -eq 'remote.SSH.connectTimeout' -and $current -match '^\d+$' -and [long]$current -ge $ConnectTimeout)) {
                Write-Ok "$key is already $current"
            } else {
                $text = $re.Replace($text, '${1}' + $value)
                Write-Ok "Changed $key from $current to $value"
            }
        } elseif ($code -match ('"' + $keyRe + '"')) {
            Write-Warn "Couldn't safely change $key in $VSCodeSettings. Please set it to $value by hand."
        } else {
            $newLines += '    "' + $key + '": ' + $value
            Write-Ok "Set $key to $value"
        }
    }

    if ($newLines.Count -gt 0) {
        # Put the new settings just after the opening {, separated by commas. The last
        # one needs a comma too if there are already settings after it.
        $insert = $newLines -join ",$nl"
        if ($hasSettings) { $insert += ',' }
        $open = [regex]'(?m)^(?![ \t]*//)([^\r\n{]*)\{[ \t]*(\r?\n)?'
        $text = $open.Replace($text, '${1}{' + $nl + $insert + $nl, 1)
    }

    if ($text -ceq $original) { return }
    if ($original) {
        Backup-File $VSCodeSettings
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $VSCodeSettings) -ErrorAction Stop | Out-Null
    }
    Write-TextFile $VSCodeSettings $text
    Write-Ok "Saved $VSCodeSettings"
}

function Main {
    Write-Host 'This script sets up this computer to connect VS Code to the BU SCC.'
    Write-Host ''

    $script:GitSsh = Find-GitSsh
    if ($script:GitSsh) {
        $script:ProxySsh = $script:GitSsh
    } else {
        $script:ProxySsh = $DefaultGitSsh
        Write-Warn 'Git for Windows was not found. The SSH config it sets up uses Git''s ssh.exe,',
                   'so install Git from https://git-scm.com/download/win before connecting.'
        Write-Host ''
    }
    $script:SshExe = Find-SshTool 'ssh'
    $script:SshKeygen = Find-SshTool 'ssh-keygen'

    $script:BuUser = Read-BuUsername
    Initialize-SshKey
    Add-SshConfigHosts
    Update-VSCodeSettings

    Write-Host ''
    Write-Host 'Finished. Next steps:'
    Write-Host '  * If you haven''t already, do the "SCC Setup" step in README-scc.md: log in to the'
    Write-Host '    SCC, clone https://github.com/bu-rcs/vscode-remote-hpc, and run scc/install-scc.sh.'
    Write-Host '  * In VS Code, install the Remote - SSH extension if you don''t have it, then press'
    Write-Host '    Ctrl-Shift-P, run "Remote-SSH: Connect to Host...", and pick SCC-remote-cpu'
    Write-Host '    or SCC-remote-cpu4.'
}

try {
    Main
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
} finally {
    # Keeps the window open when the script was started with "Run with PowerShell"
    Write-Host ''
    Read-Host 'Press Enter to finish' | Out-Null
}
