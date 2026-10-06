select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    

with all_values as (

    select
        monthly_grade as value_field,
        count(*) as n_records

    from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.mart_supplier_scorecard
    group by monthly_grade

)

select *
from all_values
where value_field not in (
    'A','B','C','D'
)



      
    ) dbt_internal_test