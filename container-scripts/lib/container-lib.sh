#!/usr/bin/env bash

: ${DOMAIN:="example.com"}
: ${ORG:="org1"}
: ${ORDERER_NAME:="orderer"}
: ${ORDERER_NAME_PREFIX:="raft"}
: ${ORDERER_DOMAIN:=${DOMAIN}}
: ${ORDERER_GENERAL_LISTENPORT:="7050"}
: ${SYSTEM_CHANNEL_ID:=orderer-system-channel}
: ${RAFT0_PORT:=7050}
: ${RAFT1_PORT:=7150}
: ${RAFT2_PORT:=7250}

: ${WGET_OPTS:=--verbose -N}

export ORG DOMAIN SYSTEM_CHANNEL_ID

: ${ORDERER_TLSCA_CERT_OPTS="--tls --cafile /etc/hyperledger/crypto-config/ordererOrganizations/${ORDERER_DOMAIN}/msp/tlscacerts/tlsca.${ORDERER_DOMAIN}-cert.pem"}
: ${ORDERER_ADDRESS="${ORDERER_NAME}.${ORDERER_DOMAIN}:${ORDERER_GENERAL_LISTENPORT}"}

function downloadOrdererMSP() {
    local remoteOrdererName=${1:?-Orderer name is required}
    local remoteOrdererDOMAIN=${2:-${ORDERER_DOMAIN}}
    local wwwPort=${3:-80}

    local mspSubPath="$remoteOrdererDOMAIN"
    local serverDNSName=${remoteOrdererName}.${remoteOrdererDOMAIN}:${wwwPort}
    downloadMSP "ordererOrganizations" ${remoteOrdererDOMAIN} ${serverDNSName}
    wget ${WGET_OPTS} --directory-prefix crypto-config/ordererOrganizations/${mspSubPath}/msp/${remoteOrdererName}.${remoteOrdererDOMAIN}/tls http://www.${serverDNSName}/msp/${remoteOrdererName}.${remoteOrdererDOMAIN}/tls/server.crt
}

function downloadOrgMSP() {
    local org=${1:?Org is required}
    downloadMSP "peerOrganizations" ${org}.${DOMAIN}
}

function downloadMSP() {
    local typeSubPath=$1
    local mspSubPath=$2
    local serverDNSName=www.${3:-${mspSubPath}}
    wget ${WGET_OPTS} --directory-prefix crypto-config/${typeSubPath}/${mspSubPath}/msp/admincerts http://${serverDNSName}/msp/admincerts/Admin@${mspSubPath}-cert.pem
    wget ${WGET_OPTS} --directory-prefix crypto-config/${typeSubPath}/${mspSubPath}/msp/cacerts http://${serverDNSName}/msp/cacerts/ca.${mspSubPath}-cert.pem
    wget ${WGET_OPTS} --directory-prefix crypto-config/${typeSubPath}/${mspSubPath}/msp/tlscacerts http://${serverDNSName}/msp/tlscacerts/tlsca.${mspSubPath}-cert.pem
}

function certificationsToEnv() {
    local org=${1:?Org is required}
    local domain=${2:-${DOMAIN}}
    local mspDir="crypto-config/peerOrganizations/${org}.${domain}/msp"
    if [ "${org}" == "orderer" ]; then
        mspDir="crypto-config/ordererOrganizations/${domain}/msp";
        org=""
    fi
    export ORG_ADMIN_CERT=`cat ${mspDir}/admincerts/Admin@${org}${org:+.}${domain}-cert.pem | base64 -w 0` \
      && export ORG_ROOT_CERT=`cat ${mspDir}/cacerts/ca.${org}${org:+.}${domain}-cert.pem | base64 -w 0` \
      && export ORG_TLS_ROOT_CERT=`cat ${mspDir}/tlscacerts/tlsca.${org}${org:+.}${domain}-cert.pem | base64 -w 0`
}

function ordererCertificationsToEnv() {
    local mspDir="crypto-config/ordererOrganizations/${DOMAIN}/msp";
    export ORG_ADMIN_CERT=`cat ${mspDir}/admincerts/Admin@${org}${org:+.}${DOMAIN:-example.com}-cert.pem | base64 -w 0` \
      && export ORG_ROOT_CERT=`cat ${mspDir}/cacerts/ca.${org}${org:+.}${DOMAIN:-example.com}-cert.pem | base64 -w 0` \
      && export ORG_TLS_ROOT_CERT=`cat ${mspDir}/tlscacerts/tlsca.${org}${org:+.}${DOMAIN:-example.com}-cert.pem | base64 -w 0`
}

function fetchChannelConfigBlock() {
    local channel=${1:?"Channel name must be specified"}
    local blockNum=${2:-config}

    mkdir -p crypto-config/configtx
    echo "Execute: channel fetch $blockNum crypto-config/configtx/${channel}.pb -o ${ORDERER_ADDRESS} -c ${channel} ${ORDERER_TLSCA_CERT_OPTS}"
    peer channel fetch $blockNum crypto-config/configtx/${channel}.pb -o ${ORDERER_ADDRESS} -c ${channel} ${ORDERER_TLSCA_CERT_OPTS}
}

function txTranslateChannelConfigBlock() {
    local channel=$1
    rm -f crypto-config/configtx/${channel}.pb crypto-config/configtx/${channel}.json crypto-config/configtx/config.json
    fetchChannelConfigBlock $channel
    configtxlator proto_decode --type 'common.Block' --input=crypto-config/configtx/${channel}.pb --output=crypto-config/configtx/${channel}.json
    jq .data.data[0].payload.data.config crypto-config/configtx/${channel}.json > crypto-config/configtx/config.json
}

function updateChannelGroupConfigForOrg() {
    local org=$1
    local templateFileOfUpdate=$2
    export NEWORG=${org}
    envsubst < "${templateFileOfUpdate}" > "crypto-config/configtx/new_config_${org}.json"
    jq -s '.[0] * {"channel_group":{"groups":.[1]}}' crypto-config/configtx/config.json crypto-config/configtx/new_config_${org}.json > crypto-config/configtx/updated_config.json
}

function mergeListsInJsons() {
    local firstFile=${1:?First file is required}
    local firstFileJsonPath=${2:?Json path in first file is required}
    local secondFile=${3:?Second file is required}
    local secondFileJsonPath=${4:?Json path in second file is required}
    local outputFile=${5:?Output file is requried}
    sh -c "jq -s '.[1][\"${secondFileJsonPath}\"] as \$addr | .[0].${firstFileJsonPath} |= .+\$addr | .[0]' $firstFile $secondFile  > ${outputFile}.temp"
    mv ${outputFile}.temp ${outputFile}
}


function createConfigUpdateEnvelope() {
    local channel=$1
    local configJson=${2:-'crypto-config/configtx/config.json'}
    local updatedConfigJson=${3:-'crypto-config/configtx/updated_config.json'}

    echo " >> Prepare config update from $org for channel $channel"
    configtxlator proto_encode --type 'common.Config' --input=${configJson} --output=config.pb \
    && configtxlator proto_encode --type 'common.Config' --input=${updatedConfigJson} --output=updated_config.pb \
    && configtxlator compute_update --channel_id=$channel --original=config.pb  --updated=updated_config.pb --output=update.pb \
    && configtxlator proto_decode --type 'common.ConfigUpdate' --input=update.pb --output=crypto-config/configtx/update.json && chown $UID crypto-config/configtx/update.json

    echo "{\"payload\":{\"header\":{\"channel_header\":{\"channel_id\":\"$channel\",\"type\":2}},\"data\":{\"config_update\":`cat crypto-config/configtx/update.json`}}}" | jq . > crypto-config/configtx/update_in_envelope.json
    configtxlator proto_encode --type 'common.Envelope' --input=crypto-config/configtx/update_in_envelope.json --output=update_in_envelope.pb
    echo " >> $org is sending channel update update_in_envelope.pb with $d by $command"
    echo "Execute: peer channel update -f update_in_envelope.pb -c ${channel} -o ${ORDERER_ADDRESS} ${ORDERER_TLSCA_CERT_OPTS}"
    peer channel update -f update_in_envelope.pb -c ${channel} -o ${ORDERER_ADDRESS} ${ORDERER_TLSCA_CERT_OPTS}
}



function insertObjectIntoChannelConfig() {
    local channel=${1:?Channel is required}
    local org=${2:?Org is required}
    local templateFile=${3:?Template is required}
    txTranslateChannelConfigBlock "$channel"
    updateChannelGroupConfigForOrg "$org" "$templateFile"
}


function updateChannelConfig() {
    local channel=${1:?Channel is required}
    local org=${2:?Org is required}
    certificationsToEnv $org
    insertObjectIntoChannelConfig $@
    createConfigUpdateEnvelope $channel
}


function mergeListIntoChannelConfig() {
    local channel=${1:?Channel is requried}
    local configInputFile=${2:?Config input file is requried}
    local configJsonPath=$3
    local mergedFile=$4
    local mergedFileJsonPath=$5
    local outputFile=${6:-crypto-config/configtx/updated_config.json}
    mergeListsInJsons ${configInputFile} ${configJsonPath} ${mergedFile} ${mergedFileJsonPath} ${outputFile}
}

function removeObjectFromChannelConfig() {
    local channel=${1:?Channel is requried}
    local configInputFile=${2:?Config input file is requried}
    local configJsonPath=$3
    local outputFile=${4:-crypto-config/configtx/updated_config.json}
    sh -c "jq 'del (.${configJsonPath})' $configInputFile > ${outputFile}.temp "
    mv ${outputFile}.temp ${outputFile}
}


function updateConsortium() {
    local org=${1:?Org to be added to consortium must be specified}
    local channel=${2:?System channel must be specified}
    local updateTemplateFile=${3:-./templates/Consortium.json}
    local consortiumName=${4:-SampleConsortium}
    export CONSORTIUM_NAME=${consortiumName}
    certificationsToEnv $org
    updateChannelConfig $channel $org "$updateTemplateFile"
}

function updateAnchorPeers() {
    local org=${1:?Org to be configured must be specified}
    local channel=${2:?Channel name must be specified}
    updateChannelConfig $channel $org ./templates/AnchorPeers.json
}

function createChannel() {
    local channelName=${1:?Channel name must be specified}
    echo "Create channel $ORG $channelName"
    downloadOrdererMSP ${ORDERER_NAME}
    mkdir -p crypto-config/configtx
    envsubst < "templates/configtx-template.yaml" > "crypto-config/configtx.yaml"

    configtxgen -configPath crypto-config/ -outputCreateChannelTx crypto-config/configtx/channel_$channelName.tx -profile CHANNEL -channelID $channelName
    peer channel create -o ${ORDERER_ADDRESS} -c $channelName -f crypto-config/configtx/channel_$channelName.tx ${ORDERER_TLSCA_CERT_OPTS}

    updateAnchorPeers "$ORG" "$channelName"

}

function addOrgToChannel() {
    local channel=${1:?"Channel must be specified"}
    local org=${2:?"New Org must be specified"}

    echo " >> Add new org '$org' to channel $channel"
    certificationsToEnv $org
    updateChannelConfig $channel $org ./templates/NewOrg.json
}

function joinChannel() {
    local channel=${1:?Channel name must be specified}

    echo "Join $ORG to channel $channel"
    fetchChannelConfigBlock $channel "0"
    CORE_PEER_ADDRESS=peer0.$ORG.$DOMAIN:7051 peer channel join -b crypto-config/configtx/$channel.pb
}

function installChaincode {
    local chaincodeName=${1:?Chaincode name must be specified}
    local chaincodePath=${2:-$chaincodeName}
    local lang=${3:-golang}
    local chaincodeVersion=${4:-1.0}

    echo "Install chaincode $chaincodeName  $chaincodePath $lang $chaincodeVersion"
    CORE_PEER_ADDRESS=peer0.$ORG.$DOMAIN:7051 peer chaincode install -n $chaincodeName -v $chaincodeVersion -p $chaincodePath -l $lang
}


function instantiateChaincode() {
    local channelName=${1:?Channel name must be specified}
    local chaincodeName=${2:?Chaincode name must be specified}
    local initArguments=${3:-[]}
    local chaincodeVersion=${4:-1.0}
    local privateCollectionPath=${5}
    local endorsementPolicy=${6}
    local arguments="{\"Args\":$initArguments}"

    if  [ "$privateCollectionPath" == "\"\"" ] || [ "$privateCollectionPath" == "''" ]; then privateCollectionPath="" ; fi
    [ -n "$privateCollectionPath" ] && privateCollectionParam=" --collections-config /opt/chaincode/${privateCollectionPath}"

    [ -n "$endorsementPolicy" ] && endorsementPolicyParam=" -P \"${endorsementPolicy}\""

    echo "Instantiate chaincode $channelName $chaincodeName '$initArguments' $chaincodeVersion $privateCollectionPath $endorsementPolicy"
    CORE_PEER_ADDRESS=peer0.$ORG.$DOMAIN:7051 peer chaincode instantiate -n $chaincodeName -v ${chaincodeVersion} -c "${arguments}" -o ${ORDERER_ADDRESS} -C $channelName ${ORDERER_TLSCA_CERT_OPTS} $privateCollectionParam $endorsementPolicyParam
}


function callChaincode() {
    channelName=${1:?Channel name must be specified}
    chaincodeName=${2:?Chaincode name must be specified}
    arguments=${3:-[]}
    arguments="{\"Args\":$arguments}"
    action=${4:-query}
    echo "CORE_PEER_ADDRESS=peer0.$ORG.$DOMAIN:7051 peer chaincode $action -n $chaincodeName -C $channelName -c '$arguments'"
    CORE_PEER_ADDRESS=peer0.$ORG.$DOMAIN:7051 peer chaincode $action -n $chaincodeName -C $channelName -c "$arguments" ${ORDERER_TLSCA_CERT_OPTS}
}

function queryChaincode() {
    callChaincode "$1" "$2" "$3" query
}

function invokeChaincode() {
    callChaincode "$1" "$2" "$3" invoke
}
