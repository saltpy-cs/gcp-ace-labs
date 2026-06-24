-- Lab 09 database setup: run against the postgres database.
-- Creates lab09_store with a products table and sample data.

CREATE DATABASE lab09_store;

\c lab09_store

CREATE TABLE products (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  price      NUMERIC(10, 2) NOT NULL,
  stock      INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO products (name, price, stock) VALUES
  ('Cloud SQL Handbook', 29.99, 150),
  ('GCP ACE Study Guide', 49.99, 200),
  ('Spanner T-Shirt', 19.99, 50),
  ('Firestore Mug', 12.99, 0);
