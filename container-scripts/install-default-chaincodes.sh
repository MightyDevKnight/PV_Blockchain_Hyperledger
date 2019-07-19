#!/usr/bin/env bash
source lib/container-lib.sh 2>/dev/null # for IDE code completion
source $(dirname "$0")/lib/container-lib.sh

echo -e "\n\nInstall DNS chaincode\n\n"
sleep 10
installChaincode dns /opt/chaincode/node/dns node 1.0
