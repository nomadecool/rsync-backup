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
    echo "Defina una ruta de configuración /backup."
    echo "This should be a physical path, such as:"
    echo "Esto debería ser una ruta física, como:"
    echo "-v \"~/backup:/backup\""
    fail="1"
fi
if [[ "${fail}" -eq "1" ]]; then
    echo "Please set environmental flag 'NODE=[sender|receiver]'"
    echo "Por favor, establezca la bandera de ambiente 'NODE=[sender|receiver]'"
    exit 1
fi

# Create rsync-user if it does not exist
if ! id -u rsync-user > /dev/null 2>&1; then
    adduser --gecos "" --disabled-password rsync-user
    mkdir -p /home/rsync-user/.ssh
    chown rsync-user:rsync-user /home/rsync-user/.ssh
    chmod 700 /home/rsync-user/.ssh
fi

if [[ "${NODE,,}" == "sender" ]]; then
    if ! grep -q "/home/rsync-user" /etc/mtab; then
        echo "Please define a rsync-user config path."
        echo "Defina una ruta de configuración rsync-user."
        echo "This should be a physical path, such as:"
        echo "Esto debería ser una ruta física, como:"
        echo "-v \"~/Docker/rsync-backup/rsync-user:/home/rsync-user\""
        exit 2
    fi
    if ! [[ -e "/home/rsync-user/.ssh/id_ed25519" ]]; then
        ssh-keygen -b 2048 -t ed25519 -f /home/rsync-user/.ssh/id_ed25519 -q -N ""
        chmod 400 "/home/rsync-user/.ssh/id_ed25519"
        chown rsync-user:rsync-user "/home/rsync-user/.ssh/id_ed25519"
        echo ""
        echo "On the receiver node, create an authorized_keys file in the config directory"
        echo "En el nodo receptor, cree un archivo authorized_keys en el directorio de configuración"
        echo ""
        echo "For example, if your 'config' volume mount on the receiver is:"
        echo "Por ejemplo, si su montaje de volumen 'config' en el receptor es:"
        echo "-v /Docker/rsync-backup/rsync-user:/home/rsync-user"
        echo ""
        echo "Then you would create a file at:"
        echo "Entonces crearías un archivo en:"
        echo "/Docker/rsync-backup/rsync-user/.ssh/authorized_keys"
        echo ""
        echo "Copy/paste the contents between the ##### markers into that authorized_keys file:"
        echo "Copie/pegue el contenido entre los marcadores ##### en ese archivo authorized_keys:"
        echo ""
        echo "####### COPY BELOW THIS LINE, BUT NOT THIS LINE ######## ####### COPIE DEBAJO DE ESTA LÍNEA, PERO NO ESTA LÍNEA ########"
        cat "/home/rsync-user/.ssh/id_ed25519.pub"
        echo "####### COPY ABOVE THIS LINE, BUT NOT THIS LINE ######## ####### COPIE ARRIBA DE ESTA LÍNEA, PERO NO ESTA LÍNEA ########"
        echo ""
        echo "Once done, re-start this container."
        echo "Una vez hecho esto, reinicie este contenedor."
        exit 0
    fi
    if ! [[ -e "/home/rsync-user/.ssh/known_hosts" ]]; then
        ssh-keyscan -p ${REM_SSH_PORT} ${REM_HOST} > /home/rsync-user/.ssh/known_hosts 2>/dev/null
        if [[ "${?}" -ne "0" || "$(wc -l "/home/rsync-user/.ssh/known_hosts" | awk '{print $1}')" -eq "0" ]]; then
            echo "Unable to initiate keyscan. Is the receiver online?"
            echo "Incapaz de iniciar el keyscan. ¿Está en línea el receptor?"
            rm "/home/rsync-user/.ssh/known_hosts"
            exit 3
        fi
    fi

    inotifywait -r -m -e close_write --format '%w%f' /backup/ | while read MODFILE
    do
        rsync -a -P -e "ssh -p ${REM_SSH_PORT}" /backup/ rsync-user@${REM_HOST}:/backup/ --delete
        if [[ "${?}" -ne "0" ]]; then
            echo "Unable to initiate backup rsync. Is the receiver online?"
            echo "Incapaz de iniciar el rsync de respaldo. ¿Está en línea el receptor?"
            exit 4
        fi
    done
fi

if [[ "${NODE,,}" == "receiver" ]]; then
    if ! grep -q "/etc/ssh" /etc/mtab; then
        echo "Please define an /etc/ssh config path."
        echo "Defina una ruta de configuración /etc/ssh."
        echo "This should be a physical path, such as:"
        echo "Esto debería ser una ruta física, como:"
        echo "-v \"~/Docker/rsync-backup/etc-ssh:/etc/ssh\""
        exit 5
    fi
    if ! grep -q "/home/rsync-user" /etc/mtab; then
        echo "Please define a rsync-user config path."
        echo "Defina una ruta de configuración rsync-user."
        echo "This should be a physical path, such as:"
        echo "Esto debería ser una ruta física, como:"
        echo "-v \"~/Docker/rsync-backup/rsync-user:/home/rsync-user\""
        exit 6
    fi
    if ! [[ -e "/home/rsync-user/.ssh/authorized_keys" ]]; then
        echo "Please obtain the 'authorized_keys' file from the sender,"
        echo "Por favor, obtenga el archivo 'authorized_keys' del remitente,"
        echo "and add it at your home/rsync-user/.ssh/authorized_keys path"
        echo "y añádalo en su ruta home/rsync-user/.ssh/authorized_keys"
        exit 7
    fi
    sshKeyArr=("ssh_host_dsa_key" "ssh_host_dsa_key.pub" "ssh_host_ecdsa_key" "ssh_host_ecdsa_key.pub" "ssh_host_ed25519_key" "ssh_host_ed25519_key.pub" "ssh_host_rsa_key" "ssh_host_rsa_key.pub")
    for i in "${sshKeyArr[@]}"; do
        if ! [[ -e "/etc/ssh/${i}" ]]; then
            ssh-keygen -A
        fi
    done
    mv /sshd_config /etc/ssh/sshd_config
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
    # Ensure permissions are correct on the rsync-user directory, or it won't let
    # us rsync/ssh in as the rsync-user
    # Asegúrese de que los permisos sean correctos en el directorio rsync-user, o no nos permitirá
    # rsync/ssh como rsync-user
    chmod 700 /home/rsync-user
    chmod 700 /home/rsync-user/.ssh
    chmod 600 /home/rsync-user/.ssh/authorized_keys
    /usr/sbin/sshd -D -e
    while true; do sleep 1000; done
fi
