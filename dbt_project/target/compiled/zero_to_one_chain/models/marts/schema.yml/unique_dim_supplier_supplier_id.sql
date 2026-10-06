
    
    

select
    supplier_id as unique_field,
    count(*) as n_records

from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.dim_supplier
where supplier_id is not null
group by supplier_id
having count(*) > 1


