#!/bin/bash

# Swarm Size.
if [ -z "${SWARM_SIZE}" ]; then
    SWARM_SIZE=3
fi

#  or 'digitalocean'
if [ -z "${DOCKER_MACHINE_DRIVER}" ]; then
    DOCKER_MACHINE_DRIVER=virtualbox
fi

function build {
    # Build images
    docker build -t ${REGISTRY_HOST}/${REGISTRY_USER}/lnmp-nginx:latest -f nginx-php/Dockerfile.nginx ./nginx-php
    docker build -t ${REGISTRY_HOST}/${REGISTRY_USER}/lnmp-php:latest -f nginx-php/Dockerfile.php ./nginx-php
    docker build -t ${REGISTRY_HOST}/${REGISTRY_USER}/lnmp-mysql:latest -f mysql/Dockerfile ./mysql
}

function push {
    # Push to the registry
    docker push ${REGISTRY_HOST}/${REGISTRY_USER}/lnmp-nginx:latest
    docker push ${REGISTRY_HOST}/${REGISTRY_USER}/lnmp-php:latest
    docker push ${REGISTRY_HOST}/${REGISTRY_USER}/lnmp-mysql:latest
}

function publish {
    # By default, `docker.io` will be used as the docker registry
    REGISTRY_HOST=docker.io

    # Login first, so we can get the user name directly
    docker login ${REGISTRY_HOST}

    # Get username
    REGISTRY_USER=$(docker info | awk '/Username/ { print $2 }')

    # Build
    build

    # Push
    push
}

function create_store {
    NAME=$1
    docker-machine create -d ${DOCKER_MACHINE_DRIVER} ${NAME}
    eval $(docker-machine env ${NAME})
    HostIP=$(docker-machine ip ${NAME})
    export KVSTORE="etcd://${HostIP}:2379"
    docker run -d \
        -p 4001:4001 -p 2380:2380 -p 2379:2379 \
        --restart=always \
        --name etcd \
        quay.io/coreos/etcd \
            -initial-advertise-peer-urls http://${HostIP}:2380 \
            -initial-cluster default=http://${HostIP}:2380 \
            -advertise-client-urls http://${HostIP}:2379,http://${HostIP}:4001 \
            -listen-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
            -listen-peer-urls http://0.0.0.0:2380
}

function create_master {
    NAME=$1
    echo "kvstore is ${KVSTORE}"
    # eth1 on virtualbox, eth0 on digitalocean
    docker-machine create -d ${DOCKER_MACHINE_DRIVER} \
        --swarm \
        --swarm-discovery=${KVSTORE} \
        --swarm-master \
        --engine-opt="cluster-store=${KVSTORE}" \
        --engine-opt="cluster-advertise=eth1:2376" \
        ${NAME}
}

function create_node {
    NAME=$1
    echo "kvstore is ${KVSTORE}"
    # eth1 on virtualbox, eth0 on digitalocean
    docker-machine create -d ${DOCKER_MACHINE_DRIVER} \
        --swarm \
        --swarm-discovery=${KVSTORE} \
        --engine-opt="cluster-store=${KVSTORE}" \
        --engine-opt="cluster-advertise=eth1:2376" \
        ${NAME}
}

function create {
    create_store kvstore
    create_master master
    for i in $(seq ${SWARM_SIZE})
    do
        create_node node${i} &
    done

    wait
}

function destroy {
    for i in $(seq ${SWARM_SIZE})
    do
        docker-machine rm -y node${i} || true
    done
    docker-machine rm -y master || true
    docker-machine rm -y kvstore || true
}


function up {
    eval $(docker-machine env --swarm master)
    docker-compose up -d
}

function down {
    eval $(docker-machine env --swarm master)
    docker-compose down
}

function usage {
    echo "Usage: $1 {create|destroy|up|down|publish}"
}

# Handle subcommand
case "$1" in
    create)     create ;;
    destroy)    destroy ;;
    up)         up ;;
    down)       down ;;
    publish)    publish ;;
    *)          usage $0 ;;
esac
