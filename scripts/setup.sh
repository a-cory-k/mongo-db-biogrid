#!/bin/sh

echo "AUTO-SETUP: Waiting for containers..."
sleep 10

wait_for() {
    container=$1
    echo "Checking $container..."
    until docker exec $container mongosh --eval "print(\"alive\")" > /dev/null 2>&1; do
        echo "   ... $container is sleeping..."
        sleep 2
    done
    echo " $container is UP!"
}

wait_for "configsvr"
wait_for "shard1"
wait_for "shard1-b"
wait_for "shard1-c"
wait_for "shard2"
wait_for "shard3"

echo "INIT REPLICA SETS..."


docker exec configsvr mongosh --port 27017 --eval "rs.initiate({_id: \"rsConfig\", configsvr: true, members: [{ _id: 0, host: \"configsvr:27017\" }]})" || true


docker exec shard1 mongosh --port 27017 --eval "rs.initiate({
  _id: \"rsShard1\",
  members: [
    { _id: 0, host: \"shard1:27017\" },
    { _id: 1, host: \"shard1-b:27017\" },
    { _id: 2, host: \"shard1-c:27017\" }
  ]
})" || true


docker exec shard2 mongosh --port 27017 --eval "rs.initiate({_id: \"rsShard2\", members: [{ _id: 0, host: \"shard2:27017\" }]})" || true
docker exec shard3 mongosh --port 27017 --eval "rs.initiate({_id: \"rsShard3\", members: [{ _id: 0, host: \"shard3:27017\" }]})" || true

echo "..."
sleep 20

wait_for "mongos"

echo "CREATING ADMIN..."
docker exec mongos mongosh --port 27017 --eval "db.getSiblingDB(\"admin\").createUser({user: \"admin\", pwd: \"password123\", roles: [\"root\"]})" || true

echo "ADDING SHARDS..."
docker exec mongos mongosh --port 27017 -u admin -p password123 --authenticationDatabase admin --eval "sh.addShard(\"rsShard1/shard1:27017\")" || true
docker exec mongos mongosh --port 27017 -u admin -p password123 --authenticationDatabase admin --eval "sh.addShard(\"rsShard2/shard2:27017\")" || true
docker exec mongos mongosh --port 27017 -u admin -p password123 --authenticationDatabase admin --eval "sh.addShard(\"rsShard3/shard3:27017\")" || true

echo "SHARDING CONFIG..."
docker exec mongos mongosh --port 27017 -u admin -p password123 --authenticationDatabase admin --eval "sh.enableSharding(\"protein_db\")" || true
docker exec mongos mongosh --port 27017 -u admin -p password123 --authenticationDatabase admin --eval "db.getSiblingDB(\"protein_db\").interactions.createIndex({ \"id_a\": \"hashed\" })" || true
docker exec mongos mongosh --port 27017 -u admin -p password123 --authenticationDatabase admin --eval "sh.shardCollection(\"protein_db.interactions\", { \"id_a\": \"hashed\" })" || true

echo "IMPORTING DATA..."
echo "--- HUMAN ---"
docker exec mongos mongoimport --host mongos --port 27017 -u admin -p password123 --authenticationDatabase admin --db protein_db --collection interactions --file /data/ppi_human.json --jsonArray
echo "--- MOUSE ---"
docker exec mongos mongoimport --host mongos --port 27017 -u admin -p password123 --authenticationDatabase admin --db protein_db --collection interactions --file /data/ppi_mouse.json --jsonArray
echo "--- YEAST ---"
docker exec mongos mongoimport --host mongos --port 27017 -u admin -p password123 --authenticationDatabase admin --db protein_db --collection interactions --file /data/ppi_yeast.json --jsonArray

echo "SUCCESS!"