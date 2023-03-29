NODE_INDEX=${HOSTNAME##*-}
echo "firehose-node Index: $NODE_INDEX"


# print all environment variables
printenv

# If genesis json exists and force_init is not set, then skip the node initialization
if [ "$FORCE_INIT" = "true" ]; then
    echo "Force init is set to true. Initializing node."
    rm -rf $HOME_DIR/*
else
    echo "Force init is set to false. Skipping node initialization."
fi


if test -f $HOME_DIR/config/genesis.json; then
    echo "Genesis.json exists. Skipping node initialization."
else
    echo "Genesis.json does not exist. Initializing node."

    NODE_NAME=$(jq -r ".firehose_nodes[$NODE_INDEX].name" /config-graph/firehose-node.json)
    echo "firehose-node Index: $NODE_INDEX, Key name: $NODE_NAME"

    # Print mnemonic
    MNEMONIC=$(jq -r ".firehose_nodes[$NODE_INDEX].mnemonic" /config-graph/firehose-node.json)
    echo "Mnemonic: $MNEMONIC"

    jq -r ".firehose_nodes[$NODE_INDEX].mnemonic" /config-graph/firehose-node.json | persistenceCore init $NODE_NAME --chain-id $CHAIN_ID --home $HOME_DIR --recover
    echo $MNEMONIC | persistenceCore keys add $NODE_NAME --recover --keyring-backend="test" --home $HOME_DIR

    # if we have GENESIS_NODE_DATA_RESOLUTION_METHOD is dynamic fetch the genesis from the GENESIS_EXPOSER_PORT on the GENESIS_HOST 
    # else fetch it directly from GENESIS_JSON_FETCH_URL
    GENESIS_NODE_ID=""
    if [ $GENESIS_NODE_DATA_RESOLUTION_METHOD = "DYNAMIC" ]; then
        echo "Config: DYNAMIC. Fetching genesis file from $GENESIS_HOST:$GENESIS_EXPOSER_PORT"
        GENESIS_NODE_ID=$(curl -s http://$GENESIS_HOST:$GENESIS_EXPOSER_PORT/node_id)
        curl http://$GENESIS_HOST:$GENESIS_EXPOSER_PORT/genesis -o $HOME_DIR/config/genesis.json
    else
        echo "Config: STATIC. Fetching genesis file from $GENESIS_JSON_FETCH_URL"
        curl $GENESIS_JSON_FETCH_URL -o $HOME_DIR/config/genesis.json
    fi

    GENESIS_NODE_P2P="$GENESIS_NODE_ID@$GENESIS_HOST:$GENESIS_PORT_P2P"
    echo "Node P2P: $GENESIS_NODE_P2P"

    # skip persistent_peers if GENESIS_NODE_DATA_RESOLUTION_METHOD is static
    if [ $GENESIS_NODE_DATA_RESOLUTION_METHOD = "DYNAMIC" ]; then
        sed -i "s/persistent_peers = \"\"/persistent_peers = \"$GENESIS_NODE_P2P\"/g" $HOME_DIR/config/config.toml
    fi
    sed -i 's#"tcp://127.0.0.1:26657"#"tcp://0.0.0.0:26657"#g' $HOME_DIR/config/config.toml
    sed -i 's/timeout_commit = "5s"/timeout_commit = "1s"/g' $HOME_DIR/config/config.toml
    sed -i 's/timeout_propose = "3s"/timeout_propose = "1s"/g' $HOME_DIR/config/config.toml
    sed -i 's/index_all_keys = false/index_all_keys = true/g' $HOME_DIR/config/config.toml

    # replace seeds if the variable is not empty
    if [ ! -z "$SEEDS" ]; then
        sed -i "s/seeds = \"\"/seeds = \"$SEEDS\"/g" $HOME_DIR/config/config.toml
    fi

    echo "Printing the whole config.toml file"

    cat << END >> $HOME_DIR/config/config.toml
        #######################################################
        ###       Extractor Configuration Options     ###
        #######################################################
        [extractor]
        enabled = true
        output_file = "stdout"
END
    
    cat $HOME_DIR/config/config.toml


    # update the app.toml pruning config to Nothing
    # sed -i 's/pruning = "default"/pruning = "nothing"/g' $HOME_DIR/config/app.toml
    # update the minimum-gas-prices in app.toml to 100uxprt
    sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "100uxprt"/g' $HOME_DIR/config/app.toml

    echo "Setting up pruning configuration in app.toml"
    sed -i 's/pruning = "default"/pruning = "custom"/g' $HOME_DIR/config/app.toml
    sed -i 's/pruning-interval = "0"/pruning-interval = "100"/g' $HOME_DIR/config/app.toml
    sed -i 's/pruning-keep-recent = "0"/pruning-keep-recent = "10000"/g' $HOME_DIR/config/app.toml


    # if STATE_RESTORE_SNAPSHOT_URL is not empty url and wasm folder doesn't exist, then download and extract the snapshot
    if [ ! -z "$STATE_RESTORE_SNAPSHOT_URL" ]; then
        echo "=> Downloading snapshot from $STATE_RESTORE_SNAPSHOT_URL"
        FILENAME=$(basename $STATE_RESTORE_SNAPSHOT_URL)
        curl $STATE_RESTORE_SNAPSHOT_URL -o $HOME_DIR/$FILENAME

        echo "=> Extracting snapshot"
        cp $HOME_DIR/data/priv_validator_state.json $HOME/priv_validator_state_backup.json

        case "$FILENAME" in
            *.tar.lz4)
                if ! command -v lz4 &> /dev/null; then
                    apk add --no-cache lz4
                fi

                lz4 -c -d $HOME_DIR/$FILENAME | tar -x -C $HOME_DIR
                # delete the $HOME_DIR/wasm/wasm/cache folder
                rm -rf $HOME_DIR/wasm/wasm/cache
                rm -rf $HOME_DIR/$FILENAME
                ;;

            *.tar.gz)
                tar -xvf $HOME_DIR/$FILENAME -C $HOME_DIR
                rm -rf $HOME_DIR/wasm/wasm/cache
                rm -rf $HOME_DIR/$FILENAME
                ;;
        esac

        mv $HOME_DIR/priv_validator_state_backup.json $HOME/data/priv_validator_state.json
        rm $HOME_DIR/priv_validator_state_backup.json
    fi

fi
# copy the firehose.yml file to the HOME_DIR because config-graph is a read-only volume
cp /config-graph/firehose-reader.yml $HOME_DIR/config/firehose.yml

# if FIRST_STREAMBLE_BLOCK is not empty, then set the first_streamable_block in firehose.yml
if [ ! -z "$FIRST_STREAMBLE_BLOCK" ]; then
    echo "Setting common-first-streamable-block to $FIRST_STREAMBLE_BLOCK"
    sed -i "s/common-first-streamable-block: 0/common-first-streamable-block: $FIRST_STREAMBLE_BLOCK/g" $HOME_DIR/config/firehose.yml
fi