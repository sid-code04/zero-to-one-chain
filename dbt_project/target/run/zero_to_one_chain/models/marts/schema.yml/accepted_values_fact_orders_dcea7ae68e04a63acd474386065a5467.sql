select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    

with all_values as (

    select
        order_health as value_field,
        count(*) as n_records

    from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.fact_orders
    group by order_health

)

select *
from all_values
where value_field not in (
    'COMPLETE','CANCELLED','OVERDUE_CRITICAL','OVERDUE','ON_TRACK'
)



      
    ) dbt_internal_test