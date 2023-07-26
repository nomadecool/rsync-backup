#!/bin/bash

fail="1"
if [[ -z "${NODE,,}" ]]; then
    fail="0"
elif [[ "${NODE,,}" == "sender" ]]; then
    fail="0"
elif [[ "${NODE,,}" == "receiver" ]]; then
    fail="0"
elif ! grep -q "/backup" /etc/mtab; then
    echo "Please define a /backup config path."
    echo "This should be a physical path, such as:"
    echo "-v \"~/backup:/backup\""
    fail="1"
fi
if [[ "${fail}" -eq "1" ]]; then
    echo "Please set environmental flag 'NODE=[sender|receiver]'"
    exit 1
fi

# Create rsync-user if it does not exist
if ! id -u rsync-user > /dev/null 2>&1; then
    useradd rsync-user
    echo "rsync-user:password" | chpasswd
    mkdir -p /home/rsync-user/.ssh
    chown rsync-user:rsync-user /home/rsync-user/.ssh
    chmod 700 /home/rsync-user/.ssh
fi

if [[ "${NODE,,}" == "sender" ]]; then
    if ! grep -q "/home/rsync-user" /etc/mtab; then
        echo "Please define a rsync-user config path."
        echo "This should be a physical path, such as:"
        echo "-v \"~/piholesync/home/rsync-user:/home/rsync-user\""
        exit 2
    fi
    if ! [[ -e "/home/rsync-user/.ssh/id_ed25519" ]]; then
        ssh-keygen -b 2048 -t ed25519 -f /home/rsync-user/.ssh/id_ed25519 -q -N ""
        chmod 400 "/home/rsync-user/.ssh/id_ed25519"
        chown rsync-user:rsync-user "/home/rsync-user/.ssh/id_ed25519"
        echo ""
        echo "On the receiver node, create an authorized_keys file in the config directory"
        echo ""
        echo "For example, if your 'config' volume mount on the receiver is:"
        echo "-v /docker/config/piholesync/home/rsync-user:/home/rsync-user"
        echo ""
        echo "Then you would create a file at:"
        echo "/docker/config/piholesync/home/rsync-user/.ssh/authorized_keys"
        echo ""
        echo "Copy/paste the contents between the ##### markers into that authorized_keys file:"
        echo ""
        echo "####### COPY BELOW THIS LINE, BUT NOT THIS LINE ########"
        cat "/home/rsync-user/.ssh/id_ed25519.pub"
        echo "####### COPY ABOVE THIS LINE, BUT NOT THIS LINE ########"
        echo ""
        echo "Once done, re-start this container."
        exit 0
    fi
    if ! [[ -e "/home/rsync-user/.ssh/known_hosts" ]]; then
        ssh-keyscan -p ${REM_SSH_PORT} ${REM_HOST} > /home/rsync-user/.ssh/known_hosts 2>/dev/null
        if [[ "${?}" -ne "0" || "$(wc -l "/home/rsync-user/.ssh/known_hosts" | awk '{print $1}')" -eq "0" ]]; then
            echo "Unable to initiate keyscan. Is the receiver online?"
            rm "/home/rsync-user/.ssh/known_hosts"
            exit 3
        fi
    fi

    inotifywait -r -m -e close_write --format '%w%f' /backup/ | while read MODFILE
    do
        rsync -a -P -e "ssh -p ${REM_SSH_PORT}" /backup/ rsync-user@${REM_HOST}:/backup/ --delete
        if [[ "${?}" -ne "0" ]]; then
            echo "Unable to initiate backup rsync. Is the receiver online?"
            exit 4
        fi
    done
fi

if [[ "${NODE,,}" == "receiver" ]]; then
    if ! grep -q "/etc/ssh" /etc/mtab; then
        echo "Please define an /etc/ssh config path."
        echo "This should be a physical path, such as:"
        echo "-v \"~/piholesync/etc-ssh:/etc/ssh\""
        exit 6
    fi
    if ! grep -q "/home/rsync-user" /etc/mtab; then
        echo "Please define a rsync-user config path."
        echo "This should be a physical path, such as:"
        echo "-v \"~/piholesync/home/rsync-user:/home/rsync-user\""
        exit 7
    fi
    if ! [[ -e "/home/rsync-user/.ssh/authorized_keys" ]]; then
        echo "Please obtain the 'authorized_keys' file from the sender,"
        echo "and add it at your home/rsync-user/.ssh/authorized_keys path"
        exit 8
    fi
    sshKeyArr=("ssh_host_dsa_key" "ssh_host_dsa_key.pub" "ssh_host_ecdsa_key" "ssh_host_ecdsa_key.pub" "ssh_host_ed25519_key" "ssh_host_ed25519_key.pub" "ssh_host_rsa_key" "ssh_host_rsa_key.pub")
    for i in "${sshKeyArr[@]}"; do
        if ! [[ -e "/etc/ssh/${i}" ]]; then
            ssh-keygen -A
        fi
    done
    mv /sshd_config /etc/ssh/sshd_config
    # Ensure permissions are correct on the rsync-user directory, or it won't let
    # us rsync/ssh in as the rsync-user
    chmod 700 /home/rsync-user
    chmod 700 /home/rsync-user/.ssh
    chmod 600 /home/rsync-user/.ssh/authorized_keys
    /usr/sbin/sshd -D -e
fi
