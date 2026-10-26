-- ============================================================
-- Домашнее задание к лекции «Продвинутый SQL»
-- Школа Аналитиков · учебная база hh_school
-- Автор: Архангельский Тимофей Витальевич
-- ============================================================

SET search_path TO hh_school;


-- ============================================================
-- БЛОК А. Качество и подготовка данных
-- ============================================================

-- ЗАДАНИЕ 1
-- Можно ли корректно связать событие с откликом
-- Запрос:
SELECT call_id,
	   COUNT(*) OVER () AS null_cnt
FROM calls
WHERE response_id IS NULL;

SELECT message_id,
	   COUNT(*) OVER () AS null_cnt
FROM messages
WHERE response_id IS NULL;

-- Комментарий: 
-- Нельзя корректно связать событие с откликом, потому что есть 8 звонков без response_id. Это влияет на факт коммуникации

-- Согласуются ли между собой индентификаторы в связанных таблицах
-- Запрос:
WITH missed_data AS (
	-- Ищет строки, где идентификаторы события не совпадают с откликом или вакансией
	SELECT 'calls: vacancy_id' AS problem_column,
		   c.call_id AS id
	FROM calls c JOIN responses r USING(response_id)
	WHERE c.vacancy_id <> r.vacancy_id
	UNION ALL
	SELECT 'calls: applicant_id',
		   c.call_id
	FROM calls c JOIN responses r USING(response_id)
	WHERE c.applicant_id <> r.resume_id
	UNION ALL
	SELECT 'calls: employer_id',
		   c.call_id
	FROM calls c JOIN vacancies r USING(vacancy_id)
	WHERE c.employer_id <> r.employer_id
	UNION ALL
	SELECT 'messages: vacancy_id',
		   m.message_id AS id
	FROM messages m JOIN responses r USING(response_id)
	WHERE m.vacancy_id <> r.vacancy_id
	UNION ALL
	SELECT 'messages: applicant_id',
		   m.message_id
	FROM messages m JOIN responses r USING(response_id)
	WHERE m.applicant_id <> r.resume_id
	UNION ALL
	SELECT 'messages: employer_id',
		   m.message_id
	FROM messages m JOIN vacancies r USING(vacancy_id)
	WHERE m.employer_id <> r.employer_id
)

SELECT problem_column,
   	   COUNT(id) AS problem_cnt
FROM missed_data
GROUP BY problem_column;

-- Комментарий: 
-- 0 рассхождений идентификаторов в связанных таблицах, поэтому проблем нет

-- Может ли событие находиться в указанной точке времени относительно отклика
-- Запрос:
WITH event_time AS (
	-- Подсчет времени ответа относительно отклика
	SELECT 'calls' AS event,
		   c.call_at - r.created_at AS answer_time
	FROM calls c JOIN responses r USING(response_id)
	UNION ALL
	SELECT 'message',
		   m.sent_at - r.created_at
	FROM messages m JOIN responses r USING(response_id)
)

SELECT event,
	   CASE WHEN answer_time <= INTERVAL '0' THEN 'раньше или в момент отклика'
		    WHEN answer_time <= INTERVAL '1 day' THEN 'до 1 дня'
	   		WHEN answer_time <= INTERVAL '7 day' THEN '1-7 дней'
	   		WHEN answer_time <= INTERVAL '30 day' THEN '7-30 дней'
	   		ELSE 'больше 30 дней' END AS response_time,
	   COUNT(*) AS cnt
FROM event_time
GROUP BY 1, 2
ORDER BY 1, 2;

-- Комментарий: 
-- Событие может находится в любой точке после отклика: от 0,01 до 31,88 дня. Раньше отклика или в тот же момент событий 
-- нет (эта группа в результате не появилась), потому что отклик - начало истории, поэтому проблем нет.

-- Согласуются ли значения внутри одной строки между собой
-- Запрос:
SELECT COUNT(*) FILTER (WHERE status = 'successful' AND NOT 'connected' = ANY(call_tags)) AS successful_without_connected,
	   COUNT(*) FILTER (WHERE status <> 'successful' AND 'connected' = ANY(call_tags)) AS failed_but_connected,
	   COUNT(*) FILTER (WHERE (caller_role = 'employer' AND NOT 'outbound' = ANY(call_tags))
	   						OR (caller_role = 'applicant' AND NOT 'inbound' = ANY(call_tags))) AS role_change,
	   COUNT(*) FILTER (WHERE status <> 'successful' AND status <> 'unsuccessful') AS other_status_cnt
FROM calls;


SELECT COUNT(*) AS unread_but_replied
FROM messages m
WHERE message_meta ->> 'is_read' = 'false' 
	  AND EXISTS (SELECT 1 
	  			  FROM messages m_extra
	  			  WHERE m.response_id = m_extra.response_id AND m.sender_role <> m_extra.sender_role 
	  			  	AND m_extra.sent_at > m.sent_at);
	  
-- Комментарий:
-- В таблице calls есть одна строка со статусом error - это влияет на факт коммуникации, потому что звонок технически не состоялся
-- В таблице message есть 204 строк, где пришел ответ на непрочитанное письмо - влияет только на атрибут is_read

-- Есть ли пропуски в данных, которые понадобятся дальше
-- Запрос:

SELECT COUNT(*) FILTER (WHERE response_id IS NULL) AS no_response,
	   COUNT(*) FILTER (WHERE call_duration IS NULL AND status = 'successful') AS successful_no_duration,
	   COUNT(*) FILTER (WHERE call_duration IS NULL AND status <> 'successful') AS failed_no_duration
FROM calls;

SELECT COUNT(*) AS empty_message_text_cnt
FROM messages
WHERE message_text IS NULL;

-- Комментарий:
-- В таблице calls есть 8 строк без response_id - это влияет на факт коммуникации, и есть 70 строк с NULL значениями в call_duration, но
-- это связано с тем, что звонка не было - влияет только на атрибут
-- В таблице messages пропусков нет

-- Есть ли значения, заметно отличающиеся от основной массы наблюдений
-- Запрос:
WITH event_time AS (
	-- Подсчет времени ответа относительно отклика
	SELECT 'calls' AS event,
		   EXTRACT(EPOCH FROM c.call_at - r.created_at) / 86400 AS answer_time
	FROM calls c JOIN responses r USING(response_id)
	UNION ALL
	SELECT 'message',
		   EXTRACT(EPOCH FROM m.sent_at - r.created_at) / 86400
	FROM messages m JOIN responses r USING(response_id)
)

SELECT event,
	   COUNT(*) AS cnt,
	   ROUND(AVG(answer_time), 2) AS avg_days,
	   ROUND(PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY answer_time)::NUMERIC, 2) AS p01_days,
	   ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY answer_time)::NUMERIC, 2) AS p99_days,
	   ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY answer_time)::NUMERIC, 2) AS median,
	   ROUND(MIN(answer_time), 2) AS min_days,
	   ROUND(MAX(answer_time), 2) AS max_days
FROM event_time
GROUP BY event;

-- Комментарий:
-- Звонки и сообщения приходят через 0,01-31,88 дня после отклика, медиана около 4,5 дня, p99 около 29 дней, p01 около 2-3 часов. 
-- Максимум немного выше p99 и минимум немного ниже p01. Заметных выбросов нет, все значения допустимы и на факт коммуникации не влияют.

-- Отдельный анализ call_duration
-- Запрос:
WITH needed_call_duration AS (
	-- Отбор нужных данных из звонков
	SELECT call_duration
	FROM calls
	WHERE status = 'successful'
),
percentile AS (
    -- Подсчет перцентиля по нужным звонкам
	SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY call_duration) AS p99_duration
	FROM needed_call_duration
)

SELECT ROUND(AVG(call_duration), 2) AS avg_duration,
	   PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY call_duration) AS median_duration,
	   MAX(p99_duration) AS p99_duration,
	   COUNT(*) FILTER (WHERE call_duration > p99_duration) AS more_p99_cnt,
	   ROUND(AVG(call_duration)  FILTER (WHERE call_duration <= p99_duration), 2) AS avg_duration_p99
FROM needed_call_duration CROSS JOIN percentile;

-- Доп. запрос для поиска id проблемных записей:
SELECT call_id
FROM calls
WHERE status = 'error';

SELECT m.message_id
FROM messages m
WHERE m.message_meta ->> 'is_read' = 'false'
	  AND EXISTS (SELECT 1 
	  			  FROM messages m_extra
	  			  WHERE m.response_id = m_extra.response_id AND m.sender_role <> m_extra.sender_role 
	  			  	    AND m_extra.sent_at > m.sent_at);

-- Вывод:
-- Найденные проблемы:
--  1. calls: 8 звонков без response_id - влияет на факт коммуникации;
--  2. calls: 1 звонок со status = 'error' (call_id - 700163), то есть звонок технически не состоялся - влияет на факт коммуникации;
--  3. message: 204 сообщения с is_read = false, на которые был дан ответ позже, то есть возможная неточность флага - влияет только на атрибут.
--
-- Значения метрик call_duration успешных звонков: среднее 467,28 сек, медиана 438 сек, p99 = 890,4 сек. Выше p99 есть два звонка, среднее
-- без них 462,49 сек.
--
-- Решение по значениям выше p99: я считаю их допустимыми выбросами, а не ошибками. Среднее почти не меняется при отсеивании звонков с 
-- call_duration выше p99. При расчете типичной длительности звонка я бы оставил значения выше p99, потому что их исключение почти не 
-- влияет на общий анализ. Также при расчете типичной длительности можно использовать медиану и не думать о граничных значениях.


-- ============================================================
-- БЛОК Б. История коммуникаций
-- ============================================================

-- ЗАДАНИЕ 2
-- Запрос:
WITH responses_prep AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
		   created_at
	FROM responses
),
calls_prep AS (
    -- Подходящие звонки 
	SELECT response_id,
		   employer_id,
		   call_id AS event_id,
		   call_at AS event_at,
		   'call' AS event_type
	FROM calls
	WHERE response_id IS NOT NULL AND caller_role = 'employer' AND status <> 'error'
),
messages_prep AS (
	-- Подходящие сообщения
	SELECT response_id,
		   employer_id,
		   message_id AS event_id,
		   sent_at AS event_at,
		   'message' AS event_type
	FROM messages
	WHERE sender_role = 'employer'
),
all_events AS (
    -- Объединение
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type  
	FROM calls_prep
	UNION ALL
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type
	FROM messages_prep
),
events_7d AS (
	-- Коммуникации в первые 7 дней после отклика
	SELECT a.response_id,
		   a.employer_id,
		   a.event_id,
		   a.event_at,
		   a.event_type
	FROM all_events a JOIN responses_prep r USING(response_id)
	WHERE a.event_at >= r.created_at AND a.event_at < r.created_at + INTERVAL '7 days'
)

SELECT COUNT(*) AS total_cnt,
	   COUNT(DISTINCT response_id) AS responses_communication,
	   COUNT(*) FILTER (WHERE event_type = 'call') AS call_cnt,
	   COUNT(*) FILTER (WHERE event_type = 'message') AS message_cnt
FROM events_7d;

-- Комментарий:
-- Общее количество событий: 1095
-- Количество различных откликов с коммуникацией: 382
-- Количество звонков: 107
-- Количество сообщений: 988

-- Вывод:
-- В первые 7 дней работодатели совершили 1095 коммуникаций по 382 откликам, основной канал общения - сообщения (988, около 90%)

-- ЗАДАНИЕ 3
-- Запрос:

-- Единый слой коммуникации из прошлого задания
WITH responses_prep AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
		   created_at
	FROM responses
),
calls_prep AS (
    -- Подходящие звонки 
	SELECT response_id,
		   employer_id,
		   call_id AS event_id,
		   call_at AS event_at,
		   'call' AS event_type
	FROM calls
	WHERE response_id IS NOT NULL AND caller_role = 'employer' AND status <> 'error'
),
messages_prep AS (
	-- Подходящие сообщения
	SELECT response_id,
		   employer_id,
		   message_id AS event_id,
		   sent_at AS event_at,
		   'message' AS event_type
	FROM messages
	WHERE sender_role = 'employer'
),
all_events AS (
    -- Объединение
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type  
	FROM calls_prep
	UNION ALL
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type
	FROM messages_prep
),
events_7d AS (
	-- Коммуникации в первые 7 дней после отклика
	SELECT a.response_id,
		   a.employer_id,
		   a.event_id,
		   a.event_at,
		   a.event_type
	FROM all_events a JOIN responses_prep r USING(response_id)
	WHERE a.event_at >= r.created_at AND a.event_at < r.created_at + INTERVAL '7 days'
)

,
event_layer AS (
       -- Слой уровня событий
	   SELECT response_id,
	   employer_id,
	   event_id,
	   event_at,
	   event_type,
	   ROW_NUMBER() OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS event_number,
	   LAG(event_at) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS previous_time,
	   LEAD(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS next_type,
	   COUNT(*) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS from_start_to_now_cnt,
	   FIRST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS first_event_for_response,
	   LAST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id
	   								ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_event_for_response
FROM events_7d
),
responses_status AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
	       status,
	       vacancy_id
 	FROM responses
),
vacancies_prep AS (
	-- Отбор нужных данных из вакансий
	SELECT vacancy_id, 
		   employer_id,
		   professional_role
    FROM vacancies
),
response_events AS (
    -- Подсчет значений для витрины
	SELECT response_id,
		   COUNT(*) AS communication_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'call') AS calls_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'message') AS messages_cnt,
		   MIN(event_at) AS first_communication_at,
		   MAX(first_event_for_response) AS first_event_type,
		   MAX(event_type) FILTER (WHERE event_number = 2)  AS second_event_type,
		   MAX(last_event_for_response) AS last_event_type,
		   MAX(EXTRACT(EPOCH FROM event_at - previous_time) / 3600) AS max_gap_hours
	FROM event_layer
	GROUP BY response_id
),
response_summary AS (
    -- Витрина уровня отклика
	SELECT rp.response_id,
		   vp.employer_id,
		   vp.professional_role,
		   rs.status,
		   COALESCE (re.communication_cnt, 0) AS communication_cnt,
		   COALESCE (re.calls_cnt, 0) AS calls_cnt,
		   COALESCE (re.messages_cnt, 0) AS messages_cnt,
		   re.first_communication_at,
		   re.first_event_type,
		   re.second_event_type,
		   re.last_event_type,
		   ROUND(EXTRACT(EPOCH FROM re.first_communication_at - rp.created_at) / 3600, 2) AS hours_to_first_communication,
		   ROUND(re.max_gap_hours, 2) AS max_gap_hours
	FROM responses_prep rp JOIN responses_status rs USING(response_id)
	LEFT JOIN vacancies_prep vp USING(vacancy_id)
	LEFT JOIN response_events re USING(response_id)
)

SELECT COUNT(*) AS total_cnt,
	   COUNT(*) FILTER (WHERE communication_cnt > 0) AS with_communication_cnt,
	   COUNT(*) FILTER (WHERE communication_cnt = 0) AS without_communication_cnt,
	   COUNT(*) FILTER (WHERE first_event_type = 'message') AS first_message_cnt,
	   COUNT(*) FILTER (WHERE first_event_type = 'call') AS first_call_cnt
FROM response_summary;

-- Комментарий:
-- Количество строк: 628
-- Количество откликов с коммуникацией: 382
-- Количество откликов без коммуникации: 246
-- Количество откликов, где первой коммуникацией было сообщение: 314
-- Количество откликов, где первой коммуникацией был звонок: 68

-- Вывод:
-- 246 откликов из 628 остались без коммуникации работадателя в первые 7 дней. Когда есть связь, первым чаще 
-- приходит сообщение (314 против 68 со звонком).

-- ============================================================
-- БЛОК В. Сравнение работодадетелей
-- ============================================================

-- ЗАДАНИЕ 4
-- Запрос:

-- Витрина уровня отклика из прошлого задания
WITH responses_prep AS (
	-- Отклики
	SELECT response_id,
		   created_at
	FROM responses
),
calls_prep AS (
    -- Подходящие звонки 
	SELECT response_id,
		   employer_id,
		   call_id AS event_id,
		   call_at AS event_at,
		   'call' AS event_type
	FROM calls
	WHERE response_id IS NOT NULL AND caller_role = 'employer' AND status <> 'error'
),
messages_prep AS (
	-- Подходящие сообщения
	SELECT response_id,
		   employer_id,
		   message_id AS event_id,
		   sent_at AS event_at,
		   'message' AS event_type
	FROM messages
	WHERE sender_role = 'employer'
),
all_events AS (
    -- Объединение
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type  
	FROM calls_prep
	UNION ALL
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type
	FROM messages_prep
),
events_7d AS (
	-- Коммуникации в первые 7 дней после отклика
	SELECT a.response_id,
		   a.employer_id,
		   a.event_id,
		   a.event_at,
		   a.event_type
	FROM all_events a JOIN responses_prep r USING(response_id)
	WHERE a.event_at >= r.created_at AND a.event_at < r.created_at + INTERVAL '7 days'
),
event_layer AS (
       -- Слой уровня событий
	   SELECT response_id,
	   employer_id,
	   event_id,
	   event_at,
	   event_type,
	   ROW_NUMBER() OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS event_number,
	   LAG(event_at) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS previous_time,
	   LEAD(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS next_type,
	   COUNT(*) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS from_start_to_now_cnt,
	   FIRST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS first_event_for_response,
	   LAST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id
	   								ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_event_for_response
		FROM events_7d
),
responses_status AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
	       status,
	       vacancy_id
 	FROM responses
),
vacancies_prep AS (
	-- Отбор нужных данных из вакансий
	SELECT vacancy_id, 
		   employer_id,
		   professional_role
    FROM vacancies
),
response_events AS (
    -- Подсчет значений для витрины
	SELECT response_id,
		   COUNT(*) AS communication_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'call') AS calls_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'message') AS messages_cnt,
		   MIN(event_at) AS first_communication_at,
		   MAX(first_event_for_response) AS first_event_type,
		   MAX(event_type) FILTER (WHERE event_number = 2)  AS second_event_type,
		   MAX(last_event_for_response) AS last_event_type,
		   MAX(EXTRACT(EPOCH FROM event_at - previous_time) / 3600) AS max_gap_hours
	FROM event_layer
	GROUP BY response_id
),
response_summary AS (
    -- Витрина уровня отклика
	SELECT rp.response_id,
		   vp.employer_id,
		   vp.professional_role,
		   rs.status,
		   COALESCE (re.communication_cnt, 0) AS communication_cnt,
		   COALESCE (re.calls_cnt, 0) AS calls_cnt,
		   COALESCE (re.messages_cnt, 0) AS messages_cnt,
		   re.first_communication_at,
		   re.first_event_type,
		   re.second_event_type,
		   re.last_event_type,
		   ROUND(EXTRACT(EPOCH FROM re.first_communication_at - rp.created_at) / 3600, 2) AS hours_to_first_communication,
		   ROUND(re.max_gap_hours, 2) AS max_gap_hours
	FROM responses_prep rp JOIN responses_status rs USING(response_id)
	LEFT JOIN vacancies_prep vp USING(vacancy_id)
	LEFT JOIN response_events re USING(response_id)
)

,
percentile_summary AS (
	-- Подсчет перцентиля
	SELECT professional_role,
		   employer_id,
		   PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours_to_first_communication) AS median_first_communication,
		   PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY hours_to_first_communication) AS p90_first_communication
	FROM response_summary
	WHERE communication_cnt > 0
	GROUP BY professional_role, employer_id
),
count_summary AS (
	-- Подсчет количества нужных строк
	SELECT professional_role,
	       employer_id,
	       COUNT(*) AS total_cnt,
	       COUNT(*) FILTER (WHERE hours_to_first_communication / 24 < 7) AS communication_less_seven_days,
	       COUNT(*) FILTER (WHERE status = 'invited') AS invited_cnt
	FROM response_summary 
	GROUP BY professional_role, employer_id
	HAVING COUNT(response_id) >= 8
),
ranked AS (
	SELECT cs.professional_role,
		   cs.employer_id, 
		   cs.total_cnt,
		   cs.communication_less_seven_days,
		   ps.median_first_communication,
		   ps.p90_first_communication,
		   cs.invited_cnt,
		   DENSE_RANK() OVER (PARTITION BY cs.professional_role
		   					  ORDER BY cs.communication_less_seven_days / cs.total_cnt::DECIMAL DESC, median_first_communication) AS place
	FROM count_summary cs LEFT JOIN percentile_summary ps ON ps.professional_role = cs.professional_role 
														     AND ps.employer_id = cs.employer_id
)

SELECT professional_role,
	   place,
	   employer_id,
	   total_cnt,
	   communication_less_seven_days,
	   ROUND(100.0 * communication_less_seven_days / total_cnt, 2) AS share_communication_pct,
	   ROUND(median_first_communication::DECIMAL, 2) AS median_first_communication,
	   ROUND(p90_first_communication::DECIMAL, 2) AS p90_first_communication,
	   ROUND(100.0 * invited_cnt / total_cnt, 2) AS conversion_pct
FROM ranked
WHERE place <= 2
ORDER BY professional_role, place, employer_id;


-- Комментарий:
-- Аналитик данных: 1 - 109, 2 - 103
-- Дата-инженер: 1 - 106, 2 - 101
-- Продуктовый аналитик: 1 - 103, 2 - 102
-- Разработчик: 1 - 112, 2 - 104
-- Тестировщик: 1 - 107, 2 - 108

-- Вывод:
-- Лидеры направлений обрабатывают 70-89% откликов за 7 дней, но скорость первого контакта у них сильно различается:
-- медиана от 9,67 ч (дата-инженер - 106) до 56,97 ч (аналитик данных - 109)

-- ЗАДАНИЕ 5
-- Запрос:
WITH prep_messages AS (
    -- Отбор нужны данных
	SELECT m.message_id,
		   m.employer_id,
		   r.response_id,
		   m.sender_role,
		   m.sent_at,
		   LAG(m.sender_role) OVER (PARTITION BY r.response_id ORDER BY m.sent_at, m.message_id) AS previous_message_sender,
		   LAG(m.sent_at) OVER (PARTITION BY r.response_id ORDER BY m.sent_at, m.message_id) AS previous_message_time
	FROM messages m JOIN responses r USING(response_id)
	WHERE m.sent_at - r.created_at < INTERVAL '7 day' AND sent_at >= created_at
),
apllicant_then_employer AS (
	-- Отобор сообщений, где первый пишет кандидат, а потом работодатель
	SELECT message_id, 
		   employer_id,
		   response_id,
		   sender_role,
		   previous_message_sender,
		   EXTRACT(EPOCH FROM sent_at - previous_message_time) / 3600 AS ans_gap
	FROM prep_messages
	WHERE previous_message_sender = 'applicant' AND sender_role = 'employer'
)

SELECT employer_id,
	   COUNT(*) AS answer_cnt,
	   ROUND(AVG(ans_gap), 2) AS avg_ans_gap,
	   ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ans_gap)::DECIMAL, 2) AS median_ans_gap,
	   ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY ans_gap)::DECIMAL, 2) AS p90_ans_gap,
	   SUM(COUNT(*)) OVER() AS total_answer_cnt
FROM apllicant_then_employer
GROUP BY employer_id
ORDER BY median_ans_gap; 

-- Комментарий:
-- Общее количество найденных ответов: 749
-- employer_id работодателя с минимальной медианой: 107
-- Значение его медианы: 3,93

-- Вывод:
-- На сообщения кандидатов работодатели отвечают быстро (медиана ответа 3,93-4,93 ч).

-- ============================================================
-- БЛОК Г. Сложные типы данных 
-- ============================================================

-- ЗАДАНИЕ 6
-- Пункт 6.1
-- Запрос:
WITH prep_calls AS (
	SELECT c.call_id,
		   c.call_tags
	FROM calls c JOIN responses r USING(response_id)
	WHERE c.caller_role = 'employer' 
		  AND c.call_at >= r.created_at
		  AND c.call_at < r.created_at + INTERVAL '7 days'
		  AND ((c.status = 'successful' AND 'connected' = ANY(call_tags)) OR (c.status = 'unsuccessful' AND 'no_answer' = ANY(call_tags)))
)

SELECT COUNT(*) AS valid_calls,
	   COUNT(*) FILTER (WHERE 'screening' = ANY(call_tags)) AS screening_cnt,
	   COUNT(*) FILTER (WHERE 'interview' = ANY(call_tags)) AS interview_cnt,
	   COUNT(*) FILTER (WHERE 'follow_up' = ANY(call_tags)) AS follow_up_cnt,
	   COUNT(*) FILTER (WHERE 'details' = ANY(call_tags)) AS details_cnt,
	   COUNT(*) FILTER (WHERE call_tags && ARRAY['screening', 'interview', 'follow_up', 'details']) AS valid_with_tag_cnt,
	   ROUND(AVG(CARDINALITY(call_tags)), 2) AS avg_tags_per_valid_call
FROM prep_calls;

-- Комментарий:
-- Количество валидных звонков: 107
-- Звонки по тегу 'screening': 25
-- Звонки по тегу 'interview': 30
-- Звонки по тегу 'follow_up': 29
-- Звонки по тегу 'details': 23
-- Количество звонков хотя бы с одним бизнес-тегом: 107
-- Среднее количество тегов на один валидный звонок: 4

-- Вывод: 
-- Противоречия между тегами и status нет. У каждого звонка ровно один бизнес-тег, чаще всего 'interview' и 'follow_up'.

-- Пункт 6.2
-- Запрос:
WITH prep_message AS (
	SELECT m.message_id,
		   COALESCE(m.message_meta ->> 'channel', 'not known') AS channel,
		   (m.message_meta ->> 'is_read')::BOOLEAN AS is_read,
		   COALESCE(JSONB_ARRAY_LENGTH(m.message_meta -> 'attachments'), 0) AS attachments_cnt
	FROM messages m JOIN responses r USING(response_id)
	WHERE m.sender_role = 'employer' 
		  AND m.sent_at >= r.created_at
		  AND m.sent_at < r.created_at + INTERVAL '7 days' 
)

SELECT channel,
	   COUNT(*) AS message_cnt,
	   COUNT(is_read) AS read_flag_cnt,
	   COUNT(*) FILTER (WHERE is_read = False) AS unread_cnt,
	   ROUND(100 * COUNT(*) FILTER (WHERE is_read = False) / NULLIF(COUNT(is_read), 0)::DECIMAL, 2) AS share_not_readed_message,
	   COUNT(*) FILTER (WHERE attachments_cnt > 0) AS not_empty_attachments,
	   ROUND(100 * COUNT(*) FILTER (WHERE attachments_cnt > 0) / COUNT(*)::DECIMAL, 2) AS share_not_empty_attachments
FROM prep_message
GROUP BY channel
ORDER BY channel;

-- Комментарий:
-- web:
--     Количество сообщений: 628
--     Количество сообщений, где признак прочтения присутствует: 628
--     Количество непрочитанных сообщений: 52
--     Доля непрочитанных среди сообщений, где признак прочтения известен: 8,28
--     Количество сообщений хотя бы с одним вложением: 25
--     Доля сообщений с вложением: 3,98
--
-- mobile_app:
--     Количество сообщений: 360
--     Количество сообщений, где признак прочтения присутствует: 360
--     Количество непрочитанных сообщений: 36
--     Доля непрочитанных среди сообщений, где признак прочтения известен: 10
--     Количество сообщений хотя бы с одним вложением: 14
--     Доля сообщений с вложением: 3,89

-- Вывод:
-- Сообщений без канала нет. Основной канал - web (628 из 988). Непрочитанных сообщений в web 8,28% и в mobile_app 10%.
-- Вложения редки - около 4% в обоих каналах

-- ============================================================
-- БЛОК Д. Самостоятельное исследование
-- ============================================================

-- ЗАДАНИЕ 7
-- Гипотеза 1: по откликам, которые закончились приглашением, работодатели чаще выходят на связь в первые 24 часа и в целом быстрее делают первый контакт.
-- Показатели: доля откликов с первым контактом в течение 24 часов, медиана времени до первой коммуникации, 
-- доля первых контактов в течение 24 часов среди откликов с коммуникацией.
--
-- Гипотеза 2а (работодатель): по откликам с приглашением работодатель общается интенсивнее:
-- больше контактов и чаще звонит.
-- Показатели: среднее число коммуникаций, доля откликов со звонком.
--
-- Гипотеза 2б (кандидат): по откликам с приглашением кандидат активнее в первые 24 часа.
-- Показатели: доля откликов с сообщениями кандидата, среднее число сообщений кандидата.
--
-- Дополнительный разрез: проверяю, объясняется ли разница в приглашениях направлением, а не коммуникацией.
-- Запрос:

-- Витрина уровня отклика из прошлого задания
WITH responses_prep AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
		   created_at
	FROM responses
),
calls_prep AS (
    -- Подходящие звонки 
	SELECT response_id,
		   employer_id,
		   call_id AS event_id,
		   call_at AS event_at,
		   'call' AS event_type
	FROM calls
	WHERE response_id IS NOT NULL AND caller_role = 'employer' AND status <> 'error'
),
messages_prep AS (
	-- Подходящие сообщения
	SELECT response_id,
		   employer_id,
		   message_id AS event_id,
		   sent_at AS event_at,
		   'message' AS event_type
	FROM messages
	WHERE sender_role = 'employer'
),
all_events AS (
    -- Объединение
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type  
	FROM calls_prep
	UNION ALL
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type
	FROM messages_prep
),
events_7d AS (
	-- Коммуникации в первые 7 дней после отклика
	SELECT a.response_id,
		   a.employer_id,
		   a.event_id,
		   a.event_at,
		   a.event_type
	FROM all_events a JOIN responses_prep r USING(response_id)
	WHERE a.event_at >= r.created_at AND a.event_at < r.created_at + INTERVAL '7 days'
),
event_layer AS (
       -- Слой уровня событий
	   SELECT response_id,
	   employer_id,
	   event_id,
	   event_at,
	   event_type,
	   ROW_NUMBER() OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS event_number,
	   LAG(event_at) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS previous_time,
	   LEAD(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS next_type,
	   COUNT(*) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS from_start_to_now_cnt,
	   FIRST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS first_event_for_response,
	   LAST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id
	   								ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_event_for_response
FROM events_7d
),
responses_status AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
	       status,
	       vacancy_id
 	FROM responses
),
vacancies_prep AS (
	-- Отбор нужных данных из вакансий
	SELECT vacancy_id, 
		   employer_id,
		   professional_role
    FROM vacancies
),
response_events AS (
    -- Подсчет значений для витрины
	SELECT response_id,
		   COUNT(*) AS communication_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'call') AS calls_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'message') AS messages_cnt,
		   MIN(event_at) AS first_communication_at,
		   MAX(first_event_for_response) AS first_event_type,
		   MAX(event_type) FILTER (WHERE event_number = 2)  AS second_event_type,
		   MAX(last_event_for_response) AS last_event_type,
		   MAX(EXTRACT(EPOCH FROM event_at - previous_time) / 3600) AS max_gap_hours
	FROM event_layer
	GROUP BY response_id
),
response_summary AS (
    -- Витрина уровня отклика
	SELECT rp.response_id,
		   vp.employer_id,
		   vp.professional_role,
		   rs.status,
		   COALESCE (re.communication_cnt, 0) AS communication_cnt,
		   COALESCE (re.calls_cnt, 0) AS calls_cnt,
		   COALESCE (re.messages_cnt, 0) AS messages_cnt,
		   re.first_communication_at,
		   re.first_event_type,
		   re.second_event_type,
		   re.last_event_type,
		   ROUND(EXTRACT(EPOCH FROM re.first_communication_at - rp.created_at) / 3600, 2) AS hours_to_first_communication,
		   ROUND(re.max_gap_hours, 2) AS max_gap_hours
	FROM responses_prep rp JOIN responses_status rs USING(response_id)
	LEFT JOIN vacancies_prep vp USING(vacancy_id)
	LEFT JOIN response_events re USING(response_id)
)

,
applicant_messages AS (
	-- Сообщения кандидата в первые 24 часа после отклика
	SELECT m.response_id,
		   COUNT(*) AS applicant_msgs
	FROM messages m JOIN responses r USING(response_id)
	WHERE m.sender_role = 'applicant'
		  AND m.sent_at >= r.created_at
		  AND m.sent_at < r.created_at + INTERVAL '1 day'
	GROUP BY m.response_id
)

SELECT CASE WHEN rs.status = 'invited' THEN 'invited' ELSE 'other' END AS grp,
	   COUNT(*) AS responses_cnt,
	   COUNT(*) FILTER (WHERE rs.communication_cnt > 0) AS with_communication_cnt,
	   -- Гипотеза 1
	   COUNT(*) FILTER (WHERE rs.hours_to_first_communication < 24) AS first_within_24h_cnt,
	   ROUND(100.0 * COUNT(*) FILTER (WHERE rs.hours_to_first_communication < 24) / COUNT(*), 2) AS pct_first_within_24h_all,
	   ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rs.hours_to_first_communication)::DECIMAL, 2) AS median_hours_first,
	   ROUND(100.0 * COUNT(*) FILTER (WHERE rs.hours_to_first_communication < 24)
	         / NULLIF(COUNT(*) FILTER (WHERE rs.communication_cnt > 0), 0), 2) AS pct_first_within_24h_with_comm,
	   -- Гипотеза 2а
	   ROUND(AVG(rs.communication_cnt) FILTER (WHERE rs.communication_cnt > 0), 2) AS avg_communications,
	   ROUND(100.0 * COUNT(*) FILTER (WHERE rs.calls_cnt > 0)
	         / NULLIF(COUNT(*) FILTER (WHERE rs.communication_cnt > 0), 0), 2) AS pct_with_call,
	   -- Гипотеза 2б
	   ROUND(100.0 * COUNT(*) FILTER (WHERE rs.communication_cnt > 0 AND COALESCE(am.applicant_msgs, 0) > 0)
	         / NULLIF(COUNT(*) FILTER (WHERE rs.communication_cnt > 0), 0), 2) AS pct_applicant_wrote,
	   ROUND(AVG(COALESCE(am.applicant_msgs, 0)) FILTER (WHERE rs.communication_cnt > 0), 2) AS avg_applicant_msgs
FROM response_summary rs LEFT JOIN applicant_messages am USING(response_id)
GROUP BY grp
ORDER BY grp DESC;


-- Витрина уровня отклика из прошлого задания
WITH responses_prep AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
		   created_at
	FROM responses
),
calls_prep AS (
    -- Подходящие звонки 
	SELECT response_id,
		   employer_id,
		   call_id AS event_id,
		   call_at AS event_at,
		   'call' AS event_type
	FROM calls
	WHERE response_id IS NOT NULL AND caller_role = 'employer' AND status <> 'error'
),
messages_prep AS (
	-- Подходящие сообщения
	SELECT response_id,
		   employer_id,
		   message_id AS event_id,
		   sent_at AS event_at,
		   'message' AS event_type
	FROM messages
	WHERE sender_role = 'employer'
),
all_events AS (
    -- Объединение
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type  
	FROM calls_prep
	UNION ALL
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type
	FROM messages_prep
),
events_7d AS (
	-- Коммуникации в первые 7 дней после отклика
	SELECT a.response_id,
		   a.employer_id,
		   a.event_id,
		   a.event_at,
		   a.event_type
	FROM all_events a JOIN responses_prep r USING(response_id)
	WHERE a.event_at >= r.created_at AND a.event_at < r.created_at + INTERVAL '7 days'
),
event_layer AS (
       -- Слой уровня событий
	   SELECT response_id,
	   employer_id,
	   event_id,
	   event_at,
	   event_type,
	   ROW_NUMBER() OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS event_number,
	   LAG(event_at) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS previous_time,
	   LEAD(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS next_type,
	   COUNT(*) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS from_start_to_now_cnt,
	   FIRST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS first_event_for_response,
	   LAST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id
	   								ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_event_for_response
FROM events_7d
),
responses_status AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
	       status,
	       vacancy_id
 	FROM responses
),
vacancies_prep AS (
	-- Отбор нужных данных из вакансий
	SELECT vacancy_id, 
		   employer_id,
		   professional_role
    FROM vacancies
),
response_events AS (
    -- Подсчет значений для витрины
	SELECT response_id,
		   COUNT(*) AS communication_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'call') AS calls_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'message') AS messages_cnt,
		   MIN(event_at) AS first_communication_at,
		   MAX(first_event_for_response) AS first_event_type,
		   MAX(event_type) FILTER (WHERE event_number = 2)  AS second_event_type,
		   MAX(last_event_for_response) AS last_event_type,
		   MAX(EXTRACT(EPOCH FROM event_at - previous_time) / 3600) AS max_gap_hours
	FROM event_layer
	GROUP BY response_id
),
response_summary AS (
    -- Витрина уровня отклика
	SELECT rp.response_id,
		   vp.employer_id,
		   vp.professional_role,
		   rs.status,
		   COALESCE (re.communication_cnt, 0) AS communication_cnt,
		   COALESCE (re.calls_cnt, 0) AS calls_cnt,
		   COALESCE (re.messages_cnt, 0) AS messages_cnt,
		   re.first_communication_at,
		   re.first_event_type,
		   re.second_event_type,
		   re.last_event_type,
		   ROUND(EXTRACT(EPOCH FROM re.first_communication_at - rp.created_at) / 3600, 2) AS hours_to_first_communication,
		   ROUND(re.max_gap_hours, 2) AS max_gap_hours
	FROM responses_prep rp JOIN responses_status rs USING(response_id)
	LEFT JOIN vacancies_prep vp USING(vacancy_id)
	LEFT JOIN response_events re USING(response_id)
)

-- Разрез по направлению
SELECT professional_role,
	   COUNT(*) AS responses_cnt,
	   COUNT(*) FILTER (WHERE status = 'invited') AS invited_cnt,
	   ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'invited') / COUNT(*), 2) AS conversion_pct,
	   ROUND(100.0 * COUNT(*) FILTER (WHERE communication_cnt > 0) / COUNT(*), 2) AS pct_with_communication,
	   ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours_to_first_communication)::DECIMAL, 2) AS median_hours_first
FROM response_summary
GROUP BY professional_role
ORDER BY conversion_pct DESC;


-- Витрина уровня отклика из прошлого задания
WITH responses_prep AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
		   created_at
	FROM responses
),
calls_prep AS (
    -- Подходящие звонки 
	SELECT response_id,
		   employer_id,
		   call_id AS event_id,
		   call_at AS event_at,
		   'call' AS event_type
	FROM calls
	WHERE response_id IS NOT NULL AND caller_role = 'employer' AND status <> 'error'
),
messages_prep AS (
	-- Подходящие сообщения
	SELECT response_id,
		   employer_id,
		   message_id AS event_id,
		   sent_at AS event_at,
		   'message' AS event_type
	FROM messages
	WHERE sender_role = 'employer'
),
all_events AS (
    -- Объединение
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type  
	FROM calls_prep
	UNION ALL
	SELECT response_id,
		   employer_id,
		   event_id,
		   event_at,
		   event_type
	FROM messages_prep
),
events_7d AS (
	-- Коммуникации в первые 7 дней после отклика
	SELECT a.response_id,
		   a.employer_id,
		   a.event_id,
		   a.event_at,
		   a.event_type
	FROM all_events a JOIN responses_prep r USING(response_id)
	WHERE a.event_at >= r.created_at AND a.event_at < r.created_at + INTERVAL '7 days'
),
event_layer AS (
       -- Слой уровня событий
	   SELECT response_id,
	   employer_id,
	   event_id,
	   event_at,
	   event_type,
	   ROW_NUMBER() OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS event_number,
	   LAG(event_at) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS previous_time,
	   LEAD(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS next_type,
	   COUNT(*) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS from_start_to_now_cnt,
	   FIRST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id) AS first_event_for_response,
	   LAST_VALUE(event_type) OVER (PARTITION BY response_id ORDER BY event_at, event_type, event_id
	   								ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_event_for_response
FROM events_7d
),
responses_status AS (
	-- Отбор нужных данных из откликов
	SELECT response_id,
	       status,
	       vacancy_id
 	FROM responses
),
vacancies_prep AS (
	-- Отбор нужных данных из вакансий
	SELECT vacancy_id, 
		   employer_id,
		   professional_role
    FROM vacancies
),
response_events AS (
    -- Подсчет значений для витрины
	SELECT response_id,
		   COUNT(*) AS communication_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'call') AS calls_cnt,
		   COUNT(*) FILTER (WHERE event_type = 'message') AS messages_cnt,
		   MIN(event_at) AS first_communication_at,
		   MAX(first_event_for_response) AS first_event_type,
		   MAX(event_type) FILTER (WHERE event_number = 2)  AS second_event_type,
		   MAX(last_event_for_response) AS last_event_type,
		   MAX(EXTRACT(EPOCH FROM event_at - previous_time) / 3600) AS max_gap_hours
	FROM event_layer
	GROUP BY response_id
),
response_summary AS (
    -- Витрина уровня отклика
	SELECT rp.response_id,
		   vp.employer_id,
		   vp.professional_role,
		   rs.status,
		   COALESCE (re.communication_cnt, 0) AS communication_cnt,
		   COALESCE (re.calls_cnt, 0) AS calls_cnt,
		   COALESCE (re.messages_cnt, 0) AS messages_cnt,
		   re.first_communication_at,
		   re.first_event_type,
		   re.second_event_type,
		   re.last_event_type,
		   ROUND(EXTRACT(EPOCH FROM re.first_communication_at - rp.created_at) / 3600, 2) AS hours_to_first_communication,
		   ROUND(re.max_gap_hours, 2) AS max_gap_hours
	FROM responses_prep rp JOIN responses_status rs USING(response_id)
	LEFT JOIN vacancies_prep vp USING(vacancy_id)
	LEFT JOIN response_events re USING(response_id)
)

-- Сравнение приглашённых и остальных внутри направления
SELECT professional_role,
	   CASE WHEN status = 'invited' THEN 'invited' ELSE 'other' END AS grp,
	   COUNT(*) AS responses_cnt,
	   COUNT(*) FILTER (WHERE communication_cnt > 0) AS with_communication_cnt,
	   ROUND(100.0 * COUNT(*) FILTER (WHERE communication_cnt > 0) / COUNT(*), 2) AS pct_with_communication,
	   ROUND(100.0 * COUNT(*) FILTER (WHERE hours_to_first_communication < 24) / COUNT(*), 2) AS pct_first_within_24h_all,
	   ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours_to_first_communication)::DECIMAL, 2) AS median_hours_first,
	   ROUND(AVG(communication_cnt) FILTER (WHERE communication_cnt > 0), 2) AS avg_communications
FROM response_summary
GROUP BY professional_role, grp
ORDER BY professional_role, grp;

-- Вывод:
-- Группы: 
--     Отклики с приглашением: 92, из них с коммуникацией 54,
--     Остальные: 536, из них с коммуникацией 328.
--
-- Гипотеза 1: не подтверждается. Первый контакт в течение 24 часов был у 19,57% откликов с приглашением
-- (18 из 92) и у 19,40% остальных (104 из 536). Медиана времени до первой коммуникации 51,09 ч против 54,67 ч,
-- а среди откликов с коммуникацией первый контакт в течение суток был у 33,33% против 31,71%.
-- Различия небольшие, значимой разницы нет.
--
-- Гипотеза 2а: не подтверждается. По откликам с коммуникацией среднее число коммуникаций
-- 2,78 против 2,88 (у приглашённых даже меньше), доля откликов со звонком 27,78% против 26,52%.
-- Работодатель не общается интенсивнее с теми, кого потом приглашает.
--
-- Гипотеза 2б: не подтверждается. Кандидат писал в первые 24 часа у 24,07% откликов с приглашением
-- против 25,00% остальных, в среднем 0,48 против 0,50 сообщения на отклик. Активность кандидата
-- в начале переписки не связана с итоговым приглашением.
--
-- Разрез по направлению: конверсия в приглашение у тестировщиков 35,90% (14 из 39), у остальных направлений 11,65-17,27%.
-- Внутри направлений сравнить приглашённых и остальных по коммуникации нельзя, потому что данных недостаточно. Приглашённых
-- с коммуникацией в направлениях от 1 (Дата-инженер) до 22 (Аналитик данных), а различия зависят от направления.
-- Например, медиана до первой коммуникации у приглашённых разработчиков 25,83 ч против 54,73 ч у остальных,
-- а у продуктовых аналитиков 86,34 ч против 57,00 ч.


-- ЗАДАНИЕ 8
-- Итог:
-- 1. После отклика работодатели выходят на связь выборочно: из 628 откликов в первые 7 дней
--    коммуникация (1095 событий: 988 сообщений и 107 звонков) была по 382 (60,8%) откликам, а по 246 (39,2%) не было ни звонка, ни сообщения.
-- 2. Когда связь есть, чаще всего она начинается с сообщения (314 откликов против 68 со звонком),
--    но не сразу: медиана времени до первой коммуникации около 51-55 часов.
-- 3. Дальше диалог идёт быстрее: измерено 749 ответов работодателей на сообщения кандидатов,
--    у самого быстрого работодателя (107) медиана ответа 3,93 часа.
-- 4. Работодатели заметно различаются: лидеры направлений обрабатывают 70-89% откликов за 7 дней, а медиана
--    до первой коммуникации у них колеблется от 9,67 часа (работодатель 106) до 56,97 часа (работодатель 109).
-- 5. Приглашением закончились 92 отклика из 628 (14,65%), а сильнее всего конверсия различается по направлениям:
--    35,90% у тестировщиков (14 из 39) против 11,65-17,27% у остальных.
-- 6. Особенности коммуникации с приглашением не связаны: у откликов с приглашением и без него почти одинаковы
--    доля откликов с первым контактом в течение суток (19,57% и 19,40%), медиана до первой коммуникации
--    (51,09 и 54,67 часа) и среднее число коммуникаций (2,78 и 2,88).
-- 7. Конверсия в приглашение заметно различается по направлениям, но проверить, связана ли с ним коммуникация
--    внутри направлений, нельзя, потому что приглашённых с коммуникацией в каждом направлении от 1 до 22. Это наблюдаемая
--    связь, а не причинно-следственный вывод.
-- 8. Ограничения: коммуникации работодателя учтены только за первые 7 дней, а в задании 7 первый контакт и сообщения
--    кандидата сравнивались только за первые 24 часа; статус отклика итоговый (неизвестно, когда он стал «приглашением»),
--    группы небольшие (54 приглашённых с коммуникацией), а из слоя исключены 8 звонков без отклика и 1 звонок с ошибкой.
-- 9. Следующий вопрос: когда именно отклик получил статус «приглашение» относительно первой коммуникации,
--    и чем вакансии тестировщиков отличаются, чтобы понять, что объясняет высокую конверсию в этом направлении.