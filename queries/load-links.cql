LOAD CSV WITH HEADERS 
  FROM 'https://raw.githubusercontent.com/nikitakyrpenko/neo4j-data/master/links.csv' 
  AS csv FIELDTERMINATOR ";"
MATCH (m1:Manufacture {sequence: toInteger(csv.from)})
MATCH (m2:Manufacture {sequence: toInteger(csv.to)})
MERGE (m1) -[:LINKS_TO {cost: toInteger(csv.cost)}]-> (m2)