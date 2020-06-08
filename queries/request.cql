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