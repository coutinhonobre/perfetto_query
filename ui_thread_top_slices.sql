-- Top slices mais caros na UI Thread (main thread) do app
SELECT
    s.name                          AS slice_name,
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
  AND s.dur >= 5e6   -- ignora slices menores que 5ms
GROUP BY s.name
ORDER BY total_ms DESC
LIMIT 40;