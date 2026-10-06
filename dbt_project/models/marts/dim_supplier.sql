-- Conformed supplier dimension: entity resolution from ERP + SRM with survivorship rules
{{ config(materialized='table') }}

WITH erp_vendors AS (
    SELECT
        vendor_code AS supplier_id,
        vendor_name AS supplier_name,
        vendor_region AS region,
        country_code AS country,
        vendor_tier AS tier,
        vendor_status AS erp_status,
        primary_category,
        certifications,
        onboarding_date,
        annual_spend_usd_mm,
        avg_lead_time_days,
        historical_otd_pct,
        defect_rate_ppm,
        financial_risk_score,
        geopolitical_risk_score,
        payment_terms,
        company_size,
        employee_count,
        dual_source_available,
        last_audit_date,
        last_audit_result,
        DATEDIFF(DAY, onboarding_date, CURRENT_DATE()) AS tenure_days,
        CASE
            WHEN vendor_status = 'Inactive' THEN 0
            WHEN vendor_status = 'Probation' THEN 1
            WHEN vendor_status = 'Active' AND vendor_tier = 'Tier 3' THEN 2
            WHEN vendor_status = 'Active' AND vendor_tier = 'Tier 2' THEN 3
            WHEN vendor_status = 'Active' AND vendor_tier = 'Tier 1' THEN 4
            ELSE 2
        END AS erp_maturity_score
    FROM {{ source('raw_erp', 'RAW_ERP_VENDORS') }}
),

srm_suppliers AS (
    SELECT
        supplier_id AS srm_id,
        erp_vendor_ref,
        supplier_name AS srm_name,
        quality_score,
        delivery_reliability_pct,
        responsiveness_score,
        innovation_score,
        sustainability_score,
        cost_competitiveness_idx,
        relationship_tier AS srm_tier,
        esg_compliance_status,
        carbon_intensity_score,
        concentration_risk,
        backup_supplier_exists,
        -- SRM composite: weighted scorecard
        ROUND(
            quality_score * 0.30
            + delivery_reliability_pct * 0.25
            + responsiveness_score * 10 * 0.15
            + innovation_score * 10 * 0.10
            + sustainability_score * 10 * 0.10
            + cost_competitiveness_idx * 0.10
        , 2) AS srm_composite_score
    FROM {{ source('raw_srm', 'RAW_SRM_SUPPLIERS') }}
),

-- Entity resolution: join ERP vendors to SRM suppliers via erp_vendor_ref
resolved AS (
    SELECT
        e.*,
        s.srm_id,
        s.srm_name,
        s.quality_score,
        s.delivery_reliability_pct,
        s.responsiveness_score,
        s.innovation_score,
        s.sustainability_score,
        s.cost_competitiveness_idx,
        s.srm_tier,
        s.esg_compliance_status,
        s.carbon_intensity_score,
        s.concentration_risk,
        s.backup_supplier_exists,
        s.srm_composite_score,
        CASE
            WHEN s.erp_vendor_ref = e.supplier_id THEN 'EXACT_KEY'
            WHEN s.srm_id IS NOT NULL THEN 'FUZZY'
            ELSE 'ERP_ONLY'
        END AS match_method,
        -- Blended risk score: weighted across ERP + SRM signals
        ROUND(
            COALESCE(e.financial_risk_score, 3) / 5 * 100 * 0.20
            + COALESCE(e.geopolitical_risk_score, 3) / 5 * 100 * 0.15
            + (100 - COALESCE(s.quality_score, 70)) * 0.20
            + (100 - COALESCE(s.delivery_reliability_pct, 70)) * 0.20
            + (100 - COALESCE(e.historical_otd_pct, 70)) * 0.15
            + CASE COALESCE(s.concentration_risk, 'Medium')
                WHEN 'Critical' THEN 100 WHEN 'High' THEN 75
                WHEN 'Medium' THEN 50 WHEN 'Low' THEN 25 ELSE 50
              END * 0.10
        , 2) AS blended_risk_score,
        -- Supplier health tier
        CASE
            WHEN e.last_audit_result = 'Fail' OR e.erp_status = 'Inactive' THEN 'RED'
            WHEN e.erp_status = 'Probation' OR COALESCE(s.quality_score, 70) < 70 THEN 'AMBER'
            WHEN COALESCE(s.srm_composite_score, 50) >= 70 AND e.historical_otd_pct >= 85 THEN 'GREEN'
            ELSE 'AMBER'
        END AS health_tier
    FROM erp_vendors e
    LEFT JOIN srm_suppliers s ON s.erp_vendor_ref = e.supplier_id
)

SELECT * FROM resolved
