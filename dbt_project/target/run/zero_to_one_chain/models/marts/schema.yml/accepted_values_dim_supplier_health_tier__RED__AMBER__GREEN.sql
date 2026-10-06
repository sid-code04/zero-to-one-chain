select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    

with all_values as (

    select
        health_tier as value_field,
        count(*) as n_records

    from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.dim_supplier
    group by health_tier

)

select *
from all_values
where value_field not in (
    'RED','AMBER','GREEN'
)



      
    ) dbt_internal_test