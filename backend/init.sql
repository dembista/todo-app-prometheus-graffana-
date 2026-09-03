-- Initialisation de la base todo_app
-- Exécuté automatiquement par le conteneur Postgres officiel au premier démarrage
-- (monté dans /docker-entrypoint-initdb.d/)

CREATE TABLE IF NOT EXISTS todos (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  done BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
