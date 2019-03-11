#!/usr/bin/env bash

source lib.sh

export MULTIHOST=true
export DOMAIN=${DOMAIN-example.com}

: ${CHANNEL:=common}
: ${CHAINCODE_INSTALL_ARGS:=reference}
: ${CHAINCODE_INSTANTIATE_ARGS:=common reference}
: ${DOCKER_COMPOSE_ARGS:= -f docker-compose.yaml -f docker-compose-couchdb.yaml -f multihost.yaml -f docker-compose-ports.yaml}
: ${CHAINCODE_HOME:=chaincode}
: ${WEBAPP_HOME:=webapp}
: ${MIDDLEWARE_HOME:=middleware}

orgs=${@:-org1}
first_org=${1:-org1}

# Set WORK_DIR as home dir on remote machine
setMachineWorkDir

# Collect IPs of remote hosts into a hosts file to copy to all hosts to be used as /etc/hosts to resolve all names
ip=$(getMachineIp orderer)
hosts="# created by network-create.sh\n${ip} www.${DOMAIN} orderer.${DOMAIN}"

# Create member organizations host machines

# Collect ip into the hosts file
for org in ${orgs}
do
    ip=$(getMachineIp ${org})
    hosts="${hosts}\n${ip} www.${org}.${DOMAIN} peer0.${org}.${DOMAIN}"
done

echo -e "${hosts}" > hosts

info "Building network for $DOMAIN using WORK_DIR=$WORK_DIR on remote machines, CHAINCODE_HOME=$CHAINCODE_HOME, WEBAPP_HOME=$WEBAPP_HOME on local host. Hosts file:"
cat hosts

# Copy generated hosts file to the host machines

#docker-machine scp hosts ${ordererMachineName}:hosts
copyFileToMachine orderer hosts hosts

for org in ${orgs}
do
    cp hosts org_hosts
    # remove entry of your own ip not to confuse docker and chaincode networking
    sed -i.bak "/.*\.$org\.$DOMAIN*/d" org_hosts
    copyFileToMachine ${org} org_hosts hosts
    rm org_hosts.bak org_hosts
done

# you may want to keep this hosts file to append to your own local /etc/hosts to simplify name resolution
# sudo cat hosts >> /etc/hosts

# Create orderer organization

info "Creating orderer organization"

copyDirToMachine orderer templates ${WORK_DIR}/templates

connectMachine orderer
./clean.sh
docker-compose -f docker-compose-orderer.yaml -f orderer-multihost.yaml up -d

# Create member organizations

for org in ${orgs}
do
    copyDirToMachine ${org} templates ${WORK_DIR}/templates
    copyDirToMachine ${org} ${CHAINCODE_HOME} ${WORK_DIR}/${CHAINCODE_HOME}
    copyDirToMachine ${org} ${WEBAPP_HOME} ${WORK_DIR}/${WEBAPP_HOME}
    copyDirToMachine ${org} ${MIDDLEWARE_HOME} ${WORK_DIR}/${MIDDLEWARE_HOME}

    info "Copying dns chaincode to remote machine ${machine}"
    machine="$org.$DOMAIN"
    docker-machine ssh ${machine} mkdir -p ${WORK_DIR}/chaincode/node
    docker-machine scp -r chaincode/node/dns ${machine}:${WORK_DIR}/chaincode/node

    info "Creating member organization $org"
    connectMachine ${org}
    ./clean.sh
    docker-compose ${DOCKER_COMPOSE_ARGS} up -d
done

# Add member organizations to the consortium

connectMachine orderer

for org in ${orgs}
do
    info "Adding $org to the consortium"
    ./consortium-add-org.sh ${org}
done

# First organization creates application channel

createChannelAndAddOthers ${CHANNEL}

# First organization creates common channel if it's not the default application channel

if [[ ${CHANNEL} != common ]]; then
    createChannelAndAddOthers common
fi

# All organizations install application chaincode

for org in ${orgs}
do
    connectMachine ${org}
    info "Installing chaincode to $ORG: $CHAINCODE_INSTALL_ARGS"
    ./chaincode-install.sh ${CHAINCODE_INSTALL_ARGS}
done

# First organization instantiates application chaincode

connectMachine ${first_org}

info "Instantiating application chaincode by $ORG: $CHAINCODE_INSTANTIATE_ARGS"
./chaincode-instantiate.sh ${CHAINCODE_INSTANTIATE_ARGS}

# All organizations install dns chaincode from local dir .../fabric-starter/chaincode

unset CHAINCODE_INSTALL_ARGS
for org in ${orgs}
do
    connectMachine ${org}
    info "Installing chaincode to $ORG: dns"
    ./chaincode-install.sh dns
done

# First organization instantiates dns chaincode

connectMachine ${first_org}

info "Instantiating dns chaincode by $ORG"
./chaincode-instantiate.sh common dns

info "Waiting for dns chaincode to build"
sleep 20

# First organization creates entries in dns chaincode

ip=$(getMachineIp orderer)
./chaincode-invoke.sh common dns "[\"put\",\"$ip\",\"www.${DOMAIN} orderer.${DOMAIN}\"]"

for org in ${orgs}
do
    ip=$(getMachineIp ${org})
    ./chaincode-invoke.sh common dns "[\"put\",\"$ip\",\"www.${org}.${DOMAIN} peer0.${org}.${DOMAIN}\"]"
done

info "Smoke test queries dns chaincode via rest api"
sleep 5

ip=$(getMachineIp ${first_org})
jwt=`(curl -d '{"username":"user1","password":"pass"}' -H "Content-Type: application/json" http://${ip}:4000/users | tr -d '"')`
curl -H "Authorization: Bearer $jwt" "http://$ip:4000/channels/common/chaincodes/dns?fcn=range&unescape=true"

echo
