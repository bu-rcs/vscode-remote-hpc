#!/bin/bash

if [ ! -d "${HOME:-~}.ssh" ]; then
    mkdir -p ${HOME:-~}/.ssh
fi

if [ ! -f "${HOME:-~}/.ssh/vscode-remote-hostkey" ]; then
    ssh-keygen -t ed25519 -f ${HOME:-~}/.ssh/vscode-remote-hostkey -N ""
fi

if [ -f "/usr/sbin/sshd" ]; then
    sshd_cmd=/usr/sbin/sshd
else
    sshd_cmd=sshd
fi

sshd_config="${TMPDIR:-/tmp}/sshd_config_${USER}_$$"

# Copy in variables related to Lmod, SGE, and the queue run environment.
vars="LMOD_COLORIZE LMOD_VERSION LMOD_SHELL_PRGM __LMOD_REF_COUNT_CMAKE_PREFIX_PATH \
LMOD_sys LOADEDMODULES LMOD_ROOT MODULEPATH MODULEPATH_ROOT MODULESHOME \
LMOD_SETTARG_FULL_SUPPORT LMOD_PKG LMOD_CMD LMOD_DIR CUDA_VISIBLE_DEVICES \
NSLOTS JOB_ID NHOSTS PE_HOSTFILE TMPDIR SGE_TASK_STEPSIZE SGE_O_WORKDIR SGE_O_HOME \
SGE_ARCH SGE_CELL SGE_TASK_LAST SGE_TASK_ID SGE_BINARY_PATH SGE_STDERR_PATH \
SGE_STDOUT_PATH SGE_ACCOUNT SGE_ROOT SGE_JOB_SPOOL_DIR SGE_CWD_PATH SGE_O_LOGNAME \
SGE_O_MAIL SGE_TASK_FIRST SGE_O_PATH SGE_O_HOST SGE_O_SHELL SGE_STDIN_PATH PATH \
LD_LIBRARY_PATH"

{
    for v in $vars; do
        if [ -n "${!v+x}" ]; then
            printf 'SetEnv %s="%s"\n' "$v" "${!v}"
        fi
    done
    printf '\n'
} > "$sshd_config"

$sshd_cmd -D -p "$1" -f "$sshd_config" -h "${HOME:-~}/.ssh/vscode-remote-hostkey"

rm -f $sshd_config
