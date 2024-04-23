#!/bin/bash

fmt=`tput setaf 45`
end="\e[0m\n"
err="\e[31m"
scss="\e[32m"


installation() {
if [ -z "$RPC_URL" ]; then
  echo -e "${err}\nYou have not set RPC_URL, please set the variable and try again${end}" && sleep 1
  exit 1;
fi

if [ -z "$PRIVATE_KEY" ]; then
  echo -e "${err}\nYou have not set PRIVATE_KEY${end}" && sleep 1
  exit 1;
fi

if [[ "${PRIVATE_KEY:0:2}" != "0x" ]]; then
    echo "First 2 chars in PRIVATE_KEY variable is not 0x"
    exit 1
fi

echo -e "${fmt}\nSetting up dependencies${end}" && sleep 1

sudo apt update && sudo apt upgrade -y

sudo apt -qy install curl git jq lz4 build-essential screen make python3-pip python3.10-venv

if ! command -v docker &> /dev/null && ! command -v docker-compose &> /dev/null; then
  sudo wget https://raw.githubusercontent.com/fackNode/requirements/main/docker.sh && chmod +x docker.sh && ./docker.sh
fi

git clone --recurse-submodules https://github.com/ritual-net/infernet-container-starter

echo -e "${fmt}\nCreating deploy-container.service${end}" && sleep 1

cd /root/infernet-container-starter

sudo tee /etc/systemd/system/deploy-container.service <<EOF
[Unit]
Description=Deploy Container Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'cd /root/infernet-container-starter && project=hello-world make deploy-container'
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable deploy-container
sudo systemctl start deploy-container

echo -e "${fmt}\nSleep 60 seconds before checking docker containers${end}" && sleep 1

sleep 60

if docker ps -a | grep -q 'anvil-node' && docker ps -a | grep -q 'hello-world' && docker ps -a | grep -q 'deploy-node-1' && docker ps -a | grep -q 'deploy-redis-1' && docker ps -a | grep -q 'deploy-fluentbit-1'; then
  echo -e "${fmt}\nContainers up correctly${end}" && sleep 1
else
  echo -e "${err}\nContainers up incorrectly${end}" && sleep 1
  exit 1;
fi

echo -e "${fmt}\nEditing config.json${end}" && sleep 1

jq --arg rpc_url "$RPC_URL" '.chain.rpc_url = $rpc_url' /root/infernet-container-starter/deploy/config.json > temp_file.json && mv temp_file.json /root/infernet-container-starter/deploy/config.json
jq --arg private_key "$PRIVATE_KEY" '.chain.wallet.private_key = $private_key' /root/infernet-container-starter/deploy/config.json > temp_file.json && mv temp_file.json /root/infernet-container-starter/deploy/config.json
jq --arg new_address "0x8D871Ef2826ac9001fB2e33fDD6379b6aaBF449c" '.chain.coordinator_address = $new_address' /root/infernet-container-starter/deploy/config.json > temp_file.json && mv temp_file.json /root/infernet-container-starter/deploy/config.json


echo -e "${fmt}\nEditing Makefile${end}" && sleep 1

sed -i 's/sender := .*/sender := '"$PRIVATE_KEY"'/' /root/infernet-container-starter/projects/hello-world/contracts/Makefile
sed -i 's|RPC_URL := .*|RPC_URL := '"$RPC_URL"'|' /root/infernet-container-starter/projects/hello-world/contracts/Makefile

echo -e "${fmt}\nEditing Deploy.s.sol${end}" && sleep 1

sed -i 's/address coordinator = 0x5FbDB2315678afecb367f032d93F642f64180aa3;/address coordinator = 0x8D871Ef2826ac9001fB2e33fDD6379b6aaBF449c;/' /root/infernet-container-starter/projects/hello-world/contracts/script/Deploy.s.sol


echo -e "${fmt}\nRestart docker containers to apply new config${end}" && sleep 1

docker restart anvil-node && sleep 1
docker restart hello-world && sleep 1 
docker restart deploy-node-1 && sleep 1
docker restart deploy-fluentbit-1 && sleep 1 
docker restart deploy-redis-1 && sleep 1

echo -e "${fmt}\nInstall Foundry${end}" && sleep 1

cd /root/

mkdir foundry
cd foundry

curl -L https://foundry.paradigm.xyz | bash

bash -i -c "source ~/.bashrc && foundryup"
}


node_tune() {
echo -e "${fmt}⚒️ Tune the node! ⚒️${end}" && sleep 1
CONTRACT_DATA_FILE="/root/infernet-container-starter/projects/hello-world/contracts/broadcast/Deploy.s.sol/8453/run-latest.json"
CONFIG_FILE="/root/infernet-container-starter/deploy/config.json"
CONTRACT_ADDRESS=$(jq -r '.receipts[0].contractAddress' "$CONTRACT_DATA_FILE")

if [ -z "$CONTRACT_ADDRESS" ]; then
    echo -e "${err}Error occurred cannot read contractAddress from $CONTRACT_DATA_FILE${end}" && sleep 1
    exit 1
fi

echo -e "${fmt}Your contract address: $CONTRACT_ADDRESS${end}" && sleep 1

if grep -qF "$CONTRACT_ADDRESS" "$CONFIG_FILE"; then
    echo "$CONTRACT_ADDRESS already in allowed_addresses array"
    exit 0
fi

echo -e "${fmt}Adding snapshot_sync params to /root/infernet-container-starter/deploy/config.json${end}" && sleep 1

jq '. += { "snapshot_sync": { "sleep": 5, "batch_size": 25 } }' "$CONFIG_FILE" > temp.json && mv temp.json "$CONFIG_FILE"

echo -e "${fmt}Adding $CONTRACT_ADDRESS in allowed_addresses to /root/infernet-container-starter/deploy/config.json${end}" && sleep 1

jq --arg contract_address "$CONTRACT_ADDRESS" '.containers[] |= if .id == "hello-world" then .allowed_addresses += [$contract_address] else . end' "$CONFIG_FILE" > temp.json && mv temp.json "$CONFIG_FILE"

cat $CONFIG_FILE

}


while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --install)
            echo -e "${fmt}🏹 Your choose $key${end}" && sleep 1
            installation
            ;;
        --node-tune)
            echo -e "${fmt}⚒️ Your choose $key${end}" && sleep 1
            node_tune
            ;;
        *)
            echo "❌ Unknown option: $key"
            ;;
    esac
    shift
done