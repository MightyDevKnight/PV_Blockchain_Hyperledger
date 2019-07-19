#!/usr/bin/env bash
: ${SYSTEM_CHANNEL_ID:=orderer-system-channel}

tree crypto-config

if [ ! -f "crypto-config/ordererOrganizations/$DOMAIN/orderers/${ORDERER_NAME}.$DOMAIN/msp/admincerts/Admin@$DOMAIN-cert.pem" ]; then
    echo "No file: crypto-config/ordererOrganizations/$DOMAIN/orderers/${ORDERER_NAME}.$DOMAIN/msp/admincerts/Admin@$DOMAIN-cert.pem"
    echo "Generation orderer MSP."

    envsubst < "templates/cryptogen-orderer-template.yaml" > "crypto-config/cryptogen-orderer.yaml"
    rm -rf crypto-config/ordererOrganizations/$DOMAIN/orderers/${ORDERER_NAME}.$DOMAIN/
    cryptogen generate --config=crypto-config/cryptogen-orderer.yaml
else
    echo "Orderer MSP exists. Generation skipped".
fi

if [ ! -f "crypto-config/configtx/genesis.pb" ]; then
    echo "Generation genesis configtx."
    envsubst < "templates/configtx-template.yaml" > "crypto-config/configtx.yaml"
    mkdir -p crypto-config/configtx
    configtxgen -configPath crypto-config/ -outputBlock crypto-config/configtx/genesis.pb -profile ${ORDERER_GENESIS_PROFILE} -channelID ${SYSTEM_CHANNEL_ID}
else
    echo "Genesis configtx exists. Generation skipped".
fi

if [ ! -f "crypto-config/hosts_orderer" ]; then
    echo "Generating crypto-config/hosts_orderer"
    echo -e "#generated at bootstrap as part of crypto- and meta-information generation" > crypto-config/hosts_orderer
else
    echo "crypto-config/hosts_orderer file exists. Generation skipped."
fi

echo "Copying well-known tls certs to nginx "
mkdir -p crypto-config/ordererOrganizations/$DOMAIN/msp/well-known
cp crypto-config/ordererOrganizations/${DOMAIN}/msp/tlscacerts/tlsca.${DOMAIN}-cert.pem crypto-config/ordererOrganizations/${DOMAIN}/msp/well-known/msp-admin.pem 2>/dev/null
cp crypto-config/ordererOrganizations/${DOMAIN}/msp/tlscacerts/tlsca.${DOMAIN}-cert.pem crypto-config/ordererOrganizations/${DOMAIN}/msp/well-known/tlsca-cert.pem 2>/dev/null

tlsCert="crypto-config/ordererOrganizations/${DOMAIN}/orderers/${ORDERER_NAME}.$DOMAIN/tls/server.crt"
tlsNginxFolder=crypto-config/ordererOrganizations/${DOMAIN}/msp/${ORDERER_NAME}.$DOMAIN/tls
echo "Copying tls certs to nginx served folder $tlsCert"
mkdir -p ${tlsNginxFolder}
cp "${tlsCert}" "${tlsNginxFolder}"


cat crypto-config/hosts_orderer
