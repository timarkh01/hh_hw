-- ============================================================
-- Домашнее задание к лекции «SQL. Введение»
-- Школа Аналитиков · учебная база hh_school
-- Автор: Архангельский Тимофей Витальевич
-- ============================================================

SET search_path TO hh_school;


-- ============================================================
-- БЛОК А. Разминка: термины и структура
-- ============================================================

-- ЗАДАНИЕ А1
-- 1. Категория и конкретный тип колонок:
--    vacancies.salary_from        — категория: числовая       тип: INT
--    vacancies.vacancy_name       — категория: строковая      тип: TEXT
--    vacancies.published_at       — категория: дата и время   тип: TIMESTAMP
--    employers.is_accredited_it   — категория: логическая     тип: BOOLEAN
--    responses.created_at         — категория: дата и время   тип: TIMESTAMP
--
-- 2. Первичные ключи таблиц:
--    areas: area_id
--    employers: employer_id
--    vacancies: vacancy_id
--    vacancy_details: vacancy_id (чем особенный: первичный ключ такой же как у vacancies. Это говорит о том, что 
--                                 связь между vacancies и vacancy_details 1:1)
--    responses: response_id
--
-- 3. Почему vacancy_name не может быть первичным ключом:
--    vacancy_name не может быть первичным ключом, потому что в этом столбце есть повторяющиеся значения.
--
--    Запрос для подтверждения числом:

-- запрос:

SELECT vacancy_name, 
	   COUNT(vacancy_name) AS cnt_vacancy
FROM vacancies
GROUP BY vacancy_name
ORDER BY cnt_vacancy DESC;


-- Вывод:
-- В столбце vacancy_name есть много повторяющихся значений (самое повторяющееся - "Стажёр: аналитик данных" - 6 раз),
-- а первичный ключ должен быть уникальным для каждой строки, поэтому, этот столбец не подойдт для уникального ключа.
--
-- 4. Что произойдёт при записи строки «по договорённости» в salary_from:
-- Если в колонку тип INT попытаться записать строку "по договорённости", то СУБД выдаст ошибку из-за неправильного типа
-- данных и запись не выоплнится. Это хорошо, потому что тип столбца гарантирует, что там лежат только числа, поэтому можно
-- спокойно применять математические операции, операции сравнения, сортировки и другие.


-- ============================================================
-- БЛОК Б. Первые запросы: SELECT, WHERE, ORDER BY
-- ============================================================

-- ЗАДАНИЕ Б1
-- Запрос: experience
SELECT DISTINCT(experience)
FROM vacancies;

-- Запрос: employment
SELECT DISTINCT(employment)
FROM vacancies;

-- Запрос: professional_role
SELECT DISTINCT(professional_role)
FROM vacancies;

-- Вывод:
-- В столбце experience и employment есть три уникальных значения. В столбце professional_role есть 5 уникальных значений.
-- Во всех столбцах нет NULL-значений и нет значений, которые имеют один и тот же смысл, но записаны по-разному


-- ЗАДАНИЕ Б2
-- Запрос 1: стажировки в Москве без опыта, вакансия открыта
SELECT v.vacancy_id,
	   v.vacancy_name, 
	   v.salary_from, 
	   v.published_at
FROM vacancies v JOIN areas a ON v.area_id = a.area_id 
WHERE v.closed_at IS NULL AND a.area_name = 'Москва' AND v.experience = 'Нет опыта'
ORDER BY v.published_at DESC;

-- Тот же запрос, но без JOIN
SELECT vacancy_id, 
	   vacancy_name, 
	   salary_from, 
	   published_at
FROM vacancies
WHERE closed_at IS NULL AND area_id = 1 AND experience = 'Нет опыта'
ORDER BY published_at DESC;

-- Запрос 2: топ-10 вакансий по salary_from
SELECT vacancy_name, 
	   professional_role, 
	   salary_from
FROM vacancies
ORDER BY salary_from DESC NULLS LAST
LIMIT 10;

-- Вывод:
-- Первый запрос нашел 13 вакансий (в одной вакансии нижняя граница зарплаты = NULL). Если убрать условие про Москву, то
-- появятся больше нужных вакансий.


-- ЗАДАНИЕ Б3
-- Ловушка 1. NULL — выполнить и объяснить результат
SELECT count(*) FROM vacancies WHERE closed_at = NULL;
SELECT count(*) FROM vacancies WHERE closed_at IS NULL;

-- Ловушка 2. AND / OR — выполнить и объяснить результат
SELECT count(*) FROM vacancies
WHERE area_id = 1 OR area_id = 2 AND experience = 'Нет опыта';

SELECT count(*) FROM vacancies
WHERE (area_id = 1 OR area_id = 2) AND experience = 'Нет опыта';

-- Вывод:
-- Первый запрос про NULL не выдал ошибку, потому что WHERE пропускает строки, где результат истинный, а сравнение
-- closed_at == NULL вернет UNKNOWN, и поэтому WHERE пропустит все строки. Это опаснее ошибки, потому что можно из-за 
-- невнимательности написать '=' вместо 'IS' и будет тяжело найти такую маленькую опечатку среди нескольких запросов.
-- NULL в closed_at означает, что вакансия открыта и никем не занята.
--
-- Первое условие во второй паре база прочитала как: "вакансия из Москвы или вакансия из Санкт-Петербурга без опыта".
-- На вопрос "вакансии из Москвы или Санкт-Петербурга, но обязательно без опыта" отвечает второй запрос во второй паре.


-- ============================================================
-- БЛОК В. Агрегации и метрики
-- ============================================================

-- ЗАДАНИЕ В1
-- Запрос 1: счётчики (строки, зарплата указана, направления, работодатели)
SELECT COUNT(*) AS total_cnt, 
	   COUNT(salary_from) AS salary_from_cnt, 
	   COUNT(DISTINCT professional_role) AS dist_role_cnt, 
	   COUNT(DISTINCT employer_id) AS dist_empl_cnt
FROM vacancies;

-- Запрос 2: доля активных вакансий (без JOIN)
SELECT COUNT(closed_at) AS opened_vacancies, 
	   COUNT(*) - COUNT(closed_at) AS closed_vacancies,
	   ROUND(COUNT(closed_at) * 100 / COUNT(*)::DECIMAL, 1) AS prs_opened_vacancies
FROM vacancies;

-- Вывод:
-- COUNT(*) - считает все строки, даже с NULL-значениями: в данной БД всего 52 строки и ,возможно, среди значений в строках есть NULL-значения;
-- COUNT(колонка) - считает все строки, но не считает NULL-значения: получили 44 строки, а у нас всего 52, значит в столбце salary_from есть 8 строк с NULL-значением;
-- COUNT(DISTINCT колонка) - считает сколько есть уникальных значений в столбце, не считает NULL-значения: получили 5 строк, значит на 52 строки есть всего 5 уникальных значений.
--
-- "Сейчас доля активных вакансий составляет 36,5%, что является 19 вакансиями из 52 вакансий за все время".


-- ЗАДАНИЕ В2
-- Запрос 1: направления — вакансии, работодатели, средняя зарплата
SELECT professional_role, 
	   COUNT(*) AS cnt_vacancies, 
	   COUNT(DISTINCT employer_id) AS dist_empl_cnt,
	   ROUND(AVG(salary_from)) AS avg_salary_from
FROM vacancies
GROUP BY professional_role
ORDER BY COUNT(*) DESC;


-- Запрос 2: то же, только направления с ≥ 5 открытыми вакансиями (WHERE + HAVING)
SELECT professional_role, 
	   COUNT(*) AS cnt_vacancies, 
	   COUNT(DISTINCT employer_id) AS dist_empl_cnt,
	   ROUND(AVG(salary_from)) AS avg_salary_from
FROM vacancies
WHERE closed_at IS NULL
GROUP BY professional_role
HAVING COUNT(*) >= 5
ORDER BY COUNT(*) DESC;

-- Вывод:
-- "Аналитик данных" (16)  и "Разработчик" (15) дают 31 из 52 вакансий, у остальных по 7. Лучше всего платят разработчикам (средняя 
-- нижняя граница 89167), хуже всего тестировщикам (56429). По данной таблице соискатель решил бы откликаться туда, где больше вакансий,
-- но для такого вывода не хватает данных об откликах и конверсии. 
-- Среди открытых вакансий лидеры прежние: "Аналитик данных" (11) и "Разработчик" (8).
--
-- в WHERE пишется "только открытые вакансии", потому что это условие проверяется для одной строки, а условие "не менее пяти" в HAVING
-- проверяет группу, в которой находится n-ое количество строк. Если в WHERE использовать агрегатные функции, то база выдаст ошибку,
-- потому что WHERE не может проверить условие для нескольких строк сразу.
--
-- avg(salary_from) помогает понять, на каком нижнем уровне в среднем находится зарплата в этом направлении, но не понятно, какая есть
-- минимальная или максимальная нижняя зарпалата, и есть ли аномальные значения, которые могут сильно повлиять на среднее значение


-- ============================================================
-- БЛОК Г. Соединение таблиц
-- ============================================================

-- ЗАДАНИЕ Г1
-- Запрос: топ-5 по salary_from с названием компании и городом (псевдонимы таблиц)
SELECT v.vacancy_id, 
	   e.employer_name, 
	   a.area_name , 
	   v.salary_from 
FROM vacancies v JOIN areas a ON v.area_id = a.area_id 
JOIN employers e ON v.employer_id = e.employer_id 
ORDER BY v.salary_from DESC NULLS LAST
LIMIT 5;

-- Вывод:
-- Если убрать псевдонимы, то база не поймет из какой таблицы нужно брать значение, потому что в двух таблицах одинаковые значения, и выдаст ошибку.


-- ЗАДАНИЕ Г2
-- Запрос 1: все работодатели, число вакансий и откликов (LEFT JOIN)
SELECT e.employer_name, 
	   COUNT(DISTINCT v.vacancy_id) AS cnt_vacancies, 
	   COUNT(r.response_id) AS cnt_responses
FROM employers e LEFT JOIN vacancies v ON e.employer_id = v.employer_id 
LEFT JOIN responses r ON v.vacancy_id = r.vacancy_id
GROUP BY e.employer_name
ORDER BY COUNT(r.response_id) DESC;

-- Запрос 2: тот же запрос с INNER JOIN
SELECT e.employer_name, 
	   COUNT(DISTINCT v.vacancy_id) AS cnt_vacancies, 
	   COUNT(r.response_id) AS cnt_responses
FROM employers e INNER JOIN vacancies v ON e.employer_id = v.employer_id 
INNER JOIN responses r ON v.vacancy_id = r.vacancy_id
GROUP BY e.employer_name
ORDER BY COUNT(r.response_id) DESC;

-- Вывод:
-- Количество вакансий приходится считать через COUNT(DISTINCT ...), потому что при соединении с таблицей employers у одной компании
-- может быть много вакансий, и из-за этого появлются повторяющиеся значения в столбце с вакансиями. 
--
-- Во втором запросе исчезла "ГринЭнерго" и ее исчезновение это проблема, потому что у этой компании есть вакансия, а при
-- поиске работы лучше не пропускать ни одну вакансию, тем более, на которой нет ни одного отклика.
--
-- INNER, когда нужны только строки, у которых есть совпадение в обеих таблицах, а LEFT, когда нужно сохранить все строки
-- левой таблицы, даже если пары в правой нет.


-- ============================================================
-- БЛОК Д. Функции и финальный кейс
-- ============================================================

-- ЗАДАНИЕ Д1
-- Запрос: помесячная динамика откликов и конверсия
-- (месяц как дата, условный агрегат, nullif в знаменателе)
SELECT DATE_TRUNC('month', created_at)::DATE AS month, 
	   COUNT(*) AS cnt_responces,
	   COUNT(*) FILTER (WHERE status = 'invited') AS cnt_invite,
	   ROUND((COUNT(*) FILTER (WHERE status = 'invited')) * 100 / NULLIF(COUNT(*), 0)::DECIMAL, 1) AS prs_invite
FROM responses
GROUP BY DATE_TRUNC('month', created_at)::DATE
ORDER BY DATE_TRUNC('month', created_at)::DATE;

-- Вывод:
-- Максимальная конверсия в шестом месяце (июнь).
--
-- Этому месяцу можно верить, потому что оно построено на большом числе откликов,а не на нескольких случайных случаях, например, 
-- в январе откликов мало, и там проценты легко скачут от одного приглашения.
--
-- Возможно, прошло еще не так много времени для рассмотрения откликов, поэтому пока что рано рассматривать этот месяц для анализа.


-- ЗАДАНИЕ Д2
-- Запрос: таблица по направлениям (вакансии, отклики, приглашения,
-- откликов на вакансию, конверсия)
SELECT professional_role,
	   COUNT(DISTINCT v.vacancy_id) AS cnt_vacancies,
	   COUNT(r.response_id) AS cnt_responses,
	   COUNT(*) FILTER (WHERE r.status = 'invited') AS cnt_invite,
	   ROUND(COUNT(r.response_id)::DECIMAL / NULLIF(COUNT(DISTINCT v.vacancy_id), 0), 2) AS mean_resp_per_vac,
	   ROUND((COUNT(*) FILTER (WHERE status = 'invited')) * 100 / NULLIF(COUNT(r.response_id), 0)::DECIMAL, 1) AS prs_invite
FROM vacancies v LEFT JOIN responses r ON v.vacancy_id = r.vacancy_id 
GROUP BY v.professional_role;

-- Письменные ответы:
-- 1. Совпадает ли направление с наибольшим числом вакансий с направлением
--    с наибольшей конверсией?
-- Нет, не совпадает. У направления "Тестировщик" меньше всего вакансий (7) и наибольшая конверсия (35,9).
--
-- 2. Какое направление выбрать и почему (опираясь на два столбца):
-- Я бы выбрал направление "Тестировщик", потому что на это направление подано относительно мало заявок (5,57 на одну вакансию), 
-- и также у этого направление очень высокий уровень конверсии, так что получить приглашение на это направление будет легче всего.
--
-- 3. Оговорка к выводу:
-- Вывод основан на маленьком число вакансий, не учитывает итоговый результат собеседования и не показывает условия от работадателей
-- для определенного направления, поэтому тяжело понять причину конверсии.


-- ============================================================
-- БЛОК Е. Со звёздочкой
-- ============================================================

-- ЗАДАНИЕ Е1
-- Исходный запрос (выполнить и посмотреть результат):
 SELECT v.professional_role,
	 count(*) AS vacancies,
	 sum(v.salary_from) AS total_salary,
	 count(r.response_id) / count(*) AS responses_per_vacancy
 FROM vacancies v
 JOIN responses r ON v.vacancy_id = r.vacancy_id
 WHERE v.closed_at = NULL
 GROUP BY 1;

-- Ошибки (минимум четыре):
-- 1. v.closed_at = NULL - WHERE пропускает все значение и не выдает ошибку, потому что условие выдаст UNKNOWN, а WHERE проверяет,
-- является ли условие истинным или не является.
-- 2. count(*) AS vacancies - при соединении таблиц появляются повторы с одинаковыми вакансиями, поэтому нужно считать уникальные значения.
-- 3. count(r.response_id) / count(*) AS responses_per_vacancy - та же ошибка, что и в 3, но еще нужно добавить NULLIF, чтобы 
-- избежать деления на 0, и чтобы получить дробную часть нужно использовать ::DECIMAL.
-- 4. При использовании JOIN вакансии без откликов отбрасываются, поэтому нужно использовать LEFT JOIN.
-- 5. sum(v.salary_from) - после JOIN с откликами вакансия повторяется по числу откликов, и ее зарпалата суммируется многократно. Поэтому
-- сумма считается в CTE по уникальным вакансиям. Sum заменил на avg, так как сумма нижних границ просто растет с числом новых вакансий и
-- не несет в себе никакой нужной информации для данного кейса, а avg показывает среднюю зарпалату по направлению среди открытых вакансий.
--
-- Исправленный запрос:
WITH vac AS (
	SELECT professional_role,
		   ROUND(AVG(salary_from)) AS avg_salary
	FROM vacancies
	GROUP BY professional_role
)

 SELECT v.professional_role,
	 count(DISTINCT(v.vacancy_id)) AS vacancies,
	 vc.avg_salary,
	 ROUND(count(r.response_id) / NULLIF(count(DISTINCT(v.vacancy_id)), 0)::DECIMAL, 2) AS responses_per_vacancy
FROM vacancies v
 LEFT JOIN responses r ON v.vacancy_id = r.vacancy_id
 LEFT JOIN vac vc ON v.professional_role = vc.professional_role
 WHERE v.closed_at IS NULL
 GROUP BY v.professional_role, vc.avg_salary;

-- Какие два правила из лекции защитили бы от этих ошибок при написании запроса:
-- 1. Подводный камень из 4.2: NULL - это не специальное значение, а отсутствие значения. Поэтому нельзя написать WHERE v.closed_at = NULL
-- 2. 7.3: NULLIF(a,b) - главное применение - защита от деления на ноль, и без неё не обходится ни один расчет конверсии.
