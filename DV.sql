-- Создание схемы
CREATE SCHEMA IF NOT EXISTS driving_license_dv;
SET search_path TO driving_license_dv;

-- 1. ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ для вычисления хэша
-- Упрощает создание ключей и проверку изменений
CREATE OR REPLACE FUNCTION md5_hash(text) RETURNS CHAR(32) AS $$
    SELECT md5($1);
$$ LANGUAGE sql IMMUTABLE;

COMMENT ON FUNCTION md5_hash IS 'Функция для вычисления MD5 хэша от входной строки. Используется для создания хэш-ключей в Data Vault.';

-- 2. ХАБЫ (HUBS) - уникальные бизнес-сущности

-- 2.1. Хаб кандидатов (ключ: паспортные данные)
CREATE TABLE hub_candidate (
    candidate_sk CHAR(32) PRIMARY KEY, -- Суррогатный хэш-ключ
    candidate_bk VARCHAR(20) NOT NULL UNIQUE, -- Бизнес-ключ: серия+номер паспорта (например '4510 123456')
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, -- Дата загрузки записи
    record_source VARCHAR(50) NOT NULL -- Источник данных (например 'CRM_System')
);

COMMENT ON TABLE hub_candidate IS 'Хаб кандидатов. Содержит уникальные бизнес-ключи (номера паспортов).';
COMMENT ON COLUMN hub_candidate.candidate_sk IS 'Суррогатный хэш-ключ (md5 от бизнес-ключа).';
COMMENT ON COLUMN hub_candidate.candidate_bk IS 'Бизнес-ключ: серия и номер паспорта через пробел.';
COMMENT ON COLUMN hub_candidate.load_dts IS 'Метка времени загрузки записи в хранилище.';
COMMENT ON COLUMN hub_candidate.record_source IS 'Система-источник данных (для трассировки).';

-- 2.2. Хаб автошкол
CREATE TABLE hub_driving_school (
    school_sk CHAR(32) PRIMARY KEY,
    school_bk VARCHAR(50) NOT NULL UNIQUE, -- Номер лицензии автошколы
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL
);
COMMENT ON TABLE hub_driving_school IS 'Хаб автошкол. Ключ - номер образовательной лицензии.';

-- 2.3. Хаб медицинских учреждений
CREATE TABLE hub_medical_center (
    med_center_sk CHAR(32) PRIMARY KEY,
    med_center_bk VARCHAR(50) NOT NULL UNIQUE, -- Номер медицинской лицензии
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL
);
COMMENT ON TABLE hub_medical_center IS 'Хаб медицинских учреждений. Ключ - номер медицинской лицензии.';

-- 2.4. Хаб подразделений ГИБДД
CREATE TABLE hub_gibdd_department (
    department_sk CHAR(32) PRIMARY KEY,
    department_bk VARCHAR(20) NOT NULL UNIQUE, -- Код подразделения (782-001)
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL
);
COMMENT ON TABLE hub_gibdd_department IS 'Хаб подразделений ГИБДД (МРЭО). Ключ - код подразделения.';

-- 2.5. Хаб экзаменаторов
CREATE TABLE hub_examiner (
    examiner_sk CHAR(32) PRIMARY KEY,
    examiner_bk VARCHAR(20) NOT NULL UNIQUE, -- Номер жетона экзаменатора
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL
);
COMMENT ON TABLE hub_examiner IS 'Хаб экзаменаторов ГИБДД. Ключ - номер служебного жетона.';

-- 2.6. Хаб типов экзаменов
CREATE TABLE hub_exam_type (
    exam_type_sk CHAR(32) PRIMARY KEY,
    exam_type_bk VARCHAR(20) NOT NULL UNIQUE, -- Код типа: THEORY, AUTODROME, CITY
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL
);
COMMENT ON TABLE hub_exam_type IS 'Хаб типов экзаменов. Справочник.';

-- 2.7. Хаб водительских удостоверений
CREATE TABLE hub_license (
    license_sk CHAR(32) PRIMARY KEY,
    license_bk VARCHAR(20) NOT NULL UNIQUE, -- Номер водительского удостоверения
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL
);
COMMENT ON TABLE hub_license IS 'Хаб водительских удостоверений. Ключ - номер В/У.';

-- 3. СВЯЗИ (LINKS) - события и отношения M:M

-- 3.1. Связь: Запись в автошколу (Кандидат + Автошкола + Время)
CREATE TABLE link_enrollment (
    enrollment_sk CHAR(32) PRIMARY KEY,
    candidate_sk CHAR(32) NOT NULL REFERENCES hub_candidate(candidate_sk),
    school_sk CHAR(32) NOT NULL REFERENCES hub_driving_school(school_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL,
    -- Бизнес-ключи для удобства (опционально)
    contract_number VARCHAR(50), -- Номер договора
    contract_date DATE, -- Дата договора
    CONSTRAINT unique_enrollment UNIQUE (candidate_sk, school_sk, contract_date)
);
COMMENT ON TABLE link_enrollment IS 'Связь: факт заключения договора обучения между кандидатом и автошколой.';
COMMENT ON COLUMN link_enrollment.enrollment_sk IS 'Хэш-ключ связи (md5 от конкатенации ключей хабов).';

-- 3.2. Связь: Выдача медицинской справки
CREATE TABLE link_medical_certificate (
    certificate_sk CHAR(32) PRIMARY KEY,
    candidate_sk CHAR(32) NOT NULL REFERENCES hub_candidate(candidate_sk),
    med_center_sk CHAR(32) NOT NULL REFERENCES hub_medical_center(med_center_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL,
    certificate_number VARCHAR(50), -- Номер справки
    issue_date DATE, -- Дата выдачи
    CONSTRAINT unique_certificate UNIQUE (candidate_sk, med_center_sk, issue_date)
);
COMMENT ON TABLE link_medical_certificate IS 'Связь: факт выдачи медицинской справки кандидату в медицинском учреждении.';

-- 3.3. Связь: Попытка сдачи экзамена (самая сложная связь)
CREATE TABLE link_exam_attempt (
    exam_attempt_sk CHAR(32) PRIMARY KEY,
    candidate_sk CHAR(32) NOT NULL REFERENCES hub_candidate(candidate_sk),
    exam_type_sk CHAR(32) NOT NULL REFERENCES hub_exam_type(exam_type_sk),
    department_sk CHAR(32) NOT NULL REFERENCES hub_gibdd_department(department_sk),
    examiner_sk CHAR(32) REFERENCES hub_examiner(examiner_sk), -- Может быть NULL для теории
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL,
    exam_timestamp TIMESTAMP, -- Дата и время экзамена
    -- Уникальность: один кандидат не может сдавать один тип экзамена в одно время
    CONSTRAINT unique_exam_attempt UNIQUE (candidate_sk, exam_type_sk, exam_timestamp)
);
COMMENT ON TABLE link_exam_attempt IS 'Связь: факт попытки сдачи экзамена. Связывает кандидата, тип экзамена, МРЭО и экзаменатора.';

-- 3.4. Связь: Выдача водительского удостоверения
CREATE TABLE link_license_issuance (
    issuance_sk CHAR(32) PRIMARY KEY,
    candidate_sk CHAR(32) NOT NULL REFERENCES hub_candidate(candidate_sk),
    license_sk CHAR(32) NOT NULL REFERENCES hub_license(license_sk),
    department_sk CHAR(32) NOT NULL REFERENCES hub_gibdd_department(department_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(50) NOT NULL,
    issue_date DATE NOT NULL,
    CONSTRAINT unique_issuance UNIQUE (candidate_sk, license_sk, issue_date)
);
COMMENT ON TABLE link_license_issuance IS 'Связь: факт выдачи водительского удостоверения кандидату в определенном МРЭО.';

-- 4. СПУТНИКИ (SATELLITES) - описательные атрибуты с историей

-- 4.1. Спутник: Персональные данные кандидата
CREATE TABLE sat_candidate_personal_data (
    candidate_sk CHAR(32) NOT NULL REFERENCES hub_candidate(candidate_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff CHAR(32) NOT NULL, -- Хэш от всех атрибутов для обнаружения изменений
    last_name VARCHAR(100) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    birth_date DATE NOT NULL,
    record_source VARCHAR(50) NOT NULL,
    PRIMARY KEY (candidate_sk, load_dts)
);
COMMENT ON TABLE sat_candidate_personal_data IS 'Спутник: персональные данные кандидата (ФИО, дата рождения). Хранит историю изменений.';
COMMENT ON COLUMN sat_candidate_personal_data.hash_diff IS 'Хэш-разность для быстрого обнаружения изменений в атрибутах.';

-- 4.2. Спутник: Контактная информация кандидата
CREATE TABLE sat_candidate_contact (
    candidate_sk CHAR(32) NOT NULL REFERENCES hub_candidate(candidate_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff CHAR(32) NOT NULL,
    address TEXT,
    phone_number VARCHAR(20),
    email VARCHAR(100),
    record_source VARCHAR(50) NOT NULL,
    PRIMARY KEY (candidate_sk, load_dts)
);
COMMENT ON TABLE sat_candidate_contact IS 'Спутник: контактная информация кандидата. Отдельный спутник, т.к. меняется реже персональных данных.';

-- 4.3. Спутник: Паспортные данные кандидата
CREATE TABLE sat_candidate_passport (
    candidate_sk CHAR(32) NOT NULL REFERENCES hub_candidate(candidate_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff CHAR(32) NOT NULL,
    passport_series VARCHAR(4) NOT NULL,
    passport_number VARCHAR(6) NOT NULL,
    passport_issued_by TEXT,
    record_source VARCHAR(50) NOT NULL,
    PRIMARY KEY (candidate_sk, load_dts)
);
COMMENT ON TABLE sat_candidate_passport IS 'Спутник: паспортные данные. Выделен отдельно, т.к. паспорт может быть заменен.';

-- 4.4. Спутник: Детали автошколы
CREATE TABLE sat_driving_school_details (
    school_sk CHAR(32) NOT NULL REFERENCES hub_driving_school(school_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff CHAR(32) NOT NULL,
    school_name VARCHAR(255) NOT NULL,
    address TEXT NOT NULL,
    director_name VARCHAR(255),
    phone_number VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    record_source VARCHAR(50) NOT NULL,
    PRIMARY KEY (school_sk, load_dts)
);
COMMENT ON TABLE sat_driving_school_details IS 'Спутник: детали автошколы (название, адрес, контакты).';

-- 4.5. Спутник: Результаты экзаменов (привязан к СВЯЗИ link_exam_attempt)
CREATE TABLE sat_exam_attempt_details (
    exam_attempt_sk CHAR(32) NOT NULL REFERENCES link_exam_attempt(exam_attempt_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff CHAR(32) NOT NULL,
    result VARCHAR(20) NOT NULL CHECK (result IN ('PASSED', 'FAILED', 'NOT_TAKEN')),
    score INTEGER CHECK (score >= 0 AND score <= 100),
    comments TEXT,
    record_source VARCHAR(50) NOT NULL,
    PRIMARY KEY (exam_attempt_sk, load_dts)
);
COMMENT ON TABLE sat_exam_attempt_details IS 'Спутник: детали попытки сдачи экзамена (результат, баллы, комментарии). Хранит историю изменений результата.';

-- 4.6. Спутник: Детали водительского удостоверения
CREATE TABLE sat_license_details (
    license_sk CHAR(32) NOT NULL REFERENCES hub_license(license_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff CHAR(32) NOT NULL,
    categories VARCHAR(50) NOT NULL,
    issue_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    record_source VARCHAR(50) NOT NULL,
    PRIMARY KEY (license_sk, load_dts),
    CONSTRAINT valid_dates CHECK (expiry_date > issue_date)
);
COMMENT ON TABLE sat_license_details IS 'Спутник: детали водительского удостоверения (категории, сроки действия).';

-- 4.7. Спутник: Описание типов экзаменов
CREATE TABLE sat_exam_type_description (
    exam_type_sk CHAR(32) NOT NULL REFERENCES hub_exam_type(exam_type_sk),
    load_dts TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff CHAR(32) NOT NULL,
    exam_type_name VARCHAR(100) NOT NULL,
    description TEXT,
    record_source VARCHAR(50) NOT NULL,
    PRIMARY KEY (exam_type_sk, load_dts)
);
COMMENT ON TABLE sat_exam_type_description IS 'Спутник: описательные атрибуты типов экзаменов.';

-- 5. ИНДЕКСЫ для оптимизации (ключевые для Data Vault)
CREATE INDEX idx_hub_candidate_bk ON hub_candidate(candidate_bk);
CREATE INDEX idx_hub_license_bk ON hub_license(license_bk);
CREATE INDEX idx_link_enrollment_candidate ON link_enrollment(candidate_sk);
CREATE INDEX idx_link_exam_attempt_composite ON link_exam_attempt(candidate_sk, exam_type_sk, exam_timestamp);
CREATE INDEX idx_sat_candidate_personal_sk ON sat_candidate_personal_data(candidate_sk);
CREATE INDEX idx_sat_exam_attempt_sk ON sat_exam_attempt_details(exam_attempt_sk);

-- 6. Вставка справочных данных (типы экзаменов)
INSERT INTO hub_exam_type (exam_type_sk, exam_type_bk, record_source) VALUES
(md5_hash('THEORY'), 'THEORY', 'SYSTEM'),
(md5_hash('AUTODROME'), 'AUTODROME', 'SYSTEM'),
(md5_hash('CITY'), 'CITY', 'SYSTEM');

INSERT INTO sat_exam_type_description (exam_type_sk, load_dts, hash_diff, exam_type_name, record_source) VALUES
(md5_hash('THEORY'), CURRENT_TIMESTAMP, md5_hash('Теоретический экзамен'), 'Теоретический экзамен', 'SYSTEM'),
(md5_hash('AUTODROME'), CURRENT_TIMESTAMP, md5_hash('Практический экзамен (автодром)'), 'Практический экзамен (автодром)', 'SYSTEM'),
(md5_hash('CITY'), CURRENT_TIMESTAMP, md5_hash('Практический экзамен (город)'), 'Практический экзамен (город)', 'SYSTEM');
