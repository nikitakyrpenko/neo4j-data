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