CREATE DATABASE IF NOT EXISTS `template` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'template'@'%' IDENTIFIED BY 'template';
GRANT ALL PRIVILEGES ON `template`.* TO 'template'@'%';
