-- Select related observations using the same bound survey parameter.
SELECT survey, count FROM observations WHERE survey = ? ORDER BY count
