import os
import time
import psycopg
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_HOST = os.getenv("DB_HOST", "postgres")
DB_NAME = os.getenv("DB_NAME", "appdb")
DB_USER = os.getenv("DB_USER", "appuser")
DB_PASS = os.getenv("DB_PASS", "apppass")

SEED_PRODUCTS = [
    ("Laptop", 999.99, "💻"),
    ("Headphones", 149.99, "🎧"),
    ("Coffee Maker", 79.99, "☕"),
    ("Running Shoes", 89.99, "👟"),
    ("Backpack", 49.99, "🎒"),
    ("Sunglasses", 34.99, "🕶️"),
    ("Water Bottle", 24.99, "🍶"),
    ("Desk Lamp", 39.99, "💡"),
]


def get_conn():
    return psycopg.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        connect_timeout=5,
    )


@app.on_event("startup")
def init_db():
    for _ in range(10):
        try:
            with get_conn() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        CREATE TABLE IF NOT EXISTS users (
                            id SERIAL PRIMARY KEY,
                            username VARCHAR(255) UNIQUE NOT NULL
                        );
                    """)
                    cur.execute("""
                        CREATE TABLE IF NOT EXISTS products (
                            id SERIAL PRIMARY KEY,
                            name VARCHAR(255) NOT NULL,
                            price NUMERIC(10,2) NOT NULL,
                            emoji VARCHAR(10) NOT NULL
                        );
                    """)
                    cur.execute("""
                        CREATE TABLE IF NOT EXISTS basket_items (
                            id SERIAL PRIMARY KEY,
                            user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                            product_id INT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
                            quantity INT NOT NULL DEFAULT 1,
                            UNIQUE (user_id, product_id)
                        );
                    """)
                    cur.execute("SELECT COUNT(*) FROM products;")
                    if cur.fetchone()[0] == 0:
                        cur.executemany(
                            "INSERT INTO products (name, price, emoji) VALUES (%s, %s, %s);",
                            SEED_PRODUCTS,
                        )
                conn.commit()
            return
        except Exception:
            time.sleep(3)


class UsernameBody(BaseModel):
    username: str


class ProductBody(BaseModel):
    product_id: int


@app.post("/api/users/switch")
def switch_user(body: UsernameBody):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO users (username) VALUES (%s)
                ON CONFLICT (username) DO UPDATE SET username = EXCLUDED.username
                RETURNING id, username;
                """,
                (body.username,),
            )
            row = cur.fetchone()
        conn.commit()
    return {"id": row[0], "username": row[1]}


@app.get("/api/products")
def list_products():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, name, price, emoji FROM products ORDER BY id;")
            rows = cur.fetchall()
    return [{"id": r[0], "name": r[1], "price": str(r[2]), "emoji": r[3]} for r in rows]


@app.post("/api/basket/{user_id}/add")
def add_to_basket(user_id: int, body: ProductBody):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE id = %s;", (user_id,))
            if not cur.fetchone():
                raise HTTPException(status_code=404, detail="User not found")
            cur.execute("SELECT id FROM products WHERE id = %s;", (body.product_id,))
            if not cur.fetchone():
                raise HTTPException(status_code=404, detail="Product not found")
            cur.execute(
                """
                INSERT INTO basket_items (user_id, product_id, quantity)
                VALUES (%s, %s, 1)
                ON CONFLICT (user_id, product_id) DO UPDATE
                SET quantity = basket_items.quantity + 1;
                """,
                (user_id, body.product_id),
            )
        conn.commit()
    return {"ok": True}


@app.get("/api/basket/{user_id}")
def get_basket(user_id: int):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE id = %s;", (user_id,))
            if not cur.fetchone():
                raise HTTPException(status_code=404, detail="User not found")
            cur.execute(
                """
                SELECT p.id, p.name, p.price, p.emoji, bi.quantity
                FROM basket_items bi
                JOIN products p ON p.id = bi.product_id
                WHERE bi.user_id = %s
                ORDER BY p.id;
                """,
                (user_id,),
            )
            rows = cur.fetchall()
    items = [
        {"id": r[0], "name": r[1], "price": str(r[2]), "emoji": r[3], "quantity": r[4]}
        for r in rows
    ]
    total = sum(float(i["price"]) * i["quantity"] for i in items)
    return {"items": items, "total": f"{total:.2f}"}


@app.post("/api/basket/{user_id}/checkout")
def checkout(user_id: int):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE id = %s;", (user_id,))
            if not cur.fetchone():
                raise HTTPException(status_code=404, detail="User not found")
            cur.execute("DELETE FROM basket_items WHERE user_id = %s;", (user_id,))
        conn.commit()
    return {"message": "Command validated"}


@app.get("/api/health")
def health():
    db = "down"
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                cur.fetchone()
        db = "up"
    except Exception:
        pass
    return {"status": "ok", "db": db}
