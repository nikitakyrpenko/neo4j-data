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