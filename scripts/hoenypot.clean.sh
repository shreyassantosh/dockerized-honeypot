#!/bin/bash

EXT_IFACE=eth0
SERVICE=22

HOSTNAME=$(/bin/hostname)
LIFETIME=$((3600 * 6)) # Six hours

datediff () {
    d1=$(/bin/date -d "$1" +%s)
    d2=$(/bin/date -d "$2" +%s)
    echo $((d1 - d2))
}

for CONTAINER_ID in $(/usr/bin/docker ps -a --no-trunc | grep "honeypot-" | cut -f1 -d" "); do
    STARTED=$(/usr/bin/docker inspect --format '{{ .State.StartedAt }}' ${CONTAINER_ID})
    RUNTIME=$(datediff now "${STARTED}")

    if [[ "${RUNTIME}" -gt "${LIFETIME}" ]]; then
        logger -p local3.info "Stopping honeypot container ${CONTAINER_ID}"
        /usr/bin/docker stop $CONTAINER_ID
    fi

    RUNNING=$(/usr/bin/docker inspect --format '{{ .State.Running }}' ${CONTAINER_ID})

    if [[ "$RUNNING" != "true" ]]; then
        # delete iptables rule
        CONTAINER_IP=$(/usr/bin/docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${CONTAINER_ID})
        REMOTE_HOST=$(/usr/bin/docker inspect --format '{{ .Name }}' ${CONTAINER_ID} | cut -f2 -d-)
        /sbin/iptables -t nat -D PREROUTING -i ${EXT_IFACE} -s ${REMOTE_HOST} -p tcp --dport ${SERVICE} -j DNAT --to-destination ${CONTAINER_IP}
        logger -p local3.info "Removing honeypot container ${CONTAINER_ID}"
        /usr/bin/docker rm $CONTAINER_ID
    fi
done
