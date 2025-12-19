BEGIN;

DROP SCHEMA IF EXISTS video_rental_dv CASCADE;
CREATE SCHEMA video_rental_dv;
SET search_path = video_rental_dv, public;

-- Вспомогательные функции
CREATE OR REPLACE FUNCTION dv_md5(p text)
RETURNS char(32) LANGUAGE sql IMMUTABLE AS $$
    SELECT md5(p)::char(32)
$$;

CREATE OR REPLACE FUNCTION nvl_txt(p text) 
RETURNS text LANGUAGE sql IMMUTABLE AS $$ 
    SELECT coalesce(p, '') 
$$;

-- ==================== HUBS ====================

-- Хаб для клиентов (бизнес-ключ: номер паспорта)
CREATE TABLE hub_customer (
    bk_passport_series text NOT NULL,
    bk_passport_number text NOT NULL,
    hk_customer        char(32) NOT NULL,
    load_dts           timestamptz NOT NULL DEFAULT now(),
    record_source      text NOT NULL,
    CONSTRAINT pk_hub_customer PRIMARY KEY (hk_customer),
    CONSTRAINT uq_bk_hub_customer UNIQUE (bk_passport_series, bk_passport_number)
);

CREATE OR REPLACE FUNCTION trg_hub_customer_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_customer := dv_md5(
        nvl_txt(NEW.bk_passport_series) || '|' || 
        nvl_txt(NEW.bk_passport_number)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_hub_customer_hk
BEFORE INSERT OR UPDATE OF bk_passport_series, bk_passport_number
ON hub_customer
FOR EACH ROW EXECUTE FUNCTION trg_hub_customer_hk();

-- Хаб для носителей (бизнес-ключ: инвентарный код)
CREATE TABLE hub_media_item (
    bk_inventory_code  text NOT NULL,
    hk_media_item      char(32) NOT NULL,
    load_dts           timestamptz NOT NULL DEFAULT now(),
    record_source      text NOT NULL,
    CONSTRAINT pk_hub_media_item PRIMARY KEY (hk_media_item),
    CONSTRAINT uq_bk_hub_media_item UNIQUE (bk_inventory_code)
);

CREATE OR REPLACE FUNCTION trg_hub_media_item_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_media_item := dv_md5(nvl_txt(NEW.bk_inventory_code));
    RETURN NEW;
END $$;

CREATE TRIGGER bi_hub_media_item_hk
BEFORE INSERT OR UPDATE OF bk_inventory_code
ON hub_media_item
FOR EACH ROW EXECUTE FUNCTION trg_hub_media_item_hk();

-- Хаб для сотрудников (бизнес-ключ: табельный номер)
CREATE TABLE hub_employee (
    bk_employee_no text NOT NULL,
    hk_employee    char(32) NOT NULL,
    load_dts       timestamptz NOT NULL DEFAULT now(),
    record_source  text NOT NULL,
    CONSTRAINT pk_hub_employee PRIMARY KEY (hk_employee),
    CONSTRAINT uq_bk_hub_employee UNIQUE (bk_employee_no)
);

CREATE OR REPLACE FUNCTION trg_hub_employee_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_employee := dv_md5(nvl_txt(NEW.bk_employee_no));
    RETURN NEW;
END $$;

CREATE TRIGGER bi_hub_employee_hk
BEFORE INSERT OR UPDATE OF bk_employee_no
ON hub_employee
FOR EACH ROW EXECUTE FUNCTION trg_hub_employee_hk();

-- Хаб для договоров аренды (бизнес-ключ: номер договора)
CREATE TABLE hub_rental (
    bk_contract_no text NOT NULL,
    hk_rental      char(32) NOT NULL,
    load_dts       timestamptz NOT NULL DEFAULT now(),
    record_source  text NOT NULL,
    CONSTRAINT pk_hub_rental PRIMARY KEY (hk_rental),
    CONSTRAINT uq_bk_hub_rental UNIQUE (bk_contract_no)
);

CREATE OR REPLACE FUNCTION trg_hub_rental_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_rental := dv_md5(nvl_txt(NEW.bk_contract_no));
    RETURN NEW;
END $$;

CREATE TRIGGER bi_hub_rental_hk
BEFORE INSERT OR UPDATE OF bk_contract_no
ON hub_rental
FOR EACH ROW EXECUTE FUNCTION trg_hub_rental_hk();

-- Хаб для платежей (бизнес-ключ: номер чека)
CREATE TABLE hub_payment (
    bk_receipt_no text NOT NULL,
    hk_payment    char(32) NOT NULL,
    load_dts      timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    CONSTRAINT pk_hub_payment PRIMARY KEY (hk_payment),
    CONSTRAINT uq_bk_hub_payment UNIQUE (bk_receipt_no)
);

CREATE OR REPLACE FUNCTION trg_hub_payment_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_payment := dv_md5(nvl_txt(NEW.bk_receipt_no));
    RETURN NEW;
END $$;

CREATE TRIGGER bi_hub_payment_hk
BEFORE INSERT OR UPDATE OF bk_receipt_no
ON hub_payment
FOR EACH ROW EXECUTE FUNCTION trg_hub_payment_hk();

-- Хаб для фильмов (бизнес-ключ: оригинальное название + год выпуска)
CREATE TABLE hub_movie (
    bk_original_title text NOT NULL,
    bk_release_year   integer NOT NULL,
    hk_movie          char(32) NOT NULL,
    load_dts          timestamptz NOT NULL DEFAULT now(),
    record_source     text NOT NULL,
    CONSTRAINT pk_hub_movie PRIMARY KEY (hk_movie),
    CONSTRAINT uq_bk_hub_movie UNIQUE (bk_original_title, bk_release_year)
);

CREATE OR REPLACE FUNCTION trg_hub_movie_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_movie := dv_md5(
        nvl_txt(NEW.bk_original_title) || '|' || 
        nvl_txt(NEW.bk_release_year::text)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_hub_movie_hk
BEFORE INSERT OR UPDATE OF bk_original_title, bk_release_year
ON hub_movie
FOR EACH ROW EXECUTE FUNCTION trg_hub_movie_hk();

-- ==================== LINKS ====================

-- Связь: Договор аренды ↔ Клиент
CREATE TABLE l_rental_customer (
    hk_link_rc   char(32) NOT NULL,
    hk_rental    char(32) NOT NULL REFERENCES hub_rental(hk_rental),
    hk_customer  char(32) NOT NULL REFERENCES hub_customer(hk_customer),
    load_dts     timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    CONSTRAINT pk_l_rental_customer PRIMARY KEY (hk_link_rc),
    CONSTRAINT uq_l_rental_customer UNIQUE (hk_rental, hk_customer)
);

CREATE OR REPLACE FUNCTION trg_l_rc_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_link_rc := dv_md5(
        nvl_txt(NEW.hk_rental) || '|' || 
        nvl_txt(NEW.hk_customer)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_l_rc_hk
BEFORE INSERT OR UPDATE OF hk_rental, hk_customer
ON l_rental_customer
FOR EACH ROW EXECUTE FUNCTION trg_l_rc_hk();

-- Связь: Договор аренды ↔ Сотрудник
CREATE TABLE l_rental_employee (
    hk_link_re   char(32) NOT NULL,
    hk_rental    char(32) NOT NULL REFERENCES hub_rental(hk_rental),
    hk_employee  char(32) NOT NULL REFERENCES hub_employee(hk_employee),
    load_dts     timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    CONSTRAINT pk_l_rental_employee PRIMARY KEY (hk_link_re),
    CONSTRAINT uq_l_rental_employee UNIQUE (hk_rental, hk_employee)
);

CREATE OR REPLACE FUNCTION trg_l_re_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_link_re := dv_md5(
        nvl_txt(NEW.hk_rental) || '|' || 
        nvl_txt(NEW.hk_employee)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_l_re_hk
BEFORE INSERT OR UPDATE OF hk_rental, hk_employee
ON l_rental_employee
FOR EACH ROW EXECUTE FUNCTION trg_l_re_hk();

-- Связь: Договор аренды ↔ Носитель (многие-ко-многим через позиции аренды)
CREATE TABLE l_rental_media (
    hk_link_rm   char(32) NOT NULL,
    hk_rental    char(32) NOT NULL REFERENCES hub_rental(hk_rental),
    hk_media_item char(32) NOT NULL REFERENCES hub_media_item(hk_media_item),
    load_dts     timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    CONSTRAINT pk_l_rental_media PRIMARY KEY (hk_link_rm),
    CONSTRAINT uq_l_rental_media UNIQUE (hk_rental, hk_media_item)
);

CREATE OR REPLACE FUNCTION trg_l_rm_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_link_rm := dv_md5(
        nvl_txt(NEW.hk_rental) || '|' || 
        nvl_txt(NEW.hk_media_item)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_l_rm_hk
BEFORE INSERT OR UPDATE OF hk_rental, hk_media_item
ON l_rental_media
FOR EACH ROW EXECUTE FUNCTION trg_l_rm_hk();

-- Связь: Платеж ↔ Договор аренды
CREATE TABLE l_payment_rental (
    hk_link_pr  char(32) NOT NULL,
    hk_payment  char(32) NOT NULL REFERENCES hub_payment(hk_payment),
    hk_rental   char(32) NOT NULL REFERENCES hub_rental(hk_rental),
    load_dts    timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    CONSTRAINT pk_l_payment_rental PRIMARY KEY (hk_link_pr),
    CONSTRAINT uq_l_payment_rental UNIQUE (hk_payment, hk_rental)
);

CREATE OR REPLACE FUNCTION trg_l_pr_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_link_pr := dv_md5(
        nvl_txt(NEW.hk_payment) || '|' || 
        nvl_txt(NEW.hk_rental)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_l_pr_hk
BEFORE INSERT OR UPDATE OF hk_payment, hk_rental
ON l_payment_rental
FOR EACH ROW EXECUTE FUNCTION trg_l_pr_hk();

-- Связь: Носитель ↔ Фильм
CREATE TABLE l_media_movie (
    hk_link_mm   char(32) NOT NULL,
    hk_media_item char(32) NOT NULL REFERENCES hub_media_item(hk_media_item),
    hk_movie     char(32) NOT NULL REFERENCES hub_movie(hk_movie),
    load_dts     timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    CONSTRAINT pk_l_media_movie PRIMARY KEY (hk_link_mm),
    CONSTRAINT uq_l_media_movie UNIQUE (hk_media_item, hk_movie)
);

CREATE OR REPLACE FUNCTION trg_l_mm_hk()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hk_link_mm := dv_md5(
        nvl_txt(NEW.hk_media_item) || '|' || 
        nvl_txt(NEW.hk_movie)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_l_mm_hk
BEFORE INSERT OR UPDATE OF hk_media_item, hk_movie
ON l_media_movie
FOR EACH ROW EXECUTE FUNCTION trg_l_mm_hk();

-- ================= SATELLITES =================

-- Сателлит для клиентов
CREATE TABLE s_customer (
    hk_customer   char(32) NOT NULL REFERENCES hub_customer(hk_customer),
    load_dts      timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    last_name     text,
    first_name    text,
    phone         text,
    email         text,
    address       text,
    registration_date date,
    bonus_points  integer,
    hashdiff      char(32) NOT NULL,
    CONSTRAINT pk_s_customer PRIMARY KEY (hk_customer, load_dts)
);

CREATE OR REPLACE FUNCTION trg_s_customer_hash()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hashdiff := dv_md5(
        nvl_txt(NEW.last_name) || '|' ||
        nvl_txt(NEW.first_name) || '|' ||
        nvl_txt(NEW.phone) || '|' ||
        nvl_txt(NEW.email) || '|' ||
        nvl_txt(NEW.address) || '|' ||
        nvl_txt(to_char(NEW.registration_date, 'YYYY-MM-DD')) || '|' ||
        nvl_txt(NEW.bonus_points::text)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_s_customer_hash
BEFORE INSERT OR UPDATE OF last_name, first_name, phone, email, address, 
                           registration_date, bonus_points
ON s_customer
FOR EACH ROW EXECUTE FUNCTION trg_s_customer_hash();

-- Сателлит для сотрудников
CREATE TABLE s_employee (
    hk_employee   char(32) NOT NULL REFERENCES hub_employee(hk_employee),
    load_dts      timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    full_name     text,
    role          text,
    phone         text,
    email         text,
    hire_date     date,
    dismissal_date date,
    salary        numeric(12,2),
    hashdiff      char(32) NOT NULL,
    CONSTRAINT pk_s_employee PRIMARY KEY (hk_employee, load_dts)
);

CREATE OR REPLACE FUNCTION trg_s_employee_hash()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hashdiff := dv_md5(
        nvl_txt(NEW.full_name) || '|' ||
        nvl_txt(NEW.role) || '|' ||
        nvl_txt(NEW.phone) || '|' ||
        nvl_txt(NEW.email) || '|' ||
        nvl_txt(to_char(NEW.hire_date, 'YYYY-MM-DD')) || '|' ||
        nvl_txt(to_char(NEW.dismissal_date, 'YYYY-MM-DD')) || '|' ||
        nvl_txt(to_char(NEW.salary, 'FM9999999990D00'))
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_s_employee_hash
BEFORE INSERT OR UPDATE OF full_name, role, phone, email, hire_date, 
                           dismissal_date, salary
ON s_employee
FOR EACH ROW EXECUTE FUNCTION trg_s_employee_hash();

-- Сателлит для носителей
CREATE TABLE s_media_item (
    hk_media_item char(32) NOT NULL REFERENCES hub_media_item(hk_media_item),
    load_dts      timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    media_type    text,
    barcode       text,
    purchase_date date,
    purchase_price numeric(12,2),
    condition     text,
    status        text,
    notes         text,
    last_maintenance_date date,
    hashdiff      char(32) NOT NULL,
    CONSTRAINT pk_s_media_item PRIMARY KEY (hk_media_item, load_dts)
);

CREATE OR REPLACE FUNCTION trg_s_media_item_hash()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hashdiff := dv_md5(
        nvl_txt(NEW.media_type) || '|' ||
        nvl_txt(NEW.barcode) || '|' ||
        nvl_txt(to_char(NEW.purchase_date, 'YYYY-MM-DD')) || '|' ||
        nvl_txt(to_char(NEW.purchase_price, 'FM9999999990D00')) || '|' ||
        nvl_txt(NEW.condition) || '|' ||
        nvl_txt(NEW.status) || '|' ||
        nvl_txt(NEW.notes) || '|' ||
        nvl_txt(to_char(NEW.last_maintenance_date, 'YYYY-MM-DD'))
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_s_media_item_hash
BEFORE INSERT OR UPDATE OF media_type, barcode, purchase_date, purchase_price,
                           condition, status, notes, last_maintenance_date
ON s_media_item
FOR EACH ROW EXECUTE FUNCTION trg_s_media_item_hash();

-- Сателлит для фильмов
CREATE TABLE s_movie (
    hk_movie      char(32) NOT NULL REFERENCES hub_movie(hk_movie),
    load_dts      timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    title         text,
    duration_min  integer,
    age_rating    text,
    description   text,
    hashdiff      char(32) NOT NULL,
    CONSTRAINT pk_s_movie PRIMARY KEY (hk_movie, load_dts)
);

CREATE OR REPLACE FUNCTION trg_s_movie_hash()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hashdiff := dv_md5(
        nvl_txt(NEW.title) || '|' ||
        nvl_txt(NEW.duration_min::text) || '|' ||
        nvl_txt(NEW.age_rating) || '|' ||
        nvl_txt(NEW.description)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_s_movie_hash
BEFORE INSERT OR UPDATE OF title, duration_min, age_rating, description
ON s_movie
FOR EACH ROW EXECUTE FUNCTION trg_s_movie_hash();

-- Сателлит для договоров аренды
CREATE TABLE s_rental (
    hk_rental     char(32) NOT NULL REFERENCES hub_rental(hk_rental),
    load_dts      timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    rental_date   timestamptz,
    planned_return_date date,
    actual_return_date date,
    status        text,
    total_rental_fee numeric(12,2),
    total_deposit    numeric(12,2),
    total_fines      numeric(12,2),
    notes         text,
    hashdiff      char(32) NOT NULL,
    CONSTRAINT pk_s_rental PRIMARY KEY (hk_rental, load_dts)
);

CREATE OR REPLACE FUNCTION trg_s_rental_hash()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hashdiff := dv_md5(
        nvl_txt(to_char(NEW.rental_date, 'YYYY-MM-DD HH24:MI:SSOF')) || '|' ||
        nvl_txt(to_char(NEW.planned_return_date, 'YYYY-MM-DD')) || '|' ||
        nvl_txt(to_char(NEW.actual_return_date, 'YYYY-MM-DD')) || '|' ||
        nvl_txt(NEW.status) || '|' ||
        nvl_txt(to_char(NEW.total_rental_fee, 'FM9999999990D00')) || '|' ||
        nvl_txt(to_char(NEW.total_deposit, 'FM9999999990D00')) || '|' ||
        nvl_txt(to_char(NEW.total_fines, 'FM9999999990D00')) || '|' ||
        nvl_txt(NEW.notes)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_s_rental_hash
BEFORE INSERT OR UPDATE OF rental_date, planned_return_date, actual_return_date,
                           status, total_rental_fee, total_deposit, total_fines, notes
ON s_rental
FOR EACH ROW EXECUTE FUNCTION trg_s_rental_hash();

-- Сателлит для платежей
CREATE TABLE s_payment (
    hk_payment   char(32) NOT NULL REFERENCES hub_payment(hk_payment),
    load_dts     timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    payment_date timestamptz,
    amount       numeric(12,2),
    payment_type text,
    purpose      text,
    notes        text,
    hashdiff     char(32) NOT NULL,
    CONSTRAINT pk_s_payment PRIMARY KEY (hk_payment, load_dts)
);

CREATE OR REPLACE FUNCTION trg_s_payment_hash()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hashdiff := dv_md5(
        nvl_txt(to_char(NEW.payment_date, 'YYYY-MM-DD HH24:MI:SSOF')) || '|' ||
        nvl_txt(to_char(NEW.amount, 'FM9999999990D00')) || '|' ||
        nvl_txt(NEW.payment_type) || '|' ||
        nvl_txt(NEW.purpose) || '|' ||
        nvl_txt(NEW.notes)
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_s_payment_hash
BEFORE INSERT OR UPDATE OF payment_date, amount, payment_type, purpose, notes
ON s_payment
FOR EACH ROW EXECUTE FUNCTION trg_s_payment_hash();

-- Сателлит для деталей позиций аренды (линк-сателлит)
CREATE TABLE s_rental_media_details (
    hk_link_rm   char(32) NOT NULL REFERENCES l_rental_media(hk_link_rm),
    load_dts     timestamptz NOT NULL DEFAULT now(),
    record_source text NOT NULL,
    daily_rate   numeric(12,2),
    deposit      numeric(12,2),
    returned_date date,
    condition_on_return text,
    damage_description text,
    compensation_amount numeric(12,2),
    hashdiff     char(32) NOT NULL,
    CONSTRAINT pk_s_rental_media_details PRIMARY KEY (hk_link_rm, load_dts)
);

CREATE OR REPLACE FUNCTION trg_s_rental_media_details_hash()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.hashdiff := dv_md5(
        nvl_txt(to_char(NEW.daily_rate, 'FM9999999990D00')) || '|' ||
        nvl_txt(to_char(NEW.deposit, 'FM9999999990D00')) || '|' ||
        nvl_txt(to_char(NEW.returned_date, 'YYYY-MM-DD')) || '|' ||
        nvl_txt(NEW.condition_on_return) || '|' ||
        nvl_txt(NEW.damage_description) || '|' ||
        nvl_txt(to_char(NEW.compensation_amount, 'FM9999999990D00'))
    );
    RETURN NEW;
END $$;

CREATE TRIGGER bi_s_rental_media_details_hash
BEFORE INSERT OR UPDATE OF daily_rate, deposit, returned_date, 
                           condition_on_return, damage_description, compensation_amount
ON s_rental_media_details
FOR EACH ROW EXECUTE FUNCTION trg_s_rental_media_details_hash();

COMMIT;
