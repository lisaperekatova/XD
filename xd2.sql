BEGIN;

-- Чистая установка (для учебных прогонов)
DROP SCHEMA IF EXISTS video_rental_3nf CASCADE;

CREATE SCHEMA video_rental_3nf;
SET search_path = video_rental_3nf, public;

-- ---------- Типы и домены ----------

CREATE TYPE payment_method AS ENUM ('cash', 'card', 'online');
CREATE TYPE employee_role AS ENUM ('manager', 'operator', 'technician');
CREATE TYPE media_condition AS ENUM ('new', 'good', 'worn', 'scratched', 'broken');
CREATE TYPE media_status AS ENUM ('available', 'rented', 'maintenance', 'written_off');
CREATE TYPE media_type AS ENUM ('vhs', 'dvd', 'bluray');
CREATE TYPE rental_status AS ENUM ('active', 'returned', 'overdue', 'cancelled');
CREATE TYPE genre AS ENUM (
    'action', 'comedy', 'drama', 'horror', 
    'sci-fi', 'fantasy', 'documentary', 'children'
);

CREATE DOMAIN money_amount AS numeric(12,2) CHECK (VALUE >= 0);
CREATE DOMAIN rating_value AS numeric(3,1) CHECK (VALUE >= 0 AND VALUE <= 10);

-- ---------- Справочники ----------

CREATE TABLE studios (
    studio_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(100) NOT NULL UNIQUE,
    country varchar(50),
    founded_year integer
);
COMMENT ON TABLE studios IS 'Кинокомпании и студии';

CREATE TABLE directors (
    director_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name varchar(50) NOT NULL,
    last_name varchar(50) NOT NULL,
    birth_date date,
    nationality varchar(50)
);
COMMENT ON TABLE directors IS 'Режиссеры фильмов';

CREATE TABLE movies (
    movie_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title varchar(200) NOT NULL,
    original_title varchar(200),
    release_year integer NOT NULL,
    director_id bigint REFERENCES directors(director_id),
    studio_id bigint REFERENCES studios(studio_id),
    duration_min integer CHECK (duration_min > 0),
    age_rating varchar(10),
    description text
);
COMMENT ON TABLE movies IS 'Фильмы в каталоге';
CREATE INDEX idx_movies_title ON movies(title);
CREATE INDEX idx_movies_year ON movies(release_year);

CREATE TABLE movie_genres (
    movie_id bigint REFERENCES movies(movie_id) ON DELETE CASCADE,
    genre genre NOT NULL,
    PRIMARY KEY (movie_id, genre)
);
COMMENT ON TABLE movie_genres IS 'Связь фильмов с жанрами (многие-ко-многим)';

-- ---------- Носители (физические копии) ----------

CREATE TABLE media_items (
    media_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    movie_id bigint NOT NULL REFERENCES movies(movie_id),
    media_type media_type NOT NULL,
    inventory_code varchar(20) NOT NULL UNIQUE,
    barcode varchar(50) UNIQUE,
    purchase_date date NOT NULL,
    purchase_price money_amount,
    condition media_condition NOT NULL DEFAULT 'good',
    status media_status NOT NULL DEFAULT 'available',
    notes text,
    last_maintenance_date date
);
COMMENT ON TABLE media_items IS 'Физические носители (кассеты, диски)';
CREATE INDEX idx_media_items_status ON media_items(status);
CREATE INDEX idx_media_items_movie ON media_items(movie_id);

-- ---------- Клиенты и сотрудники ----------

CREATE TABLE customers (
    customer_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    last_name varchar(50) NOT NULL,
    first_name varchar(50) NOT NULL,
    phone varchar(20) NOT NULL UNIQUE,
    email varchar(100) UNIQUE,
    registration_date date NOT NULL DEFAULT CURRENT_DATE,
    address text,
    passport_series varchar(4),
    passport_number varchar(6),
    bonus_points integer DEFAULT 0 CHECK (bonus_points >= 0)
);
COMMENT ON TABLE customers IS 'Клиенты видеопроката';

CREATE TABLE employees (
    employee_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name varchar(100) NOT NULL,
    role employee_role NOT NULL,
    phone varchar(20),
    email varchar(100),
    hire_date date NOT NULL,
    dismissal_date date,
    salary money_amount,
    CONSTRAINT chk_dates CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date)
);
COMMENT ON TABLE employees IS 'Сотрудники пункта проката';

-- ---------- Тарифы ----------

CREATE TABLE tariffs (
    tariff_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name varchar(50) NOT NULL,
    media_type media_type NOT NULL,
    price_per_day money_amount NOT NULL,
    overdue_fine_per_day money_amount NOT NULL DEFAULT 0,
    deposit_amount money_amount NOT NULL DEFAULT 0,
    valid_from date NOT NULL,
    valid_to date,
    CONSTRAINT chk_tariff_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT uq_tariff UNIQUE (media_type, name, valid_from)
);
COMMENT ON TABLE tariffs IS 'Тарифы на аренду по типам носителей';
CREATE INDEX idx_tariffs_type ON tariffs(media_type, valid_from DESC);

-- ---------- Договоры аренды ----------

CREATE TABLE rentals (
    rental_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_number varchar(20) NOT NULL UNIQUE,
    customer_id bigint NOT NULL REFERENCES customers(customer_id),
    employee_id bigint NOT NULL REFERENCES employees(employee_id),
    rental_date timestamptz NOT NULL DEFAULT now(),
    planned_return_date date NOT NULL,
    actual_return_date date,
    status rental_status NOT NULL DEFAULT 'active',
    total_rental_fee money_amount,
    total_deposit money_amount,
    total_fines money_amount DEFAULT 0,
    notes text,
    CONSTRAINT chk_rental_dates CHECK (
        planned_return_date > rental_date::date 
        AND (actual_return_date IS NULL OR actual_return_date >= rental_date::date)
    )
);
COMMENT ON TABLE rentals IS 'Договоры аренды';
CREATE INDEX idx_rentals_customer ON rentals(customer_id);
CREATE INDEX idx_rentals_employee ON rentals(employee_id);
CREATE INDEX idx_rentals_status ON rentals(status);

-- ---------- Позиции аренды ----------

CREATE TABLE rental_items (
    rental_item_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rental_id bigint NOT NULL REFERENCES rentals(rental_id) ON DELETE CASCADE,
    media_id bigint NOT NULL REFERENCES media_items(media_id),
    tariff_applied_id bigint NOT NULL REFERENCES tariffs(tariff_id),
    daily_rate money_amount NOT NULL,
    deposit money_amount NOT NULL,
    returned_date date,
    condition_on_return media_condition,
    damage_description text,
    compensation_amount money_amount DEFAULT 0,
    CONSTRAINT uq_rental_media UNIQUE (rental_id, media_id)
);
COMMENT ON TABLE rental_items IS 'Конкретные носители в договоре аренды';
CREATE INDEX idx_rental_items_media ON rental_items(media_id);

-- ---------- Платежи ----------

CREATE TABLE payments (
    payment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rental_id bigint NOT NULL REFERENCES rentals(rental_id),
    payment_date timestamptz NOT NULL DEFAULT now(),
    amount money_amount NOT NULL,
    payment_type payment_method NOT NULL,
    purpose varchar(50) NOT NULL CHECK (purpose IN ('rent', 'deposit', 'fine', 'compensation')),
    receipt_number varchar(30),
    notes text
);
COMMENT ON TABLE payments IS 'Платежи по арендам';
CREATE INDEX idx_payments_rental ON payments(rental_id);

-- ---------- Обслуживание носителей ----------

CREATE TABLE maintenance_log (
    log_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    media_id bigint NOT NULL REFERENCES media_items(media_id),
    maintenance_date date NOT NULL DEFAULT CURRENT_DATE,
    maintenance_type varchar(50) NOT NULL,
    description text NOT NULL,
    technician_id bigint REFERENCES employees(employee_id),
    cost money_amount DEFAULT 0,
    result media_condition NOT NULL
);
COMMENT ON TABLE maintenance_log IS 'Журнал обслуживания и ремонта носителей';
CREATE INDEX idx_maintenance_media ON maintenance_log(media_id);

-- ---------- Отзывы и рейтинги ----------

CREATE TABLE customer_reviews (
    review_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id bigint NOT NULL REFERENCES customers(customer_id),
    movie_id bigint NOT NULL REFERENCES movies(movie_id),
    review_date date NOT NULL DEFAULT CURRENT_DATE,
    rating rating_value NOT NULL,
    comment text,
    CONSTRAINT uq_customer_movie_review UNIQUE (customer_id, movie_id)
);
COMMENT ON TABLE customer_reviews IS 'Отзывы и оценки клиентов';

-- Триггер для проверки доступности носителя при добавлении в аренду
CREATE OR REPLACE FUNCTION check_media_availability()
RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT status FROM media_items WHERE media_id = NEW.media_id) != 'available' THEN
        RAISE EXCEPTION 'Носитель с ID % не доступен для аренды', NEW.media_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_media_availability
BEFORE INSERT ON rental_items
FOR EACH ROW EXECUTE FUNCTION check_media_availability();

-- Триггер для обновления статуса носителя при аренде
CREATE OR REPLACE FUNCTION update_media_status_on_rent()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE media_items 
    SET status = 'rented'
    WHERE media_id = NEW.media_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_media_status_on_rent
AFTER INSERT ON rental_items
FOR EACH ROW EXECUTE FUNCTION update_media_status_on_rent();

-- Триггер для обновления статуса носителя при возврате
CREATE OR REPLACE FUNCTION update_media_status_on_return()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.returned_date IS NOT NULL AND OLD.returned_date IS NULL THEN
        UPDATE media_items 
        SET status = 'available',
            last_maintenance_date = CASE 
                WHEN NEW.condition_on_return IN ('worn', 'scratched') THEN CURRENT_DATE
                ELSE last_maintenance_date
            END
        WHERE media_id = NEW.media_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_media_status_on_return
AFTER UPDATE ON rental_items
FOR EACH ROW EXECUTE FUNCTION update_media_status_on_return();

COMMIT;
