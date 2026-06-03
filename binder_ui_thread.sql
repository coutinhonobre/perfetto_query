-- Binder calls lentos na UI Thread — principais candidatos a ANR e jank
SELECT
    s.name                          AS binder_call,
    COUNT(*)                        AS ocorrencias,
    ROUND(AVG(s.dur) / 1e6, 2)     AS avg_ms,
    ROUND(MAX(s.dur) / 1e6, 2)     AS max_ms,
    ROUND(SUM(s.dur) / 1e6, 2)     AS total_ms
FROM slice s
JOIN thread_track tr ON s.track_id = tr.id
JOIN thread t  ON tr.utid = t.utid
JOIN process p ON t.upid  = p.upid
WHERE p.name LIKE 'com.myapp%'
  AND t.name = 'main'
  AND (
      s.name LIKE 'binder%'
      OR s.name LIKE '%AIDL%'
      OR s.name LIKE 'android.%'
  )
  AND s.dur >= 1e6   -- ignora chamadas menores que 1ms
GROUP BY s.name
ORDER BY max_ms DESC
LIMIT 30;