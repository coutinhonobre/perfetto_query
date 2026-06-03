-- Resumo de jank por processo: total de frames, % janky e pior frame
SELECT
    p.name                                                          AS process_name,
    COUNT(*)                                                        AS total_frames,
    SUM(CASE WHEN afs.jank_type != 'None' THEN 1 ELSE 0 END)       AS janky_frames,
    ROUND(
        100.0 * SUM(CASE WHEN afs.jank_type != 'None' THEN 1 ELSE 0 END)
              / COUNT(*),
        2
    )                                                               AS jank_rate_pct,
    ROUND(MAX(afs.dur) / 1e6, 2)                                   AS worst_frame_ms,
    ROUND(AVG(afs.dur) / 1e6, 2)                                   AS avg_frame_ms
FROM actual_frame_timeline_slice afs
JOIN process p ON afs.upid = p.upid
WHERE p.name LIKE 'com.myapp%'
GROUP BY p.name
ORDER BY jank_rate_pct DESC;