# 1. část semestrální práce - NoSQL databáze - MongoDB

## Architektura

### Jak se případně liší od doporučeného používání a proč?

Mé řešení se liší v tom, že využívá **hybridní architekturu**:
1.  **Shard 1** je plnohodnotný **Replica Set (3 uzly)**, který demonstruje High Availability a Failover.
2.  **Shard 2, Shard 3 a Config Server** jsou nasazeny jako **Single Node** (1 uzel).

**Důvod:** Toto řešení bylo zvoleno jako "Proof of Concept" s ohledem na hardwarové limity vývojového prostředí (notebooku). Spuštění plného clusteru (cca 15 kontejnerů) by bylo neúměrně náročné na RAM a CPU. Hybridní model umožňuje demonstrovat všechny klíčové vlastnosti (Sharding i Replikaci) s polovičním počtem kontejnerů.

### Schéma a popis architektury

![Описание картинки](pics/arch.png)



**Popis schématu:**
Schéma znázorňuje kontejnerizované řešení v privátní síti `mongo-cluster`.
* **User/App:** Přistupuje do systému výhradně přes `mongos` router.
* **mongos (Router):**
    * Kontejner: `mongos`
    * Port: `27017:27017`
    * Funkce: Směruje dotazy na příslušné shardy.
* **configsvr (Metadata):**
    * Kontejner: `configsvr`
    * Port: `27019:27017`
    * Funkce: Uchovává topologii clusteru.
* **Shard 1 (High Availability Cluster):**
    * Kontejnery: `shard1` (Primary, port 27018), `shard1-b` (Secondary, port 27022), `shard1-c` (Secondary, port 27023).
    * Funkce: Ukládá cca 1/3 dat s plnou redundancí.
* **Shard 2 & 3 (Standard):**
    * Kontejnery: `shard2` (port 27020), `shard3` (port 27021).
    * Funkce: Ukládají zbylé 2/3 dat bez redundance.

### Specifika konfigurace
Celá infrastruktura je definována v souboru `docker-compose.yml`.

* **Služby:** Každý uzel databáze (shard, config, mongos) je samostatná služba.
* **Keyfile Auth:** Všechny databázové kontejnery využívají `docker build` krok k vygenerování a nastavení oprávnění pro `/etc/mongo-keyfile` (bezpečnostní klíč), což obchází problémy s mapováním oprávnění souborů na hostitelském OS (macOS/Windows).
* **Porty:** Externí porty jsou mapovány unikátně (27017-27023) pro možnost přímého ladění, interně v síti Dockeru komunikují všechny služby na standardním portu 27017.
* **Setup Node:** Speciální kontejner `setup-node` (image `docker:cli`) slouží k automatizaci. Po startu se připojí k Docker socketu, provede `rs.initiate()` pro repliky, přidá shardy do routeru (`sh.addShard`) a importuje data.

## Cluster (minimálně 1)
Pro řešení využívám **1 Sharded Cluster**.
**Důvod:** Cluster je nezbytný pro horizontální škálování. Vzhledem k povaze dat (velké množství interakcí proteinů) umožňuje cluster rozložit zátěž zápisu a objem dat mezi více strojů, což by u jedné instance nebylo možné.

## Uzly (minimálně 3)
Celkově řešení využívá **7 databázových uzlů** + 1 router + 1 automatizační uzel.
1.  **Mongos (Router)**
2.  **Config Server**
3.  **Shard 1 - Node A** (Primary)
4.  **Shard 1 - Node B** (Secondary)
5.  **Shard 1 - Node C** (Secondary)
6.  **Shard 2** (Single)
7.  **Shard 3** (Single)

**Důvod:** Tento počet je minimální nutný pro demonstraci funkčního Shardingu (3 shardy) a zároveň funkčního Failover mechanismu (3 uzly v rámci jednoho Replica Setu).

## Sharding (minimálně 3)
Pro řešení využívám **3 logické Shardy** (`rsShard1`, `rsShard2`, `rsShard3`).
**Důvod:** Tři shardy jsou dostatečné pro ukázku rovnoměrné distribuce dat (Chunk Balancing). Jako Shard Key byl zvolen atribut `id_a` s využitím **Hashed Shardingu**. To zajišťuje, že i když jdou ID sekvenčně, data jsou náhodně a rovnoměrně rozprostřena mezi všechny 3 shardy, čímž se předchází vzniku "Hot Spots".

## Replikace (minimálně 3)
Využívám hybridní model replikace:
* **Shard 1:** Replikační faktor **3**.
* **Shard 2 a 3:** Replikační faktor **1**.

**Důvod:** Replikační faktor 3 u prvního shardu je kritický pro demonstraci **High Availability**. Umožňuje simulovat výpadek (zastavení kontejneru), volbu nového lídra a zachování dostupnosti dat. U ostatních shardů je replikace omezena z důvodu úspory HW prostředků.

## Perzistence dat (minimálně 3)
Databáze využívá storage engine **WiredTiger**.
1.  **Primární paměť (RAM):** WiredTiger využívá interní cache pro operace čtení a přípravu zápisů.
2.  **Sekundární paměť (Disk):** Data jsou perzistována na disk pomocí mechanismu **Journaling** (zápisový log pro crash recovery) a **Checkpoints** (pravidelné ukládání snapshotu dat, defaultně každých 60s).
3.  **Volumes:** Všechny kontejnery mají namapované Docker Volumes (`./data/...`), což zajišťuje, že data přežijí restart i smazání kontejnerů.

## Distribuce dat
Data jsou do systému zapisována přes **Mongos**. Ten na základě `configsvr` rozhodne, na který shard data patří (podle hash klíče `id_a`).
* Pokud data padnou na **Shard 1**, jsou zapsána na uzel *Primary* a okamžitě replikována přes *Oplog* (Operations Log) na uzly *Secondary* (`shard1-b`, `shard1-c`).
* Čtení probíhá standardně z Primary uzlu, což zaručuje konzistenci. V případě výpadku Primary uzlu na Shardu 1 systém automaticky přesměruje čtení/zápis na nově zvoleného lídra.

## Zabezpečení
Databáze je zabezpečena na dvou úrovních:
1.  **Autentizace a Autorizace:** Je vytvořen uživatel `admin` s rolí `root`. Přístup k databázi je možný pouze s platným jménem a heslem.
2.  **Interní Cluster Auth (Keyfile):** Mezi uzly (Shardy, Config, Mongos) probíhá autentizace pomocí souboru `/etc/mongo-keyfile`. Bez tohoto klíče by se uzly navzájem odmítly spojit. Toto je kritické bezpečnostní opatření pro MongoDB v clusterovém režimu.

## Případ užití
**Zvolená doména:** Analýza interakcí proteinů (PPI - Protein-Protein Interactions).
**Důvod volby MongoDB:**
* **Flexibilní schéma:** Data o proteinech z různých zdrojů (Human, Mouse, Yeast) mohou mít různé atributy (někde chybí skóre, jinde publikace). Dokumentový model (JSON/BSON) toto zvládá přirozeně bez nutnosti `ALTER TABLE`.
* **Škálovatelnost:** Objem biologických dat roste exponenciálně. Sharding umožňuje horizontální škálování prostým přidáním nových serverů.
* **Agregace:** MongoDB Aggregation Framework umožňuje provádět složité analytické dotazy (bucketing, grafové průchody) efektivně.

## Výhody a nevýhody
**Výhody:**
* **Vysoká dostupnost (HA):** Díky Replica Setu systém přežije pád uzlu.
* **Horizontální škálování:** Výkon roste s počtem shardů.
* **Výkon:** Rychlý zápis díky Hashed Shardingu.

**Nevýhody:**
* **Složitost konfigurace:** Nastavení clusteru, sítě, klíčů a orchestrace je výrazně složitější než u monolitické SQL databáze.
* **Nároky na zdroje:** I v minimalizované verzi běží 9 kontejnerů, což je náročné na RAM.
* **Eventual Consistency:** Při čtení ze sekundárních uzlů (pokud by bylo povoleno) hrozí čtení neaktuálních dat.

## CAP teorém
V defaultní konfiguraci splňuje MongoDB **CP (Consistency + Partition Tolerance)**.
* **Consistency (Konzistence):** Systém garantuje, že čtení vrací nejnovější data (protože čteme z Primary).
* **Partition Tolerance (Odolnost vůči rozdělení):** Cluster funguje i při ztrátě komunikace, pokud má většina (Quorum) spojení.
* **Availability (Dostupnost) - Omezení:** V okamžiku pádu Primary uzlu (na Shardu 1) je systém po dobu voleb (několik sekund) nedostupný pro zápis. Tím obětuje dostupnost (A) ve prospěch konzistence (C).

## Dataset

### Popis datových souborů
Pro demonstraci funkcionality distribuované databáze byly zvoleny tři oddělené datové soubory reprezentující biologické sítě (Protein-Protein Interaction Networks) pro různé modelové organismy. Data pocházejí z reálné databáze **BioGRID**.

Celkem databáze obsahuje **24 000 záznamů** rozdělených do tří souborů:

* **`ppi_human.json`**
    * **Obsah:** Interakce proteinů pro organismus *Homo sapiens* (Člověk).
    * **Počet záznamů:** 8 000 dokumentů.
    * **Velikost:** Cca 2.5 MB.

* **`ppi_mouse.json`**
    * **Obsah:** Interakce proteinů pro organismus *Mus musculus* (Myš domácí).
    * **Počet záznamů:** 8 000 dokumentů.
    * **Velikost:** Cca 2.4 MB.

* **`ppi_yeast.json`**
    * **Obsah:** Interakce proteinů pro organismus *Saccharomyces cerevisiae* (Kvasinka pivní).
    * **Počet záznamů:** 8 000 dokumentů.
    * **Velikost:** Cca 2.2 MB.

### Struktura a formát dat
Data jsou uložena ve formátu **JSON** (JavaScript Object Notation), konkrétně jako pole objektů (`jsonArray`). Každý dokument v databázi reprezentuje jednu unikátní interakci mezi dvěma proteiny.

**Příklad struktury jednoho dokumentu:**

```json
{
  "id_a": "P0DP23",
  "id_b": "P0DP24",
  "score": 0.985,
  "method": "experimental",
  "publications": ["pubmed:123456", "pubmed:789012"]
}
```

#### Popis atributů:

`id_a (String):` Unikátní identifikátor prvního proteinu (např. UniProt ID). Tento atribut slouží zároveň jako Shard Key (Hashed) pro distribuci dat v clusteru.

`id_b (String):` Identifikátor druhého proteinu v páru.

`score (Double):` Číselná hodnota v intervalu 0.0 až 1.0 vyjadřující pravděpodobnost/sílu interakce (confidence score).

`method (String):` Typ metody, kterou byla interakce zjištěna (např. "experimental", "text-mining", "homology").

`publications (Array of Strings):` Seznam odkazů na vědecké publikace ověřující tuto interakci.
#### Způsob nahrání do databáze
Nahrání dat probíhá plně automatizovaně při startu prostředí.
#### Jak databáze nakládá s daty?
Po importu MongoDB analyzuje pole id_a (Shard Key). Aplikuje na něj hashovací funkci a na základě výsledného hashe umístí dokument do příslušného "chunku" na jednom ze tří shardů. Tím je zajištěno, že ačkoliv vkládáme tři soubory sekvenčně, výsledná data jsou v clusteru promíchána a rovnoměrně rozložena, což optimalizuje výkon pro čtení i zápis.

#### Zdroje a generování dat
Data jsou reálná a odpovídají záznamům z veřejné databáze BioGRID, upraveným pro potřeby semestrální práce.
## Závěr
V první části semestrální práce se podařilo navrhnout a zprovoznit komplexní **Sharded Cluster** na platformě Docker.
**Přínos:** Řešení prokazuje schopnost MongoDB škálovat a odolávat výpadkům (ověřeno testem vypnutí uzlu). Automatizační skripty umožňují nasadit celou infrastrukturu jedním příkazem (`docker-compose up`).
**Úskalí:** Hlavní výzvou byla správa zdrojů na lokálním stroji a nutnost hybridní architektury. Dále bylo nutné řešit čištění "špinavých" dat (převod typů) v rámci agregačních dotazů.

## Zdroje
* BioGRID https://thebiogrid.org
* MERMAID https://mermaid.js.org
* Oficiální dokumentace MongoDB (docs.mongodb.com) - Sharding, Replication, Docker images.
* Docker Documentation (docs.docker.com) - Compose file version 3, Networking.
* StackOverflow - řešení problémů s `keyfile` oprávněními na Windows/macOS.
* GitHub repozitář `docker-library/mongo` - vzorové Dockerfile.