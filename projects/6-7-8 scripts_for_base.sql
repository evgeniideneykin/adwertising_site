USE advertising_site;
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
			-- 6. скрипты характерных выборок (включающие группировки, JOIN'ы, вложенные таблицы) --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- количество активных (не удаленых) мужчин старше 18ти лет которые написали более одного сообщения вложенные запросы

SELECT DISTINCT COUNT(*) AS cnt
FROM users u 
WHERE u.id IN(
	SELECT m.from_user  FROM messages m GROUP BY m.from_user HAVING COUNT(*) > 1) AND is_deleted = 0 AND u.id IN(   -- HAVING просмотр результата агрегатной функции
	SELECT p2.user_id FROM profiles p2 WHERE DATEDIFF(CURRENT_DATE(), p2.birthday)/365.25 > 18) AND u.id IN(
	SELECT p.user_id FROM profiles p WHERE p.gender = "m");

-- количество активных (не удаленых) мужчин старше 18ти лет которые написали более одного сообщения joinы

SELECT COUNT(DISTINCT u.id) AS cnt -- вот тут не уверен что это правильная конструкция, прошу дать обратную связь по решению
FROM users u 
JOIN messages m ON u.id = m.from_user 
JOIN profiles p ON u.id = p.user_id 
WHERE p.gender = "m" AND u.is_deleted = 0 AND DATEDIFF(CURRENT_DATE(), p.birthday)/365.25 > 18 AND u.id IN (
	SELECT m2.from_user FROM messages m2 GROUP BY m2.from_user HAVING COUNT(*) > 1);

-- Сравнить количество пользователей не выложивших ни одного объявления с количеством пользователей выложивших объявление в %

SELECT @cnt:= COUNT(*) FROM users u2;                           -- можно решить с OVER без присваивания
SELECT (@cnt - COUNT(*))*100/@cnt AS cnt_user_without_ads, (COUNT(*))*100/@cnt AS cnt_user_with_ads
FROM users u 
WHERE u.id NOT IN(SELECT a.user_id FROM ads a);

-- Вывести топ 10 пользователей по сумме средств на кошельке в рублях

SELECT CONCAT(u.firstname, " ", u.lastname) AS users,
	CASE WHEN w.currency = 'usd' THEN w.balance * 60 
		 WHEN w.currency = 'euro' THEN w.balance * 58
		 ELSE w.balance END AS sum_rub
	FROM wallet w 
	JOIN users u ON w.user_id = u.id
 	ORDER BY sum_rub DESC
	LIMIT 10;

-- Вывести количество и среднюю оценку пользователей с средней оценкой выше или равно 4 в разрезе пола

SELECT p.gender, COUNT(DISTINCT p.user_id) AS users_count, ROUND(AVG(r.grade),1) AS avg_grade
FROM profiles p 
JOIN rewiews r ON p.user_id = r.to_ads_id 
WHERE p.user_id IN(
	SELECT r.to_ads_id FROM rewiews r GROUP BY r.to_ads_id HAVING AVG(r.grade) >= 4)	-- HAVING просмотр результата агрегатной функции
GROUP BY p.gender
ORDER BY p.gender DESC;

-- Вывести в процентном соотношении занятое место в хранилище медиафайлов в разрезе категорий объявлений

SELECT ac.name AS category, ROUND(SUM(m.size_file)*100/SUM(m.size_file) OVER(), 3) AS size_media -- OVER обход группировки SUM
FROM ads a
JOIN ads_category ac ON a.category_id = ac.id 
JOIN media m ON m.id = a.media_id 
GROUP BY ac.name 
ORDER BY size_media DESC;

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
										-- 7. представления (минимум 2) --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Представление вида имя,фамилия пользователя, пол, остаток на кошельке средств, валюта кошелька, количество размещенных объявлений (шт)

DROP VIEW IF EXISTS advertising_site.view_1;
CREATE VIEW view_1 AS
SELECT u.firstname, u.lastname, p.gender, w.balance, w.currency, COUNT (a.user_id) AS cnt
FROM users u 
JOIN profiles p ON u.id = p.user_id 
JOIN wallet w ON u.id = w.user_id 
JOIN ads a ON u.id = a.user_id 
GROUP BY a.user_id 
ORDER BY w.balance DESC;

SELECT * FROM view_1 v;

-- Представление разделит всех пользователей на 3 группы rich, midle, poor - более 10, 5-10, менее 5 тыс руб на кошельке соответственно, кол-во пользователей в категории

DROP VIEW IF EXISTS advertising_site.view_2;
CREATE VIEW view_2 AS
SELECT CASE WHEN (
	CASE WHEN w.currency = 'usd' THEN w.balance * 60 
		 WHEN w.currency = 'euro' THEN w.balance * 58
		 ELSE w.balance END) > 10000 THEN "rich"
		 WHEN (
	CASE WHEN w.currency = 'usd' THEN w.balance * 60 
		 WHEN w.currency = 'euro' THEN w.balance * 58
		 ELSE w.balance END) < 5000 THEN "poor"
		 ELSE "midle" END AS category, COUNT(*) AS cnt
FROM wallet w 
GROUP BY category;

SELECT * FROM view_2;

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
									-- 8. хранимые процедуры / триггеры (по 2) --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Процедура, выводящая сумму всех кошельков в валюте, указанной в параметре процедуры ("rub" и т.д.).

DROP PROCEDURE IF EXISTS balance;
DELIMITER //
CREATE PROCEDURE balance (IN summa VARCHAR(10))
BEGIN 
	SELECT SUM(balance) AS full_balance FROM wallet WHERE currency = summa;
	END

CALL balance("rub");

-- Процедура, выводящая самых молодых сотрудников, зарегестрированных в базе их возраст (количество и пол задать параметром)

DROP PROCEDURE IF EXISTS unit;
DELIMITER //
CREATE PROCEDURE unit (IN cnt INT, IN fgender CHAR(5))
BEGIN 
	SELECT u.firstname, u.lastname, p.gender, p.birthday, 
		ROUND(DATEDIFF(CURRENT_DATE(), p.birthday)/365.25,0) AS age  
			FROM profiles p JOIN users u ON p.user_id = u.id 
			WHERE gender = fgender ORDER BY birthday DESC LIMIT cnt;
END

CALL unit(10, "m");
CALL unit(5, "f");

-- Тригер запрещающий NULL в price, и пустые значения в body структуры ads

DROP TRIGGER IF EXISTS advertising_site.check_body_price_notnull_update;
DELIMITER $$
CREATE TRIGGER check_body_price_notnull_update
BEFORE UPDATE
ON ads FOR EACH ROW
BEGIN 
IF NEW.body = "" AND NEW.price IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'body и price не должно быть пустым'; 	
END IF;
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS advertising_site.check_body_price_notnull_insert;
DELIMITER $$
CREATE TRIGGER check_body_price_notnull_insert
BEFORE INSERT
ON ads FOR EACH ROW
BEGIN 
IF NEW.body = "" AND NEW.price IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'body и price не должно быть пустым'; 	
END IF;
END $$
DELIMITER ;

-- Добавить тригерры записывающие количество активных пользователей в системе в переменную @cnt_users

-- на вставку
DROP TRIGGER IF EXISTS advertising_site.count_users_insert;
USE advertising_site;
DELIMITER $$
CREATE TRIGGER count_users_insert
AFTER INSERT
ON users FOR EACH ROW
BEGIN 
	SELECT COUNT(*) INTO @cnt_users FROM users WHERE is_deleted = 0;
END $$
DELIMITER ;

-- на обновление
DROP TRIGGER IF EXISTS advertising_site.count_users_update;
USE advertising_site;
DELIMITER $$
CREATE TRIGGER count_users_update
AFTER UPDATE
ON users FOR EACH ROW
BEGIN 
	SELECT COUNT(*) INTO @cnt_users FROM users WHERE is_deleted = 0;
END $$
DELIMITER ;

-- на удаление
DROP TRIGGER IF EXISTS advertising_site.count_users_delete;
USE advertising_site;
DELIMITER $$
CREATE TRIGGER count_users_delete
AFTER DELETE
ON users FOR EACH ROW
BEGIN 
	SELECT COUNT(*) INTO @cnt_users FROM users WHERE is_deleted = 0;
END $$
DELIMITER ;

-- проверяем переменную
SELECT @cnt_users;
