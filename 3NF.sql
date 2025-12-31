-- Создание схемы
CREATE SCHEMA IF NOT EXISTS driving_license_3nf;
SET search_path TO driving_license_3nf;

-- 1. Таблица кандидатов (основная сущность)
CREATE TABLE candidate (
    candidate_id SERIAL PRIMARY KEY,
    last_name VARCHAR(100) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    birth_date DATE NOT NULL,
    passport_series VARCHAR(4) NOT NULL,
    passport_number VARCHAR(6) NOT NULL,
    passport_issued_by TEXT,
    address TEXT,
    phone_number VARCHAR(20),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_passport UNIQUE (passport_series, passport_number) -- Паспорт уникален
);

COMMENT ON TABLE candidate IS 'Физические лица - кандидаты на получение водительских прав.';
COMMENT ON COLUMN candidate.candidate_id IS 'Внутренний уникальный идентификатор кандидата (суррогатный ключ).';
COMMENT ON COLUMN candidate.last_name IS 'Фамилия кандидата.';
COMMENT ON COLUMN candidate.passport_series IS 'Серия паспорта (для идентификации личности).';

-- 2. Справочник автошкол
CREATE TABLE driving_school (
    school_id SERIAL PRIMARY KEY,
    school_name VARCHAR(255) NOT NULL,
    license_number VARCHAR(50) NOT NULL UNIQUE, -- Номер лицензии Минобра
    address TEXT NOT NULL,
    director_name VARCHAR(255),
    phone_number VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE driving_school IS 'Автошколы (учебные заведения), имеющие лицензию на подготовку водителей.';
COMMENT ON COLUMN driving_school.license_number IS 'Государственный номер лицензии образовательной деятельности.';

-- 3. Справочник медицинских учреждений
CREATE TABLE medical_center (
    med_center_id SERIAL PRIMARY KEY,
    med_center_name VARCHAR(255) NOT NULL,
    license_number VARCHAR(50) NOT NULL UNIQUE, -- Мед. лицензия
    address TEXT NOT NULL,
    phone_number VARCHAR(20)
);

COMMENT ON TABLE medical_center IS 'Медицинские учреждения, аккредитованные для освидетельствования водителей.';

-- 4. Справочник подразделений ГИБДД (МРЭО)
CREATE TABLE gibdd_department (
    department_id SERIAL PRIMARY KEY,
    department_code VARCHAR(20) NOT NULL UNIQUE, -- Код подразделения (например, 782-001)
    department_name VARCHAR(255) NOT NULL, -- Название (например, МРЭО ГИБДД №1 г.Санкт-Петербурга)
    address TEXT NOT NULL,
    phone_number VARCHAR(20)
);

COMMENT ON TABLE gibdd_department IS 'Экзаменационные подразделения ГИБДД (МРЭО).';

-- 5. Таблица экзаменаторов ГИБДД
CREATE TABLE examiner (
    examiner_id SERIAL PRIMARY KEY,
    last_name VARCHAR(100) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    badge_number VARCHAR(20) NOT NULL UNIQUE, -- Номер жетона
    department_id INTEGER NOT NULL REFERENCES gibdd_department(department_id) ON DELETE RESTRICT,
    is_active BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE examiner IS 'Сотрудники ГИБДД, имеющие право принимать практические экзамены по вождению.';
COMMENT ON COLUMN examiner.badge_number IS 'Служебный номер (жетон) экзаменатора.';

-- 6. Справочник типов экзаменов
CREATE TABLE exam_type (
    exam_type_id SERIAL PRIMARY KEY,
    exam_type_code VARCHAR(20) NOT NULL UNIQUE, -- Код типа: THEORY, AUTODROME, CITY
    exam_type_name VARCHAR(100) NOT NULL -- Название: 'Теоретический экзамен', 'Практический экзамен (автодром)', 'Практический экзамен (город)'
);

COMMENT ON TABLE exam_type IS 'Справочник видов экзаменов, которые необходимо сдать для получения прав.';
INSERT INTO exam_type (exam_type_code, exam_type_name) VALUES
('THEORY', 'Теоретический экзамен'),
('AUTODROME', 'Практический экзамен (автодром)'),
('CITY', 'Практический экзамен (город)');

-- 7. Таблица записей/договоров с автошколой (факт заключения договора)
CREATE TABLE enrollment (
    enrollment_id SERIAL PRIMARY KEY,
    candidate_id INTEGER NOT NULL REFERENCES candidate(candidate_id) ON DELETE CASCADE,
    school_id INTEGER NOT NULL REFERENCES driving_school(school_id) ON DELETE RESTRICT,
    contract_number VARCHAR(50) NOT NULL UNIQUE, -- Номер договора
    contract_date DATE NOT NULL,
    category VARCHAR(10) NOT NULL, -- Изучаемая категория (B, C, D...)
    hours_planned INTEGER NOT NULL CHECK (hours_planned > 0), -- Плановое кол-во часов обучения
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE enrollment IS 'Договоры на обучение между кандидатами и автошколами.';
COMMENT ON COLUMN enrollment.contract_number IS 'Уникальный номер договора (бизнес-ключ).';

-- 8. Таблица медицинских справок (факт выдачи справки)
CREATE TABLE medical_certificate (
    certificate_id SERIAL PRIMARY KEY,
    candidate_id INTEGER NOT NULL REFERENCES candidate(candidate_id) ON DELETE CASCADE,
    med_center_id INTEGER NOT NULL REFERENCES medical_center(med_center_id) ON DELETE RESTRICT,
    certificate_number VARCHAR(50) NOT NULL UNIQUE, -- Номер справки
    issue_date DATE NOT NULL,
    valid_until_date DATE NOT NULL, -- Справка действительна до...
    has_restrictions BOOLEAN DEFAULT FALSE, -- Есть ли ограничения по здоровью
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_dates CHECK (valid_until_date > issue_date)
);

COMMENT ON TABLE medical_certificate IS 'Медицинские справки установленного образца, выданные кандидатам.';
COMMENT ON COLUMN medical_certificate.certificate_number IS 'Уникальный номер медицинской справки (бизнес-ключ).';

-- 9. ТАБЛИЦА ЭКЗАМЕНОВ (Центральная сущность процесса)
CREATE TABLE exam (
    exam_id SERIAL PRIMARY KEY,
    candidate_id INTEGER NOT NULL REFERENCES candidate(candidate_id) ON DELETE CASCADE,
    department_id INTEGER NOT NULL REFERENCES gibdd_department(department_id) ON DELETE RESTRICT,
    exam_type_id INTEGER NOT NULL REFERENCES exam_type(exam_type_id) ON DELETE RESTRICT,
    examiner_id INTEGER REFERENCES examiner(examiner_id) ON DELETE SET NULL, -- Может быть NULL для теоретического экзамена
    exam_date TIMESTAMP NOT NULL,
    result VARCHAR(20) NOT NULL CHECK (result IN ('PASSED', 'FAILED', 'NOT_TAKEN')), -- Результат: Сдал, Не сдал, Не явился
    score INTEGER CHECK (score >= 0 AND score <= 100), -- Баллы (актуально для теории)
    comments TEXT, -- Комментарии экзаменатора (например, причина провала)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Уникальность: кандидат не должен сдавать один и тот же тип экзамена несколько раз в один момент времени
    CONSTRAINT unique_candidate_exam_type_date UNIQUE (candidate_id, exam_type_id, exam_date)
);

COMMENT ON TABLE exam IS 'Записи о попытках сдачи экзаменов кандидатами в подразделениях ГИБДД.';
COMMENT ON COLUMN exam.examiner_id IS 'Экзаменатор, принимавший практический экзамен. Для теории может быть NULL.';
COMMENT ON COLUMN exam.result IS 'Результат попытки: PASSED - сдал, FAILED - не сдал, NOT_TAKEN - не явился.';

-- 10. Таблица выданных водительских удостоверений (финальный результат)
CREATE TABLE license (
    license_id SERIAL PRIMARY KEY,
    candidate_id INTEGER NOT NULL UNIQUE REFERENCES candidate(candidate_id) ON DELETE CASCADE, -- У одного кандидата одна действующая карта
    license_number VARCHAR(20) NOT NULL UNIQUE, -- Номер в/у (например, 99 99 999999)
    department_issued_id INTEGER NOT NULL REFERENCES gibdd_department(department_id) ON DELETE RESTRICT, -- Какое МРЭО выдало
    issue_date DATE NOT NULL,
    expiry_date DATE NOT NULL, -- Дата окончания действия (обычно 10 лет)
    categories VARCHAR(50) NOT NULL, -- Категории, например, 'B,C1'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_license_dates CHECK (expiry_date > issue_date)
);

COMMENT ON TABLE license IS 'Выданные водительские удостоверения.';
COMMENT ON COLUMN license.license_number IS 'Уникальный номер водительского удостоверения (главный бизнес-ключ системы).';

-- Создание индексов для ускорения часто используемых запросов (поиск по паспорту, датам экзаменов)
CREATE INDEX idx_candidate_passport ON candidate(passport_series, passport_number);
CREATE INDEX idx_exam_candidate_date ON exam(candidate_id, exam_date DESC);
CREATE INDEX idx_enrollment_candidate ON enrollment(candidate_id);
CREATE INDEX idx_medical_certificate_candidate ON medical_certificate(candidate_id);
CREATE INDEX idx_license_candidate ON license(candidate_id);
