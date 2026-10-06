-- Customer delivery performance: SLA tracking with breach analysis
{{ config(materialized='table') }}

WITH customer_monthly AS (
    SELECT
        customer_id,
        customer_name,
        customer_region,
        industry,
        segment,
        service_tier,
        order_month,
        COUNT(*) AS total_lines,
        COUNT_IF(is_on_time) AS on_time_lines,
        COUNT_IF(is_otif) AS otif_lines,
        COUNT_IF(is_sla_breach) AS sla_breaches,
        SUM(net_value_usd) AS total_revenue,
        SUM(CASE WHEN NOT is_on_time THEN net_value_usd ELSE 0 END) AS late_order_revenue,
        AVG(delivery_variance_days) AS avg_delivery_variance,
        AVG(fill_rate_pct) AS avg_fill_rate,
        COUNT_IF(order_health = 'OVERDUE_CRITICAL') AS critical_overdue_count
    FROM {{ ref('fact_orders') }}
    WHERE order_date IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),

with_metrics AS (
    SELECT
        cm.*,
        ROUND(DIV0(cm.on_time_lines, cm.total_lines) * 100, 2) AS otd_pct,
        ROUND(DIV0(cm.otif_lines, cm.total_lines) * 100, 2) AS otif_pct,
        ROUND(DIV0(cm.late_order_revenue, NULLIF(cm.total_revenue, 0)) * 100, 2) AS late_revenue_pct,

        -- Month-over-month trend
        LAG(ROUND(DIV0(cm.on_time_lines, cm.total_lines) * 100, 2))
            OVER (PARTITION BY cm.customer_id ORDER BY cm.order_month) AS prev_month_otd,

        -- 3-month rolling average
        AVG(ROUND(DIV0(cm.on_time_lines, cm.total_lines) * 100, 2))
            OVER (PARTITION BY cm.customer_id ORDER BY cm.order_month
                  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS otd_3m_rolling,

        -- Customer revenue rank (overall)
        DENSE_RANK() OVER (PARTITION BY cm.order_month ORDER BY cm.total_revenue DESC) AS revenue_rank,

        -- Cumulative SLA breaches YTD
        SUM(cm.sla_breaches)
            OVER (PARTITION BY cm.customer_id, DATE_TRUNC('YEAR', cm.order_month)
                  ORDER BY cm.order_month) AS ytd_sla_breaches
    FROM customer_monthly cm
),

final AS (
    SELECT
        wm.*,
        CASE
            WHEN wm.otd_pct >= 95 AND wm.sla_breaches = 0 THEN 'EXCELLENT'
            WHEN wm.otd_pct >= 85 THEN 'GOOD'
            WHEN wm.otd_pct >= 70 THEN 'AT_RISK'
            ELSE 'CRITICAL'
        END AS delivery_health,
        CASE
            WHEN wm.ytd_sla_breaches > 10 AND wm.service_tier IN ('Platinum', 'Gold') THEN 'ESCALATION_REQUIRED'
            WHEN wm.ytd_sla_breaches > 5 THEN 'REVIEW_REQUIRED'
            WHEN wm.critical_overdue_count > 0 THEN 'ATTENTION'
            ELSE 'OK'
        END AS action_status
    FROM with_metrics wm
)

SELECT * FROM final
