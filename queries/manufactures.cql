MATCH (m :Manufacture)
RETURN m.number as Number, m.name as Name, m.category as Category, m.zone as Zone
  ORDER BY m.zone, m.category, m.number