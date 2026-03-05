# Návod ke zprovoznění 1. části semestrální práce

### Postup spuštění
Celý cluster se spouští jedním příkazem. Automatizační kontejner (setup-node) se postará o inicializaci Replica Setů, Shardingu a import dat.

##### 1. Otevřete terminál v kořenové složce projektu.

##### 2. Spusťte sestavení a start kontejnerů:
```
docker-compose up -d --build
```
##### 3. Čekejte na dokončení automatizace. Skript setup.sh potřebuje cca 30-60 sekund na nastavení clusteru. Průběh můžete sledovat příkazem:
```
docker logs -f setup-node
```
Jakmile uvidíte zprávu `SUCCESS`, cluster je připraven k použití.

##### 4. Ověření funkčnosti

A. Kontrola běžících kontejnerů
Zadejte příkaz:
```
docker-compose ps
```
Měli byste vidět běžící kontejnery: mongos, configsvr, shard1, shard1-b, shard1-c, shard2, shard3 (vše ve stavu Up).

B. Připojení k databázi (CLI)
Pro interakci s databází se připojujeme k routeru (mongos).

Přihlašovací údaje:

`User: admin`

`Password: password123`

Příkaz pro připojení:
```
docker exec -it mongos mongosh --port 27017 -u admin -p password123 --authenticationDatabase admin
```
##### 5. Testování a Dotazování
```
use protein_db
```
Test 1: Počet záznamů (základní kontrola)
```
db.interactions.countDocuments()
// Očekávaný výsledek: cca 24000
```
Test 2: Distribuce dat mezi Shardy Ověření, že data jsou fyzicky rozdělena na různé servery
```
db.interactions.getShardDistribution()
```
##### 6. Test odolnosti proti výpadku 

oto je klíčová část práce pro demonstraci High Availability. Budeme simulovat pád hlavního uzlu na Shardu 1.

Krok 1: Zjištění stavu
V novém okně terminálu zjistěte, který uzel je aktuálně PRIMARY (pravděpodobně ```shard1```):
```
docker exec -it shard1 mongosh --port 27017 --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"
```
Krok 2: Simulace
```
docker stop shard1
```
Krok 3: Ověření dostupnosti dat
```
# Tento příkaz musí vrátit počet záznamů i při vypnutém uzlu
docker exec mongos mongosh --quiet --port 27017 -u admin -p password123 --authenticationDatabase admin --eval "db.getSiblingDB('protein_db').interactions.countDocuments()"
```
Krok 4: Obnova
Zapněte zpět vypnutý uzel. Automaticky se synchronizuje a připojí jako SECONDARY.
```
docker start shard1
```


