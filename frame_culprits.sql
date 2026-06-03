-- Frames lentos/congelados: motivo do jank + método real que causou o problema
--
-- Estratégia:
--   1. Leaf slices  → nível mais profundo da call stack (método real, sem inflar com pai)
--   2. Overlap      → slices que SOBREPÕEM o frame, não apenas os contidos nele
--   3. overlap_ms   → quanto tempo do frame esse método consumiu de fato
--   4. contexto     → slice pai, para saber de onde o método foi chamado
--
-- jank_type possíveis:
--   App Deadline Missed          → app não terminou a renderização a tempo
--   SurfaceFlinger CPU Deadline Missed → SF atrasou no lado CPU
--   SurfaceFlinger GPU Deadline Missed → GPU não terminou a tempo
--   Buffer Stuffing              → fila de buffers cheia (app adiantado demais)
--   Dropped Frame                → frame descartado
--   Unknown Jank                 → causa não identificada

WITH janky_frames AS (
    SELECT
        afs.id          AS frame_id,
        afs.ts          AS frame_ts,
        afs.dur         AS frame_dur,
        afs.jank_type,
        afs.present_type,
        afs.upid,
        p.name          AS process_name
    FROM actual_frame_timeline_slice afs
    JOIN process p ON afs.upid = p.upid
    WHERE p.name LIKE 'com.myapp%'
      AND afs.jank_type != 'None'
      AND afs.dur >= 16e6
),
leaf_slices AS (
    -- Apenas slices sem filhos: método real executado (não wrapper/pai)
    SELECT s.id, s.ts, s.dur, s.name, s.track_id, s.parent_id, s.depth
    FROM slice s
    WHERE NOT EXISTS (
        SELECT 1 FROM slice child WHERE child.parent_id = s.id
    )
      AND s.dur >= 1e6
),
culprits AS (
    SELECT
        f.frame_id,
        f.frame_ts,
        f.frame_dur,
        f.jank_type,
        f.present_type,
        f.process_name,
        t.name                      AS thread_name,
        p_slice.name                AS contexto,
        ls.name                     AS metodo_culpado,
        -- tempo efetivo que o slice ocupou dentro da janela do frame
        (MIN(ls.ts + ls.dur, f.frame_ts + f.frame_dur)
         - MAX(ls.ts, f.frame_ts))  AS overlap_dur,
        ROW_NUMBER() OVER (
            PARTITION BY f.frame_id
            ORDER BY
                (MIN(ls.ts + ls.dur, f.frame_ts + f.frame_dur)
                 - MAX(ls.ts, f.frame_ts)) DESC
        ) AS rank_no_frame
    FROM janky_frames f
    JOIN thread t        ON t.upid      = f.upid
    JOIN thread_track tr ON tr.utid     = t.utid
    JOIN leaf_slices ls  ON ls.track_id = tr.id
    LEFT JOIN slice p_slice ON p_slice.id = ls.parent_id
    -- sobreposição: slice começa antes do fim do frame E termina após o início
    WHERE ls.ts  < (f.frame_ts + f.frame_dur)
      AND (ls.ts + ls.dur) > f.frame_ts
      AND t.name IN ('main', 'RenderThread')
)
SELECT
    process_name,
    frame_id,
    ROUND(frame_dur  / 1e6, 2)          AS frame_ms,
    CASE
        WHEN frame_dur >= 700e6 THEN 'FROZEN'
        WHEN frame_dur >= 100e6 THEN 'SLOW'
        ELSE 'JANKY'
    END                                 AS severidade,
    jank_type                           AS motivo,
    present_type,
    thread_name,
    contexto,
    metodo_culpado,
    ROUND(overlap_dur / 1e6, 2)         AS overlap_ms,
    ROUND(100.0 * overlap_dur / frame_dur, 1) AS pct_do_frame
FROM culprits
WHERE rank_no_frame <= 5
ORDER BY frame_dur DESC, overlap_dur DESC;