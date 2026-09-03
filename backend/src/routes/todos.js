import { Router } from "express";
import pool from "../db.js";

const router = Router();

// GET /api/todos — liste (nécessaire pour que le frontend affiche les tâches)
router.get("/", async (req, res, next) => {
  try {
    const result = await pool.query(
      "SELECT * FROM todos ORDER BY created_at DESC"
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// POST /api/todos — création
router.post("/", async (req, res, next) => {
  try {
    const { title } = req.body;
    if (!title || !title.trim()) {
      return res.status(400).json({ error: 'Le champ "title" est requis' });
    }
    const result = await pool.query(
      "INSERT INTO todos (title) VALUES ($1) RETURNING *",
      [title.trim()]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

// PUT /api/todos/:id — modification (titre et/ou statut "done")
router.put("/:id", async (req, res, next) => {
  try {
    const { id } = req.params;
    const { title, done } = req.body;

    const existing = await pool.query("SELECT * FROM todos WHERE id = $1", [
      id,
    ]);
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: "Tâche introuvable" });
    }

    const next_title =
      title !== undefined ? title.trim() : existing.rows[0].title;
    const next_done = done !== undefined ? done : existing.rows[0].done;

    const result = await pool.query(
      "UPDATE todos SET title = $1, done = $2 WHERE id = $3 RETURNING *",
      [next_title, next_done, id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

// DELETE /api/todos/:id — suppression
router.delete("/:id", async (req, res, next) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      "DELETE FROM todos WHERE id = $1 RETURNING *",
      [id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Tâche introuvable" });
    }
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

export default router;
