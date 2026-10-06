select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    

with all_values as (

    select
        trend_direction as value_field,
        count(*) as n_records

    from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.mart_supplier_scorecard
    group by trend_direction

)

select *
from all_values
where value_field not in (
    'DECLINING_FAST','DECLINING','STABLE','IMPROVING'
)



      
    ) dbt_internal_test