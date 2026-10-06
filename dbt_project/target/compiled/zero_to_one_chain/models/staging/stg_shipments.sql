-- Staged shipments from TMS


SELECT
    shipment_id,
    bill_of_lading,
    ship_date::DATE AS ship_date,
    estimated_arrival::DATE AS estimated_arrival,
    actual_arrival::DATE AS actual_arrival,
    UPPER(TRIM(shipment_status)) AS shipment_status,
    UPPER(TRIM(transport_mode)) AS transport_mode,
    UPPER(TRIM(carrier_name)) AS carrier_name,
    UPPER(TRIM(carrier_code)) AS carrier_code,
    UPPER(TRIM(origin_plant)) AS origin_plant,
    UPPER(TRIM(destination_plant)) AS destination_plant,
    UPPER(TRIM(origin_region)) AS origin_region,
    UPPER(TRIM(destination_region)) AS destination_region,
    GREATEST(gross_weight_kg, 0) AS gross_weight_kg,
    GREATEST(volume_cbm, 0) AS volume_cbm,
    GREATEST(package_count, 0) AS package_count,
    freight_cost_usd,
    insurance_cost_usd,
    customs_duty_usd,
    handling_charges_usd,
    ROUND(COALESCE(freight_cost_usd,0) + COALESCE(insurance_cost_usd,0) + COALESCE(customs_duty_usd,0) + COALESCE(handling_charges_usd,0), 2) AS total_logistics_cost_usd,
    UPPER(TRIM(incoterm)) AS incoterm,
    transit_exceptions_count,
    co2_emissions_kg,
    CASE WHEN actual_arrival IS NOT NULL AND actual_arrival <= estimated_arrival THEN TRUE ELSE FALSE END AS is_on_time,
    CASE WHEN actual_arrival IS NOT NULL THEN DATEDIFF(DAY, estimated_arrival, actual_arrival) ELSE NULL END AS delay_days,
    reference_po,
    _loaded_at,
    _source_system
FROM ZERO_TO_ONE_CHAIN.L1_INGESTION.RAW_TMS_SHIPMENTS