#!/bin/bash

EXT_IFACE=ens4
MEM_LIMIT=128M
SERVICE=22

QUOTA_IN=5242880
QUOTA_OUT=1310720
REMOTE_HOST=`echo ${REMOTE_HOST} | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'`

{
    CONTAINER_NAME="honeypot-${REMOTE_HOST}"
    HOSTNAME=$(/bin/hostname)

    # check if the container exists
    if ! /usr/bin/docker inspect "${CONTAINER_NAME}" &> /dev/null; then
        # create new container
        CONTAINER_ID=$(/usr/bin/docker run --name ${CONTAINER_NAME} -h ${HOSTNAME} -e "REMOTE_HOST=${REMOTE_HOST}" -m ${MEM_LIMIT} -d -i honeypot ) ##/sbin/init)
        CONTAINER_IP=$(/usr/bin/docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${CONTAINER_ID})
        PROCESS_ID=$(/usr/bin/docker inspect --format '{{ .State.Pid }}' ${CONTAINER_ID})

        # drop all inbound and outbound traffic by default
        /usr/bin/nsenter --target ${PROCESS_ID} -n /sbin/iptables -P INPUT DROP
        /usr/bin/nsenter --target ${PROCESS_ID} -n /sbin/iptables -P OUTPUT DROP

        # allow access to the service regardless of the quota
        /usr/bin/nsenter --target ${PROCESS_ID} -n /sbin/iptables -A INPUT -p tcp -m tcp --dport ${SERVICE} -j ACCEPT
        /usr/bin/nsenter --target ${PROCESS_ID} -n /sbin/iptables -A INPUT -m quota --quota ${QUOTA_IN} -j ACCEPT

        # allow related outbound access limited by the quota
        /usr/bin/nsenter --target ${PROCESS_ID} -n /sbin/iptables -A OUTPUT -p tcp --sport ${SERVICE} -m state --state ESTABLISHED,RELATED -m quota --quota ${QUOTA_OUT} -j ACCEPT

        # enable the host to connect to rsyslog on the host
        /usr/bin/nsenter --target ${PROCESS_ID} -n /sbin/iptables -A OUTPUT -p tcp -m tcp --dst 172.17.0.1 --dport 514 -j ACCEPT

        # add iptables redirection rule
        /sbin/iptables -t nat -A PREROUTING -i ${EXT_IFACE} -s ${REMOTE_HOST} -p tcp --dport ${SERVICE} -j DNAT --to-destination ${CONTAINER_IP}
        /sbin/iptables -t nat -A POSTROUTING -j MASQUERADE
    else
        # start container if exited and grab the cid
        /usr/bin/docker start "${CONTAINER_NAME}" &> /dev/null
        CONTAINER_ID=$(/usr/bin/docker inspect --format '{{ .Id }}' "${CONTAINER_NAME}")
        CONTAINER_IP=$(/usr/bin/docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${CONTAINER_ID})

        # add iptables redirection rule
        /sbin/iptables -t nat -A PREROUTING -i ${EXT_IFACE} -s ${REMOTE_HOST} -p tcp --dport ${SERVICE} -j DNAT --to-destination ${CONTAINER_IP}
        /sbin/iptables -t nat -A POSTROUTING -j MASQUERADE
    fi
} &> /dev/null

# forward traffic to the container
exec /usr/bin/socat stdin tcp:${CONTAINER_IP}:22,retry=60
           