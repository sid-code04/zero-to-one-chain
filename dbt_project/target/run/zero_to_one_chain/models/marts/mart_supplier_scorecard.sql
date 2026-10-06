
  
    

        create or replace transient table ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.mart_supplier_scorecard
         as
        (-- Supplier scorecard: aggregated monthly performance with trend detection


WITH monthly_po AS (
    SELECT
        supplier_id,
        DATE_TRUNC('MONTH', po_date) AS score_month,
        COUNT(*) AS total_lines,
        COUNT_IF(is_on_time) AS on_time_lines,
        COUNT_IF(is_otif) AS otif_lines,
        SUM(ordered_qty) AS total_ordered,
        SUM(received_qty) AS total_received,
        SUM(rejected_qty) AS total_rejected,
        SUM(landed_cost_usd) AS total_spend,
        AVG(delivery_variance_days) AS avg_delivery_variance,
        AVG(CASE WHEN ordered_qty > 0 THEN landed_cost_usd / ordered_qty END) AS avg_unit_cost
    FROM ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.fact_purchase_orders
    WHERE po_date IS NOT NULL
    GROUP BY supplier_id, DATE_TRUNC('MONTH', po_date)
),

scored AS (
    SELECT
        m.*,
        ROUND(DIV0(m.on_time_lines, m.total_lines) * 100, 2) AS otd_pct,
        ROUND(DIV0(m.otif_lines, m.total_lines) * 100, 2) AS otif_pct,
        ROUND(DIV0(m.total_rejected, NULLIF(m.total_ordered, 0)) * 100, 2) AS reject_rate_pct,
        ROUND(DIV0(m.total_received, NULLIF(m.total_ordered, 0)) * 100, 2) AS fill_rate_pct,

        -- Trend: compare to previous month using LAG
        LAG(ROUND(DIV0(m.on_time_lines, m.total_lines) * 100, 2))
            OVER (PARTITION BY m.supplier_id ORDER BY m.score_month) AS prev_month_otd,
        ROUND(DIV0(m.on_time_lines, m.total_lines) * 100, 2)
            - COALESCE(LAG(ROUND(DIV0(m.on_time_lines, m.total_lines) * 100, 2))
                OVER (PARTITION BY m.supplier_id ORDER BY m.score_month), 0) AS otd_mom_change,

        -- 3-month moving average
        AVG(ROUND(DIV0(m.on_time_lines, m.total_lines) * 100, 2))
            OVER (PARTITION BY m.supplier_id ORDER BY m.score_month
                  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS otd_3m_avg,

        -- Spend rank within month
        RANK() OVER (PARTITION BY m.score_month ORDER BY m.total_spend DESC) AS spend_rank_in_month

    FROM monthly_po m
),

with_grade AS (
    SELECT
        s.*,
        sup.supplier_name,
        sup.region AS supplier_region,
        sup.tier,
        sup.health_tier,
        CASE
            WHEN s.otd_pct >= 95 AND s.reject_rate_pct <= 1 THEN 'A'
            WHEN s.otd_pct >= 85 AND s.reject_rate_pct <= 5 THEN 'B'
            WHEN s.otd_pct >= 70 THEN 'C'
            ELSE 'D'
        END AS monthly_grade,
        CASE
            WHEN s.otd_mom_change < -10 THEN 'DECLINING_FAST'
            WHEN s.otd_mom_change < -3 THEN 'DECLINING'
            WHEN s.otd_mom_change > 5 THEN 'IMPROVING'
            ELSE 'STABLE'
        END AS trend_direction
    FROM scored s
    LEFT JOIN ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.dim_supplier sup ON sup.supplier_id = s.supplier_id
)

SELECT * FROM with_grade
        );
      
  