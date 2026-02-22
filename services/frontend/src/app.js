let currentUser = null;

const usernameInput = document.getElementById("username-input");
const switchBtn = document.getElementById("switch-btn");
const accountStatus = document.getElementById("account-status");
const productGrid = document.getElementById("product-grid");
const basketItemsEl = document.getElementById("basket-items");
const basketTotalEl = document.getElementById("basket-total");
const checkoutBtn = document.getElementById("checkout-btn");
const checkoutMsg = document.getElementById("checkout-msg");

async function apiPost(path, body) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return res.json();
}

async function apiGet(path) {
  const res = await fetch(path);
  return res.json();
}

async function switchAccount() {
  const username = usernameInput.value.trim();
  if (!username) return;
  const data = await apiPost("/api/users/switch", { username });
  currentUser = data;
  accountStatus.textContent = `Logged in as: ${data.username}`;
  usernameInput.value = "";
  updateAddButtons();
  refreshBasket();
}

async function renderProducts() {
  const products = await apiGet("/api/products");
  productGrid.innerHTML = "";
  products.forEach(p => {
    const card = document.createElement("div");
    card.className = "product-card";
    card.innerHTML = `
      <div class="product-emoji">${p.emoji}</div>
      <div class="product-name">${p.name}</div>
      <div class="product-price">$${parseFloat(p.price).toFixed(2)}</div>
      <button class="add-btn" data-id="${p.id}" disabled>Add to basket</button>
    `;
    card.querySelector(".add-btn").addEventListener("click", () => addToBasket(p.id));
    productGrid.appendChild(card);
  });
}

function updateAddButtons() {
  document.querySelectorAll(".add-btn").forEach(btn => {
    btn.disabled = !currentUser;
  });
}

async function addToBasket(productId) {
  if (!currentUser) return;
  await apiPost(`/api/basket/${currentUser.id}/add`, { product_id: productId });
  refreshBasket();
}

async function refreshBasket() {
  if (!currentUser) {
    basketItemsEl.innerHTML = "<em style='color:#999;font-size:0.82rem'>No account selected.</em>";
    basketTotalEl.textContent = "";
    checkoutBtn.disabled = true;
    return;
  }
  const data = await apiGet(`/api/basket/${currentUser.id}`);
  if (!data.items || data.items.length === 0) {
    basketItemsEl.innerHTML = "<em style='color:#999;font-size:0.82rem'>Basket is empty.</em>";
    basketTotalEl.textContent = "";
    checkoutBtn.disabled = true;
    return;
  }
  basketItemsEl.innerHTML = "";
  data.items.forEach(item => {
    const row = document.createElement("div");
    row.className = "basket-item";
    row.innerHTML = `
      <span class="basket-item-name">${item.emoji} ${item.name}</span>
      <span class="basket-item-qty">x${item.quantity}</span>
      <span class="basket-item-price">$${(parseFloat(item.price) * item.quantity).toFixed(2)}</span>
    `;
    basketItemsEl.appendChild(row);
  });
  basketTotalEl.textContent = `Total: $${parseFloat(data.total).toFixed(2)}`;
  checkoutBtn.disabled = false;
}

async function checkout() {
  if (!currentUser) return;
  checkoutBtn.disabled = true;
  await apiPost(`/api/basket/${currentUser.id}/checkout`, {});
  checkoutMsg.classList.remove("hidden");
  setTimeout(() => checkoutMsg.classList.add("hidden"), 3000);
  refreshBasket();
}

switchBtn.addEventListener("click", switchAccount);
usernameInput.addEventListener("keydown", e => { if (e.key === "Enter") switchAccount(); });
checkoutBtn.addEventListener("click", checkout);

renderProducts();
refreshBasket();
