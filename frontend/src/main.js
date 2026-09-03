import { api } from "./api.js";
import "./style.css";

const app = document.getElementById("app");

let todos = [];
let loadError = null;

function render() {
  const doneCount = todos.filter((t) => t.done).length;

  app.innerHTML = `
    <div class="page">
      <header class="header">
        <span class="eyebrow">MEDISHOP / OPS v7</span>
        <h1>Tâches</h1>
        <p class="subtitle">${todos.length} élément${
    todos.length !== 1 ? "s" : ""
  } · ${doneCount} terminé${doneCount !== 1 ? "s" : ""}</p>
      </header>

      <form id="add-form" class="add-form">
        <input type="text" id="new-title" placeholder="Ajouter une tâche…" autocomplete="off" />
        <button type="submit">Ajouter</button>
      </form>

      ${loadError ? `<p class="error">${escapeHtml(loadError)}</p>` : ""}

      <ul class="todo-list">
        ${
          todos.map(renderTodo).join("") ||
          '<li class="empty">Aucune tâche pour l’instant.</li>'
        }
      </ul>
    </div>
  `;

  bindEvents();
}

function renderTodo(todo) {
  return `
    <li class="todo-row ${todo.done ? "done" : ""}" data-id="${todo.id}">
      <button class="toggle" data-action="toggle" data-id="${
        todo.id
      }" aria-label="Basculer le statut">${todo.done ? "[x]" : "[ ]"}</button>
      <span class="title">${escapeHtml(todo.title)}</span>
      <button class="edit" data-action="edit" data-id="${
        todo.id
      }">Éditer</button>
      <button class="delete" data-action="delete" data-id="${
        todo.id
      }">Supprimer</button>
    </li>
  `;
}

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function bindEvents() {
  document.getElementById("add-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const input = document.getElementById("new-title");
    const title = input.value.trim();
    if (!title) return;
    try {
      const created = await api.create(title);
      todos.unshift(created);
      loadError = null;
      render();
    } catch (err) {
      loadError = err.message;
      render();
    }
  });

  app.querySelectorAll('[data-action="toggle"]').forEach((btn) => {
    btn.addEventListener("click", () => onToggle(btn.dataset.id));
  });
  app.querySelectorAll('[data-action="edit"]').forEach((btn) => {
    btn.addEventListener("click", () => onEdit(btn.dataset.id));
  });
  app.querySelectorAll('[data-action="delete"]').forEach((btn) => {
    btn.addEventListener("click", () => onDelete(btn.dataset.id));
  });
}

async function onToggle(id) {
  const todo = todos.find((t) => String(t.id) === id);
  if (!todo) return;
  try {
    const updated = await api.update(id, { done: !todo.done });
    todos = todos.map((t) => (String(t.id) === id ? updated : t));
    render();
  } catch (err) {
    loadError = err.message;
    render();
  }
}

async function onEdit(id) {
  const todo = todos.find((t) => String(t.id) === id);
  if (!todo) return;
  const newTitle = prompt("Modifier la tâche :", todo.title);
  if (newTitle === null) return;
  const trimmed = newTitle.trim();
  if (!trimmed || trimmed === todo.title) return;
  try {
    const updated = await api.update(id, { title: trimmed });
    todos = todos.map((t) => (String(t.id) === id ? updated : t));
    render();
  } catch (err) {
    loadError = err.message;
    render();
  }
}

async function onDelete(id) {
  if (!confirm("Supprimer cette tâche ?")) return;
  try {
    await api.remove(id);
    todos = todos.filter((t) => String(t.id) !== id);
    render();
  } catch (err) {
    loadError = err.message;
    render();
  }
}

async function init() {
  try {
    todos = await api.list();
  } catch (err) {
    loadError = `Impossible de contacter l'API (${err.message}). Vérifiez que le backend tourne.`;
  }
  render();
}

init();
