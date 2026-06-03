-- GC pauses: eventos de garbage collection e seu impacto na UI
SELECT
    s.name                          AS gc_event,
    s.ts,
    ROUND(s.dur / 1e6, 2)          AS duration_ms,
    t.name                          AS thread_name,
    p.name                          AS process_name
FROM slice s
JOIN thread_track tr ON s.track_id = tr.id
JOIN thread t  ON tr.utid = t.utid
JOIN process p ON t.upid  = p.upid
WHERE p.name LIKE 'com.myapp%'
  AND (
      s.name LIKE '%GC%'
      OR s.name LIKE '%garbage%'
      OR s.name LIKE 'Heap%'
      OR s.name LIKE 'CollectGarbage%'
      OR s.name LIKE 'Background%GC%'
      OR s.name LIKE 'Explicit%GC%'
  )
ORDER BY s.dur DESC;