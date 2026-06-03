-- Diagnóstico rápido: houve problema de performance?
-- Retorna uma linha por processo com veredicto e principais sintomas

WITH frame_stats AS (
    SELECT
        p.name                                                          AS process_name,
        COUNT(*)                                                        AS total_frames,
        SUM(CASE WHEN afs.jank_type != 'None'   THEN 1 ELSE 0 END)    AS janky,
        SUM(CASE WHEN afs.dur >= 100e6          THEN 1 ELSE 0 END)    AS slow,
        SUM(CASE WHEN afs.dur >= 700e6          THEN 1 ELSE 0 END)    AS frozen,
        ROUND(MAX(afs.dur)  / 1e6, 1)                                  AS pior_frame_ms,
        ROUND(AVG(afs.dur)  / 1e6, 1)                                  AS media_frame_ms
    FROM actual_frame_timeline_slice afs
    JOIN process p ON afs.upid = p.upid
    WHERE p.name LIKE 'com.myapp%'
    GROUP BY p.name
),
top_cause AS (
    -- causa de jank mais frequente por processo
    SELECT
        p.name  AS process_name,
        afs.jank_type,
        COUNT(*) AS cnt,
        ROW_NUMBER() OVER (PARTITION BY p.name ORDER BY COUNT(*) DESC) AS rn
    FROM actual_frame_timeline_slice afs
    JOIN process p ON afs.upid = p.upid
    WHERE p.name LIKE 'com.myapp%'
      AND afs.jank_type != 'None'
    GROUP BY p.name, afs.jank_type
),
top_thread AS (
    -- thread mais responsável por frames lentos (maior overlap_dur agregado)
    SELECT
        p.name  AS process_name,
        t.name  AS thread_name,
        SUM(
            MIN(s.ts + s.dur, afs.ts + afs.dur) - MAX(s.ts, afs.ts)
        )       AS total_overlap,
        ROW_NUMBER() OVER (
            PARTITION BY p.name
            ORDER BY SUM(MIN(s.ts + s.dur, afs.ts + afs.dur) - MAX(s.ts, afs.ts)) DESC
        ) AS rn
    FROM actual_frame_timeline_slice afs
    JOIN process p    ON afs.upid   = p.upid
    JOIN thread t     ON t.upid     = p.upid
    JOIN thread_track tr ON tr.utid = t.utid
    JOIN slice s      ON s.track_id = tr.id
    WHERE p.name LIKE 'com.myapp%'
      AND afs.jank_type != 'None'
      AND s.ts  < (afs.ts + afs.dur)
      AND (s.ts + s.dur) > afs.ts
      AND t.name IN ('main', 'RenderThread')
    GROUP BY p.name, t.name
)
SELECT
    fs.process_name,
    CASE
        WHEN fs.frozen > 0                             THEN 'CRITICO'
        WHEN fs.slow   > 0                             THEN 'DEGRADADO'
        WHEN ROUND(100.0 * fs.janky / fs.total_frames) > 5 THEN 'ATENCAO'
        ELSE 'OK'
    END                                                         AS veredicto,
    fs.total_frames,
    fs.janky                                                    AS janky_frames,
    fs.slow                                                     AS slow_frames,
    fs.frozen                                                   AS frozen_frames,
    ROUND(100.0 * fs.janky / fs.total_frames, 1)               AS jank_rate_pct,
    fs.pior_frame_ms,
    fs.media_frame_ms,
    tc.jank_type                                                AS causa_principal,
    tt.thread_name                                              AS thread_mais_lenta
FROM frame_stats fs
LEFT JOIN top_cause  tc ON tc.process_name = fs.process_name AND tc.rn = 1
LEFT JOIN top_thread tt ON tt.process_name = fs.process_name AND tt.rn = 1
ORDER BY
    CASE veredicto
        WHEN 'CRITICO'   THEN 1
        WHEN 'DEGRADADO' THEN 2
        WHEN 'ATENCAO'   THEN 3
        ELSE 4
    END;