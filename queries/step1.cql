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