
    
    

with all_values as (

    select
        action_status as value_field,
        count(*) as n_records

    from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.mart_customer_delivery
    group by action_status

)

select *
from all_values
where value_field not in (
    'ESCALATION_REQUIRED','REVIEW_REQUIRED','ATTENTION','OK'
)


