// Progressive enhancement: vote without a page reload. Without JS the same
// forms post normally and redirect back.
document.addEventListener("submit", async (event) => {
  const form = event.target.closest(".votes form");
  if (!form) return;

  event.preventDefault();
  const post = form.closest(".post");
  const button = form.querySelector("button");

  try {
    const response = await fetch(form.action, {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(new FormData(form)),
    });
    if (!response.ok) throw new Error(response.statusText);

    const { score, value } = await response.json();
    post.querySelector(".score").textContent = score;
    post.querySelectorAll(".arrow").forEach((arrow) => arrow.classList.remove("on"));
    if (value === 1) post.querySelector(".arrow.up").classList.add("on");
    if (value === -1) post.querySelector(".arrow.down").classList.add("on");
  } catch (error) {
    form.submit(); // fall back to a normal post
  }
});
