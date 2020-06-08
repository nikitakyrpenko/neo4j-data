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