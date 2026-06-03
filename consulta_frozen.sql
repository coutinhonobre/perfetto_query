WITH frozen_frames AS (
    -- 1. Encontra os frames congelados em qualquer processo do Itaú
    SELECT 
        actual.id AS frame_id,
        actual.ts AS frame_ts,
        actual.dur AS frame_dur,
        actual.upid,
        p.name AS process_name
    FROM actual_frame_timeline_slice actual
    JOIN process p ON actual.upid = p.upid
    WHERE p.name LIKE 'com.myapp%'
      AND actual.dur >= 700000000 -- Filtro de Frozen Frame (700ms)
),
app_threads AS (
    -- 2. Mapeia as threads desses processos (Main threads e RenderThreads)
    SELECT utid, upid, name AS thread_name
    FROM thread
    WHERE name LIKE 'com.myapp%' OR name = 'RenderThread'
)
-- 3. Junta tudo com as fatias de código para expor o culpado
SELECT 
    f.process_name,
    f.frame_id,
    f.frame_dur / 1000000.0 AS frame_duration_ms,
    t.thread_name,
    s.name AS culprit_method_name,
    s.dur / 1000000.0 AS method_duration_ms
FROM frozen_frames f
JOIN app_threads t ON f.upid = t.upid
JOIN thread_track tr ON t.utid = tr.utid
JOIN slice s ON s.track_id = tr.id
WHERE s.ts >= f.frame_ts 
  AND (s.ts + s.dur) <= (f.frame_ts + f.frame_dur)
  AND s.dur >= 30000000 -- Filtra métodos menores que 30ms para limpar o ruído
ORDER BY f.frame_dur DESC, s.dur DESC;