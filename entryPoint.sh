#!/bin/bash

fail="1"
if [[ -z "${NODE,,}" ]]; then
    fail="0"
elif [[ "${NODE,,}" == "sender" ]]; then
    fail="0"
elif [[ "${NODE,,}" == "receiver" ]]; then
    fail="0"
elif ! grep -q "/backup" /etc/mtab; then
    echo "Defina una ruta de configuración /backup - Please define a /backup config path."
    echo "Esto debería ser una ruta física, como: - This should be a physical path, such as:"
    echo "-v \\"~/backup:/backup\\""
    fail="1"
fi
if [[ "${fail}" -eq "1" ]]; then
    echo "Por favor, establezca la bandera de ambiente 'NODE=[sender|receiver]'"
    echo "Please set environmental flag 'NODE=[sender|receiver]'"
    exit 1
fi

if [[ "${NODE,,}" == "sender" ]]; then
    if ! grep -q "/home/root" /etc/mtab; then
        echo "Por favor defina una ruta de configuración para root - Please define a root config path."
        echo "Esto debería ser una ruta física, como: - This should be a physical path, such as:"
        echo "-v \\"~/Docker/rsync-backup/root:/home/root\\""
        exit 2
    fi
    if ! [[ -e "/home/root/.ssh/id_ed25519" ]]; then
        mkdir -p /home/root/.ssh
        ssh-keygen -b 2048 -t ed25519 -f /home/root/.ssh/id_ed25519 -q -N ''
        chmod 400 "/home/root/.ssh/id_ed25519"
        chown root:root "/home/root/.ssh/id_ed25519"
        echo ""
        echo "En el nodo receptor, crea un archivo authorized_keys en el directorio de configuración - On the receiver node, create an authorized_keys file in the config directory"
        echo ""
        echo "Por ejemplo, si su montaje de volumen 'config' en el receptor es / For example, if your 'config' volume mount on the receiver is:"
        echo "-v /Docker/rsync-backup/root:/home/root"
        echo ""
        echo "Entonces crearías un archivo en / Then you would create a file at:"
        echo "/Docker/rsync-backup/root/.ssh/authorized_keys"
        echo ""
        echo "Copie/pegue el contenido entre los marcadores ##### en ese archivo authorized_keys / Copy/paste the contents between the ##### markers into that authorized_keys file:"
        echo ""
        echo "####### COPY BELOW THIS LINE, BUT NOT THIS LINE ######## ####### COPIE DEBAJO DE ESTA LÍNEA, PERO NO ESTA LÍNEA ########"
        cat "/home/root/.ssh/id_ed25519.pub"
        echo "####### COPY ABOVE THIS LINE, BUT NOT THIS LINE ######## ####### COPIE ARRIBA DE ESTA LÍNEA, PERO NO ESTA LÍNEA ########"
        echo ""
        echo "Una vez hecho esto, reinicie este contenedor / Once done, re-start this container."
        exit 0
    fi
    echo $(REM_HOST)
    echo $(REM_SSH_PORT)
    echo $(ls -ld /home/root/.ssh)
    if ! [[ -e "/home/root/.ssh/known_hosts" ]]; then
        ssh-keyscan -p ${REM_SSH_PORT} -t rsa ${REM_HOST} > /home/root/.ssh/known_hosts #2>/dev/null
        if [[ "${?}" -ne "0" || "$(wc -l "/root/.ssh/known_hosts" | awk '{print $1}')" -eq "0" ]]; then
            echo "Incapaz de iniciar el keyscan. ¿Está en línea el receptor? / Unable to initiate keyscan. Is the receiver online?"
            rm "/root/.ssh/known_hosts"
            exit 3
        fi
    fi

    inotifywait -r -m -e close_write --format '%w%f' /backup/ | while read MODFILE
    do
        rsync -a -P -e "ssh -p ${REM_SSH_PORT}" /backup/ root@${REM_HOST}:/backup/ --delete
        if [[ "${?}" -ne "0" ]]; then
            echo "Incapaz de iniciar el rsync de respaldo. ¿Está en línea el receptor? / Unable to initiate backup rsync. Is the receiver online?"
            exit 4
        fi
    done
fi

if [[ "${NODE,,}" == "receiver" ]]; then
    if ! grep -q "/etc/ssh" /etc/mtab; then
        echo "Defina una ruta de configuración /etc/ssh."
        echo "Please define an /etc/ssh config path."
        echo "Esto debería ser una ruta física, como / This should be a physical path, such as:"
        echo "-v \\"~/Docker/rsync-backup/etc-ssh:/etc/ssh\\""
        exit 5
    fi
    if ! grep -q "/home/root" /etc/mtab; then
        echo "Por favor defina una ruta de configuración para root / Please define a root config path."
        echo "Esto debería ser una ruta física, como / This should be a physical path, such as:"
        echo "-v \\"~/Docker/rsync-backup/root:/home/root\\""
        exit 6
    fi
    if ! [[ -e "/home/root/.ssh/authorized_keys" ]]; then
        mkdir -p /home/root/.ssh
        touch /home/root/.ssh/authorized_keys
        echo "Por favor, obtenga el archivo 'authorized_keys' del remitente / Please obtain the 'authorized_keys' file from the sender,"
        echo "y añádalo en su ruta home/root/.ssh/authorized_keys / and add it at your home/root/.ssh/authorized_keys path"
        exit 7
    fi
    num_lines=$(cat "/home/root/.ssh/authorized_keys" | wc -l)
    if [[ $num_lines -lt 1 ]] ; then
        echo "Por favor añada la keys del sender / Please add the key from sender,"
        echo "al archivo home/root/.ssh/authorized_keys / to your file home/root/.ssh/authorized_keys"
        exit 7
    fi
    sshKeyArr=("ssh_host_dsa_key" "ssh_host_dsa_key.pub" "ssh_host_ecdsa_key" "ssh_host_ecdsa_key.pub" "ssh_host_ed25519_key" "ssh_host_ed25519_key.pub" "ssh_host_rsa_key" "ssh_host_rsa_key.pub")
    for i in "${sshKeyArr[@]}"; do
        if ! [[ -e "/etc/ssh/${i}" ]]; then
            ssh-keygen -A
        fi
    done
    mkdir -p /run/sshd
    mv /sshd_config /etc/ssh/sshd_config
    # No podemos hacer SSH en root si no se establece una contraseña / We can't SSH into the root if it doesn't have a password set
    # Establecer una cadena aleatoria de 36 caracteres como contraseña / Set a random 36 character string as the password
    rootPass="$(date +%s | sha256sum | base64 | head -c 36)"
    echo "root:${rootPass}" | chpasswd
    # Asegúrese de que los permisos sean correctos en el directorio root, o no nos permitirá / Ensure permissions are correct on the root directory, or it won't let
    # rsync/ssh como root - us rsync/ssh in as the root user
    chmod 700 /root
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    /usr/sbin/sshd -D -e
fi
