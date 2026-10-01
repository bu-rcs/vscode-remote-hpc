#!/bin/bash
#
# install-mac-scc.sh -- set up a Mac to use vscode-remote-hpc on the BU SCC
#
# This does the steps from README-scc.md that happen on your own computer:
#
#   Step 1: create an SSH key pair, if you don't have one, and copy it to the SCC
#   Step 2: add the sample SCC-remote-cpu and SCC-remote-cpu4 hosts to ~/.ssh/config
#   Step 3: set the VS Code Remote-SSH settings, including Connect Timeout = 3600
#
# You still need to do the "SCC Setup" step from README-scc.md on the SCC itself.
#
# To run it, open a Terminal window, cd to the folder holding this script, and run:
#
#     bash install-mac-scc.sh
#
# It asks before each step, backs up any file it changes, and is safe to re-run.

if [ -z "$BASH_VERSION" ]; then
    echo "Please run this script with bash:  bash install-mac-scc.sh"
    exit 1
fi

LOGIN_NODE=scc1.bu.edu
CONNECT_TIMEOUT=3600

SSH_DIR="$HOME/.ssh"
KEY_FILE="$SSH_DIR/id_ed25519"
SSH_CONFIG="$SSH_DIR/config"

if [ "$(uname -s)" = "Darwin" ]; then
    VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
else
    VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
fi

# The Remote-SSH settings from README-scc.md Step 3, as key=JSON value
VSCODE_SSH_SETTINGS="remote.SSH.connectTimeout=$CONNECT_TIMEOUT
remote.SSH.enableAgentForwarding=true
remote.SSH.enableDynamicForwarding=true
remote.SSH.enableRemoteCommand=true
remote.SSH.useLocalServer=true"

# Marks the lines this script adds to ~/.ssh/config so a re-run can find them
BLOCK_BEGIN="# BEGIN vscode-remote-hpc SCC hosts"
BLOCK_END="# END vscode-remote-hpc SCC hosts"


# ask "question" y|n -- the second argument is the answer used if you just press Return
function ask () {
    local reply hint="[y/N]"
    [ "$2" = "y" ] && hint="[Y/n]"
    while true; do
        read -r -p "$1 $hint " reply
        reply=$(printf '%s' "${reply:-$2}" | tr '[:upper:]' '[:lower:]')
        case "$reply" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
        esac
        echo "Please answer y or n."
    done
}

# backup FILE -- copy FILE to FILE.bak.<date-time>
function backup () {
    local copy
    copy="$1.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "$1" "$copy" || return 1
    echo "  + Backed up $1 to $copy"
}

# key_login_works -- true if the key logs in to the SCC without a password
function key_login_works () {
    ssh -n -q -o BatchMode=yes -o ConnectTimeout=15 -o IdentitiesOnly=yes \
        -i "$KEY_FILE" "$BU_USER@$LOGIN_NODE" true > /dev/null 2>&1
}

function get_username () {
    while true; do
        read -r -p "Your BU username (the one you use to log in to the SCC): " BU_USER || exit 1
        BU_USER=$(printf '%s' "$BU_USER" | tr '[:upper:]' '[:lower:]')
        BU_USER=${BU_USER%@bu.edu}
        if [[ ! $BU_USER =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
            echo "  - That doesn't look like a BU username, please try again."
        elif ask "Use '$BU_USER'?" y; then
            return
        fi
    done
}

function setup_ssh_key () {
    echo
    echo "Step 1: SSH key"

    if [ -f "$KEY_FILE" ] && [ -f "$KEY_FILE.pub" ]; then
        echo "  + Found your SSH key pair $KEY_FILE and $KEY_FILE.pub"
    elif [ -f "$KEY_FILE" ]; then
        echo "  Found $KEY_FILE but not $KEY_FILE.pub, recreating the public key."
        if ! ssh-keygen -y -f "$KEY_FILE" > "$KEY_FILE.pub"; then
            rm -f "$KEY_FILE.pub"
            echo "  - Could not recreate $KEY_FILE.pub"
            return
        fi
        echo "  + Created $KEY_FILE.pub"
    elif [ -f "$KEY_FILE.pub" ]; then
        echo "  - Found $KEY_FILE.pub but not the matching private key $KEY_FILE."
        echo "    Rename $KEY_FILE.pub and re-run this script to create a new key pair."
        return
    else
        echo "  You don't have an SSH key pair ($KEY_FILE) yet."
        if ! ask "Create one now?" y; then
            echo "  - Skipped. The SSH config in Step 2 expects $KEY_FILE."
            return
        fi
        if [ ! -d "$SSH_DIR" ]; then
            mkdir -m 700 "$SSH_DIR" || return
        fi
        if ! ssh-keygen -q -t ed25519 -N "" -f "$KEY_FILE"; then
            echo "  - ssh-keygen failed"
            return
        fi
        echo "  + Created $KEY_FILE and $KEY_FILE.pub"
    fi

    echo "  Checking whether the key logs you in to $LOGIN_NODE..."
    if key_login_works; then
        echo "  + Passwordless login to $LOGIN_NODE already works"
        return
    fi
    echo "  Your public key needs to be copied to the SCC. ssh-copy-id will ask for your"
    echo "  BU password, and if it asks whether to continue connecting, answer yes."
    if ! ask "Copy $KEY_FILE.pub to $BU_USER@$LOGIN_NODE now?" y; then
        echo "  - Skipped. To copy it later, run: ssh-copy-id -i $KEY_FILE $BU_USER@$LOGIN_NODE"
        return
    fi
    ssh-copy-id -i "$KEY_FILE.pub" "$BU_USER@$LOGIN_NODE"
    if key_login_works; then
        echo "  + Passwordless login to $LOGIN_NODE works"
    else
        echo "  - Passwordless login to $LOGIN_NODE still doesn't work. To try again, run:"
        echo "      ssh-copy-id -i $KEY_FILE $BU_USER@$LOGIN_NODE"
    fi
}

function setup_ssh_config () {
    echo
    echo "Step 2: SSH config file $SSH_CONFIG"

    local tmp block="$BLOCK_BEGIN
# Added by install-mac-scc.sh. See README-scc.md for how to customize these hosts.

# A 1-core 4-hour job
Host SCC-remote-cpu
    User $BU_USER
    IdentityFile ~/.ssh/id_ed25519
    ProxyCommand ssh $BU_USER@$LOGIN_NODE \"~/bin/vscode-remote-scc -l h_rt=04:00:00\"
    StrictHostKeyChecking no

# A 4-core 12-hour job
# Modules python3/3.13.8 and matlab/2025a are preloaded
Host SCC-remote-cpu4
    User $BU_USER
    IdentityFile ~/.ssh/id_ed25519
    ProxyCommand ssh $BU_USER@$LOGIN_NODE \"~/bin/vscode-remote-scc -pe omp 4 -l h_rt=12:00:00 -z python3/3.13.8,matlab/2025a\"
    StrictHostKeyChecking no
$BLOCK_END"

    if [ ! -d "$SSH_DIR" ]; then
        mkdir -m 700 "$SSH_DIR" || return
    fi

    if [ -f "$SSH_CONFIG" ] && grep -qxF "$BLOCK_BEGIN" "$SSH_CONFIG"; then
        tmp=$(mktemp "${TMPDIR:-/tmp}/vscode-remote-hpc.XXXXXX") || return
        # Swap the old block for the new one. Fails if the END line is missing.
        if ! BLOCK="$block" awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
                $0 == b { print ENVIRON["BLOCK"]; skip = 1; next }
                skip    { if ($0 == e) skip = 0; next }
                        { print }
                END     { exit skip }' "$SSH_CONFIG" > "$tmp"; then
            rm -f "$tmp"
            echo "  - $SSH_CONFIG has a \"$BLOCK_BEGIN\" line with no"
            echo "    \"$BLOCK_END\" line after it. Fix it by hand, then re-run this script."
            return
        fi
        echo "  $SSH_CONFIG already has the SCC hosts from an earlier run of this script."
        if ! ask "Replace them with a fresh copy?" n; then
            rm -f "$tmp"
            echo "  + Left $SSH_CONFIG unchanged"
            return
        fi
        backup "$SSH_CONFIG" || { rm -f "$tmp"; return; }
        cat "$tmp" > "$SSH_CONFIG"
        rm -f "$tmp"
        echo "  + Replaced the SCC hosts in $SSH_CONFIG"
    elif [ -f "$SSH_CONFIG" ] &&
         grep -qiE '^[[:space:]]*Host[[:space:]](.*[[:space:]])?SCC-remote-cpu4?([[:space:]]|$)' "$SSH_CONFIG"; then
        echo "  - $SSH_CONFIG already has an SCC-remote-cpu or SCC-remote-cpu4 host, so it"
        echo "    was left unchanged. Compare it with the Mac example in README-scc.md."
    else
        if [ -f "$SSH_CONFIG" ]; then
            backup "$SSH_CONFIG" || return
            # Finish an unterminated last line, then leave a blank line before the new hosts
            [ -n "$(tail -c 1 "$SSH_CONFIG")" ] && echo >> "$SSH_CONFIG"
            [ -s "$SSH_CONFIG" ] && echo >> "$SSH_CONFIG"
        else
            touch "$SSH_CONFIG" && chmod 600 "$SSH_CONFIG" || return
        fi
        printf '%s\n' "$block" >> "$SSH_CONFIG"
        echo "  + Added hosts SCC-remote-cpu and SCC-remote-cpu4 to $SSH_CONFIG"
    fi
}

# Edits settings.json as text, rather than parsing it, so its comments and layout survive
function setup_vscode () {
    echo
    echo "Step 3: VS Code Remote-SSH settings"
    echo "  This sets Connect Timeout to $CONNECT_TIMEOUT seconds and turns on Enable Agent"
    echo "  Forwarding, Enable Dynamic Forwarding, Enable Remote Command, and Use Local"
    echo "  Server in $VSCODE_SETTINGS"
    if ! ask "Update your VS Code settings?" y; then
        echo "  - Skipped. Set these by hand as described in Step 3 of README-scc.md."
        return
    fi

    local file="$VSCODE_SETTINGS" work kv key key_re value current new="" changed=0

    work=$(mktemp "${TMPDIR:-/tmp}/vscode-remote-hpc.XXXXXX") || return
    if [ -f "$file" ] && grep -q '[^[:space:]]' "$file"; then
        cp "$file" "$work"
    else
        printf '{\n}\n' > "$work"
        changed=1
    fi
    if ! grep -v '^[[:space:]]*//' "$work" | grep -q '{'; then
        echo "  - $file doesn't look like a VS Code settings file, so it was left unchanged."
        rm -f "$work"
        return
    fi

    for kv in $VSCODE_SSH_SETTINGS; do
        key=${kv%%=*}
        value=${kv#*=}
        key_re=$(printf '%s' "$key" | sed 's/\./\\./g')
        if grep -qE "^[[:space:]]*\"$key_re\"[[:space:]]*:" "$work"; then
            # The setting is on a line of its own: change its value in place
            current=$(sed -nE "s#^[[:space:]]*\"$key_re\"[[:space:]]*:[[:space:]]*([^,}/[:space:]]*).*#\1#p" "$work" | head -n 1)
            if [ "$current" = "$value" ] ||
               { [ "$key" = remote.SSH.connectTimeout ] && [[ $current =~ ^[0-9]+$ ]] && [ "$current" -ge "$value" ]; }; then
                echo "  + $key is already $current"
            else
                sed -E "s#^([[:space:]]*\"$key_re\"[[:space:]]*:[[:space:]]*)[^,}/[:space:]]*#\1$value#" "$work" > "$work.new" &&
                    mv "$work.new" "$work"
                echo "  + Changed $key from $current to $value"
                changed=1
            fi
        elif grep -v '^[[:space:]]*//' "$work" | grep -qF "\"$key\""; then
            echo "  - Couldn't safely change $key in $file. Please set it to $value by hand."
        else
            new="$new    \"$key\": $value
"
            echo "  + Set $key to $value"
            changed=1
        fi
    done

    if [ -n "$new" ]; then
        # Put the new settings just after the opening {, separated by commas. The last
        # one needs a comma too if there are already settings after it.
        new=$(printf '%s' "$new" | sed '$!s/$/,/')
        if grep -v '^[[:space:]]*//' "$work" | grep -q '"'; then
            new="$new,"
        fi
        NEW="$new" awk '
            !done && !/^[ \t]*\/\// && (i = index($0, "{")) {
                print substr($0, 1, i)
                print ENVIRON["NEW"]
                rest = substr($0, i + 1)
                if (rest ~ /[^ \t]/) print rest
                done = 1
                next
            }
            { print }' "$work" > "$work.new" && mv "$work.new" "$work"
    fi

    if [ "$changed" = 1 ]; then
        if [ -f "$file" ]; then
            backup "$file" || { rm -f "$work"; return; }
        else
            mkdir -p "$(dirname "$file")" || { rm -f "$work"; return; }
        fi
        cat "$work" > "$file" && echo "  + Saved $file"
    fi
    rm -f "$work"
}


echo "This script sets up this computer to connect VS Code to the BU SCC."
echo
get_username
setup_ssh_key
setup_ssh_config
setup_vscode

cat <<EOF

Finished. Next steps:
  * If you haven't already, do the "SCC Setup" step in README-scc.md: log in to the
    SCC, clone https://github.com/bu-rcs/vscode-remote-hpc, and run scc/install-scc.sh.
  * In VS Code, install the Remote - SSH extension if you don't have it, then press
    Cmd-Shift-P, run "Remote-SSH: Connect to Host...", and pick SCC-remote-cpu
    or SCC-remote-cpu4.
EOF
