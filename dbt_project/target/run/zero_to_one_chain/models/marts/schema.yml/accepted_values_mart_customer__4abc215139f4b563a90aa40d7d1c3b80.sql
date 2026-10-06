select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    

with all_values as (

    select
        delivery_health as value_field,
        count(*) as n_records

    from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.mart_customer_delivery
    group by delivery_health

)

select *
from all_values
where value_field not in (
    'EXCELLENT','GOOD','AT_RISK','CRITICAL'
)



      
    ) dbt_internal_test