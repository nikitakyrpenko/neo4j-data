### Створення схеми

```cypher
LOAD CSV WITH HEADERS
  FROM 'https://raw.githubusercontent.com/nikitakyrpenko/neo4j-data/master/nodes.csv' 
  AS csv FIELDTERMINATOR ";"
CREATE (m :Manufacture {
  sequence: toInteger(csv.id),
  number: csv.number,
  name: csv.name,
  zone: csv.zone,
  category: csv.category
})
MERGE (z:zone { name: csv.zone})
WITH m, z
CALL apoc.create.addLabels( 
  id(m), 
  [apoc.text.capitalize(z.name)]
) YIELD node
MERGE (z) -[:HOSTS]-> (m)
```
`Added 68 labels, created 68 nodes, set 308 properties, created 60 relationships, completed after 540 ms.`

![alt text](https://github.com/nikitakyrpenko/neo4j-data/blob/master/images/load-manufactures.png?raw=true)

Сценарій завантаження виконує наступні дії:

- Створює виробничі вузли на основі (https://raw.githubusercontent.com/nikitakyrpenko/neo4j-data/master/nodes.csv).

- Створіть вузлові зони на основі даних про зону.

- Додає мітки зони для вузлів виробників

- Пов’язує зони до виробників із співвідношенням `: HOSTS`.

Наступне [load_links.cql](https://raw.githubusercontent.com/nikitakyrpenko/neo4j-data/master/links.csv).

```cypher
LOAD CSV WITH HEADERS 
  FROM 'https://raw.githubusercontent.com/nikitakyrpenko/neo4j-data/master/links.csv' 
  AS csv FIELDTERMINATOR ";"
MATCH (m1:Manufacture {sequence: toInteger(csv.from)})
MATCH (m2:Manufacture {sequence: toInteger(csv.to)})
MERGE (m1) -[:LINKS_TO {cost: toInteger(csv.cost)}]-> (m2)
```

`Set 87 properties, created 87 relationships, completed after 347 ms.`

![alt text](https://github.com/nikitakyrpenko/neo4j-data/blob/master/images/load-links.png?raw=true)

Сценарій створює зв'язки між виробництвом на основі (https://raw.githubusercontent.com/nikitakyrpenko/neo4j-data/master/links.csv).

### Перевірка даних

```cypher
MATCH (m :Manufacture)
RETURN m.number as Number, m.name as Name, m.category as Category, m.zone as Zone
  ORDER BY m.zone, m.category, m.number
```

![alt text](https://github.com/nikitakyrpenko/neo4j-data/blob/master/images/manufactures.png?raw=true)


## Оптимізація маршруту
### Вибір товарів

Тож тепер, коли ми налаштовані і готові до роботи, давайте виберемо виробництво, яке ми збираємося придбати.

- Для ООО Мясні продукти, Баранина.
- Для ООО Овочеві продукти, Морква.
- Для ООО Піцці, Піца і тісто.
- Для ООО Солодощі, Солодощі.

```cypher
WITH [{ number: "Баранина", for: "ООО Мясні продукти"},
       {number: "Морква", for: "ООО Овочеві продукти"},
       {number: "Піца і тісто", for: "ООО Піцці"},
       {number: "Солодощі", for: "ООО Солодощі"}
     ] as gifts
UNWIND gifts as gift
MATCH (m:Manufacture { number: gift.number})
RETURN
  gift.number as Number,
  gift.for as For,
  m.name as Name,
  m.zone as Zone,
  m.category as Category
  ORDER by m.zone, m.number
```

![alt text](https://github.com/nikitakyrpenko/neo4j-data/blob/master/images/request.png?raw=true)

### Алгоритм
 
Давайте знайдемо оптимальний маршрут навколо області. Пояснення подано нижче.

```cypher
WITH ["Баранина","Морква","Піца і тісто","Солодощі"] as selection
MATCH (m:Manufacture) where m.number in selection
WITH collect(m) as manufactures
UNWIND manufactures as m1
WITH m1,
     filter(m in manufactures where m.number > m1.number) as c2s,
     manufactures
UNWIND c2s as m2
CALL algo.shortestPath.stream(m1, m2, 'cost', {relationshipQuery: 'LINKS_TO'}) YIELD nodeId, cost
WITH m1,
     m2,
     max(cost) as totalCost,
     collect(nodeId) as shortestHopNodeIds,
     manufactures
MERGE (m1) -[r:SHORTEST_ROUTE_TO]- (m2)
SET r.cost = totalCost
SET r.shortestHopNodeIds = shortestHopNodeIds
WITH m1,
     m2,
     (size(manufactures) - 1) as level,
     manufactures
CALL apoc.path.expandConfig(m1, {
        relationshipFilter: 'SHORTEST_ROUTE_TO', 
        minLevel: level, 
        maxLevel: level, 
        whitelistNodes: manufactures, 
        terminatorNodes: [m2], 
        uniqueness: 'NODE_PATH' }
      ) YIELD path
WITH nodes(path) as orderedChalets,
     extract(n in nodes(path) | id(n)) as ids,
     reduce(cost = 0, x in relationships(path) | cost + x.cost) as totalCost,
     extract(r in relationships(path) | r.shortestHopNodeIds) as shortestRouteNodeIds
  ORDER BY totalCost LIMIT 1
  UNWIND range(0, size(orderedChalets) - 1) as index
UNWIND shortestRouteNodeIds[index] as shortestHopNodeId
WITH orderedChalets, totalCost, index,
     CASE WHEN shortestRouteNodeIds[index][0] = ids[index]
     THEN tail(collect(shortestHopNodeId))
       ELSE tail(reverse(collect(shortestHopNodeId)))
       END as orderedHopNodeIds
  ORDER BY index
UNWIND orderedHopNodeIds as orderedHopNodeId
MATCH (m: Manufacture) where id(m) = orderedHopNodeId
RETURN extract(m in orderedChalets | m.name) as names, 
       extract(m in orderedChalets | m.number) as chaletNumbers, 
       [orderedChalets[0].number] + collect(m.number) as chaletRoute, 
      totalCost
```

#### Крок 1

На кроці 1 обчислюється найкоротший шлях між кожною з виробництв, використовуючи алгоритм `algo.shortestPath.stream`. 

Зв'язки "SHORTEST_ROUTE_TO" об'єднуються між кожною окремою парою вибраних виробників, із загальною вартістю найкоротшого шляху та стрибками найкоротшого шляху, що зберігаються у відносинах. 

Певна оптимізація досягається завдяки забезпеченню, що найкоротший шлях між парою вузлів обчислюється лише в одному напрямку.

#### Крок 2

Крок 2 алгоритму використовує ці щойно розраховані витрати, щоб повернути найкоротший шлях, який включає всі обрані виробники. 

Цей крок використовує процедуру APOC `apoc.path.expandConfig`, використовуючи зв'язки SHORTEST_ROUTE_TO для визначення шляхів. 

Результати шляху впорядковані за загальною вартістю.

Path expander config обмежує алгоритм розширення контуру, щоб гарантувати, що всі вибрані вузли виробників відвідуються лише один раз у межах мережі SHORTEST_ROUTE_TO. 

Це робиться, гарантуючи, що кількість пройдених рівнів ("minLevel" і "maxLevel") дорівнює кількості виробництв - 1 (в даному випадку 7), і що всі вузли, які пройшли, є унікальними. 

`whitelistNodes` обмежує шляхи до вибору виробників, що забезпечує деяку оптимізацію.

#### Крок 3

Крок 3 алгоритму готує дані до повернення та надає список повного маршруту через виробників. 

Він використовує `shortestHopNodeIds`, обчислений на кроці 1, він прив'язує маршрут видалення дублікатів, і це забезпечує послідовний напрямок.

Для наших обраних виробників результатом роботи алгоритму є:

![alt text](https://github.com/nikitakyrpenko/neo4j-data/blob/master/images/result.png?raw=true)

## Візуалізація маршруту

У цьому другому розділі ми розглянемо, як ми можемо відобразити маршрут, обчислений алгоритмом у першому розділі. 

Ідея полягає у створенні корисного планувальника маршрутів, який спрямовує користувача від виробництва до виробництва.

1) Виробник в маршруті.
2) Порядок переходу виробника.
3) Вхідні та вихідні точки маршруту.
4) Виробництво в одній зоні забарвлене однаково.
5) Зонні вузли, приєднані до шале, щоб вказати, коли відбувається зміна зони.
6) Відображаються назви виробників.
7) Необхідно вказати виробництво вибраних товарів.

Віртуальні вузли та зв'язки APOC допомагають досягти цього спеціального візуального зображення.

```cypher
WITH ["Баранина","Морква","Піца і тісто","Солодощі"] AS selection,
     ["Баранина", "Індичатина", "Селера", "Сьомга", "Морозиво", "Солодощі", "Крабові палочки", "Персик", "Морква", "Лосось", "Часник", "Піца і тісто"] AS route
MATCH (manufacture :Manufacture) WHERE manufacture.number IN route 
WITH route, manufacture,
     CASE WHEN manufacture.number in selection 
         THEN 'Selected' 
         ELSE 'NotSelected' 
         END AS selected,
     CASE WHEN manufacture.number in selection 
         THEN '* '+manufacture.number+': '+manufacture.name 
          ELSE manufacture.number+': '+manufacture.name 
          END AS title
CALL apoc.create.vNode([selected] + labels(manufacture), {title: title}) YIELD node 
WITH route, collect(manufacture) AS manufacture, collect(node) as vChalets
CALL apoc.create.vNode(['EntryExit'], { ee: 'Enter'}) YIELD node as enter 
CALL apoc.create.vNode(['EntryExit'], { ee: 'Exit'}) YIELD node as exit 
MATCH (firstChalet :Manufacture { number: head(route)})
MATCH (lastChalet :Manufacture { number: last(route)})
CALL apoc.create.vRelationship(enter, 'VIA', {}, vChalets[apoc.coll.indexOf(manufacture, firstChalet)] ) 
  YIELD rel as enteringVia
CALL apoc.create.vRelationship(vChalets[apoc.coll.indexOf(manufacture, lastChalet)], 'VIA', {}, exit ) 
  YIELD rel as exitingVia
WITH apoc.coll.pairs(route) as hops, manufacture, vChalets, enter, exit, enteringVia, exitingVia
UNWIND hops as hop
MATCH (from :Manufacture {number: hop[0]}) -[l:LINKS_TO]- (to :Manufacture {number: hop[1]}) 
CALL apoc.create.vRelationship(
  vChalets[apoc.coll.indexOf(manufacture, from)], 
  'NEXT', 
  properties(l), 
  vChalets[apoc.coll.indexOf(manufacture, to)] 
  )  YIELD rel as next
CALL apoc.create.vNode([null], { name: to.zone }) YIELD node as zone
CALL apoc.create.vRelationship(zone, 'HOSTS', {}, vChalets[apoc.coll.indexOf(manufacture, to)] ) 
  YIELD rel as hosts
WITH manufacture, vChalets, enter, exit, enteringVia, exitingVia, collect(next) as nexts, hops
MATCH (startZone :zone) -[:HOSTS]-> (startChalet:Manufacture { number: hops[0][0]})
CALL apoc.create.vNode(['Zone'], properties(startZone)) 
  YIELD node as vStartZone
CALL apoc.create.vRelationship(
  vStartZone, 
  'HOSTS', 
  {}, 
  vChalets[apoc.coll.indexOf(manufacture, startChalet)]
  ) YIELD rel as startHost
UNWIND hops as hop
MATCH (zone1 :zone) -[:HOSTS]-> (from:Manufacture { number: hop[0]})
MATCH (zone2 :zone) -[:HOSTS]-> (to:Manufacture { number: hop[1]})
  WHERE apoc.coll.different([zone1, zone2])
CALL apoc.create.vNode(['Zone'], properties(zone2)) 
  YIELD node as zone
CALL apoc.create.vRelationship(zone, 'HOSTS', {}, vChalets[apoc.coll.indexOf(manufacture, to)]) 
  YIELD rel as host
RETURN 
  vChalets, 
  enter, 
  exit, 
  enteringVia, 
  exitingVia, 
  nexts, 
  vStartZone, 
  startHost, 
  collect(zone) as zones, 
  collect(host) as hosts
```

Спочатку виробники узгоджуються на основі маршруту, розрахованого алгоритмом у Розділі 1.

Потім виробники позначаються як "Вибрані" або "Невибрані" на основі того, чи вони також існують у вихідному списку відбору. 

Текст, який відображатиметься на всіх вузлах виробників, визначається 'title', а для кожного виготовлення створюються віртуальні вузли з мітками та властивостями, що відображають відповідність.

Створюються віртуальні вузли для вхідних та вихідних точок та пов'язані з віртуальним відношенням VIA до першого та останнього виробників маршруту.

Віртуальні відносини `NEXT` створюються для показу хмелю між кожним виробництвом. Співвідношення `NEXT` забезпечує спрямованість від виробництва до виробництва через маршрут.

![alt text](https://github.com/nikitakyrpenko/neo4j-data/blob/master/images/visual.png?raw=true)
