const API_URL =
  import.meta.env.VITE_API_URL !== undefined
    ? import.meta.env.VITE_API_URL
    : "http://localhost:3000";

async function handleResponse(res) {
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `Erreur ${res.status}`);
  }
  if (res.status === 204) return null;
  return res.json();
}

export const api = {
  list: () => fetch(`${API_URL}/api/todos`).then(handleResponse),

  create: (title) =>
    fetch(`${API_URL}/api/todos`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title }),
    }).then(handleResponse),

  update: (id, changes) =>
    fetch(`${API_URL}/api/todos/${id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(changes),
    }).then(handleResponse),

  remove: (id) =>
    fetch(`${API_URL}/api/todos/${id}`, { method: "DELETE" }).then(
      handleResponse
    ),
};