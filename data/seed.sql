INSERT INTO participants (id, name, team, target) VALUES
    ('alice', 'Alice', 'Sharks', 300000),
    ('bob', 'Bob', 'Sharks', 300000),
    ('chloe', 'Chloe', 'Eagles', 300000),
    ('dave', 'Dave', 'Eagles', 300000),
    ('erin', 'Erin', 'Wolves', 300000),
    ('finn', 'Finn', 'Wolves', 300000)
ON CONFLICT (id) DO UPDATE 
    SET name = EXCLUDED.name, team = EXCLUDED.team, target = EXCLUDED.target;


INSERT INTO daily_targets (day_number, date, daily_target, cumulative_target)
SELECT
    d AS day_number,
    DATE '2026-01-01' + (d - 1) AS date,
    10000 AS daily_target,
    10000 * d AS cumulative_target
FROM generate_series(1, 30) AS d
ON CONFLICT (day_number) DO UPDATE
    SET date = EXCLUDED.date,
        daily_target = EXCLUDED.daily_target,
        cumulative_target = EXCLUDED.cumulative_target;

INSERT INTO challenge_state (id, today, day_number, daily_target, cumulative_target)
SELECT TRUE, date, day_number, daily_target, cumulative_target
FROM daily_targets
WHERE day_number = 1
ON CONFLICT (id) DO UPDATE
    SET today = EXCLUDED.today,
        day_number = EXCLUDED.day_number,
        daily_target = EXCLUDED.daily_target,
        cumulative_target = EXCLUDED.cumulative_target;