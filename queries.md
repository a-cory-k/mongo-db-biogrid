##### 1. Rozdělení interakcí podle metody a průměrné skóre
```
db.interactions.aggregate([
  {
    $match: { score: { $ne: "-" } } 
  },
  {
    $addFields: { numericScore: { $toDouble: "$score" } } 
  },
  {
    $group: {
      _id: "$method", // Seskupit podle metody
      count: { $sum: 1 },
      avgScore: { $avg: "$numericScore" } 
    }
  },
  {
    $project: {
      _id: 0,
      method: "$_id",
      totalInteractions: "$count",
      averageConfidence: { $round: ["$avgScore", 2] }
    }
  },
  { $sort: { averageConfidence: -1 } }
])
```
##### Výsledek
```
[
  {
    method: 'Proximity Label-MS',
    totalInteractions: 716,
    averageConfidence: 30.08
  },
  {
    method: 'Affinity Capture-MS',
    totalInteractions: 2147,
    averageConfidence: 24.73
  },
  {
    method: 'Two-hybrid',
    totalInteractions: 28,
    averageConfidence: 2.8
  },
  {
    method: 'Affinity Capture-RNA',
    totalInteractions: 22,
    averageConfidence: 1.52
  },
  {
    method: 'Reconstituted Complex',
    totalInteractions: 3,
    averageConfidence: 1.44
  },
  {
    method: 'Positive Genetic',
    totalInteractions: 843,
    averageConfidence: 0.91
  },
  {
    method: 'Co-fractionation',
    totalInteractions: 2443,
    averageConfidence: 0.81
  },
  {
    method: 'Synthetic Growth Defect',
    totalInteractions: 7,
    averageConfidence: 0.55
  },
  {
    method: 'Synthetic Lethality',
    totalInteractions: 26,
    averageConfidence: 0.02
  },
  {
    method: 'Dosage Growth Defect',
    totalInteractions: 12,
    averageConfidence: -0.33
  },
  {
    method: 'Negative Genetic',
    totalInteractions: 4143,
    averageConfidence: -0.79
  }
]
```
##### 2. Filtrace silných interakcí (Top 5)
```
db.interactions.aggregate([
  { $match: { score: { $ne: "-" } } },
  { $addFields: { numericScore: { $toDouble: "$score" } } },
  { $match: { numericScore: { $gt: 0.9 } } }, 
  { 
    $project: { 
      _id: 0, 
      pair: { $concat: [{ $toString: "$id_a" }, " <-> ", { $toString: "$id_b" }] },
      confidence: "$numericScore"
    } 
  },
  { $sort: { confidence: -1 } },
  { $limit: 5 }
])
```
##### Výsledek
```
[
  { pair: '115757 <-> 119722', confidence: 18190 },
  { pair: '122422 <-> 113854', confidence: 4148 },
  { pair: '215050 <-> 223700', confidence: 1902 },
  { pair: '109570 <-> 116185', confidence: 1865 },
  { pair: '110434 <-> 109230', confidence: 1436.4 }
]
```
##### 3. Statistika "Hub" proteinů
```
db.interactions.aggregate([
  { 
    $group: { 
      _id: "$id_a", 
      connections: { $sum: 1 }
    } 
  },
  { $sort: { connections: -1 } },
  { $limit: 3 }
])
```
##### Výsledek
```
[
  { _id: 215410, connections: 140 },
  { _id: 229254, connections: 124 },
  { _id: 197991, connections: 116 }
]
```
##### 4. Bucketing: Kategorie kvality
```
db.interactions.aggregate([
  { $match: { score: { $ne: "-" } } },
  { $addFields: { numericScore: { $toDouble: "$score" } } },
  {
    $bucket: {
      groupBy: "$numericScore", 
      boundaries: [0, 0.4, 0.7, 1.0], 
      default: "Other",
      output: {
        count: { $sum: 1 },
        sample: { $first: "$id_a" }
      }
    }
  }
])
```
##### Výsledek
```
[
  { _id: 0, count: 953, sample: 121884 },
  { _id: 0.4, count: 243, sample: 4383857 },
  { _id: 0.7, count: 3987, sample: 126289 },
  { _id: 'Other', count: 5207, sample: 120668 }
]
```
##### 5. Náhodný výběr vzorku
```
db.interactions.aggregate([
  { $match: { score: { $ne: "-" } } },
  { 
     $match: { 
        $expr: { $gt: [ { $toDouble: "$score" }, 0.5 ] } 
     } 
  },
  { $sample: { size: 3 } }
])
```
##### Výsledek
```
[
  {
    _id: ObjectId('69353fd1617fc905e876dd59'),
    id_a: 214464,
    id_b: 223241,
    gene_a: 'Arhgap19',
    gene_b: 'Lpxn',
    method: 'Co-fractionation',
    publication: 'PUBMED:32325033',
    score: '0.773',
    imported_at: '2025-12-06T15:27:19.268419'
  },
  {
    _id: ObjectId('69353fd02a6474df39874791'),
    id_a: 111782,
    id_b: 129236,
    gene_a: 'PEX19',
    gene_b: 'ASPM',
    method: 'Affinity Capture-MS',
    publication: 'PUBMED:33961781',
    score: '0.986515233',
    imported_at: '2025-12-06T15:27:16.012476'
  },
  {
    _id: ObjectId('69353fd02a6474df398746c8'),
    id_a: 111691,
    id_b: 111675,
    gene_a: 'PSMD13',
    gene_b: 'PSMC3',
    method: 'Affinity Capture-MS',
    publication: 'PUBMED:17353931',
    score: '0.569',
    imported_at: '2025-12-06T15:27:16.012476'
  }
]
```
##### 6. Detekce anomálií
```
db.interactions.aggregate([
  { $match: { score: { $ne: "-" } } },
  { $addFields: { numericScore: { $toDouble: "$score" } } },
  { $match: { numericScore: { $lt: 0.2 } } },
  { 
    $addFields: { 
      status: "Suspicious", 
      checkRequired: true 
    } 
  },
  { $project: { id_a: 1, id_b: 1, score: 1, status: 1 } },
  { $limit: 5 }
])
```
##### Výsledek
```
[
  {
    _id: ObjectId('69353fd02a6474df39873d71'),
    id_a: 121884,
    id_b: 117140,
    score: '0.072533806',
    status: 'Suspicious'
  },
  {
    _id: ObjectId('69353fd02a6474df39873d80'),
    id_a: 108377,
    id_b: 115824,
    score: '0.01',
    status: 'Suspicious'
  },
  {
    _id: ObjectId('69353fd02a6474df39873d91'),
    id_a: 110969,
    id_b: 115063,
    score: '0.0',
    status: 'Suspicious'
  },
  {
    _id: ObjectId('69353fd02a6474df39873efb'),
    id_a: 115842,
    id_b: 111839,
    score: '0.129184137',
    status: 'Suspicious'
  },
  {
    _id: ObjectId('69353fd02a6474df39873f64'),
    id_a: 107036,
    id_b: 107262,
    score: '0.0',
    status: 'Suspicious'
  }
]
```
##### 7. Fazetové vyhledávání (Multi-report)
```
db.interactions.aggregate([
  { $match: { score: { $ne: "-" } } },
  { $addFields: { num: { $toDouble: "$score" } } },
  {
    $facet: {
      "stats_score": [
        { $group: { _id: null, avg: { $avg: "$num" }, max: { $max: "$num" } } }
      ],
      "stats_count": [
        { $count: "total_records" }
      ]
    }
  }
])
```
##### Výsledek
```
[
  {
    stats_score: [ { _id: null, avg: 7.145639124780222, max: 18190 } ],
    stats_count: [ { total_records: 10390 } ]
  }
]
```
##### 8. Vytvoření nové kolekce "high_quality"
```
db.interactions.aggregate([
  { $match: { score: { $ne: "-" } } },
  { $addFields: { numericScore: { $toDouble: "$score" } } },
  { $match: { numericScore: { $gte: 0.85 } } },
  { $out: "high_quality_interactions" }
])
```
##### Výsledek
```
show collections
```
high_quality_interactions
interactions

##### 9. Analýza nové kolekce
```
db.high_quality_interactions.find({}, { _id: 0, id_a: 1, numericScore: 1 }).sort({ numericScore: -1 }).limit(3)
```
##### Výsledek
```
[
  { id_a: 115757, numericScore: 18190 },
  { id_a: 122422, numericScore: 4148 },
  { id_a: 215050, numericScore: 1902 }
]
```
##### 10. Sharding Statistics
```
db.interactions.aggregate([
  { $collStats: { storageStats: { } } },
  { 
    $project: { 
      shard: "$shard", 
      count: "$storageStats.count", 
      size_mb: { $divide: ["$storageStats.size", 1048576] } 
    } 
  }
])
```
##### Výsledek
```
[
  { shard: 'rsShard3', count: 8205, size_mb: 1.5746784210205078 },
  { shard: 'rsShard1', count: 8031, size_mb: 1.5423355102539062 },
  { shard: 'rsShard2', count: 7764, size_mb: 1.4914627075195312 }
]
```
##### 11. Hledání duplicit
```
db.interactions.aggregate([
  {
    $group: {
      _id: { p1: "$id_a", p2: "$id_b" },
      dups: { $sum: 1 }
    }
  },
  { $match: { dups: { $gt: 1 } } },
  { $limit: 5 }
])
```
##### Výsledek
```
[
  { _id: { p1: 32940, p2: 36917 }, dups: 2 },
  { _id: { p1: 206690, p2: 116870 }, dups: 2 },
  { _id: { p1: 199564, p2: 199384 }, dups: 3 },
  { _id: { p1: 202250, p2: 608294 }, dups: 2 },
  { _id: { p1: 30968, p2: 32149 }, dups: 2 }
]
```
##### 12. Textová transformace (Upper Case)
```
db.interactions.aggregate([
  { $limit: 3 },
  {
    $project: {
      protein_A: { $toString: "$id_a" }, // ID na text
      original_score: "$score"
    }
  },
  {
     $project: {
        protein_A_upper: { $toUpper: "$protein_A" },
        original_score: 1
     }
  }
])
```
##### Výsledek
```
[
  {
    _id: ObjectId('69353fd02a6474df39873d3e'),
    original_score: '-',
    protein_A_upper: '124219'
  },
  {
    _id: ObjectId('69353fd02a6474df39873d3f'),
    original_score: '0.899573064',
    protein_A_upper: '109878'
  },
  {
    _id: ObjectId('69353fd02a6474df39873d48'),
    original_score: '0.954835903',
    protein_A_upper: '123046'
  }
]
```
##### 13. Podmíněné formátování (Switch Case)
```
db.interactions.aggregate([
  { $match: { score: { $ne: "-" } } },
  { $addFields: { ns: { $toDouble: "$score" } } },
  { $limit: 5 },
  {
    $project: {
      id_a: 1,
      score: 1,
      qualityLabel: {
        $switch: {
          branches: [
            { case: { $gte: ["$ns", 0.9] }, then: "Excellent" },
            { case: { $gte: ["$ns", 0.7] }, then: "Good" }
          ],
          default: "Average"
        }
      }
    }
  }
])
```
##### Výsledek
```
[
  {
    _id: ObjectId('69353fd02a6474df39873d46'),
    id_a: 126289,
    score: '0.842473106',
    qualityLabel: 'Good'
  },
  {
    _id: ObjectId('69353fd02a6474df39873d47'),
    id_a: 119274,
    score: '0.982463916',
    qualityLabel: 'Excellent'
  },
  {
    _id: ObjectId('69353fd02a6474df39873d4d'),
    id_a: 126680,
    score: '0.999999622',
    qualityLabel: 'Excellent'
  },
  {
    _id: ObjectId('69353fd02a6474df39873d56'),
    id_a: 111717,
    score: '0.930154419',
    qualityLabel: 'Excellent'
  },
  {
    _id: ObjectId('69353fd02a6474df39873d58'),
    id_a: 120343,
    score: '0.999298249',
    qualityLabel: 'Excellent'
  }
]
```
##### 14. GraphLookup (Síťová analýza)
```
db.interactions.aggregate([
  { $limit: 1 }, 
  {
    $graphLookup: {
      from: "interactions",
      startWith: "$id_b",
      connectFromField: "id_b",
      connectToField: "id_a",
      as: "network_connections",
      maxDepth: 1
    }
  },
  { $project: { start_protein: "$id_a", network_size: { $size: "$network_connections" } } }
])
```
##### Výsledek
```
[
  {
    _id: ObjectId('69353fd02a6474df39873d41'),
    start_protein: 121509,
    network_size: 10
  }
]
```
##### 15. Clean-up (Unset)
```
db.interactions.aggregate([
  { $limit: 3 },
  { $unset: ["_id", "gene_b", "publication"] } 
])
```
##### Výsledek
```
[
  {
    id_a: 121509,
    id_b: 115508,
    gene_a: 'NMRAL1',
    method: 'Affinity Capture-MS',
    score: '-',
    imported_at: '2025-12-06T15:27:16.012476'
  },
  {
    id_a: 114908,
    id_b: 109544,
    gene_a: 'BAG2',
    method: 'Affinity Capture-Western',
    score: '-',
    imported_at: '2025-12-06T15:27:16.012476'
  },
  {
    id_a: 126289,
    id_b: 121311,
    gene_a: 'TPRA1',
    method: 'Affinity Capture-MS',
    score: '0.842473106',
    imported_at: '2025-12-06T15:27:16.012476'
  }
]
```
---------------

#### Práce s Clusterem a simulace výpadku (High Availability Test)

V rámci projektu bylo implementováno horizontální škálování (Sharding) i replikace (Replication).

Architektura: Data jsou distribuována mezi 3 Shardy.

Shard 1: Nakonfigurován jako plnohodnotný Replica Set (3 uzly: Primary + 2 Secondaries) pro demonstraci vysoké dostupnosti.

Shard 2 & 3: Běží jako samostatné uzly (Single Node) pro úsporu systémových zdrojů (Proof of Concept).

Distribuce: Shard Key je { "id_a": "hashed" }.

Scénář simulace výpadku (Failover Test)

Cílem je ověřit, že systém přežije pád primárního uzlu bez ztráty dat.

1. Krok: Identifikace Primary uzlu Pomocí příkazu rs.status() na Shard 1 zjistíme, který kontejner je aktuálně PRIMARY (např. shard1).

2. Krok: Sabotáž (Simulace havárie) V terminálu "zabijeme" hlavní uzel prvního shardu:

Bash

```
docker stop shard1
```
10 sec


```
docker exec -it shard1-b mongosh --port 27017 --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"
```
shard1:27017: (not reachable)/ unhealthy.

shard1-b:27017: PRIMARY
```
docker exec -it mongos mongosh --port 27017 -u admin -p password123 --authenticationDatabase admin
```
```
use protein_db
db.interactions.getShardDistribution()
```
A bude to fungovat bez chyby. Pokud to uděláme např. s shard2, vratí to s chybou

3. Krok: Automatická obnova (Election) Zbylé uzly (shard1-b, shard1-c) detekují ztrátu spojení. Proběhne hlasování (Election) a během několika sekund je jeden ze záložních uzlů povýšen na nového PRIMARY.

4. Krok: Ověření dostupnosti Provádíme čtení dat přes router mongos.

Výsledek: Data umístěná na Shard 1 jsou stále dostupná. Uživatel nezaznamenal výpadek, dotazy jsou automaticky směrovány na nový hlavní uzel.

Poznámka: Pokud bychom vypnuli Shard 2 (který nemá repliky), část dat by se stala nedostupnou. Tím demonstrujeme nutnost Replica Setů v produkčním prostředí.